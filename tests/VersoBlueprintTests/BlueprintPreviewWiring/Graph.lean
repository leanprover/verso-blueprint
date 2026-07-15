/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.Graph

open Verso
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

set_option doc.verso true

#docs (Genre.Manual) lrDirectionGraphDoc "Blueprint LR Direction Graph" :=
:::::::
:::definition "def:graph.lr.base"
Base statement for an explicit left-to-right graph.
:::

{blueprint_graph (direction := LR) (pack := false)}
:::::::

#docs (Genre.Manual) hoverPreviewGraphDoc "Blueprint Hover Preview Graph" :=
:::::::
:::definition "def:graph.hover.base"
Base statement for an explicit hover-preview graph with the default docked panel.
:::

{blueprint_graph (preview := hover)}
:::::::

#docs (Genre.Manual) anchoredHoverPreviewGraphDoc "Blueprint Anchored Hover Preview Graph" :=
:::::::
:::definition "def:graph.hover.anchored.base"
Base statement for an explicit anchored hover-preview graph.
:::

{blueprint_graph (preview := hover) (previewPlacement := anchored)}
:::::::

set_option verso.blueprint.graph.defaultPreviewMode "hover" in
#docs (Genre.Manual) optionHoverPreviewGraphDoc "Blueprint Option Hover Preview Graph" :=
:::::::
:::definition "def:graph.option.hover.base"
Base statement for graph preview mode option coverage.
:::

{blueprint_graph}
:::::::

#guard (Informal.Commands.parseGraphPreviewMode? "hover").map (·.dataValue) == some "hover"
#guard (Informal.Commands.parseGraphPreviewMode? "pinned").map (·.dataValue) == some "pinned"
#guard (Informal.Commands.parseGraphPreviewMode? "transient").isNone
#guard (Informal.Commands.parseGraphPreviewMode? "click").isNone
#guard (Informal.Commands.parseGraphPreviewMode? "click-to-pin").isNone
#guard (Informal.Commands.parseGraphPreviewPlacement? "docked").map (·.dataValue) == some "docked"
#guard (Informal.Commands.parseGraphPreviewPlacement? "anchored").map (·.dataValue) == some "anchored"
#guard (Informal.Commands.parseGraphPreviewPlacement? "fixed").isNone
#guard (Informal.Commands.parseGraphPreviewPlacement? "near-node").isNone
#guard
  Informal.Commands.fallbackGraphControlId (default : Verso.Multi.InternalId) "--view" ==
    "bp-graph--0023-003C0-003E--view"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls previewWiringDoc
    let graphJs? := findGraphPreviewJs? st
    pure (
      hasSubstr out "bp_graph_preview" &&
      hasSubstr out "class=\"bp_graph_preview bp_preview_panel\"" &&
      hasSubstr out "data-bp-preview-mode=\"pinned\"" &&
      hasSubstr out "data-bp-preview-placement=\"docked\"" &&
      hasSubstr out "class=\"bp_graph_controls_select bp_graph_preview_mode_select\"" &&
      hasSubstr out "data-bp-graph-default-preview-mode=\"pinned\"" &&
      hasSubstr out "class=\"bp_graph_controls_select bp_graph_preview_placement_select\"" &&
      hasSubstr out "data-bp-graph-default-preview-placement=\"docked\"" &&
      hasSubstr out "value=\"pinned\"" &&
      hasSubstr out "Click to pin" &&
      hasSubstr out "value=\"hover\"" &&
      hasSubstr out "Hover" &&
      hasSubstr out "value=\"docked\"" &&
      hasSubstr out "Docked" &&
      hasSubstr out "value=\"anchored\"" &&
      hasSubstr out "Near node" &&
      !hasSubstr out "class=\"bp_graph_preview_store\"" &&
      !hasSubstr out "class=\"bp_graph_preview_tpl\"" &&
      hasSubstr out "class=\"bp_group_hover_preview bp_preview_panel\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_header bp_preview_panel_header\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_title bp_preview_panel_title\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_close bp_preview_panel_close\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_graph bp_preview_panel_body\"" &&
      hasSubstr out "aria-label=\"Close group preview\"" &&
      hasSubstr out "class=\"bp-graph-data\"" &&
      hasSubstr out "\"variants\":" &&
      !hasSubstr out "class=\"bp-graph-variants\"" &&
      !hasSubstr out "dot-source" &&
      hasSubstr out "class=\"bp_graph_controls_button bp_graph_options_button\"" &&
      hasSubstr out "class=\"bp_graph_options_popover\"" &&
      hasSubstr out "class=\"bp_graph_controls_select bp_graph_direction_select\"" &&
      hasSubstr out "class=\"bp_graph_pack_input\"" &&
      hasSubstr out "data-bp-graph-direction=\"TB\"" &&
      hasSubstr out "data-bp-graph-pack=\"false\"" &&
      hasSubstr out "data-bp-graph-default-pack=\"false\"" &&
      hasSubstr out "\"options\":{\"direction\":\"TB\",\"pack\":false}" &&
      hasSubstr out "data-bp-tex-prelude-id" &&
      !hasSubstr out "data-bp-tex-prelude=\"" &&
      !hasSubstr out "bp_preview_tex_prelude" &&
      graphJs?.isNone &&
      !hasExtraJs st "window.VersoBlueprint.onRenderReady" &&
      !hasExtraJs st "window.bpGraphApi"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, _) ← renderManualDocHtmlStringAndState manualImpls hoverPreviewGraphDoc
    pure (
      hasSubstr out "data-bp-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-preview-placement=\"docked\"" &&
      hasSubstr out "data-bp-graph-default-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-graph-default-preview-placement=\"docked\"" &&
      hasSubstr out "value=\"pinned\"" &&
      hasSubstr out "Click to pin" &&
      hasSubstr out "value=\"hover\"" &&
      hasSubstr out "Hover" &&
      hasSubstr out "value=\"docked\"" &&
      hasSubstr out "Docked" &&
      hasSubstr out "value=\"anchored\"" &&
      hasSubstr out "Near node"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, _) ← renderManualDocHtmlStringAndState manualImpls anchoredHoverPreviewGraphDoc
    pure (
      hasSubstr out "data-bp-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-preview-placement=\"anchored\"" &&
      hasSubstr out "data-bp-graph-default-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-graph-default-preview-placement=\"anchored\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, _) ← renderManualDocHtmlStringAndState manualImpls optionHoverPreviewGraphDoc
    pure (
      hasSubstr out "data-bp-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-preview-placement=\"docked\"" &&
      hasSubstr out "data-bp-graph-default-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-graph-default-preview-placement=\"docked\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, _) ← renderManualDocHtmlStringAndState manualImpls lrDirectionGraphDoc
    pure (
      hasSubstr out "data-bp-graph-direction=\"LR\"" &&
      hasSubstr out "data-bp-graph-pack=\"false\"" &&
      hasSubstr out "data-bp-graph-default-direction=\"LR\"" &&
      hasSubstr out "data-bp-graph-default-pack=\"false\"" &&
      (hasSubstr out "selected value=\"LR\"" || hasSubstr out "value=\"LR\" selected") &&
      hasSubstr out "\"options\":{\"direction\":\"LR\",\"pack\":false}" &&
      hasSubstr out "rankdir=LR;" &&
      hasSubstr out "pack=false;" &&
      !hasSubstr out "dotByDirection"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_, state) ← renderManualDocHtmlStringAndState manualImpls previewWiringDoc
    let malformedKey := "graph:malformed"
    let state :=
      Informal.TraversalIndex.Graphs.saveId state malformedKey default
        |>.saveDomainObjectData
          Informal.TraversalIndex.Graphs.domainName malformedKey (Lean.Json.str "malformed")
    let errors ← IO.mkRef #[]
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls
      (fun msg => errors.modify (·.push msg)) state
    let errors ← errors.get
    pure <|
      !files.manifest.graphs.isEmpty &&
        errors.any fun msg =>
          hasSubstr msg "Blueprint manifest: malformed graph entry graph:malformed:"

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.Graph
