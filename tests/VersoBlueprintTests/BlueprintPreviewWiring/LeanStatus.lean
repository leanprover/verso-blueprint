/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.LeanStatus

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

/-- info: #[] -/
#guard_msgs in
#eval
  show IO (Array String) from do
    let model := leanStatusChipDocBlueprint.model
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls leanStatusChipDoc (model := model)
    let removedTemplateBinderJs? := findRemovedTemplatePreviewBinderJs? st
    let assessmentFor? (label : String) :=
      (model.nodes.find? (·.label == Lean.Name.mkSimple label)).bind (·.assessment)
    let isCapturedComplete (label : String) := (assessmentFor? label).any fun assessment =>
      assessment.hasNativeDeclarations && assessment.nativeStatementComplete &&
        assessment.nativeProofComplete && assessment.requiredComplete
    let isCapturedIncomplete (label : String) := (assessmentFor? label).any fun assessment =>
      assessment.hasNativeDeclarations && !assessment.nativeProofComplete && !assessment.requiredComplete
    let isCapturedAxiom (label : String) := (assessmentFor? label).any fun assessment =>
      assessment.hasNativeDeclarations && assessment.hasAxiomLike
    let isNativeFree (label : String) := (assessmentFor? label).any fun assessment =>
      !assessment.hasNativeDeclarations
    let checks : Array (String × Bool) := #[
      ("complete source has an actual captured native validation", isCapturedComplete "def:status.proved"),
      ("sorry source remains unfinished in native validation", isCapturedIncomplete "def:status.sorry"),
      ("axiom-like classification comes from current provider inventory", isCapturedAxiom "def:status.axiom"),
      ("prose-only source remains native-unassessed", isNativeFree "def:status.none"),
      ("captured incomplete source is warning", hasSubstr out "bp_code_link_status_warning"),
      ("captured complete source is proved", hasSubstr out "bp_code_link_status_proved"),
      ("axiom classification is displayed", hasSubstr out "bp_code_link_status_axiom"),
      ("code-free node stays absent", hasSubstr out "bp_code_link_status_absent"),
      ("axiom classification stays in source display", hasSubstr out "bp_code_decl_status_axiom"),
      ("preview root", hasSubstr out "bp_code_summary_preview_root"),
      ("preview trigger", hasSubstr out "bp_code_summary_preview_wrap_active"),
      ("preview template", hasSubstr out "bp_code_summary_preview_tpl"),
      ("preview panel", hasSubstr out "bp_code_summary_preview_panel"),
      ("preview id", hasSubstr out "data-bp-preview-id=\"bp-code-summary\""),
      ("keyboard trigger", hasSubstr out "tabindex=\"0\""),
      ("incomplete glyph", hasSubstr out ">⚠</span>"),
      ("completed native validation glyph", hasSubstr out ">✓</span>"),
      ("axiom classification glyph", hasSubstr out ">A</span>"),
      ("absent glyph", hasSubstr out ">X</span>"),
      ("preview CSS", hasExtraCss st ".bp_code_summary_preview_panel"),
      ("preview descriptor", hasTemplatePreviewDescriptor out
        ".bp_code_summary_preview_panel"
        "template.bp_code_summary_preview_tpl[data-bp-preview-id]"
        ".bp_code_summary_preview_wrap_active[data-bp-preview-id]"
        ".bp_code_summary_preview_title"
        ".bp_code_summary_preview_body"
        ".bp_code_summary_preview_close"),
      ("preview title attribute", hasSubstr out "data-bp-template-preview-title-attr=\"data-bp-preview-title\""),
      ("legacy preview binder absent", removedTemplateBinderJs?.isNone)]
    pure <| checks.filterMap fun (name, ok) => if ok then none else some name

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.LeanStatus
