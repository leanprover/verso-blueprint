/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintTexMacros.Root
import VersoBlueprintTests.Blueprint.Support
import VersoBlueprint.Widget

namespace Verso.VersoBlueprintTests.BlueprintTexMacros

open Lean
open Verso
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

set_option doc.verso true

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let chunks ← Informal.Macros.getTexPreludeChunks
    pure (chunks == #[r#"\newcommand{\sharedmacro}{\mathsf{Shared}}"#])

tex_prelude r#"\newcommand{\widgetmacro}{\mathsf{Widget}}"#

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let chunks ← Informal.Macros.getTexPreludeChunks
    pure (
      chunks == #[
        r#"\newcommand{\sharedmacro}{\mathsf{Shared}}"#,
        r#"\newcommand{\widgetmacro}{\mathsf{Widget}}"#
      ]
    )

#docs (Genre.Manual) widgetPreviewDoc "Blueprint Widget Preview" :=
:::::::
:::definition "widget_preview"
Widget preview uses $`\widgetmacro`.
:::
:::::::

/-- Captured in this fixture's environment before unrelated fixtures are imported. -/
def widgetPreviewDocBlueprint : Informal.BlueprintDocument := .capture widgetPreviewDoc.toPart

/-- info: true -/
#guard_msgs in
#eval
  show Lean.Elab.Term.TermElabM Bool from do
    let out ← buildFor (Name.mkSimple "widget_preview")
    let some selection := out.previewSelection?
      | return false
    let previewHtml := toJson (← Informal.PreviewSource.renderWidgetHtml (some selection.preview))
    let encoded := Json.compress previewHtml
    pure (
      selection.facet == .statement &&
      selection.key == PreviewCache.statementKey (Name.mkSimple "widget_preview") &&
      !selection.preview.blocks.isEmpty &&
      selection.preview.stxs.isEmpty &&
      hasSubstr encoded "data-bp-tex-prelude-id" &&
      !hasSubstr encoded "data-bp-tex-prelude=\\\"" &&
      !hasSubstr encoded "\"texPrelude\"" &&
      !hasSubstr blueprintWidget.javascript "texPrelude"
    )

end Verso.VersoBlueprintTests.BlueprintTexMacros
