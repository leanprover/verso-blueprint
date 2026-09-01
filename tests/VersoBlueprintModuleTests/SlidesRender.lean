/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Slides.Render
meta import VersoBlueprint.Slides.Render

namespace VersoBlueprintModuleTests.SlidesRender

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let node : Informal.Graft.BlueprintNode := {
      label := "module.slides.render"
      key := "module-slides-render--statement"
    }
    let ctx := Informal.Graft.RenderContext.ofPreviewData? none
    let rendered ← Informal.Slides.renderBlueprintSlideNode ctx node
    pure <|
      ctx.manifestIndex?.isNone &&
        rendered.asString.contains "Preview manifest unavailable"

end VersoBlueprintModuleTests.SlidesRender
