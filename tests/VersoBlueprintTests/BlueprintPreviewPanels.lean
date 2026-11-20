/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.HtmlId
import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintPreviewPanels

open Informal.HoverRender
open Verso.VersoBlueprintTests.Blueprint.Support

#guard previewKey "alpha.beta" == Informal.HtmlId.key "alpha.beta"
#guard previewId "bp-preview" "alpha.beta" == Informal.HtmlId.prefixed "bp-preview" "alpha.beta"

private def hasSharedPanelScaffolding (html rootClass headerClass titleClass closeClass bodyClass closeLabel : String) : Bool :=
  hasSubstr html s!"class=\"{rootClass}\"" &&
  hasSubstr html s!"class=\"{headerClass}\"" &&
  hasSubstr html s!"class=\"{titleClass}\"" &&
  hasSubstr html s!"class=\"{closeClass}\"" &&
  hasSubstr html s!"class=\"{bodyClass}\"" &&
  hasSubstr html s!"aria-label=\"{closeLabel}\""

/-- info: true -/
#guard_msgs in
#eval
  let graphHtml := graphPreviewPanel.render
  let groupHtml := graphGroupPreviewPanel.render
  let summaryHtml := summaryPreviewPanel.render
  let codeSummaryHtml := codeSummaryPreviewPanel.render
  hasSharedPanelScaffolding
      graphHtml
      "bp_graph_preview bp_preview_panel"
      "bp_graph_preview_header bp_preview_panel_header"
      "bp_graph_preview_title bp_preview_panel_title"
      "bp_graph_preview_close bp_preview_panel_close"
      "bp_graph_preview_body bp_preview_panel_body"
      "Close informal preview" &&
    hasSharedPanelScaffolding
      groupHtml
      "bp_group_hover_preview bp_preview_panel"
      "bp_group_hover_preview_header bp_preview_panel_header"
      "bp_group_hover_preview_title bp_preview_panel_title"
      "bp_group_hover_preview_close bp_preview_panel_close"
      "bp_group_hover_preview_graph bp_preview_panel_body"
      "Close group preview" &&
    hasSharedPanelScaffolding
      summaryHtml
      "bp_summary_preview_panel bp_preview_panel"
      "bp_summary_preview_panel_header bp_preview_panel_header"
      "bp_summary_preview_panel_title bp_preview_panel_title"
      "bp_summary_preview_panel_close bp_preview_panel_close"
      "bp_summary_preview_panel_body bp_preview_panel_body"
      "Close summary preview" &&
    hasSharedPanelScaffolding
      codeSummaryHtml
      "bp_code_summary_preview_panel bp_preview_panel"
      "bp_code_summary_preview_header bp_preview_panel_header"
      "bp_code_summary_preview_title bp_preview_panel_title"
      "bp_code_summary_preview_close bp_preview_panel_close"
      "bp_code_summary_preview_body bp_preview_panel_body"
      "Close Lean summary preview"

/-- info: true -/
#guard_msgs in
#eval
  let anchoredHoverHtml := (graphGroupPreviewPanel .hover .anchored).render
  hasSubstr anchoredHoverHtml "data-bp-preview-mode=\"hover\"" &&
    hasSubstr anchoredHoverHtml "data-bp-preview-placement=\"anchored\"" &&
    hasSubstr anchoredHoverHtml "hidden"

end Verso.VersoBlueprintTests.BlueprintPreviewPanels
