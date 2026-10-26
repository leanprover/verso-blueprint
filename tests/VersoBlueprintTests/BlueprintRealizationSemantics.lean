/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintRealizationSemantics.Owner
import VersoBlueprint.Realizations.Report

/-! Ordinary import/build semantic invalidation control. Native observations are
real. Review observations below are explicitly MOCK test reviews, never persisted
or presented as an actual human correspondence assessment. The optional saved
binding is an ephemeral test control, not a product receipt/import feature. -/

open Lean Elab Command Term Informal Realizations Validation Translations
open FIRSemanticFixture

private def ensure (value : Bool) (message : String) : TermElabM Unit :=
  unless value do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok result => pure result
  | .error error => throwError "Unexpected rejection: {repr error}"

run_cmd liftTermElabM do
  let r ← obtain ((← Realizations.Capture.capture).map (·.registry))
  ensure ((r.resultForRequirement proofKey).complete &&
    (r.resultFor (.translation correspondence)).status == .pending)
    "Actual native validity and unreviewed correspondence must remain separate"
  ensure (!r.bindingInputs.isEmpty) "Ordinary source capture must retain current semantic inputs"
  let mode := (← IO.getEnv "VBP_SEMANTIC_REVIEW_MODE").getD "smoke"
  let path? ← IO.getEnv "VBP_SEMANTIC_REVIEW_CONTROL"
  let keys := #[subjectReview, closureReview]
  let current ← keys.mapM fun key => do
    let some binding := r.bindingFor key | throwError "Missing current semantic binding"
    pure binding
  if mode == "capture" then
    let some path := path? | throwError "Capture needs an explicit test-control path"
    IO.FS.writeFile path (toJson current).compress
  let saved ← if mode == "stale" || mode == "current" then do
      let some path := path? | throwError "Comparison needs an explicit test-control path"
      let json ← obtain (Json.parse (← IO.FS.readFile path))
      obtain (fromJson? (α := Array String) json)
    else pure current
  ensure (saved.size == keys.size) "Wrong test-control shape"
  let moduleName ← getMainModule
  let reviews := keys.mapIdx fun index key => ({
    origin := { id := .num `mockReviewInput index, moduleName }
    value := {
      id := .num `mockReview index, requirement := key, binding := saved[index]!
      observation := .review {
        criterion := `runtimeMeaning, reviewer := `MOCK_REVIEWER, outcome := .passed
        coverage := if index == 0 then .subject else .dependencyClosure } } } : Contribution Evidence)
  let reviewed ← obtain (admit { r.contributions with evidence := r.contributions.evidence ++ reviews })
  ensure ((reviewed.resultForRequirement proofKey).complete) "Fresh native proof must survive semantic review invalidation"
  for key in keys do
    let result := reviewed.localResult key
    if mode == "stale" then
      ensure (!result.complete && result.diagnostics.any (·.code == "stale-content"))
        "Imported semantics changed but an old correspondence review remained current"
    else
      ensure result.complete "Exact current inputs should accept the MOCK test review"
  let report := Report.ofRegistry reviewed
  ensure (!(report.compress.contains "providerSources") && !(report.compress.contains "semanticInputs"))
    "Reports must not export private semantic/build inputs"
  logInfo m!"Semantic binding control {mode}: native complete; both review scopes checked"
