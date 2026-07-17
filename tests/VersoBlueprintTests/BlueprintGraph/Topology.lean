/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintGraph.Shared

namespace Verso.VersoBlueprintTests.BlueprintGraph.Topology

open Lean
open Informal
open Informal.Data
open Informal.Graph

private def topologyUse (label : Name) (origin : UseOrigin := UseOrigin.manual) : UseRef := {
  label
  origin
}

private def topologyNode
    (label : Name)
    (statementUses : Array UseRef := #[])
    (proofUses : Array UseRef := #[])
    (parent : Option Name := none) : NodeData := {
  label
  title := label.toString
  displayLabel := label.toString
  parent
  statementUses
  proofUses
  visual := { fillcolor := "#ffffff" }
}

/- A wire edge cannot introduce a dependency absent from its target node. -/
/-- info: true -/
#guard_msgs in
#eval
  let finalized :=
    ({ nodes := #[topologyNode `edge_source, topologyNode `edge_target] } : GraphModel)
      |>.finish "inconsistent-edge" {}
  let inconsistent := (toJson finalized).setObjVal! "edges" (toJson #[({
    source := `edge_source
    target := `edge_target
    axes := #[EdgeAxis.statement]
  } : EdgeData)])
  match fromJson? (α := GraphData) inconsistent with
  | .error _ => true
  | .ok _ => false

/- Repeated live/disk-equivalent refs collapse to one semantic mixed-axis edge. -/
/-- info: true -/
#guard_msgs in
#eval
  let live : GraphModel := {
    nodes := #[
      topologyNode `duplicate_source,
      topologyNode `duplicate_target
        #[topologyUse `duplicate_source UseOrigin.automatic,
          topologyUse `duplicate_source UseOrigin.manual]
        #[topologyUse `duplicate_source, topologyUse `duplicate_source]
    ]
  }
  let disk : GraphModel := {
    nodes := #[
      topologyNode `duplicate_source,
      topologyNode `duplicate_target
        #[topologyUse `duplicate_source]
        #[topologyUse `duplicate_source]
    ]
  }
  let finalized := live.mergePreferLeft disk |>.finish "duplicate-edge" {}
  match finalized.nodes.find? (·.label == `duplicate_target), finalized.edges[0]? with
  | some target, some edge =>
      target.statementUses.size == 1 &&
        target.statementUses[0]!.origin == UseOrigin.manual &&
        target.proofUses.size == 1 &&
        finalized.edges.size == 1 &&
        edge.source == `duplicate_source &&
        edge.target == `duplicate_target &&
        edge.axes == #[EdgeAxis.statement, EdgeAxis.proof]
  | _, _ => false

/- Dangling dependencies remain node metadata but do not become graph edges. -/
/-- info: true -/
#guard_msgs in
#eval
  let model : GraphModel := {
    nodes := #[topologyNode `dangling_target #[topologyUse `missing_source]]
  }
  let finalized := model.finish "dangling-edge" {}
  finalized.edges.isEmpty &&
    match finalized.nodes[0]? with
    | some target => target.statementUses.map (·.label) == #[`missing_source]
    | none => false

private def diskGroupModel : GraphModel := {
  nodes := #[
    topologyNode `moved_node (parent := some `disk_group),
    topologyNode `live_group_peer (parent := some `live_group)
  ]
  groupMetadata := #[
    {
      label := `disk_group
      title := "Disk-recorded group"
      declared := true
    },
    {
      label := `live_group
      title := "Live selected group"
      declared := true
    }
  ]
}

/- A preferred live node replaces its disk copy as one unit, including parent. -/
/-- info: true -/
#guard_msgs in
#eval
  let disk := diskGroupModel.finish "disk" {}
  let live : GraphModel := {
    nodes := #[topologyNode `moved_node (parent := some `live_group)]
  }
  let merged := live.mergePreferLeft disk.toModel |>.finish "merged" {}
  match
      merged.groups.find? (·.label == `disk_group),
      merged.groups.find? (·.label == `live_group) with
  | none, some group =>
      group.title == "Live selected group" &&
        group.declared &&
        group.children == #[`moved_node, `live_group_peer]
  | _, _ => false

private def nestedGroupModel : GraphModel := {
  nodes := #[
    topologyNode `inner_group (parent := some `outer_group),
    topologyNode `outer_peer (parent := some `outer_group),
    topologyNode `inner_leaf_a #[topologyUse `outer_peer] (parent := some `inner_group),
    topologyNode `inner_leaf_b (parent := some `inner_group)
  ]
  groupMetadata := #[
    {
      label := `outer_group
      title := "Outer group title"
      declared := true
    },
    {
      label := `inner_group
      title := "Inner group title"
      declared := true
    }
  ]
}

/- Nested group membership is derived at both parent levels and still renders. -/
/-- info: true -/
#guard_msgs in
#eval
  let finalized := nestedGroupModel.finish "nested" {}
  let dot := finalized.variants.find? (·.key == "full") |>.map (·.dot) |>.getD ""
  match
      finalized.groups.find? (·.label == `outer_group),
      finalized.groups.find? (·.label == `inner_group) with
  | some outer, some inner =>
      outer.children == #[`inner_group, `outer_peer] &&
        inner.children == #[`inner_leaf_a, `inner_leaf_b] &&
        dot.contains "Outer group title" &&
        dot.contains "Inner group title"
  | _, _ => false

/- Topology changes happen on GraphModel and finishing regenerates every variant. -/
/-- info: true -/
#guard_msgs in
#eval
  let original : GraphModel := {
    nodes := #[
      topologyNode `old_source,
      topologyNode `new_source,
      topologyNode `variant_target #[topologyUse `old_source]
    ]
  }
  let rendered := original.finish "variants" {}
  let changed : GraphModel := {
    original with
      nodes := original.nodes.map fun (node : NodeData) =>
        if node.label == `variant_target then
          { node with statementUses := #[topologyUse `new_source] }
        else
          node
  }
  let regenerated := changed.finish "variants" {}
  rendered.variants.any (fun variant =>
      variant.key == "full" &&
        variant.dot.contains "\"old_source\" -> \"variant_target\"") &&
    regenerated.variants.any (fun variant =>
      variant.key == "full" &&
        variant.dot.contains "\"new_source\" -> \"variant_target\"" &&
        !variant.dot.contains "\"old_source\" -> \"variant_target\"")

/- A stale serialized variant cannot cross the public GraphData decode boundary. -/
/-- info: true -/
#guard_msgs in
#eval
  let original : GraphModel := {
    nodes := #[
      topologyNode `old_source,
      topologyNode `new_source,
      topologyNode `variant_target #[topologyUse `old_source]
    ]
  }
  let changed : GraphModel := {
    nodes := #[
      topologyNode `old_source,
      topologyNode `new_source,
      topologyNode `variant_target #[topologyUse `new_source]
    ]
  }
  let oldFinished := original.finish "variants" {}
  let changedFinished := changed.finish "variants" {}
  let stale := (toJson changedFinished).setObjVal! "variants" (toJson oldFinished.variants)
  match fromJson? (α := GraphData) stale with
  | .error _ => true
  | .ok _ => false

/- Preview filtering cannot reopen or rewrite finalized topology. -/
/-- info: true -/
#guard_msgs in
#eval
  let retainedKey := "informal:retained_preview:statement"
  let removedKey := "informal:removed_preview:statement"
  let model : GraphModel := {
    nodes := #[
      {
        topologyNode `preview_source with
          previewKey := PreviewKey.ofString? retainedKey
      },
      {
        topologyNode `preview_target #[topologyUse `preview_source]
            (parent := some `preview_group) with
          previewKey := PreviewKey.ofString? removedKey
      }
    ]
    groupMetadata := #[{
      label := `preview_group
      title := "Preview group"
      declared := true
    }]
  }
  let finalized := model.finish "preview-filter" {}
  let filtered := finalized.filterPreviewReferences fun key => key.value == retainedKey
  let nodeTopologyUnchanged :=
    (filtered.nodes.zip finalized.nodes).all fun (after, before) =>
      after.label == before.label &&
        after.statementUses == before.statementUses &&
        after.proofUses == before.proofUses &&
        after.parent == before.parent
  let variantsUnchangedExceptPreview :=
    (filtered.variants.zip finalized.variants).all fun (after, before) =>
      after.key == before.key &&
        after.label == before.label &&
        after.dot == before.dot &&
        after.options == before.options &&
        after.selectOnNodeId == before.selectOnNodeId &&
        after.hoverOnNodeId == before.hoverOnNodeId
  filtered.nodes.size == finalized.nodes.size &&
    filtered.variants.size == finalized.variants.size &&
    nodeTopologyUnchanged &&
    filtered.edges == finalized.edges &&
    filtered.groups == finalized.groups &&
    variantsUnchangedExceptPreview &&
    (match filtered.nodes.find? (·.label == `preview_source) with
      | some node => node.previewKey == PreviewKey.ofString? retainedKey
      | none => false) &&
    (match filtered.nodes.find? (·.label == `preview_target) with
      | some node => node.previewKey.isNone
      | none => false) &&
    (match filtered.variants.find? (·.key == "full") with
      | some variant =>
          variant.previewKeyByNodeId == #[(graphNodeSvgId `preview_source, retainedKey)]
      | none => false) &&
    filtered.variants.all fun variant =>
      variant.previewKeyByNodeId.all fun (_, key) => key == retainedKey

/- Finalized decoding has no obsolete-schema or variant-less compatibility path. -/
/-- info: true -/
#guard_msgs in
#eval
  let finalized := nestedGroupModel.finish "strict-schema" {}
  let obsoleteSchema := (toJson finalized).setObjVal! "schemaVersion" (toJson 2)
  let noVariants := (toJson finalized).setObjVal! "variants" (toJson (#[] : Array GraphRenderVariant))
  finalized.schemaVersion == 3 &&
  (match fromJson? (α := GraphData) obsoleteSchema with
    | .error _ => true
    | .ok _ => false) &&
  (match fromJson? (α := GraphData) noVariants with
    | .error _ => true
    | .ok _ => false)

/- The traversal cache contains only the canonical semantic model and options. -/
/-- info: true -/
#guard_msgs in
#eval
  let cached : CachedGraphData := {
    model := nestedGroupModel.canonicalize
    options := { direction := .LR, pack := true }
  }
  let json := Json.compress (toJson cached)
  json.contains "\"model\"" &&
    json.contains "\"groupMetadata\"" &&
    !json.contains "\"edges\"" &&
    !json.contains "\"children\"" &&
    !json.contains "\"variants\""

private def edgeMatchesAuthoritativeNode (data : GraphData) (edge : EdgeData) : Bool :=
  data.nodes.any (·.label == edge.source) &&
    match data.nodes.find? (·.label == edge.target) with
    | none => false
    | some target =>
      let statement := target.statementUses.any (fun useRef => useRef.label == edge.source)
      let proof := target.proofUses.any (fun useRef => useRef.label == edge.source)
      edge.axes == edgeAxesForTest statement proof
where
  edgeAxesForTest (statement proof : Bool) : Array EdgeAxis :=
    let axes := if statement then #[EdgeAxis.statement] else #[]
    if proof then axes.push EdgeAxis.proof else axes

private def groupsMatchAuthoritativeParents (data : GraphData) : Bool :=
  data.groups.all fun group =>
    group.children.all fun child =>
      data.nodes.any fun node => node.label == child && node.parent == some group.label

/- JSON round-trip preserves a finalized record whose public projections agree exactly. -/
/-- info: true -/
#guard_msgs in
#eval
  let finalized := nestedGroupModel.finish "nested" {}
  match Lean.fromJson? (α := GraphData) (Lean.toJson finalized) with
  | .error _ => false
  | .ok decoded =>
    match decoded.variants[0]? with
    | none => false
    | some firstVariant =>
      let expected := decoded.toModel.finish decoded.key firstVariant.options
      decoded.edges == expected.edges &&
        decoded.groups == expected.groups &&
        decoded.variants == expected.variants &&
        decoded.edges.all (edgeMatchesAuthoritativeNode decoded) &&
        groupsMatchAuthoritativeParents decoded &&
        decoded.nodes.all fun node =>
          match node.parent with
          | none => true
          | some parent =>
            decoded.groups.any fun group =>
              group.label == parent && group.children.contains node.label

end Verso.VersoBlueprintTests.BlueprintGraph.Topology
