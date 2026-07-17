/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintGraph.Shared

namespace Verso.VersoBlueprintTests.BlueprintGraph.Groups

open Lean
open Informal.Graph
open Verso.VersoBlueprintTests.BlueprintGraph.Shared

def groupedGraphInput : Informal.Graph.Graph String := #[
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

def groupedOverview : Informal.Graph.Graph String :=
  Informal.Graph.mkParentOverviewGraph groupedGraphInput #[`group_alpha, `group_beta] groupedGraphTitleMap

def groupedNodeData (node : Informal.Graph.GraphNode String) : Informal.Graph.NodeData := {
  label := node.label
  title := node.displayLabel
  displayLabel := node.displayLabel
  parent := node.parent?
  statementUses := node.deps.map fun label => { label }
  proofUses := node.proofDeps.map fun label => { label }
  visual := Informal.Graph.NodeVisual.ofGraphNode node
}

def groupedGraphModel : Informal.Graph.GraphModel := {
    nodes := groupedGraphInput.map groupedNodeData
    groupMetadata := groupedGraphTitles.map fun (label, title) => {
      label
      title
      declared := true
    }
  }

def groupedGraphData : Informal.Graph.GraphData :=
  groupedGraphModel.finish "grouped-test" { direction := .TB, pack := true }

def groupedVariants : Array Informal.Graph.GraphRenderVariant :=
  groupedGraphData.variants

/-- info: true -/
#guard_msgs in
#eval
  hasNodeWith groupedOverview `group_alpha (fun n =>
    n.shape == "tab" &&
    n.displayLabel? == some "Readable Alpha Group Title" &&
    n.deps.contains `group_beta &&
    n.proofDeps.contains `group_beta &&
    n.tooltip?.getD "" == "Group View: Readable Alpha Group Title (2 nodes)")

/-- info: true -/
#guard_msgs in
#eval
  graphNodeSvgId `group_alpha == "bp-node-group-005Falpha" &&
  match groupedVariants.find? (·.key == Informal.Graph.groupVariantKey) with
  | none => false
  | some variant =>
    let expectedId := graphNodeSvgId `group_alpha
    let expectedLabel := escapeDotString "Readable Alpha Group Title"
    let expectedVariantKey := s!"parent:{`group_alpha}"
    variant.selectOnNodeId.contains (expectedId, expectedVariantKey) &&
    variant.hoverOnNodeId.contains (expectedId, expectedVariantKey) &&
    variant.dot.contains s!"id=\"{expectedId}\"" &&
    variant.dot.contains s!"label=\"{expectedLabel}\"" &&
    !variant.dot.contains "label=\"group_alpha\""

/-- info: true -/
#guard_msgs in
#eval
  Informal.Graph.graphDotHeader |>.contains "pack=false;"

/-- info: true -/
#guard_msgs in
#eval
  Informal.Graph.graphDotHeader { direction := .TB, pack := true } |>.contains "pack=true;"

/-- info: true -/
#guard_msgs in
#eval
  groupedGraphData.edges.any (fun edge =>
    edge.source == `gb_source &&
    edge.target == `ga_stmt &&
    edge.axes == #[Informal.Graph.EdgeAxis.statement]) &&
  match groupedGraphData.groups.find? (·.label == `group_alpha) with
  | none => false
  | some group =>
    group.title == "Readable Alpha Group Title" &&
    group.declared &&
    group.children.contains `ga_stmt &&
    group.children.contains `ga_proof

end Verso.VersoBlueprintTests.BlueprintGraph.Groups
