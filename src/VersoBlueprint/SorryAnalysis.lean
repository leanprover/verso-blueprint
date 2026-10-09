/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Std.Data.HashMap.Lemmas
import VersoBlueprint.Data

namespace Informal.Data

open Lean

/-- Whether a declaration has an inspectable body, no body, or a body hidden by import. -/
inductive BodyAccess where
  | available (value : Expr)
  | unavailable
  | absent

/-- The positive own-name convention comes from `Lean.Util.CollectAxioms`:
a genuine checked axiom inserts its own name, while a hidden theorem's public
axiom view retains a precomputed footprint of dependencies. Without positive
kind evidence its body remains unavailable; cached absence grants no coverage. -/
def ConstantInfo.blueprintBodyAccess (name : Name) (info : ConstantInfo)
    (axioms : Array Name) : BodyAccess :=
  match info.value? (allowOpaque := true) with
  | some value => .available value
  | none =>
    match info with
    | .axiomInfo _ => if axioms.contains name then .absent else .unavailable
    | _ => .absent

/-- Actual dependencies read from a checked declaration, with explicit coverage.
Cached positive footprints are observations; cached absence never grants coverage. -/
structure InspectedDeclaration where
  dependencies : Array Name := #[]
  directSorry : Bool := false
  cachedSorry : Bool := false
  unverified : Option VerificationReason := none
deriving Repr, Inhabited

/-- The graph actually inspected by the production absence checker. -/
abbrev InspectedDeclarations := Std.HashMap Name InspectedDeclaration

/-- An inspection certificate must cover the roots and every outgoing edge.
It fails on holes, hidden/missing information, or an open graph boundary. -/
def certifiedNoSorry (roots : Array Name) (declarations : InspectedDeclarations) : Bool :=
  roots.all declarations.contains && declarations.toList.all fun (name, info) =>
    name != ``sorryAx && !info.directSorry && !info.cachedSorry && info.unverified.isNone &&
      info.dependencies.all declarations.contains

/-- One actual dependency edge in the inspected production graph. -/
def InspectedDeclarations.edge (declarations : InspectedDeclarations) (source target : Name) : Prop :=
  ∃ info, declarations[source]? = some info ∧ target ∈ info.dependencies.toList

/-- Reflexive transitive reachability, expressed as membership in every closed
region. This is a specification over the production graph, not another graph model. -/
def InspectedDeclarations.reachable (declarations : InspectedDeclarations) (root target : Name) : Prop :=
  ∀ region : Name → Prop, region root →
    (∀ source target, region source → declarations.edge source target → region target) → region target

/-- The certificate establishes a closed set of inspected, hole-free declarations. -/
theorem certifiedNoSorry_closed (roots : Array Name) (declarations : InspectedDeclarations)
    (h : certifiedNoSorry roots declarations = true) :
    (∀ root ∈ roots.toList, root ∈ declarations) ∧
    (∀ source target, source ∈ declarations → declarations.edge source target → target ∈ declarations) ∧
    (∀ name ∈ declarations, name ≠ ``sorryAx) := by
  have hroots := (Bool.and_eq_true_iff.mp h).1
  have hnodes := (Bool.and_eq_true_iff.mp h).2
  have checked (name : Name) (info : InspectedDeclaration)
      (hget : declarations[name]? = some info) :=
    List.all_eq_true.mp hnodes (name, info)
      (Std.HashMap.mem_toList_iff_getElem?_eq_some.mpr hget)
  constructor
  · intro root hroot
    exact Std.HashMap.contains_iff_mem.mp (List.all_eq_true.mp (by simpa using hroots) root hroot)
  constructor
  · intro source target _ hedge
    obtain ⟨info, hget, hdep⟩ := hedge
    have hdeps := (Bool.and_eq_true_iff.mp (checked source info hget)).2
    exact Std.HashMap.contains_iff_mem.mp (List.all_eq_true.mp (by simpa using hdeps) target hdep)
  · intro name hmem
    obtain ⟨info, hget⟩ := Option.isSome_iff_exists.mp (Std.HashMap.mem_iff_isSome_getElem?.mp hmem)
    have hn := (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp
      (Bool.and_eq_true_iff.mp (checked name info hget)).1).1).1).1
    simpa using hn

/-- Core soundness law: certified completion excludes a reachable sorryAx.
The production checker uses this exact certificate; no negative cache premise
appears in the statement. Extraction uses the ordinary checked Lean declaration API. -/
theorem certifiedNoSorry_not_reachable (roots : Array Name) (declarations : InspectedDeclarations)
    (h : certifiedNoSorry roots declarations = true) (root : Name) (hroot : root ∈ roots.toList) :
    ¬declarations.reachable root ``sorryAx := by
  intro hreach
  obtain ⟨hroots, hclosed, hnoSorry⟩ := certifiedNoSorry_closed roots declarations h
  have hmem := hreach (fun name => name ∈ declarations) (hroots root hroot) hclosed
  exact hnoSorry ``sorryAx hmem rfl

/-- Runtime result of the full inspection, before axis attribution. -/
structure SorryInspection where
  roots : Array Name := #[]
  declarations : InspectedDeclarations := {}
deriving Inhabited

def SorryInspection.isComplete (inspection : SorryInspection) : Bool :=
  certifiedNoSorry inspection.roots inspection.declarations

def SorryInspection.hasSorry (inspection : SorryInspection) : Bool :=
  inspection.declarations.toList.any fun (name, info) =>
    name == ``sorryAx || info.directSorry || info.cachedSorry

def SorryInspection.verificationGaps (inspection : SorryInspection) (location : SorryWhere) :
    Array VerificationGap :=
  inspection.declarations.toList.toArray.filterMap fun (name, info) =>
    info.unverified.map fun reason => { location, declaration := name, reason }

/-- Extract every relevant expression from a checked declaration. Recursor
reduction rules and inductive constructors are included, not only owner types. -/
def declarationExpressions (info : ConstantInfo) : Array Expr :=
  let expressions := #[info.type]
  match info.value? (allowOpaque := true) with
  | some value => expressions.push value
  | none => match info with
    | .recInfo rec => expressions ++ rec.rules.toArray.map (·.rhs)
    | _ => expressions

/-- Inspect one constant. A bodyless axiom view is covered only when positive
own-name evidence identifies a genuine axiom; otherwise it can hide a body.
That convention uses positive kind evidence, never a negative sorry footprint. -/
def inspectDeclaration [Monad m] [MonadEnv m] (name : Name) : m InspectedDeclaration := do
  let some info := (← getEnv).checked.get.find? name
    | return { unverified := some .declarationUnavailable }
  let axioms ← match info with
    | .axiomInfo _ => collectAxioms name
    | _ => pure #[]
  let expressions := declarationExpressions info
  let mut dependencies := expressions.foldl (fun deps expression =>
    deps ++ expression.getUsedConstants) #[]
  let directSorry := dependencies.contains ``sorryAx
  if let .inductInfo induct := info then
    dependencies := dependencies ++ induct.ctors.toArray
  if let .recInfo rec := info then
    dependencies := dependencies ++ rec.all.toArray ++ rec.rules.toArray.map (·.ctor)
  let unverified :=
    if expressions.any (fun expression => expression.hasMVar || expression.hasFVar) then
      some .uncheckedExpression
    else match ConstantInfo.blueprintBodyAccess name info axioms with
      | .unavailable => some .bodyUnavailable
      | _ => none
  return {
    dependencies
    directSorry
    cachedSorry := axioms.contains ``sorryAx
    unverified
  }

/-- Cache of actual declaration views within one stable environment inspection.
It stores graph nodes, not premature empty closure results for recursive names. -/
abbrev SorryInspectionM (m : Type → Type) := StateT InspectedDeclarations m

/-- Breadth-first inspection of actual checked dependencies. In blocker-search
mode, stop at the first observed hole or verification failure. Partial graphs
never certify absence: `isComplete` still requires closed coverage of every edge.
Full mode collects the entire closure, including cycles, before certification. -/
partial def inspectSorryDependencies [Monad m] [MonadEnv m] (roots : Array Name)
    (stopAtBlocker : Bool := false) : SorryInspectionM m SorryInspection := do
  let declarations ← visit { dList := roots.toList } {}
  return { roots, declarations }
where
  visit (pending : Std.Queue Name) (declarations : InspectedDeclarations) :
      SorryInspectionM m InspectedDeclarations := do
    match pending.dequeue? with
    | none => return declarations
    | some (name, pending) =>
      if declarations.contains name then return ← visit pending declarations
      let cache ← get
      let info ← match cache[name]? with
        | some info => pure info
        | none =>
          let info ← inspectDeclaration name
          modify (·.insert name info)
          pure info
      let declarations := declarations.insert name info
      if stopAtBlocker && (name == ``sorryAx || info.directSorry ||
          info.cachedSorry || info.unverified.isSome) then
        return declarations
      let pending := info.dependencies.foldl (fun queue dep => queue.enqueue dep) pending
      visit pending declarations

end Informal.Data
