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

@[reducible] private def defaultSlidesTraverse :
    Verso.Doc.Traverse VersoSlides.Slides VersoSlides.TraverseM :=
  inferInstance

/--
During the normal Verso Slides traversal, turn `{blueprint_node}` placeholders
into already-rendered HTML blocks.

`blueprint_node` elaboration only knows the requested label/options, so it emits
a `BlockExt.wrap` placeholder. At `slidesMainWithBlueprintPreviews` time we also
have the Blueprint manifest/cache and can render that placeholder to static
Blueprint HTML. `BlockExt.ofHtml` hands the result back to the normal Slides
renderer.
-/
@[reducible] private def blueprintSlidesTraverse
    (renderContext : Informal.Graft.RenderContext) :
    Verso.Doc.Traverse VersoSlides.Slides VersoSlides.TraverseM :=
  { defaultSlidesTraverse with
    genreBlock := fun container contents => do
      match container with
      | .wrap attrs =>
          match Informal.Graft.BlueprintNode.fromAttrs? attrs with
          | some node =>
              let html ← renderBlueprintSlideNode renderContext node
              pure <| some <| .other (VersoSlides.BlockExt.ofHtml html) #[]
          | none =>
              defaultSlidesTraverse.genreBlock container contents
      | _ =>
          defaultSlidesTraverse.genreBlock container contents
  }

/--
Render Blueprint slide-node carriers to `VersoSlides.BlockExt.ofHtml` during
the normal Verso Slides traversal.

Backport note: the supported 4.30 branch keeps its older
`GenreHtml.block` override because `verso-slides` 4.30 does not provide
`BlockExt.ofHtml`. The current implementation uses `BlockExt.ofHtml` while
still mirroring the small `slidesMain` output loop so `quiet := true` remains
supported and the rendered-fragment cache can seed the generated hover table.
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
  let logger : Verso.Logger IO := {
    log severity text loc := do
      match severity with
      | .error => hasError.set true
      | .warning => pure ()
      IO.eprintln (Verso.LogMessage.format { severity, text, loc })
    errors := pure #[]
    warnings := pure #[]
  }
  let renderContext := Informal.Graft.RenderContext.ofPreviewData? manifest? htmlCache?
    (logError := logError)
  let traverseDoc : VersoSlides.TraverseM (Verso.Doc.Part VersoSlides.Slides) :=
    let _ : Verso.Doc.Traverse VersoSlides.Slides VersoSlides.TraverseM :=
      blueprintSlidesTraverse renderContext
    VersoSlides.Slides.traverse doc
  let (doc, traverseState) ← traverseDoc () {}
  let ctx : Verso.Doc.Html.HtmlT.Context VersoSlides.Slides := {
    options := {}
    traverseContext := ()
    traverseState := traverseState
    definitionIds := {}
    linkTargets := {}
    codeOptions := {}
  }
  let initialHoverState := htmlCache?.map (·.hoverState) |>.getD {}
  let render : Verso.Doc.Html.HtmlT VersoSlides.Slides (Verso.BuildLogT IO) Verso.Output.Html :=
    VersoSlides.renderDocument config doc
  let (slidesHtml, hoverState) ←
    ((render.run ctx).run initialHoverState).run logger
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
