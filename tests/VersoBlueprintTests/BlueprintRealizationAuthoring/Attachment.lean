/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintRealizationAuthoring.Owner

open Lean Elab Command Informal
open Realizations

namespace VersoBlueprintTests.BlueprintRealizationAuthoring.Attachment

def context : Realizations.Context := ⟨`rocq, `TranslationHarnessReuse⟩
def source : DocumentKey := ⟨context, "tests/fixtures/realizations/rocq/Flag.v"⟩
def config : DocumentKey := ⟨context, "tests/fixtures/realizations/rocq/_RocqProject"⟩
def reference : ObjectKey := ⟨context, "TranslationHarnessReuse.Flag.toggle_involutive"⟩
def batch : Environment.AuthoredBatch := {
  sources := #[source, config]
  references := #[(reference, some source)]
  realizations := #[{
    key := Owner.rocqKey, context
    role := `statement
    documents := #[source, config]
    declarations := #[{ object := reference, projection := .statement }] }] }

run_cmd liftCoreM do
  let before ← Environment.stagedAuthoring
  match ← Environment.stageAuthored `notEnrolled batch with
  | .error issues => unless issues.any (·.code == "missing-project") do throwError "Wrong project diagnostic"
  | .ok _ => throwError "Importing Owner implicitly enrolled Attachment"
  unless decide (before = (← Environment.stagedAuthoring)) do throwError "Failed stage changed buffers"

run_cmd liftCoreM <| Realizations.Authoring.configureProject Owner.projectName
run_cmd liftCoreM <| Realizations.Authoring.stage `rocq batch
run_cmd liftCoreM <| Realizations.Authoring.stage `rocq batch

-- First capture exposes the exact binding for the source-authored review slot.
-- A test-only review is then authored with that binding and selected explicitly;
-- it never stands in for the real native proof checks or Rocq source resolution.
run_cmd do
  let binding ← liftTermElabM do
    let initial ← Realizations.Capture.capture
    let registry ← match initial with
      | .ok snapshot => pure snapshot.registry
      | .error issues => throwError "Complete authoring batch did not capture: {repr issues}"
    unless (registry.resultFor (.translation Owner.versoLink)).status == .pending &&
        registry.reviewSelections.all (·.requirement != Owner.versoReview) do
      throwError "A review slot without an authored judgment must remain pending"
    let some binding := registry.bindingFor Owner.versoReview
      | throwError "The complete staged model has no binding for the Verso review slot"
    pure binding
  let reviewId := `mockVersoCorrespondence
  liftCoreM <| Realizations.Authoring.stage `mockReviewEvidence {
    reviews := #[{
      id := reviewId, requirement := Owner.versoReview, binding
      observation := {
        criterion := `statementCorrespondence, reviewer := `MockReviewer
        outcome := .passed, explanation := "MOCK test review; not human evidence" } }]
    reviewSelections := #[
      { requirement := Owner.versoReview, judgment := some reviewId },
      { requirement := Owner.rocqReview, judgment := none }] }

run_cmd liftTermElabM do
  let captured ← Realizations.Capture.capture
  let registry ← match captured with
    | .ok snapshot => pure snapshot.registry
    | .error issues => throwError "Complete reviewed authoring batch did not capture: {repr issues}"
  unless registry.reviewSelections.any (fun selection =>
      selection.requirement == Owner.versoReview && selection.judgment == some `mockVersoCorrespondence) &&
      registry.reviewSelections.any (fun selection =>
      selection.requirement == Owner.rocqReview && selection.judgment.isNone) do
    throwError "Authored review selections were not retained by complete capture"
  unless (registry.resultFor (.realization Owner.leanProofKey)).complete do
    throwError "The source-authored review selection changed the native proof result"
  unless (registry.resultForRequirement Owner.versoReview).complete &&
      (registry.resultFor (.translation Owner.versoLink)).complete &&
      (registry.resultFor (.translation Owner.rocqLink)).status == .blocked do
    throwError "Selected mock correspondence approval or unsupported Rocq resolution was misreported"

end VersoBlueprintTests.BlueprintRealizationAuthoring.Attachment
