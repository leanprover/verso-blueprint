/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean
import Verso.Instances.Deriving

namespace Informal.Realizations

/-- Serializable projection of an admitted current capture. This is presentation
output, never an input assertion or persisted source authority. The exact assessed
subjects, contracts, observations and selection diagnostics are in `details`.
No native declarations means unassessed, not a failed or implicitly required proof.
An absent assessment at a consumer means uncaptured; legacy source snapshots must
not supply substitute completion. -/
structure NodeAssessment where
  hasNativeDeclarations : Bool := false
  /-- Fresh provider inventory, not a completion or axiom-acceptance policy. -/
  hasAxiomLike : Bool := false
  /-- Local own-declaration statement checks, before Blueprint prerequisites. -/
  nativeStatementComplete : Bool := false
  /-- The selected native declarations have a required proof or implementation check. -/
  hasNativeBodyRequirement : Bool := false
  /-- True when at least one body check applies, every selected declaration has its
  native contract and all selected proof and implementation bodies pass locally. -/
  nativeBodyComplete : Bool := false
  /-- Present when a native proof role is selected. Success requires contract
  coverage for every selected declaration and passing local proof checks. -/
  proofRoleComplete : Option Bool := none
  /-- Generated native requirements with their selected prerequisites. This
  summary does not aggregate correspondence reviews or alternative proofs. -/
  requiredComplete : Bool := false
  /-- Uses selected for ordinary native realizations in their exact contexts,
  including failed target selections. Other realization/context uses remain in
  the full `details.uses` inventory but do not enter its completion checks. -/
  selectedLeanUseCount : Nat := 0
  statementDependenciesComplete : Bool := false
  proofDependenciesComplete : Bool := false
  /-- Safe output only: no source bodies, raw contributions or content bindings. -/
  details : Lean.Json := .null
  deriving Inhabited, BEq, Lean.ToJson

/-- The persisted assessment always supplies every field, including nullable
proof-role coverage and the public inspection details. -/
instance : Lean.FromJson NodeAssessment where
  fromJson? json := do
    let details ← json.getObjVal? "details"
    unless details == .null || details.getObj?.isOk do
      throw "assessment details must be a JSON object or null"
    return {
      hasNativeDeclarations := ← json.getObjValAs? Bool "hasNativeDeclarations"
      hasAxiomLike := ← json.getObjValAs? Bool "hasAxiomLike"
      nativeStatementComplete := ← json.getObjValAs? Bool "nativeStatementComplete"
      hasNativeBodyRequirement := ← json.getObjValAs? Bool "hasNativeBodyRequirement"
      nativeBodyComplete := ← json.getObjValAs? Bool "nativeBodyComplete"
      proofRoleComplete := ← json.getObjVal? "proofRoleComplete" >>= Lean.fromJson?
      requiredComplete := ← json.getObjValAs? Bool "requiredComplete"
      selectedLeanUseCount := ← json.getObjValAs? Nat "selectedLeanUseCount"
      statementDependenciesComplete := ← json.getObjValAs? Bool "statementDependenciesComplete"
      proofDependenciesComplete := ← json.getObjValAs? Bool "proofDependenciesComplete"
      details }

instance : Repr NodeAssessment where
  reprPrec value _ := Std.Format.text (Lean.toJson value).compress

/-- All applicable local checks have passed, before Blueprint prerequisites. -/
def NodeAssessment.nativeLocallyComplete (assessment : NodeAssessment) : Bool :=
  assessment.hasNativeDeclarations && assessment.nativeStatementComplete &&
    (!assessment.hasNativeBodyRequirement || assessment.nativeBodyComplete)

/-- User-facing status of the ordinary native checks and their selected prerequisites. -/
def NodeAssessment.leanRequirementMessage (assessment : NodeAssessment) : String :=
  let status := if !assessment.hasNativeDeclarations then "unassessed"
    else if assessment.requiredComplete then "complete" else "unfinished"
  s!"Native Lean requirements: {status}"

/-- Shared wording for consumers of the typed selection/completion projection. -/
def NodeAssessment.leanDependencyMessage (assessment : NodeAssessment) : String :=
  if assessment.selectedLeanUseCount == 0 then "No Lean prerequisites selected"
  else if assessment.statementDependenciesComplete && assessment.proofDependenciesComplete then
    "Selected Lean prerequisites complete"
  else "Selected Lean prerequisites unfinished"

/-- Status wording shared by the widget and informal block headings. -/
def NodeAssessment.nativeStatusMessage (assessment : NodeAssessment) : String :=
  if !assessment.hasNativeDeclarations then assessment.leanRequirementMessage else
  let statement := if assessment.nativeStatementComplete then "passed" else "unfinished"
  let body := if assessment.hasNativeBodyRequirement then
    if assessment.nativeBodyComplete then "passed" else "unfinished"
    else "not required"
  let classification := if assessment.hasAxiomLike then "Axiom-like declarations present. " else ""
  s!"{classification}Native statement: {statement}. Native body: {body}. " ++
    s!"{assessment.leanRequirementMessage}. {assessment.leanDependencyMessage}."

def NodeAssessment.fromJsonString! (serialized : String) : NodeAssessment :=
  match Lean.Json.parse serialized >>= Lean.fromJson? with
  | .ok value => value
  | .error message => panic! s!"Invalid captured node assessment: {message}"

instance : Lean.Quote NodeAssessment where
  quote value := Lean.Syntax.mkCApp ``NodeAssessment.fromJsonString!
    #[Lean.quote (Lean.toJson value).compress]

end Informal.Realizations

namespace Informal.Graph

open Lean

/-- Upstream-aligned statement-track status (node border). -/
inductive StatementStatus where
  | unassessed
  | blocked
  | ready
  | formalized
  | mathlib
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/-- Upstream-aligned background status (proof-track for theorem-like nodes). -/
inductive ProofStatus where
  | unassessed
  | none
  | incomplete
  | formalized
  | formalizedWithAncestors
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/-- Project native checks and their selected prerequisites onto the compact graph
statuses. Actionability is exported independently of proof status. -/
def statusesForAssessment (assessment : Realizations.NodeAssessment) :
    StatementStatus × ProofStatus := Id.run do
  if !assessment.hasNativeDeclarations then
    return (.unassessed, .unassessed)
  let statement :=
    if assessment.nativeStatementComplete then .formalized
    else if assessment.statementDependenciesComplete then .ready
    else .blocked
  let proof :=
    if assessment.proofRoleComplete == some false then
      .incomplete
    else if assessment.nativeBodyComplete then
      if assessment.statementDependenciesComplete && assessment.proofDependenciesComplete then
        .formalizedWithAncestors
      else
        .formalized
    else
      .none
  return (statement, proof)

/-- A next step is available only after its captured prerequisites are complete.
Prose/cross-language realizations without an authored native check remain
unassessed and do not create an automatic task. -/
def actionableStageForAssessment? (assessment : Realizations.NodeAssessment) : Option String :=
  if !assessment.hasNativeDeclarations then none
  else if !assessment.nativeStatementComplete then
    if assessment.statementDependenciesComplete then some "statement" else none
  else if assessment.hasNativeBodyRequirement && !assessment.nativeBodyComplete then
    if assessment.proofDependenciesComplete then some "proof" else none
  else
    none

end Informal.Graph
