/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintGraph.Shared

namespace Verso.VersoBlueprintTests.BlueprintGraph.Groups

open Lean
open Informal.Commands
open Informal.Graph
open Verso.VersoBlueprintTests.BlueprintGraph.Shared

def groupedGraphInput : Informal.Commands.Graph := #[
  {
    label := `ga_stmt
    deps := #[`gb_source]
    proofDeps := #[]
    parent? := some `group_alpha
    shape := "ellipse"
    fillcolor := proofBackgroundFormalizedColor
    color := statementBorderFormalizedColor
    fontcolor := "#111827"
  },
  {
    label := `ga_proof
    deps := #[]
    proofDeps := #[`gb_source]
    parent? := some `group_alpha
    shape := "ellipse"
    fillcolor := proofBackgroundReadyColor
    color := statementBorderReadyColor
    fontcolor := "#111827"
  },
  {
    label := `gb_source
    deps := #[]
    proofDeps := #[]
    parent? := some `group_beta
    shape := "box"
    fillcolor := proofBackgroundFormalizedAncColor
    color := statementBorderFormalizedColor
    fontcolor := "#ffffff"
  },
  {
    label := `gb_aux
    deps := #[]
    proofDeps := #[]
    parent? := some `group_beta
    shape := "ellipse"
    fillcolor := proofBackgroundFormalizedColor
    color := statementBorderFormalizedColor
    fontcolor := "#111827"
  }
]

def groupedGraphTitles : Array (Name × String) := #[
  (`group_alpha, "Readable Alpha Group Title"),
  (`group_beta, "Readable Beta Source Group")
]

def groupedGraphTitleMap : Lean.NameMap String :=
  groupedGraphTitles.foldl (init := ({} : Lean.NameMap String)) fun acc (group, title) =>
    acc.insert group title

def groupedOverview : Informal.Commands.Graph :=
  Informal.Commands.mkParentOverviewGraph groupedGraphInput #[`group_alpha, `group_beta] groupedGraphTitleMap

def groupedVariants : Array Informal.Commands.GraphRenderVariant :=
  Informal.Commands.mkGraphVariants
    { graph := groupedGraphInput, options := { direction := .TB, pack := true }, groupTitles := groupedGraphTitles }
    (fun _ => none)
    groupedGraphTitleMap

/-- info: true -/
#guard_msgs in
#eval
  hasNodeWith groupedOverview `group_alpha (fun n =>
    n.shape == "tab" &&
    n.displayLabel? == some (Informal.Commands.graphParentDisplayLabel groupedGraphTitleMap `group_alpha) &&
    n.deps.contains `group_beta &&
    n.proofDeps.contains `group_beta &&
    n.tooltip?.getD "" == "Group View: Readable Alpha Group Title (2 nodes)")

/-- info: true -/
#guard_msgs in
#eval
  match groupedVariants.find? (·.key == Informal.Commands.groupVariantKey) with
  | none => false
  | some variant =>
    let expectedId := graphNodeSvgId `group_alpha
    let expectedLabel := escapeDotString (Informal.Commands.graphParentDisplayLabel groupedGraphTitleMap `group_alpha)
    variant.selectOnNodeId.contains (expectedId, Informal.Commands.parentVariantKey `group_alpha) &&
    variant.hoverOnNodeId.contains (expectedId, Informal.Commands.parentVariantKey `group_alpha) &&
    variant.dot.contains s!"id=\"{expectedId}\"" &&
    variant.dot.contains s!"label=\"{expectedLabel}\"" &&
    !variant.dot.contains "label=\"group_alpha\""

/-- info: true -/
#guard_msgs in
#eval
  Informal.Commands.graphDotHeader |>.contains "pack=false;"

/-- info: true -/
#guard_msgs in
#eval
  Informal.Commands.graphDotHeader { direction := .TB, pack := true } |>.contains "pack=true;"

end Verso.VersoBlueprintTests.BlueprintGraph.Groups
