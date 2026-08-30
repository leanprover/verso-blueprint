/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.ExternalMarkupView
meta import VersoBlueprint.Informal.ExternalMarkupView

namespace VersoBlueprintModuleTests.ExternalMarkupView

open Lean
open Informal
open Informal.Data

local macro "externalMarkupViewContract" : term => do
  let markup : ExternalMarkup := {
    language := .markdown
    slot := "statement"
    raw := "# Module <contract>"
  }
  return quote markup

/-- info: true -/
#guard_msgs in
#eval
  let markup : ExternalMarkup := externalMarkupViewContract
  let html := ExternalMarkupView.sourceDetailsHtml markup |>.asString
  ExternalMarkupView.displaySummary markup == "External Markdown markup (statement)" &&
    ExternalMarkupView.sourceSummary markup == "external Markdown source (statement)" &&
    html.contains "bp_external_markup_source_markdown" &&
    html.contains "# Module &lt;contract&gt;"

end VersoBlueprintModuleTests.ExternalMarkupView
