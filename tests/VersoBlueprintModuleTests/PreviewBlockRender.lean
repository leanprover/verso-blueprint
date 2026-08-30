/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.PreviewManifest.BlockRender
meta import VersoBlueprint.PreviewManifest.BlockRender

namespace VersoBlueprintModuleTests.PreviewBlockRender

/-- info: true -/
#guard_msgs in
#eval
  let entry : Informal.PreviewManifest.Entry := {
    key := "module-block"
    targetKind := .block
    label := `module.block
    facet := .statement
    kind := some .definition
    title := "Module block"
  }
  let content :=
    Informal.PreviewManifest.BlockRender.RenderedContent.ofHtmlStrings
      "<p>Module body</p>"
  let rendered :=
    Informal.PreviewManifest.BlockRender.renderWithRenderedContent {} entry content
  content.body.asString == "<p>Module body</p>" &&
    Informal.PreviewManifest.BlockRender.RelationPanelKind.usedBy.key == "used-by" &&
    rendered.asString != ""

end VersoBlueprintModuleTests.PreviewBlockRender
