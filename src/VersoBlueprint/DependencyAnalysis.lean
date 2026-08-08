/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Environment

/-!
LeanArchitect-style automatic dependency inference for Verso Blueprint.

LeanArchitect recursively expands untagged Lean constants until it reaches
blueprint nodes. Verso Blueprint uses a document-first variant: it scans direct
constants from compiled declarations and maps each associated Lean declaration
to its Blueprint labels.
-/

namespace Informal

open Lean

namespace DependencyAnalysis

register_option verso.blueprint.autoDeps : Bool := {
  defValue := false
  descr := "Enable automatic Blueprint dependency inference by default"
}

/--
Dependency labels inferred from a compiled Lean declaration.

The analysis is intentionally direct: it scans constants mentioned by the
declaration's type and body, but it does not recursively expand untagged helper
declarations. Untagged constants are implementation details unless authors tag
them with `@[blueprint]` or add a manual dependency edge.
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
  let statement := Data.UseRef.mergeByLabel (automaticUseRefs statementLabels) statementManual
  let statementLabels := Data.UseRef.labels statement
  let proofLabels := proofLabels.filter fun label => !statementLabels.contains label
  {
    statement
    proof := automaticUseRefs proofLabels
  }

private def directLabelsForExpr (root : Name) (expr : Expr) : CoreM (Array Data.Label) := do
  let root := root.eraseMacroScopes
  expr.getUsedConstants.foldlM (init := #[]) fun labels decl => do
    let decl := decl.eraseMacroScopes
    if decl == root then
      return labels
    else
      let declLabels ← Environment.labelsForLeanDecl decl
      return declLabels.foldl Data.Label.pushUnique labels

private def directBodyLabels (root : Name) (info : ConstantInfo) : CoreM (Array Data.Label) := do
  match info with
  | .axiomInfo _ => return #[]
  | .defnInfo info => directLabelsForExpr root info.value
  | .thmInfo info => directLabelsForExpr root info.value
  | .opaqueInfo info => directLabelsForExpr root info.value
  | .quotInfo _ => return #[]
  | .ctorInfo info => directLabelsForExpr root info.type
  | .recInfo info => directLabelsForExpr root info.type
  | .inductInfo info =>
    info.ctors.foldlM (init := #[]) fun labels ctor => do
      match (← getEnv).find? ctor with
      | some (.ctorInfo ctorInfo) =>
        let ctorLabels ← directLabelsForExpr root ctorInfo.type
        return ctorLabels.foldl Data.Label.pushUnique labels
      | _ => return labels

def infer (decl : Name) (info : ConstantInfo) : CoreM InferredDeps := do
  let decl := decl.eraseMacroScopes
  let statement ← directLabelsForExpr decl info.type
  let proof ← directBodyLabels decl info
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

private def payloadWithUseRefs
    (ref : Syntax) (useRefs : Array Data.UseRef) (current? : Option Data.InformalData) :
    Option Data.InformalData :=
  if useRefs.isEmpty then
    current?
  else
    match current? with
    | some payload =>
      some (payload.withMergedDeps useRefs)
    | none =>
      some { stx := ref, deps := useRefs }

def attachInferredUseRefs (label : Data.Label) (ref : Syntax) (useRefs : InferredUseRefs) :
    CoreM Unit := do
  if useRefs.statement.isEmpty && useRefs.proof.isEmpty then
    pure ()
  else
    Environment.modifyDataForLabel label fun data => do
      let data :=
        match data.get? label with
        | some node =>
          let statement := payloadWithUseRefs ref useRefs.statement node.statement
          let proof := payloadWithUseRefs ref useRefs.proof node.proof
          data.insert label { node with statement, proof }
        | none =>
          let statement := payloadWithUseRefs ref useRefs.statement none
          let proof := payloadWithUseRefs ref useRefs.proof none
          data.insert label { statement, proof }
      return data

end DependencyAnalysis

end Informal
