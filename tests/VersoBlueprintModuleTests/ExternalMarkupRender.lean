/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.ExternalMarkupRender
meta import VersoBlueprint.Informal.ExternalMarkupRender

namespace VersoBlueprintModuleTests.ExternalMarkupRender

open Lean
open Informal
open Informal.Data

local macro "selectedExternalMarkupContract" : term => do
  let tex : ExternalMarkup := {
    language := .tex
    slot := "statement"
    raw := "\\begin{theorem}Fallback\\end{theorem}"
  }
  let markdown : ExternalMarkup := {
    language := .markdown
    slot := "statement"
    raw := "# Module rendering"
  }
  return quote (ExternalMarkupRender.selected? {} #[tex, markdown])

/-- info: true -/
#guard_msgs in
#eval
  match (selectedExternalMarkupContract : Option ExternalMarkup) with
  | none => false
  | some selected =>
    match ExternalMarkupRender.body? {} selected with
    | none => false
    | some body =>
      let html := body.asString
      selected.language == ExternalMarkupLanguage.markdown &&
        ExternalMarkupRender.Mode.parse? "md" == some ExternalMarkupRender.Mode.markdown &&
        ExternalMarkupRender.Mode.parse? "raw" == some ExternalMarkupRender.Mode.source &&
        (ExternalMarkupRender.sourceBackedAttrs selected).contains
          ("data-bp-external-markup-language", "markdown") &&
        html.contains "Module rendering"

end VersoBlueprintModuleTests.ExternalMarkupRender
