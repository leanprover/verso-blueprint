/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Summary.Order
meta import VersoBlueprint.Commands.Summary.Order

namespace VersoBlueprintModuleTests.SummaryData

open Lean

private meta def priorityItems : Array Informal.Commands.PriorityItem := #[
  {
    label := `module.low
    kind := "theorem"
    stage := "proof"
    priority := "low"
    statementStatus := "complete"
    directUses := 10
  },
  {
    label := `module.high
    kind := "lemma"
    stage := "statement"
    priority := "high"
    statementStatus := "pending"
  },
  {
    label := `module.medium
    kind := "definition"
    stage := "proof"
    priority := "medium"
    statementStatus := "complete"
  }
]

local macro "summaryPriorityOrderContract" : term => do
  let labels :=
    Informal.Commands.sortPriorityItems priorityItems |>.map (·.label)
  return quote labels

/-- info: true -/
#guard_msgs in
#eval
  let priorityLabels : Array Name := summaryPriorityOrderContract
  let usageItems : Array Informal.Commands.UsageItem := #[
    { label := `module.lessUsed, kind := "lemma", directUses := 2 },
    { label := `module.moreUsed, kind := "theorem", directUses := 7 }
  ]
  let usageLabels := Informal.Commands.sortUsageItems usageItems |>.map (·.label)
  let summary : Informal.Commands.Summary := {
    totalEntries := 3
    theorems := 1
    lemmas := 1
    definitions := 1
  }
  priorityLabels == #[`module.high, `module.medium, `module.low] &&
    usageLabels == #[`module.moreUsed, `module.lessUsed] &&
    match (fromJson? (toJson summary) : Except String Informal.Commands.Summary) with
    | .ok decoded =>
        decoded.totalEntries == 3 && decoded.theorems == 1 &&
          decoded.lemmas == 1 && decoded.definitions == 1
    | .error _ => false

end VersoBlueprintModuleTests.SummaryData
