/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Slides.Assets
meta import VersoBlueprint.Slides.Assets

namespace VersoBlueprintModuleTests.SlidesAssets

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let config := Informal.Slides.withBlueprintSlidesAssets {}
    let plan ← Informal.Slides.collectSlideAssets config
    pure <|
      config.extraCss.any
        (·.filename == Informal.Slides.blueprintSlidesCssFilename) &&
      plan.assets.contains Informal.Slides.blueprintSlidesCssFilename &&
      Informal.Slides.blueprintSlidesCss != "" &&
      Informal.Slides.blueprintSlidesManifestPath "deck" ==
        "deck" / "-verso-data" / "blueprint-manifest.json" &&
      Informal.Slides.blueprintSlidesHtmlCachePath "deck" ==
        "deck" / "-verso-data" / "blueprint-html-cache.json"

end VersoBlueprintModuleTests.SlidesAssets
