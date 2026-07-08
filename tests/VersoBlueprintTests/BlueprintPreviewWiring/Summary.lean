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

private def sourceLocationOkWithPath
    (result : Informal.Data.SourceLocationResult) (needle : String) : Bool :=
  result.ok &&
    match result.location with
    | some location => hasSubstr location.path needle
    | none => false

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
      inlineJs?.isNone &&
      !hasExtraJs st "window.VersoBlueprint.onRenderReady" &&
      match mathJs? with
      | some mathJs =>
        hasSubstr mathJs "\\\\newcommand{\\\\previewmacro}{\\\\mathsf{Preview}}" &&
        !hasSubstr mathJs "window.VersoBlueprint.onRenderReady"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildManualPreviewDataFiles manualImpls externalDocstringDedupDoc
    let some blockEntry := files.manifest.findPrimaryBlockEntry? "def:external.docstring.one"
      | return false
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.externalDocstringDedupDecl
    let some codeEntry := files.manifest.findEntry? codeKey
      | return false
    pure (
      sourceLocationOkWithPath blockEntry.sourceLocation "Shared.lean" &&
        sourceLocationOkWithPath codeEntry.sourceLocation "Shared.lean"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildManualPreviewDataFiles manualImpls usedByPreviewDoc
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupInlineKey
      (Lean.Name.mkSimple "def:used.target")
    let some codeEntry := files.manifest.findEntry? codeKey
      | return false
    pure <| sourceLocationOkWithPath codeEntry.sourceLocation "Shared.lean"

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
      inlineJs?.isNone
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
    let previewEntries := Informal.TraversalIndex.LeanCodePreviews.entries st
    let previewData? := previewEntries[0]?.bind fun
      | .ok stored => some (Lean.toJson stored.data).compress
      | .error _ => none
    pure (
      countSubstr out s!"data-bp-preview-key=\"{previewKey}\"" >= 2 &&
      previewEntries.size == 1 &&
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
    let proofKey := PreviewCache.proofKey label
    let statementKey := PreviewCache.statementKey label
    pure (
      hasSubstr out "bp_summary_preview_wrap_active" &&
      hasSubstr out s!"data-bp-preview-key=\"{proofKey}\"" &&
      !hasSubstr out s!"data-bp-preview-key=\"{statementKey}\""
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.Summary
