/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.LeanStatus

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls leanStatusChipDoc
    let removedTemplateBinderJs? := findRemovedTemplatePreviewBinderJs? st
    pure (
      hasSubstr out "bp_code_link_status_proved" &&
      hasSubstr out "bp_code_link_status_warning" &&
      hasSubstr out "bp_code_link_status_axiom" &&
      hasSubstr out "bp_code_link_status_absent" &&
      hasSubstr out "bp_code_summary_preview_root" &&
      hasSubstr out "bp_code_summary_preview_wrap_active" &&
      hasSubstr out "bp_code_summary_preview_tpl" &&
      hasSubstr out "bp_code_summary_preview_panel" &&
      hasSubstr out "data-bp-preview-id=\"bp-code-summary\"" &&
      hasSubstr out "tabindex=\"0\"" &&
      hasSubstr out ">✓</span>" &&
      hasSubstr out ">⚠</span>" &&
      hasSubstr out ">A</span>" &&
      hasSubstr out ">X</span>" &&
      hasExtraCss st ".bp_code_summary_preview_panel" &&
      hasTemplatePreviewDescriptor out
        ".bp_code_summary_preview_panel"
        "template.bp_code_summary_preview_tpl[data-bp-preview-id]"
        ".bp_code_summary_preview_wrap_active[data-bp-preview-id]"
        ".bp_code_summary_preview_title"
        ".bp_code_summary_preview_body"
        ".bp_code_summary_preview_close" &&
      hasSubstr out "data-bp-template-preview-title-attr=\"data-bp-preview-title\"" &&
      removedTemplateBinderJs?.isNone
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.LeanStatus
