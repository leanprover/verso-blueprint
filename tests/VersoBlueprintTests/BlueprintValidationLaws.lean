/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Validation.Laws

/-! Contract examples for supplied observations. These are explicitly synthetic
checker/reviewer reports, not claims that this test invokes a native provider. -/
namespace VersoBlueprintTests.ValidationLaws
open Lean Informal.Realizations Informal.Validation

private def context : Context := ⟨`lean, `project⟩
private def realization : RealizationKey := ⟨`node, `lean⟩
private def object : ObjectKey := ⟨context, "witness"⟩
private def key : RequirementKey := ⟨.declaration realization object, `body⟩
private def native : Requirement := {
  key, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }
private def checked : CheckObservation := {
  validator := NativeLean.bodyValidator, declaration := some object
  outcome := .passed, coverage := .dependencyClosure }
private def evidence : Evidence := {
  id := `observation, requirement := key, binding := "current", observation := .check checked }

-- Nonvacuity and independent identity/freshness/coverage failures.
#guard evidence.mismatch? native "current" == none
#guard evidence.mismatch? native "changed" == some "stale-content"
#guard ({ evidence with binding := "" }).mismatch? native "" == some "stale-content"
#guard evidence.mismatch? { native with key := { key with name := `other } } "current" ==
  some "wrong-subject"
#guard ({ evidence with observation := .check { checked with coverage := .subject } }).mismatch?
  native "current" == some "insufficient-coverage"

-- Same spelling in another project is a different declaration. A native check
-- also cannot certify a whole realization by omitting its declaration subject.
#guard
  let other := { object with context := ⟨`lean, `otherProject⟩ }
  ({ evidence with observation := .check { checked with declaration := some other } }).mismatch?
    native "current" == some "wrong-check-object"
#guard ({ evidence with observation := .check { checked with declaration := none } }).mismatch?
  native "current" == some "wrong-check-object"
#guard
  let wholeKey := { key with subject := .realization realization }
  ({ evidence with requirement := wholeKey }).mismatch?
    { native with key := wholeKey } "current" == some "wrong-native-subject"

-- Generic named checks deliberately need not identify a declaration.
#guard
  let generic := { native with expected := .check `jointTest }
  ({ evidence with observation := .check {
    checked with validator := `jointTest, declaration := none } }).mismatch? generic "current" == none

private def goal : Goal := ⟨context, "expected proposition fingerprint", #[]⟩
private def proofRequirement : Requirement := {
  key, expected := .proof goal object, coverage := .subject }
private def proofReport : ProofObservation := {
  witness := object, actualType := some goal, outcome := .passed, coverage := .dependencyClosure }
private def proofEvidence : Evidence := { evidence with observation := .proof proofReport }

-- Independent proof contracts require proof evidence with closure coverage even
-- when the requirement asks only for subject coverage.
#guard proofEvidence.mismatch? proofRequirement "current" == none
#guard evidence.mismatch? proofRequirement "current" == some "wrong-evidence-kind"
#guard ({ proofEvidence with observation := .proof { proofReport with coverage := .subject } }).mismatch?
  proofRequirement "current" == some "insufficient-coverage"
#guard ({ proofEvidence with observation := .proof { proofReport with actualType := none } }).mismatch?
  proofRequirement "current" == some "wrong-proof"
#guard
  let other := { goal with fingerprint := "another proposition" }
  ({ proofEvidence with observation := .proof { proofReport with actualType := some other } }).mismatch?
    proofRequirement "current" == some "wrong-proof"
#guard ({ proofEvidence with observation := .proof { proofReport with outcome := .unavailable } }).mismatch?
  proofRequirement "current" == some "validation-unavailable"
#guard ({ proofEvidence with observation := .proof { proofReport with outcome := .notApplicable } }).mismatch?
  proofRequirement "current" == some "not-applicable"

private def reviewRequirement : Requirement := { native with expected := .review `faithful }
private def review : ReviewObservation := {
  criterion := `faithful, reviewer := `reviewer, outcome := .passed, coverage := .dependencyClosure }
#guard ({ evidence with observation := .review review }).mismatch? reviewRequirement "current" == none
#guard ({ evidence with observation := .review { review with reviewer := .anonymous } }).mismatch?
  reviewRequirement "current" == some "wrong-review"
#guard ({ evidence with observation := .review review }).mismatch? proofRequirement "current" ==
  some "wrong-evidence-kind"

-- Consumers obtain logical identity and freshness from successful execution,
-- without an additional naming or provider-correctness premise.
example (e : Evidence) (r : Requirement) (binding : ContentBinding)
    (h : e.mismatch? r binding = none) : e.requirement = r.key ∧ e.binding = binding :=
  ⟨Evidence.accepted_requirement h, (Evidence.accepted_binding h).2⟩

end VersoBlueprintTests.ValidationLaws
