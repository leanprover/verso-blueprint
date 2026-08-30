/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.PreviewManifest
meta import VersoBlueprint.PreviewManifest

namespace VersoBlueprintModuleTests.PreviewManifest

open Lean

/-- info: true -/
#guard_msgs in
#eval
  let entry : Informal.PreviewManifest.Entry := {
    key := "module-preview"
    targetKind := .block
    label := `module.preview
    facet := .statement
    title := "Module preview"
  }
  let file : Informal.PreviewManifest.File := { previews := #[entry] }
  let index := file.index
  index.findEntry? "module-preview" |>.map (·.title) == some "Module preview" &&
    Informal.PreviewManifest.manifestInternalSchemaVersion == 3 &&
    Informal.PreviewManifest.schemaString != ""

end VersoBlueprintModuleTests.PreviewManifest
