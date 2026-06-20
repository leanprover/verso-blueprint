/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.Summary

open Informal
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls previewWiringDoc
    let removedTemplateBinderJs? := findRemovedTemplatePreviewBinderJs? st
    let inlineJs? := findInlinePreviewJs? st
    let mathJs? := findMathPreludeJs? st
    pure (
      !hasSubstr out "class=\"bp_summary_preview_store\"" &&
      !hasSubstr out "class=\"bp_summary_preview_tpl\"" &&
      !hasSubstr out "class=\"bp_label_preview_tpl\"" &&
      hasSubstr out "bp_summary_preview_panel" &&
      hasSubstr out "data-bp-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-preview-placement=\"anchored\"" &&
      hasSubstr out "bp_summary_preview_wrap_active" &&
      hasSubstr out "data-bp-preview-key=\"«def:preview.base»--statement\"" &&
      hasExtraCss st ".bp_inline_preview_panel[hidden]" &&
      hasExtraCss st ".bp_preview_header_label" &&
      hasExtraCss st ".bp_inline_preview_panel_footer" &&
      !hasSubstr out "data-bp-tex-prelude=\"" &&
      !hasSubstr out "bp_preview_tex_prelude" &&
      !hasSubstr out "verso-tex-prelude" &&
      hasTemplatePreviewDescriptor out
        ".bp_summary_preview_panel"
        "template.bp_summary_preview_tpl[data-bp-preview-label]"
        ".bp_summary_preview_wrap_active[data-bp-preview-label]"
        ".bp_summary_preview_panel_title"
        ".bp_summary_preview_panel_body"
        ".bp_summary_preview_panel_close"
        (allowHtmlCache := true) &&
      removedTemplateBinderJs?.isNone &&
      match inlineJs?, mathJs? with
      | some inlineJs, some mathJs =>
        hasSubstr mathJs "\\\\newcommand{\\\\previewmacro}{\\\\mathsf{Preview}}" &&
        hasRenderReadyWiring inlineJs "previewUtils" &&
        hasAllSubstr inlineJs [
          "bp-inline-preview-child-panel",
          "previewUtils.createPreviewSurface({",
          "data-bp-preview-footer-html"
        ] &&
        lacksAllSubstr inlineJs [
          "typeof previewUtils.readPanelBehavior",
          "typeof previewUtils.previewDebug",
          "function onBlueprintRenderReady(fn)",
          ".replaceAll(\"&\", \"&amp;\")",
          "ensureInlinePreviewStore",
          "template.bp_inline_preview_tpl"
        ]
      | _, _ => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls leanCodeLinkPreviewDoc
    let inlineJs? := findInlinePreviewJs? st
    let previewKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey `Nat.add
    pure (
      countSubstr out s!"data-bp-preview-key=\"{previewKey}\"" >= 1 &&
      !hasSubstr out s!"data-bp-preview-key=\"{previewKey}\" data-bp-preview-fallback-label=" &&
      hasSubstr out "class=\"bp_summary_decl_list\"" &&
      hasSubstr out "class=\"bp_inline_preview_ref\"" &&
      hasSubstr out "Nat.add</code>" &&
      !hasSubstr out "Lean code:" &&
      hasExtraCss st ".bp_inline_preview_panel" &&
      match inlineJs? with
      | some inlineJs =>
        hasSubstr inlineJs "const triggerSelector = \".bp_inline_preview_ref[data-bp-preview-id]\"" &&
        hasSubstr inlineJs "data-bp-preview-fallback-label"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls shortExternalNamePreviewDoc
    let canonicalKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.ShortExternalPreview.openedSummaryDecl
    let shortKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      (Lean.Name.mkSimple "openedSummaryDecl")
    pure (
      hasSubstr out "<code>openedSummaryDecl</code>" &&
      hasSubstr out s!"data-bp-preview-key=\"{canonicalKey}\"" &&
      !hasSubstr out s!"data-bp-preview-key=\"{shortKey}\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls externalDocstringDedupDoc
    let previewKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.externalDocstringDedupDecl
    let previewObjects :=
      match Informal.TraversalIndex.LeanCodePreviews.domain? st with
      | some domain => domain.objects.toArray
      | none => #[]
    let previewData? := previewObjects[0]?.map fun (_key, obj) => obj.data.compress
    pure (
      countSubstr out s!"data-bp-preview-key=\"{previewKey}\"" >= 2 &&
      previewObjects.size == 1 &&
      match previewData? with
      | some previewData =>
        hasSubstr previewData "External declaration docstring dedup marker"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls proofFallbackSummaryDoc
    let label := Lean.Name.mkSimple "thm:preview.proof_fallback"
    let proofKey := PreviewCache.key label .proof
    let statementKey := PreviewCache.key label .statement
    pure (
      hasSubstr out "bp_summary_preview_wrap_active" &&
      hasSubstr out s!"data-bp-preview-key=\"{proofKey}\"" &&
      !hasSubstr out s!"data-bp-preview-key=\"{statementKey}\""
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.Summary
