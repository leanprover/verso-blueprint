/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintGraph.Shared
import VersoBlueprint
import VersoBlueprint.Widget

namespace Verso.VersoBlueprintTests.BlueprintGraph.Legend

open Informal Informal.Graph
open Lean Verso.Genre

def legendGroupByKey (groups : Array LegendGroup) (key : String) : Option LegendGroup :=
  groups.find? (·.key == key)

def legendItemByLabel (group : LegendGroup) (label : String) : Option LegendItem :=
  group.items.find? (·.label == label)

def defaultLegend : Array LegendGroup := graphLegendGroups false
def legendWithMathlib : Array LegendGroup := graphLegendGroups true
def groupLegend : Array LegendGroup := groupGraphLegendGroups

/-- info: true -/
#guard_msgs in
#eval
  let hasMathlibLabel : Bool :=
    defaultLegend.any fun group => (group.items.any (·.label == "In Mathlib"))
  let hasIncompleteProofLabel : Bool :=
    defaultLegend.any fun group => (group.items.any (·.label == proofStatusIncompleteText))
  let hasUnassessedStatementLabel : Bool :=
    defaultLegend.any fun group => (group.items.any (·.label == statementStatusUnassessedText))
  let hasUnassessedProofLabel : Bool :=
    defaultLegend.any fun group => (group.items.any (·.label == proofStatusUnassessedText))
  let hasUpdatedProofLabel : Bool :=
    defaultLegend.any fun group => (group.items.any (·.label == proofStatusFormalizedAncestorsText))
  let warningHasOnlyUnknownReference : Bool :=
    defaultLegend.any fun group => group.title == "Warning Markers" &&
      group.items.map (·.label) == #["Unknown reference"]
  let hasUpdatedDashedText : Bool :=
    defaultLegend.any fun group => (group.items.any (·.label == "Dashed: statement deps from box-shaped sources"))
  !hasMathlibLabel && hasIncompleteProofLabel && hasUnassessedStatementLabel &&
    hasUnassessedProofLabel && hasUpdatedProofLabel &&
    warningHasOnlyUnknownReference && hasUpdatedDashedText

/-- info: true -/
#guard_msgs in
#eval
  legendWithMathlib.any fun group => (group.items.any (·.label == "In Mathlib"))

/-- info: true -/
#guard_msgs in
#eval
  match legendGroupByKey defaultLegend "proof" with
  | none => false
  | some proofGroup =>
    match legendItemByLabel proofGroup proofStatusIncompleteText with
    | none => false
    | some item =>
      match item.swatch? with
      | none => false
      | some swatch =>
        swatch.background == proofBackgroundIncompleteColor &&
        proofStatusIncompleteText == "Lean code incomplete" &&
        !(proofGroup.items.any (·.label == proofStatusReadyText))

/-- info: true -/
#guard_msgs in
#eval
  match legendGroupByKey groupLegend "group-edge" with
  | none => false
  | some edgeGroup =>
    edgeGroup.items.any (·.label == groupEdgeMixedText) &&
    graphLegendGroupViewNote.contains "tab-shaped"

#docs (Manual) widgetLegendDoc "Widget graph legend" :=
:::::::
:::group "widget.legend.group"
Shared Widget Fixture
:::

:::theorem "widget.legend.leaf" (parent := "widget.legend.group")
One member of the group.
:::

:::theorem "widget.legend.root" (parent := "widget.legend.group") (uses := "widget.legend.leaf")
The other member uses the first.
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show Lean.Elab.Term.TermElabM Bool from do
    let root ← buildFor (Name.mkSimple "widget.legend.root")
    let leaf ← buildFor (Name.mkSimple "widget.legend.leaf")
    let full : Legend := { kind := "full", note := graphLegendFullViewNote, groups := defaultLegend }
    let group : Legend := { kind := "group", note := graphLegendGroupViewNote, groups := groupLegend }
    pure (!root.dot.isEmpty && root.legends == toJson #[full, group] &&
      !leaf.dot.isEmpty && leaf.legends == toJson #[full])

end Verso.VersoBlueprintTests.BlueprintGraph.Legend
