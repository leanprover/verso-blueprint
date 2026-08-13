/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Std.Data.HashMap
import VersoSlides
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Graft.Assets
import VersoBlueprint.Html
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.PreviewManifest

namespace Informal.Slides

def blueprintSlidesCssFilename : String := "blueprint-slides.css"
def blueprintSlideRuntimeModuleFilename : String := "blueprint-slide-runtime.mjs"
def blueprintSlidesModulePath : String := "Slides/blueprint-slides.mjs"
def blueprintSlideRuntimeModulePath : String := "-verso-data/" ++ blueprintSlideRuntimeModuleFilename

private def slideNodeCss : String := include_str "blueprint-slides.css"
private def slideRuntimeModuleMjs : String := include_str "blueprint-slide-runtime.mjs"
private def slideNodeHydrationModuleMjs : String := include_str "blueprint-slides.mjs"

def blueprintSlidesAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  { css :=
      (Informal.Commands.previewPanelInlinePreviewCssAssetBundle
        [ Informal.Block.Assets.css,
          Informal.Graft.css,
          Verso.Genre.Manual.docstringStyle,
          Informal.Commands.graphCss,
          slideNodeCss]).css }

def blueprintSlidesCss : String :=
  String.intercalate "\n\n" blueprintSlidesAssetBundle.css

def blueprintSlidesCssFile : VersoSlides.CssFile where
  filename := blueprintSlidesCssFilename
  contents := ⟨blueprintSlidesCss⟩

private def pushIfMissing [BEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

private def blueprintSlideRuntimeHead : Verso.Output.Html :=
  open Verso.Output.Html in
  {{<script type="module" src={{blueprintSlideRuntimeModulePath}}></script>}}

private def ensureParentDir (path : System.FilePath) : IO Unit := do
  let dir := path.parent.getD "."
  if !(← dir.pathExists) then
    IO.FS.createDirAll dir

private def writeTextFileWithDirs (path : System.FilePath) (content : String) : IO Unit := do
  ensureParentDir path
  IO.FS.writeFile path content

private def writeBinFileWithDirs (path : System.FilePath) (content : ByteArray) : IO Unit := do
  ensureParentDir path
  IO.FS.writeBinFile path content

def writeSlideImages
    (outputDir : System.FilePath)
    (imageFiles : Std.HashMap String String) : IO Unit := do
  unless imageFiles.isEmpty do
    let imagesDir := outputDir / "images"
    IO.FS.createDirAll imagesDir
    for (resolved, outputName) in imageFiles.toList do
      let contents ← IO.FS.readBinFile resolved
      writeBinFileWithDirs (imagesDir / outputName) contents

/-- Add the Blueprint slide CSS assets to a Verso Slides config. -/
public def withBlueprintSlidesAssets (config : VersoSlides.Config := {}) : VersoSlides.Config :=
  { config with
    extraCss := pushIfMissing config.extraCss blueprintSlidesCssFile
    extraHead := VersoBlueprint.Html.pushIfRenderedMissing config.extraHead
      blueprintSlideRuntimeHead }

/-- Write the slide-specific ESM runtime files under the deck's `-verso-data/`. -/
public def writeBlueprintSlidesRuntimeModules (outputDir : System.FilePath) : IO Unit := do
  let dataDir := outputDir / "-verso-data"
  writeTextFileWithDirs (dataDir / blueprintSlideRuntimeModuleFilename) slideRuntimeModuleMjs
  writeTextFileWithDirs (dataDir / blueprintSlidesModulePath) slideNodeHydrationModuleMjs

private def blueprintSlidesDataPath (outputDir : System.FilePath) (filename : String) :
    System.FilePath :=
  outputDir / "-verso-data" / filename

/-- Output path where slide decks expect the semantic Blueprint manifest. -/
public def blueprintSlidesManifestPath (outputDir : System.FilePath) : System.FilePath :=
  blueprintSlidesDataPath outputDir Informal.PreviewManifest.manifestFilename

/-- Output path where slide decks expect the rendered-fragment cache. -/
public def blueprintSlidesHtmlCachePath (outputDir : System.FilePath) : System.FilePath :=
  blueprintSlidesDataPath outputDir Informal.PreviewManifest.htmlCacheFilename

/-- Copy a generated semantic Blueprint manifest into a slide deck output directory. -/
public def copyBlueprintManifest
    (outputDir source : System.FilePath) : IO Unit := do
  let contents ← IO.FS.readFile source
  writeTextFileWithDirs (blueprintSlidesManifestPath outputDir) contents

/-- Copy a generated rendered-fragment cache into a slide deck output directory. -/
public def copyBlueprintHtmlCache
    (outputDir source : System.FilePath) : IO Unit := do
  let contents ← IO.FS.readFile source
  writeTextFileWithDirs (blueprintSlidesHtmlCachePath outputDir) contents

end Informal.Slides
