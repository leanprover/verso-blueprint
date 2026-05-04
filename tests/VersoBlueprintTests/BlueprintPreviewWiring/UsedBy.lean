/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.UsedBy

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls usedByPreviewDoc
    let usedByJs? := findExtraJsContaining? st "function bindUsedByPanel(panel)"
    pure (
      hasSubstr out "used by 2" &&
      !hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      hasSubstr out "class=\"bp_used_by_wrap\"" &&
      hasSubstr out "class=\"bp_used_by_panel\"" &&
      hasSubstr out "class=\"bp_used_by_item bp_used_by_item_active\"" &&
      !hasSubstr out "class=\"bp_used_by_preview_fallback_tpl\"" &&
      hasSubstr out "class=\"bp_used_by_preview_message\"" &&
      hasSubstr out "Loading preview" &&
      !hasSubstr out "class=\"bp_used_by_preview_empty\"" &&
      hasSubstr out "data-bp-used-preview-id" &&
      hasSubstr out "data-bp-used-preview-key" &&
      hasSubstr out ">statement</span>" &&
      hasSubstr out ">proof</span>" &&
      appearsBefore out "class=\"bp_code_summary_preview_root\"" "class=\"bp_used_by_wrap\"" &&
      match usedByJs? with
      | some usedByJs =>
        hasSubstr usedByJs "function bindUsedByPanel(panel)" &&
        hasSubstr usedByJs "function previewUnavailableHtml(previewUtils, previewKey, fallbackDetail)" &&
        hasSubstr usedByJs "body.innerHTML = loadingPreviewHtml();" &&
        hasSubstr usedByJs "previewUtils.loadSharedPreviewEntry(previewKey)" &&
        !hasSubstr usedByJs "fallbackTemplates" &&
        hasSubstr usedByJs "const initialItem = items.find(function (item) {" &&
        hasSubstr usedByJs "item.classList.contains(\"bp_used_by_item_active\")" &&
        hasSubstr usedByJs "function loadActivePreview()" &&
        hasSubstr usedByJs "selectItem(initialItem)" &&
        !hasSubstr usedByJs "activate(initialItem, { openWrap: false })" &&
        hasSubstr usedByJs "item.addEventListener(\"mouseenter\"" &&
        hasSubstr usedByJs "item.addEventListener(\"focusin\""
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls usedBySinglePreviewDoc
    pure (
      hasSubstr out "used by 1" &&
      hasSubstr out "used by 0" &&
      hasSubstr out "bp_code_link_status_absent" &&
      hasSubstr out "bp_code_link_empty" &&
      hasSubstr out "No associated Lean declarations" &&
      hasSubstr out ">X</span>" &&
      hasSubstr out ">L∃∀N</span>" &&
      hasSubstr out "class=\"bp_used_by_chip bp_used_by_chip_empty\"" &&
      hasSubstr out "class=\"bp_inline_preview_ref\"" &&
      !hasSubstr out "class=\"bp_inline_preview_tpl\" data-bp-preview-id=\"bp-used-by-" &&
      hasSubstr out "data-bp-preview-id=\"bp-used-by-" &&
      hasSubstr out "data-bp-preview-key="
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls groupPreviewDoc
    let usedByJs? := findExtraJsContaining? st "function bindUsedByPanel(panel)"
    pure (
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_group\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      hasSubstr out "Hover another entry in this group to preview it." &&
      hasSubstr out "class=\"bp_used_by_item bp_used_by_item_active\"" &&
      hasSubstr out "class=\"bp_used_by_preview_message\"" &&
      hasSubstr out "Loading preview" &&
      !hasSubstr out "class=\"bp_used_by_preview_fallback_tpl\"" &&
      !hasSubstr out "class=\"bp_used_by_preview_empty\"" &&
      hasSubstr out "data-bp-used-preview-id=\"bp-group-" &&
      hasSubstr out "Preview group title." &&
      hasSubstr out "used by 1" &&
      match usedByJs? with
      | some usedByJs =>
        hasSubstr usedByJs "function bindUsedByPanel(panel)" &&
        hasSubstr usedByJs "previewUtils.loadSharedPreviewEntry(previewKey)" &&
        hasSubstr usedByJs "selectItem(initialItem)" &&
        !hasSubstr usedByJs "activate(initialItem, { openWrap: false })"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls missingGroupPreviewDoc
    pure (
      hasSubstr out "bp_used_by_chip_warn" &&
      hasSubstr out "data-bp-preview-id=\"bp-group-" &&
      hasSubstr out "data-bp-preview-key=" &&
      hasSubstr out "grp:missing"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls singleDeclaredGroupDoc
    pure (
      !hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      !hasSubstr out "bp_used_by_chip_warn" &&
      !hasSubstr out "data-bp-used-preview-id=\"bp-group-"
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.UsedBy
