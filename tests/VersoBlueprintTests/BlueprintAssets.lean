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
import VersoBlueprint.PreviewManifest
import VersoBlueprint.Informal.Uses
import VersoBlueprint.Slides

namespace Verso.VersoBlueprintTests.BlueprintAssets

/-- Every popup page gets the shared panel shell before its own styles. -/
private def panelCss (extras : List String) : List String :=
  [Informal.Commands.blueprintTokensCss, Informal.Commands.previewPanelCss,
    Informal.Commands.previewHeaderCss, Informal.Commands.inlinePreviewCss] ++ extras

/-- info: true -/
#guard_msgs in
#eval
  let bundle :=
    Informal.Commands.previewPanelAssetBundle
      (cssExtras := ["graph-css"])
      (jsAfter := ["graph-js"])
  bundle.css == panelCss ["graph-css"] &&
    bundle.js == ["graph-js"]

/-- info: true -/
#guard_msgs in
#eval
  Informal.Commands.graphAssetBundle.css == panelCss [Informal.Commands.graphCss] &&
    Informal.Commands.graphAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.Commands.summaryAssetBundle.css == panelCss [Informal.Commands.summaryCss] &&
    Informal.Commands.summaryAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.Commands.bibliographyAssetBundle.css == panelCss [Informal.Commands.bibliographyCss] &&
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
      panelCss [Informal.Block.Assets.css, Verso.Genre.Manual.docstringStyle] &&
    Informal.Block.Assets.blockAssetBundle.js ==
      [Informal.Macros.blueprintMathJs, Informal.PageBehavior.jsInteractive]

/-- info: true -/
#guard_msgs in
#eval
  Informal.Graft.manualGraftAssetBundle.css ==
      Informal.Block.Assets.blockCssAssets ++ Informal.Graft.cssAssets &&
    Informal.Graft.manualGraftAssetBundle.js == Informal.Block.Assets.blockJsAssets

/-- info: true -/
#guard_msgs in
#eval
  Informal.Cite.citeAssetBundle.css == panelCss [] &&
    Informal.Cite.citeAssetBundle.js == []

/-- info: true -/
#guard_msgs in
#eval
  Informal.usesAssetBundle.css == panelCss [] &&
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

/-- Blueprint's cascade is fixed, whatever order the stylesheets arrive in. -/
private def cascadeFixture : String :=
  ".bp_block {}\n\n:root { --bp-token: 0; }"

/-- info: true -/
#guard_msgs in
#eval
  Informal.PreviewManifest.blueprintCascadeCss
      #[":root { --bp-token: 0; }", ".verso {}", ".bp_block {}"] == cascadeFixture &&
    Informal.PreviewManifest.blueprintCascadeCss
      #[".bp_block {}", ":root { --bp-token: 0; }", ".verso {}"] == cascadeFixture

end Verso.VersoBlueprintTests.BlueprintAssets
