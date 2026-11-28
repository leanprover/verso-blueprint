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

-- Template preview roots describe their panel; the runtime builds it from the shared shell.
/-- info: true -/
#guard_msgs in
#eval
  let attrs := templatePreviewDescriptorAttrs "bp_code_summary_preview_panel"
    "template.tpl[data-k]" ".trigger[data-k]" (eyebrow := "Lean code") (closeLabel := "Close it")
  let html := (Verso.Output.Html.tag "span" attrs .empty).asString
  hasSubstr html "data-bp-template-preview-panel-class=\"bp_code_summary_preview_panel\"" &&
    hasSubstr html "data-bp-template-preview-eyebrow=\"Lean code\"" &&
    hasSubstr html "data-bp-template-preview-close-label=\"Close it\"" &&
    hasSubstr html "data-bp-template-preview-mode=\"hover\"" &&
    hasSubstr html "data-bp-template-preview-placement=\"anchored\"" &&
    !hasSubstr html "<aside"

/-- info: true -/
#guard_msgs in
#eval
  let html := (templatePreviewRoot "root" "wrap" "wrap_active" "tpl" "data-k" "key" "Title"
    "bp_summary_preview_panel" (trigger := .empty) (body := .empty)).asString
  hasSubstr html "data-bp-template-preview-panel-class=\"bp_summary_preview_panel\"" &&
    !hasSubstr html "data-bp-template-preview-eyebrow" &&
    !hasSubstr html "bp_preview_panel"

end Verso.VersoBlueprintTests.BlueprintPreviewPanels
