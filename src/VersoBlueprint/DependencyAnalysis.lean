/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.DependencyAnalysis.Config
import VersoBlueprint.Environment

/-!
Automatic dependency inference for Verso Blueprint.

Walks compiled declaration types and bodies through permitted unassociated helpers,
stopping at the first Blueprint-associated declarations on each path. Direct-only
inference is the default; the scoped expansion policy permits more. Associations are
those available when inference runs. An empty result does not establish
mathematical independence. See the Manual for the full contract.
-/

namespace Informal

open Lean

namespace DependencyAnalysis

register_option verso.blueprint.autoDeps : Bool := {
  defValue := false
  descr := "Infer Blueprint dependencies by default, using the configured helper expansion policy"
}

/--
Dependency labels inferred from a compiled Lean declaration.

Each axis reaches the first Blueprint-associated declarations through permitted helper
types and bodies. Label-level axis suppression and manual precedence are applied
separately by `toUseRefs` and contribution validation.
-/
structure InferredDeps where
  statement : Array Data.Label := #[]
  proof : Array Data.Label := #[]
deriving Inhabited, Repr

structure InferredUseRefs where
  statement : Array Data.UseRef := #[]
  proof : Array Data.UseRef := #[]
deriving Inhabited, Repr

def enabled (opts : Options) (local? : Option Bool) : Bool :=
  local?.getD (verso.blueprint.autoDeps.get opts)

def automaticUseRef (label : Data.Label) : Data.UseRef :=
  { label, origin := .automatic }

def sortLabels (labels : Array Data.Label) : Array Data.Label :=
  labels.qsort fun a b => a.toString < b.toString

def InferredDeps.merge (current incoming : InferredDeps) : InferredDeps :=
  {
    statement := incoming.statement.foldl Data.Label.pushUnique current.statement
    proof := incoming.proof.foldl Data.Label.pushUnique current.proof
  }

private def automaticUseRefs (labels : Array Data.Label) : Array Data.UseRef :=
  (sortLabels labels).foldl (init := #[]) fun acc label =>
    Data.UseRef.pushMergeByLabel acc (automaticUseRef label)

private def removeSelfLabel (currentLabel? : Option Data.Label) (labels : Array Data.Label) :
    Array Data.Label :=
  match currentLabel? with
  | none => labels
  | some currentLabel => labels.filter (· != currentLabel)

def InferredDeps.toUseRefs (deps : InferredDeps)
    (statementManual : Array Data.UseRef := #[]) (currentLabel? : Option Data.Label := none) :
    InferredUseRefs :=
  let statementLabels := removeSelfLabel currentLabel? deps.statement
  let proofLabels := removeSelfLabel currentLabel? deps.proof
  -- Keep both authorities until contribution validation. Effective-edge
  -- precedence must not hide automatic conflicts from later contributions.
  let statement := automaticUseRefs statementLabels ++ statementManual
  let statementLabels := Data.UseRef.labels statement
  let proofLabels := proofLabels.filter fun label => !statementLabels.contains label
  {
    statement
    proof := automaticUseRefs proofLabels
  }

private def bodyConstants (info : ConstantInfo) : Array Name :=
  match info with
  | .defnInfo info => info.value.getUsedConstants
  | .thmInfo info => info.value.getUsedConstants
  | .opaqueInfo info => info.value.getUsedConstants
  | .ctorInfo info => info.type.getUsedConstants
  | .recInfo info => info.type.getUsedConstants
  | .inductInfo info => info.ctors.toArray
  | .axiomInfo _ | .quotInfo _ => #[]

/-- Constructor types are the root inductive's own body, not helper expansion.
Keep direct-only inference for inductive roots while respecting any explicit
constructor associations supplied through the contribution API. -/
private def rootBodyConstants (info : ConstantInfo) : CoreM (Array Name) := do
  let .inductInfo info := info | return bodyConstants info
  let mut constants := #[]
  for ctor in info.ctors do
    if !(← Environment.labelsForLeanDecl ctor).isEmpty then
      constants := constants.push ctor
    else if let some ctorInfo := (← getEnv).find? ctor then
      constants := constants ++ ctorInfo.type.getUsedConstants
  return constants

/--
The Blueprint frontier of a declaration graph, following LeanArchitect's
`CollectUsed` boundary: associated declarations and unassociated axioms are
leaves. Unlike its collector, this returns labels only, not axiom/status evidence.
An explicit worklist avoids recursion-depth limits on long helper chains.
Visited names are local to this walk: later associations must never reuse stale
cached frontiers. The root is reserved to prevent self references crossing axes.
-/
private def frontierLabels (root : Name) (seeds : Array Name)
    (mayExpand : Name → Bool) : CoreM (Array Data.Label) := do
  let env ← getEnv
  let mut pending := seeds
  let mut visited : NameSet := ({} : NameSet).insert root.eraseMacroScopes
  let mut labels : NameSet := {}
  while !pending.isEmpty do
    Core.checkSystem "Blueprint dependency inference"
    let decl := pending.back!.eraseMacroScopes
    pending := pending.pop
    if visited.contains decl then
      continue
    visited := visited.insert decl
    let associated ← Environment.labelsForLeanDecl decl
    if !associated.isEmpty then
      for label in associated do
        labels := labels.insert label
      continue
    if !mayExpand decl then
      continue
    match env.find? decl with
    | none | some (.axiomInfo _) | some (.quotInfo _) => pure ()
    | some info =>
      pending := pending ++ info.type.getUsedConstants ++ bodyConstants info
  return sortLabels labels.toArray

def infer (decl : Name) (info : ConstantInfo) : CoreM InferredDeps := do
  let decl := decl.eraseMacroScopes
  let mayExpand := (← getHelperExpansion).permits
  let statement ← frontierLabels decl info.type.getUsedConstants mayExpand
  let proof ← frontierLabels decl (← rootBodyConstants info) mayExpand
  return { statement, proof }

def inferDecl? (decl : Name) : CoreM InferredDeps := do
  let decl := decl.eraseMacroScopes
  match (← getEnv).find? decl with
  | some info => infer decl info
  | none => pure {}

def inferDecls (decls : Array Name) : CoreM InferredDeps :=
  decls.foldlM (init := {}) fun acc decl => do
    return acc.merge (← inferDecl? decl)

def inferExternalRefs (refs : Array Data.ExternalRef) : CoreM InferredDeps :=
  inferDecls (refs.filter (·.present) |>.map (·.canonical))

end DependencyAnalysis

end Informal
