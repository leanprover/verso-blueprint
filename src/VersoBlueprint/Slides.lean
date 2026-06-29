/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoSlides
import Verso.Doc.Elab
import VersoBlueprint.PreviewManifest
import VersoBlueprint.Slides.Assets
import VersoBlueprint.Slides.Node
import VersoBlueprint.Slides.Render

namespace Informal.Slides

open Verso Doc Elab

@[reducible] private def defaultSlidesGenreHtml :
    Verso.Doc.Html.GenreHtml VersoSlides.Slides IO :=
  inferInstance

@[reducible] private def blueprintSlidesGenreHtml
    (renderContext : Informal.Graft.RenderContext) :
    Verso.Doc.Html.GenreHtml VersoSlides.Slides IO :=
  { defaultSlidesGenreHtml with
    block := fun inlineHtml blockHtml container contents => do
      match container with
      | .wrap attrs =>
        match renderBlueprintSlideNodeFromAttrs? renderContext attrs with
        | some render => render
        | none => defaultSlidesGenreHtml.block inlineHtml blockHtml container contents
      | _ =>
        defaultSlidesGenreHtml.block inlineHtml blockHtml container contents
  }

/--
Local upstream workaround pending the Verso Slides `Block.ofHtml` constructor
tracked in `doc/UPSTREAM_BACKLOG.md`: keep this close to upstream `slidesMain`
so the copied asset/write loop can disappear.
-/
private def slidesMainWithBlueprintRenderer
    (config : VersoSlides.Config)
    (manifest? : Option Informal.PreviewManifest.File)
    (htmlCache? : Option Informal.PreviewManifest.HtmlCache.File)
    (doc : Verso.Doc.Part VersoSlides.Slides)
    (quiet : Bool := false) : IO UInt32 := do
  let assetPlan ← collectSlideAssets config
  let hasError ← IO.mkRef false
  let logError (msg : String) : IO Unit := do
    hasError.set true
    IO.eprintln msg
  let renderContext := Informal.Graft.RenderContext.ofPreviewData? manifest? htmlCache?
    (logError := logError)
  let (doc, traverseState) ←
    (VersoSlides.Slides.traverse doc : VersoSlides.TraverseM (Verso.Doc.Part VersoSlides.Slides)) () {}
  let ctx : Verso.Doc.Html.HtmlT.Context VersoSlides.Slides IO := {
    options := { logError := logError }
    traverseContext := ()
    traverseState := traverseState
    definitionIds := {}
    linkTargets := {}
    codeOptions := {}
  }
  let initialHoverState := htmlCache?.map (·.hoverState) |>.getD {}
  let (slidesHtml, hoverState) ←
    (let _ : Verso.Doc.Html.GenreHtml VersoSlides.Slides IO :=
        blueprintSlidesGenreHtml renderContext
     (VersoSlides.renderDocument config doc).run ctx |>.run initialHoverState)
  let title := VersoSlides.inlinesToPlainText doc.title
  let fullHtml := VersoSlides.renderFullHtml config title slidesHtml traverseState.cssBlocks
  let dir := config.outputDir
  if !(← dir.pathExists) then
    IO.FS.createDirAll dir
  let indexPath := dir / "index.html"
  IO.FS.writeFile indexPath ("<!doctype html>\n" ++ fullHtml.asString)
  IO.FS.writeFile (dir / "-verso-docs.json") (toString hoverState.dedup.docJson)
  VersoSlides.writeVendoredAssets dir config.theme
  writeSlideAssets dir assetPlan
  writeSlideImages dir traverseState.imageFiles
  unless quiet do
    IO.println s!"Slides written to {indexPath}"
  if ← hasError.get then
    IO.eprintln "Errors were encountered!"
    pure 1
  else
    pure 0

/--
Generate a slide deck with Blueprint preview-node assets enabled.

When `previewManifest?` and `previewHtmlCache?` are provided, the manifest and
rendered-fragment cache are read during slide generation so `{blueprint_node}`
blocks render as static Blueprint shells. Both files are also copied to the
deck's `-verso-data/` directory after the deck is written, alongside the ESM
runtime modules used to hydrate the deck in the browser.
-/
public def slidesMainWithBlueprintPreviews
    (config : VersoSlides.Config := {})
    (previewManifest? : Option System.FilePath := none)
    (doc : Verso.Doc.Part VersoSlides.Slides)
    (previewHtmlCache? : Option System.FilePath := none)
    (quiet : Bool := false) : IO UInt32 := do
  let config := withBlueprintSlidesAssets config
  let htmlCachePath? := previewHtmlCache? <|> previewManifest?.map (fun path =>
    path.parent.getD "." / Informal.PreviewManifest.htmlCacheFilename)
  let manifest? ← previewManifest?.mapM Informal.Graft.readBlueprintManifest
  let htmlCache? ← htmlCachePath?.mapM Informal.Graft.readBlueprintHtmlCache
  let rc ← slidesMainWithBlueprintRenderer config manifest? htmlCache? doc (quiet := quiet)
  if rc == 0 then
    Informal.PreviewManifest.writeBlueprintRuntimeModules (config.outputDir / "-verso-data")
    writeBlueprintSlidesRuntimeModules config.outputDir
    if let some previewManifest := previewManifest? then
      copyBlueprintManifest config.outputDir previewManifest
    if let some previewHtmlCache := htmlCachePath? then
      copyBlueprintHtmlCache config.outputDir previewHtmlCache
  pure rc

end Informal.Slides
