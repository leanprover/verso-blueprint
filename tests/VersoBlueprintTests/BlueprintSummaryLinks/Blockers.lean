/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintSummaryLinks.Shared

namespace Verso.VersoBlueprintTests.BlueprintSummaryLinks.Blockers

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls summaryBlockersDoc
    pure (
      hasSubstr out "Current blockers (2)" &&
      hasSubstr out "Missing external Lean declaration:" &&
      hasSubstr out "Declaration with sorry:" &&
      !hasSubstr out "Incomplete details ("
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let status : Informal.Data.ProvedStatus := .containsSorry
      #[{ location := .proof, origin := .unknown }]
    let model := summaryBlockersDocBlueprint.model
    let model := { model with summary := { model.summary with sorryDetails := [{
      label := Lean.Name.mkSimple "def:blocker.sorry"
      kind := "theorem"
      decl := `Hidden.proof
      isTheorem := true
      status
    }] } }
    let out ← renderManualDocHtmlString manualImpls summaryBlockersDoc (model := model)
    return hasSubstr out "Declaration with detected sorry:" &&
      hasSubstr out "sorry detected; in proof; refs: unknown" &&
      !hasSubstr out "Declaration depending on sorry:"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let status : Informal.Data.ProvedStatus := .containsSorry #[
      { location := .proof }, { location := .proof, origin := .dependency }]
    let model := summaryBlockersDocBlueprint.model
    let model := { model with summary := { model.summary with sorryDetails := [{
      label := Lean.Name.mkSimple "def:blocker.sorry"
      kind := "theorem"
      decl := `Mixed.proof
      isTheorem := true
      status
    }] } }
    let out ← renderManualDocHtmlString manualImpls summaryBlockersDoc (model := model)
    return hasSubstr out "Declaration with sorry:" &&
      hasSubstr out "contains sorry; in proof; refs: unknown"

end Verso.VersoBlueprintTests.BlueprintSummaryLinks.Blockers
