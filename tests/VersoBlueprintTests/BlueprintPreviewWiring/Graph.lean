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

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls previewWiringDoc
    let graphJs? :=
      findExtraJsContaining? st
        "function attachPreviewHandlers(graphBlock, graphContainer, previewMap, previewController, previewKeyByNodeId)"
    pure (
      hasSubstr out "bp_graph_preview" &&
      hasSubstr out "class=\"bp_graph_preview bp_preview_panel\"" &&
      hasSubstr out "data-bp-preview-mode=\"pinned\"" &&
      hasSubstr out "data-bp-preview-placement=\"docked\"" &&
      !hasSubstr out "class=\"bp_graph_preview_store\"" &&
      !hasSubstr out "class=\"bp_graph_preview_tpl\"" &&
      hasSubstr out "class=\"bp_group_hover_preview bp_preview_panel\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_header bp_preview_panel_header\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_title bp_preview_panel_title\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_close bp_preview_panel_close\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_graph bp_preview_panel_body\"" &&
      hasSubstr out "aria-label=\"Close group preview\"" &&
      hasSubstr out "class=\"bp-graph-variants\"" &&
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
      match graphJs? with
      | some graphJs =>
        hasSubstr graphJs "return utils.readPreviewTemplate(entry);" &&
        hasSubstr graphJs "function layoutGraphCanvas(graphRoot, graphState)" &&
        hasSubstr graphJs "function ensureGraphBlockState(graphBlock)" &&
        hasSubstr graphJs "function createPanelController(panel, behavior, titleSelector, bodySelector, options)" &&
        hasSubstr graphJs "function bindHoverablePanelLifetime(previewUtils, controller, getActiveAnchor, boundAttr)" &&
        hasSubstr graphJs "function configurePanelCloseButton(previewUtils, closeButton, hidePanel, behavior)" &&
        hasSubstr graphJs "const previewKey = nodeId ? (previewKeys.get(nodeId) || \"\") : \"\";" &&
        hasSubstr graphJs "previewUtils.loadSharedPreviewEntry(previewKey)" &&
        hasSubstr graphJs "previewUtils.readPanelBehavior(previewPanelNode, { mode: \"pinned\", placement: \"docked\" })" &&
        hasSubstr graphJs "previewUtils.hydratePreviewSubtree(body)" &&
        hasSubstr graphJs "previewUtils.readPanelBehavior(groupHoverPanel, { mode: \"pinned\", placement: \"docked\" })" &&
        hasSubstr graphJs "attachPreviewHandlers(graphBlock, graphContainer, previewMap, previewController, previewKeyByNodeId)" &&
        hasSubstr graphJs "graphState.previewActiveNode === node && !previewController.panel.hidden" &&
        hasSubstr graphJs "configurePanelCloseButton(previewUtils, previewClose" &&
        hasSubstr graphJs "configurePanelCloseButton(previewUtils, groupHoverClose" &&
        hasSubstr graphJs "previewKeyByNodeId: new Map(previewKeyByNodeId)" &&
        hasSubstr graphJs "graphviz: null," &&
        hasSubstr graphJs "renderedVariantKey: \"\"," &&
        hasSubstr graphJs "renderedOptionsKey: \"\"," &&
        hasSubstr graphJs "renderToken: 0," &&
        hasSubstr graphJs "function dotWithGraphOptions(dot, options)" &&
        hasSubstr graphJs "function dotForVariantOptions(variant, options)" &&
        hasSubstr graphJs "return dotWithGraphOptions(variant.dot, options);" &&
        hasSubstr graphJs "function resetGraphvizForVariant(graphRoot, graphState)" &&
        hasSubstr graphJs "function bindOptionsPopover(graphBlock)" &&
        hasSubstr graphJs "const finalizeRender = function () {" &&
        hasSubstr graphJs "if (graphState.renderToken !== renderToken) return;" &&
        hasSubstr graphJs "const gv = graphState.graphviz || graphContainer.graphviz();" &&
        hasSubstr graphJs "const directionSelector = graphBlock.querySelector(\".bp_graph_direction_select\");" &&
        hasSubstr graphJs "const packInput = graphBlock.querySelector(\".bp_graph_pack_input\");" &&
        hasSubstr graphJs "let activeOptions = normalizeGraphOptions({" &&
        hasSubstr graphJs "switchDirection(directionSelector.value);" &&
        hasSubstr graphJs "switchPack(packInput.checked);" &&
        hasSubstr graphJs ".zoom(true)" &&
        hasSubstr graphJs "function normalizeGraphDirection(rawDirection)" &&
        hasSubstr graphJs "function normalizeGraphPack(rawPack)" &&
        hasSubstr graphJs "layoutGraphCanvas(graphRoot, graphState)" &&
        hasSubstr graphJs "if (typeof ResizeObserver === \"function\")" &&
        hasSubstr graphJs ".fit(true)" &&
        hasSubstr graphJs "syncLegend(graphBlock, activeKey)"
      | none => false
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

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.Graph
