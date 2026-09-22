/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Slides
meta import VersoBlueprint.Slides

namespace VersoBlueprintBoundaryTests.SlidesRoot

example :
    (config : VersoSlides.Config) →
    (manifest? : Option System.FilePath) →
    (doc : Verso.Doc.Part VersoSlides.Slides) →
    (cache? : Option System.FilePath) →
    IO UInt32 :=
  fun config manifest? doc cache? =>
    Informal.Slides.slidesMainWithBlueprintPreviews
      config manifest? doc cache? (quiet := true)

/-- info: true -/
#guard_msgs in
#eval
  let config := Informal.Slides.withBlueprintSlidesAssets {}
  config.extraCss.any
    (·.filename == Informal.Slides.blueprintSlidesCssFilename)

end VersoBlueprintBoundaryTests.SlidesRoot
