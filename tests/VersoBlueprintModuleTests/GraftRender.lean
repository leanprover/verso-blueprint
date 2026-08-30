/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Graft.Render
meta import VersoBlueprint.Graft.Render

namespace VersoBlueprintModuleTests.GraftRender

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let node : Informal.Graft.BlueprintNode := {
      label := "module.graft"
      key := "module-graft"
    }
    let ctx := Informal.Graft.RenderContext.ofPreviewData? none
    let rendered ← Informal.Graft.renderNodeFromManifestCache {} ctx node
    pure <|
      ctx.manifestIndex?.isNone &&
        rendered.asString != "" &&
        (Informal.Graft.renderNotice "notice" "info" "Title" "Detail").asString != ""

end VersoBlueprintModuleTests.GraftRender
