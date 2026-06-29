/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Commands.Bibliography
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary
import VersoBlueprint.Cite
import VersoBlueprint.Graft
import VersoBlueprint.Informal.RustBlock
import VersoBlueprint.Informal.Uses
import VersoBlueprint.Slides

namespace Verso.VersoBlueprintTests.BlueprintAssets

/-- info: true -/
#guard_msgs in
#eval
  let bundle :=
    Informal.Commands.previewPanelAssetBundle
      (cssExtras := ["graph-css"])
      (jsAfter := ["graph-js"])
  bundle.css ==
      [Informal.Commands.blueprintTokensCss, Informal.Commands.previewPanelCss, "graph-css"] &&
    bundle.js == ["graph-js"]

/-- info: true -/
#guard_msgs in
#eval
  let bundle :=
    Informal.Commands.inlinePreviewAssetBundle
      (cssExtras := ["bibliography-css"])
      (jsBefore := ["open-target"])
  bundle.css ==
      [Informal.Commands.blueprintTokensCss, "bibliography-css",
        Informal.Commands.previewHeaderCss, Informal.Commands.inlinePreviewCss] &&
    bundle.js == ["open-target"]

/-- info: true -/
#guard_msgs in
#eval
  Informal.Commands.graphAssetBundle.css ==
      [Informal.Commands.blueprintTokensCss, Informal.Commands.previewPanelCss,
        Informal.Commands.graphCss] &&
    Informal.Commands.graphAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.Commands.summaryAssetBundle.css ==
      [Informal.Commands.blueprintTokensCss, Informal.Commands.previewPanelCss,
        Informal.Commands.summaryCss, Informal.Commands.previewHeaderCss,
        Informal.Commands.inlinePreviewCss] &&
    Informal.Commands.summaryAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.Commands.bibliographyAssetBundle.css ==
      [Informal.Commands.blueprintTokensCss, Informal.Commands.bibliographyCss,
        Informal.Commands.previewHeaderCss, Informal.Commands.inlinePreviewCss] &&
    Informal.Commands.bibliographyAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.Block.Assets.codeAssetBundle.css ==
      [Informal.Commands.blueprintTokensCss, Informal.Block.Assets.css,
        Verso.Genre.Manual.docstringStyle] &&
    Informal.Block.Assets.codeAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.Block.Assets.blockAssetBundle.css ==
      [Informal.Commands.blueprintTokensCss, Informal.Commands.previewPanelCss,
        Informal.Block.Assets.css, Informal.StyleSwitcher.css, Verso.Genre.Manual.docstringStyle,
        Informal.Commands.previewHeaderCss, Informal.Commands.inlinePreviewCss] &&
    Informal.Block.Assets.blockAssetBundle.js == [Informal.StyleSwitcher.jsInteractive]

/-- info: true -/
#guard_msgs in
#eval
  Informal.Graft.manualGraftAssetBundle.css ==
      Informal.Block.Assets.blockCssAssets ++ Informal.Graft.cssAssets &&
    Informal.Graft.manualGraftAssetBundle.js == Informal.Block.Assets.blockJsAssets

/-- info: true -/
#guard_msgs in
#eval
  Informal.Cite.citeAssetBundle.css ==
      [Informal.Commands.blueprintTokensCss, Informal.Commands.previewHeaderCss,
        Informal.Commands.inlinePreviewCss] &&
    Informal.Cite.citeAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.usesAssetBundle.css ==
      [Informal.Commands.blueprintTokensCss, Informal.Commands.previewHeaderCss,
        Informal.Commands.inlinePreviewCss] &&
    Informal.usesAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.rustBlockAssetBundle.css ==
      Informal.Block.Assets.codeCssAssets ++ [Informal.Rust.css] &&
    Informal.rustBlockAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.Slides.blueprintSlidesCss ==
      String.intercalate "\n\n" Informal.Slides.blueprintSlidesAssetBundle.css &&
    Informal.Slides.blueprintSlidesAssetBundle.js == []

end Verso.VersoBlueprintTests.BlueprintAssets
