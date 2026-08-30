/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.PreviewManifest.Cli
meta import VersoBlueprint.PreviewManifest.Cli

namespace VersoBlueprintModuleTests.PreviewCli

open Verso.Genre Manual

example : List String → ReaderT ExtensionImpls IO RenderConfig :=
  Informal.PreviewManifest.parseRenderConfigOptions

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (markupConfig, remaining) ←
      Informal.PreviewManifest.parseExternalMarkupRenderOptionsIO {}
        ["--draft", "--external-markup-render", "source", "--pdf"]
    let pdfContract :=
      match Informal.PreviewManifest.parsePdfOptions
          ["--draft", "--pdf-engine", "tectonic", "--pdf-runs", "3"] with
      | .ok (pdf, rest) =>
          pdf.enabled && pdf.engine == "tectonic" && pdf.runs == 3 && rest == ["--draft"]
      | .error _ => false
    let invalidRunsRejected :=
      match Informal.PreviewManifest.parsePdfOptions ["--pdf-runs", "0"] with
      | .error error => error.contains "positive integer"
      | .ok _ => false
    pure <|
      decide (markupConfig.mode = Informal.ExternalMarkupRender.Mode.source) &&
      remaining == ["--draft", "--pdf"] &&
      pdfContract && invalidRunsRejected &&
      Informal.PreviewManifest.stripFlag "--draft" ["--draft", "--pdf"] == ["--pdf"] &&
      Informal.PreviewManifest.helpText.contains "Blueprint PDF options"

end VersoBlueprintModuleTests.PreviewCli
