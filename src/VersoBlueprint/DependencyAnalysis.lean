/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Environment
import VersoBlueprint.Validation.Lean

/-!
Automatic dependency inference for Verso Blueprint.

Walks compiled declaration types and bodies through unassociated helpers,
stopping at the first Blueprint-associated declarations on each path. Helper
expansion is enabled by default and can be disabled for direct-only inference. Associations are
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

register_option verso.blueprint.autoDeps.expandUntagged : Bool := {
  defValue := true
  descr := "Infer dependencies through Lean declarations without Blueprint associations, stopping at associated declarations; false inspects direct references only. Requires autoDeps to be enabled."
}

/-- Blueprint labels reached from the type and value of one compiled declaration,
before assigning a source realization or a target requirement. -/
structure DeclarationReferences where
  type : Array Data.Label := #[]
  body : Array Data.Label := #[]
deriving Inhabited, Repr

def enabled (opts : Options) (local? : Option Bool) : Bool :=
  local?.getD (verso.blueprint.autoDeps.get opts)

def automaticUseRef (label : Data.Label) : Data.UseRef :=
  { label, origin := .automatic }

def sortLabels (labels : Array Data.Label) : Array Data.Label :=
  labels.qsort fun a b => a.toString < b.toString

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
    (expandHelpers : Bool) : CoreM (Array Data.Label) := do
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
    if !expandHelpers then
      continue
    match env.find? decl with
    | none | some (.axiomInfo _) | some (.quotInfo _) => pure ()
    | some info =>
      pending := pending ++ info.type.getUsedConstants ++ bodyConstants info
  return sortLabels labels.toArray

def infer (decl : Name) (info : ConstantInfo) : CoreM DeclarationReferences := do
  let decl := decl.eraseMacroScopes
  let expandHelpers := verso.blueprint.autoDeps.expandUntagged.get (← getOptions)
  let type ← frontierLabels decl info.type.getUsedConstants expandHelpers
  let body ← frontierLabels decl (← rootBodyConstants info) expandHelpers
  return { type, body }

def inferDecl? (decl : Name) : CoreM DeclarationReferences := do
  let decl := decl.eraseMacroScopes
  match (← getEnv).find? decl with
  | some info => infer decl info
  | none => pure {}

/-- Attach each use to the checked role that supplies its content. A data
implementation owns both axes. A proposition definition's value supplies its
statement. A proof-valued declaration has distinct type and proof obligations. -/
private def inferUses (label decl : Name) (info : ConstantInfo) : CoreM (Array SourceData.UseDeclaration) := do
  let refs ← infer decl info
  if refs.type.isEmpty && refs.body.isEmpty then return #[]
  let roles ← Validation.NativeLean.declarationRoles info
  let typeOwner := if roles.contains `implementation then `implementation else `statement
  let bodyOwner := if roles.contains `proof then `proof else typeOwner
  let uses (owner axis : Name) (targets : Array Data.Label) :=
    let source := (Realizations.RealizationKey.forRole ⟨label, `lean⟩ owner).name
    SourceData.usesFor label (some source) axis ((targets.filter (· != label)).map automaticUseRef)
  let typeUses := uses typeOwner `statement refs.type
  let bodyUses := uses bodyOwner (if bodyOwner == `statement then `statement else `proof) refs.body
  return typeUses ++ bodyUses

def inferDeclUses (label : Name) (decls : Array Name) : CoreM (Array SourceData.UseDeclaration) := do
  let env ← getEnv
  let mut uses := #[]
  let mut seen : Std.HashSet (Option Name × Name × Name) := {}
  for decl in decls do
    let name := decl.eraseMacroScopes
    if let some info := env.find? name then
      for use in ← inferUses label name info do
        let key := (use.realization, use.role, (use.reference.label : Name))
        unless seen.contains key do
          seen := seen.insert key
          uses := uses.push use
  return uses.qsort fun a b => a.reference.label.toString < b.reference.label.toString

end DependencyAnalysis

end Informal
