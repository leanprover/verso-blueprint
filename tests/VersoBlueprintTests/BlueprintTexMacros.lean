/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintTexMacros.Root
import VersoBlueprintTests.Blueprint.Support
import VersoBlueprint.Lib.PreviewSource

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

/-- info: true -/
#guard_msgs in
#eval
  show Lean.Elab.Term.TermElabM Bool from do
    let label := Name.mkSimple "widget_preview"
    let some selection := Informal.PreviewSource.environmentSelection? (← getEnv) label
      | return false
    let previewHtml := toJson (← Informal.PreviewSource.renderWidgetHtml (some selection.preview))
    let encoded := Json.compress previewHtml
    pure (
      selection.facet == PreviewCache.Facet.statement &&
      selection.key == PreviewCache.statementKey label &&
      !selection.preview.blocks.isEmpty &&
      selection.preview.stxs.isEmpty &&
      hasSubstr encoded "data-bp-tex-prelude-id" &&
      !hasSubstr encoded "data-bp-tex-prelude=\\\"" &&
      !hasSubstr encoded "\"texPrelude\""
    )

end Verso.VersoBlueprintTests.BlueprintTexMacros
