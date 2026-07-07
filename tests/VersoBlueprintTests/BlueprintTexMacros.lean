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

end Verso.VersoBlueprintTests.BlueprintTexMacros
