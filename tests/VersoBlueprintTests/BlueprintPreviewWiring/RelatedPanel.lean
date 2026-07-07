/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.PreviewManifest.RelatedPanel
import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.RelatedPanel

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

private def samplePanelEntry : Informal.RelatedPanel.PanelEntry := {
  previewId := "preview"
  previewKey := "preview-key"
  previewTitle := "Target"
  label := Lean.Name.mkSimple "target"
}

private def sampleMissingPreviewPanelEntry : Informal.RelatedPanel.PanelEntry := {
  previewId := "missing-preview"
  previewKey := ""
  previewTitle := "Missing Preview"
  label := Lean.Name.mkSimple "missing.preview"
}

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let entry : Informal.PreviewManifest.RelatedEntry := {
      label := Lean.Name.mkSimple "target"
      title := "Target"
      previewKey := "informal:target:statement"
      axes := #[.statement, .proof]
    }
    let badges := entry.badgesHtml.asString
    hasSubstr badges "bp_relation_badge_statement" &&
      hasSubstr badges "bp_relation_badge_proof" &&
      hasSubstr badges "title=\"Declared in the statement\"" &&
      hasSubstr badges "title=\"Declared in the proof\""

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := Lean.Name.mkSimple "source"
    let statementCfg := Informal.RelatedPanel.statementUsesPanelConfig source
    let proofCfg := Informal.RelatedPanel.proofUsesPanelConfig source
    statementCfg.panelTitle 2 == "Statement uses 2" &&
      statementCfg.chipTitle 1 == "Statement dependencies used by source" &&
      statementCfg.singleTitle samplePanelEntry == "Statement dependency: Target" &&
      proofCfg.panelTitle 2 == "Proof uses 2" &&
      proofCfg.chipTitle 1 == "Proof dependencies used by source" &&
      proofCfg.singleTitle samplePanelEntry == "Proof dependency: Target"

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let cfg := Informal.RelatedPanel.statementUsesPanelConfig (Lean.Name.mkSimple "source")
    let inlineOut := (Informal.RelatedPanel.renderPanel cfg #[sampleMissingPreviewPanelEntry]).asString
    let panelOut :=
      (Informal.RelatedPanel.renderPanel cfg #[sampleMissingPreviewPanelEntry, samplePanelEntry]).asString
    hasSubstr inlineOut "data-bp-preview-id=\"missing-preview\"" &&
      !hasSubstr inlineOut "data-bp-preview-key=" &&
      hasSubstr panelOut "data-bp-relation-preview-id=\"missing-preview\"" &&
      !hasSubstr panelOut "data-bp-relation-preview-id=\"missing-preview\" data-bp-relation-preview-key" &&
      hasSubstr panelOut "data-bp-relation-preview-key=\"preview-key\""

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls usedByPreviewDoc
    let relationJs? := findRelationPanelJs? st
    pure (
      hasSubstr out "used by 2" &&
      !hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      hasSubstr out "class=\"bp_relation_wrap\"" &&
      hasSubstr out "class=\"bp_relation_panel\"" &&
      hasSubstr out "class=\"bp_relation_item bp_relation_item_active\"" &&
      !hasSubstr out "class=\"bp_relation_preview_fallback_tpl\"" &&
      hasSubstr out "class=\"bp_relation_preview_message\"" &&
      hasSubstr out "Loading preview" &&
      hasSubstr out "Reverse dependency previews" &&
      !hasSubstr out "Hover a use site to preview it." &&
      !hasSubstr out "class=\"bp_relation_preview_empty\"" &&
      hasSubstr out "class=\"bp_relation_preview_header_label bp_preview_header_label\"" &&
      hasSubstr out "data-bp-relation-preview-id" &&
      hasSubstr out "data-bp-relation-preview-key" &&
      hasSubstr out "data-bp-preview-header-label=" &&
      hasSubstr out "data-bp-preview-header-href=" &&
      hasSubstr out ">statement</span>" &&
      hasSubstr out ">proof</span>" &&
      hasSubstr out ">automatic</span>" &&
      hasSubstr out ">technical</span>" &&
      hasSubstr out ">auxiliary</span>" &&
      hasSubstr out "bp_relation_badge_statement" &&
      hasSubstr out "bp_relation_badge_proof" &&
      hasSubstr out "bp_relation_badge_origin_automatic" &&
      hasSubstr out "bp_relation_badge_intent_technical" &&
      hasSubstr out "bp_relation_badge_intent_auxiliary" &&
      !hasSubstr out "bp_uses_chip" &&
      !hasSubstr out "bp_uses_origin_badge" &&
      !hasSubstr out "bp_uses_intent_badge" &&
      hasExtraCss st ".content-wrapper > section:has(.bp_relation_panel)" &&
      hasExtraCss st ".bp_preview_header_label" &&
      hasExtraCss st ".bp_relation_badge_origin::before" &&
      hasExtraCss st ".bp_relation_badge_intent_technical" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_uses\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_used_by\"" "class=\"bp_extra_slot bp_extra_slot_code\"" &&
      relationJs?.isNone &&
      !hasExtraJs st "window.VersoBlueprint.onRenderReady"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls usedBySinglePreviewDoc
    pure (
      hasSubstr out "uses 1" &&
      hasSubstr out "uses 0" &&
      hasSubstr out "used by 1" &&
      hasSubstr out "used by 0" &&
      hasSubstr out "bp_code_link_status_absent" &&
      hasSubstr out "bp_code_link_empty" &&
      hasSubstr out "No associated Lean declarations" &&
      hasSubstr out ">X</span>" &&
      hasSubstr out ">L∃∀N</span>" &&
      hasSubstr out "class=\"bp_relation_chip bp_relation_chip_empty\"" &&
      hasSubstr out "class=\"bp_inline_preview_ref\"" &&
      !hasSubstr out "class=\"bp_inline_preview_tpl\" data-bp-preview-id=\"bp-used-by-" &&
      !hasSubstr out "data-bp-relation-preview-id=\"bp-uses-" &&
      hasSubstr out "data-bp-preview-id=\"bp-used-by-" &&
      hasSubstr out "data-bp-preview-id=\"bp-uses-" &&
      hasSubstr out "data-bp-preview-header-label=" &&
      hasSubstr out "data-bp-preview-header-href=" &&
      hasSubstr out "data-bp-preview-footer-html=" &&
      hasSubstr out "data-bp-preview-key="
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls usesPreviewDoc
    let relationJs? := findRelationPanelJs? st
    pure (
      hasSubstr out "uses 2" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      hasSubstr out "class=\"bp_relation_chip\"" &&
      hasSubstr out "class=\"bp_relation_panel\"" &&
      hasSubstr out "Statement uses 2" &&
      hasSubstr out "Statement dependency previews" &&
      hasSubstr out "Proof uses 2" &&
      hasSubstr out "Proof dependency previews" &&
      !hasSubstr out "Hover a dependency to preview it." &&
      hasSubstr out "class=\"bp_relation_preview_header_label bp_preview_header_label\"" &&
      hasSubstr out "data-bp-relation-preview-id=\"bp-uses-" &&
      hasSubstr out "data-bp-preview-header-label=" &&
      hasSubstr out "data-bp-preview-header-href=" &&
      hasSubstr out "def:uses.hidden" &&
      hasSubstr out "def:uses.inline" &&
      hasSubstr out "def:uses.proof" &&
      hasSubstr out "def:uses.proof.extra" &&
      hasSubstr out ">statement</span>" &&
      hasSubstr out ">proof</span>" &&
      hasSubstr out ">automatic</span>" &&
      hasSubstr out ">technical</span>" &&
      hasSubstr out ">auxiliary</span>" &&
      hasSubstr out "bp_relation_badge_statement" &&
      hasSubstr out "bp_relation_badge_proof" &&
      hasSubstr out "bp_relation_badge_origin_automatic" &&
      hasSubstr out "bp_relation_badge_intent_technical" &&
      hasSubstr out "bp_relation_badge_intent_auxiliary" &&
      !hasSubstr out "bp_uses_chip" &&
      !hasSubstr out "bp_uses_origin_badge" &&
      !hasSubstr out "bp_uses_intent_badge" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_uses\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_used_by\"" "class=\"bp_extra_slot bp_extra_slot_code\"" &&
      relationJs?.isNone
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls groupPreviewDoc
    let relationJs? := findRelationPanelJs? st
    pure (
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_group\"" "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_uses\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_used_by\"" "class=\"bp_extra_slot bp_extra_slot_code\"" &&
      hasSubstr out "Group member previews" &&
      !hasSubstr out "Hover another entry in this group to preview it." &&
      hasSubstr out "class=\"bp_relation_item bp_relation_item_active\"" &&
      hasSubstr out "class=\"bp_relation_preview_message\"" &&
      hasSubstr out "Loading preview" &&
      !hasSubstr out "class=\"bp_relation_preview_fallback_tpl\"" &&
      !hasSubstr out "class=\"bp_relation_preview_empty\"" &&
      hasSubstr out "data-bp-relation-preview-id=\"bp-group-" &&
      hasSubstr out "Preview group title." &&
      hasSubstr out "used by 1" &&
      relationJs?.isNone
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls missingGroupPreviewDoc
    pure (
      hasSubstr out "bp_relation_chip_warn" &&
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
      !hasSubstr out "bp_relation_chip_warn" &&
      !hasSubstr out "data-bp-relation-preview-id=\"bp-group-"
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.RelatedPanel
