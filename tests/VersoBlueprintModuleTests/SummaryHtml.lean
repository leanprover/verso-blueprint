/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Summary.Html
meta import VersoBlueprint.Commands.Summary.Html

namespace VersoBlueprintModuleTests.SummaryHtml

open Lean

/-- info: true -/
#guard_msgs in
#eval
  let first : Informal.Commands.IndexItem := {
    label := `module.summary.first
    kind := "definition"
  }
  let second : Informal.Commands.IndexItem := {
    label := `module.summary.second
    kind := "theorem"
  }
  let summary : Informal.Commands.Summary := {
    definitionIndex := [first]
    theoremLikeIndex := [second]
    noDependents := [first]
  }
  let labels := summary.previewLabels
  let card := Informal.Commands.summaryCard "Entries" "2" |>.asString
  Informal.Commands.statusCountsText {
      completed := 1
      completedDepsNo := 2
      withSorries := 3
      noProof := 4
    } == "completed: 1; deps incomplete: 2; sorries: 3; no proof: 4" &&
    labels == #[`module.summary.first, `module.summary.second] &&
    card.contains Informal.Commands.summaryCardClass &&
    card.contains "Entries" && card.contains "2" &&
    Informal.Commands.summaryAssetBundle.css.contains Informal.Commands.summaryCss &&
    Informal.Commands.summaryCss.contains "bp_summary_card"

end VersoBlueprintModuleTests.SummaryHtml
