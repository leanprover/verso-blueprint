/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Init.Data.Random
import VersoBlueprint.Slides
import Verso.Doc.Concrete
import VersoBlueprintTests.Blueprint.Support
import VersoBlueprintTests.BlueprintPreviewWiring.Shared

open VersoSlides

namespace Verso.VersoBlueprintTests.BlueprintSlides

open Verso
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

#docs (Slides) blueprintNodeSlideFixture "Blueprint Node Slide" :=
:::::::
# Example Blueprint Node

{blueprint_node "addition_assoc" (siteBase := "blueprint")}
:::::::

#docs (Slides) staticBlueprintNodeSlideFixture "Static Blueprint Node Slide" :=
:::::::
# Static Blueprint Node

{blueprint_node "def:code.preview" (siteBase := "blueprint")}
:::::::

#docs (Slides) sideBySideBlueprintNodeSlideFixture "Side-by-Side Blueprint Node Slide" :=
:::::::
# Side-by-Side Blueprint Nodes

:::blueprint_side_by_side +boxed
{blueprint_node "def:graft.slide.left" -header (siteBase := "blueprint")}

{blueprint_node "def:graft.slide.right" -header (siteBase := "blueprint")}
:::
:::::::

#docs (Genre.Manual) slideMetadataPanelDoc "Slide Metadata Panel" :=
:::::::
:::definition "def:slide.meta.panel" (tags := "slides, renderer") (effort := "small") (priority := "high")
Manifest-backed slide rendering should use the standard Blueprint block renderer.
:::
:::::::

#docs (Genre.Manual) slideGraftSourceDoc "Slide Blueprint Graft Sources" :=
:::::::
:::definition "def:graft.slide.left"
Slide left graft body.
:::

:::definition "def:graft.slide.right"
Slide right graft body.
:::
:::::::

private def blueprintNode (label key : String) : Informal.Graft.BlueprintNode where
  label := label
  facet := "statement"
  key := key
  displayLabel? := none
  compact := false
  siteBase? := some "blueprint"

private def manifestCodeEntry (key : String) : Informal.PreviewManifest.Entry where
  key := key
  targetKind := .leanDecl
  label := Lean.Name.mkSimple key
  facet := .statement
  title := key

private def htmlCacheEntry (key html : String) : Informal.PreviewManifest.HtmlCache.Entry where
  key := key
  html := html

private def manifestBlockEntry (key : String) (codeKeys : Array String) :
    Informal.PreviewManifest.Entry where
  key := key
  targetKind := .block
  label := Lean.Name.mkSimple key
  facet := .statement
  title := key
  leanCodePreviewKeys := codeKeys

private def dummySlidesCss (filename body : String) : VersoSlides.CssFile where
  filename
  contents := ⟨body⟩

private partial def freshSlidesSmokeRoot : IO System.FilePath := do
  let suffix ← IO.rand 0 1000000000000
  let root :=
    System.FilePath.mk ".lake" / "build" / "tmp" /
      "verso-blueprint-slides-smoke-test" / toString suffix
  if ← root.pathExists then
    freshSlidesSmokeRoot
  else
    pure root

private def buildPreviewDataFor
    (doc : Doc.VersoDoc Genre.Manual) : IO Informal.PreviewManifest.Files :=
  buildManualPreviewDataFiles manualImpls doc

private def writeSlidesPreviewDataFiles
    (root : System.FilePath)
    (files : Informal.PreviewManifest.Files) : IO System.FilePath := do
  let manifestPath := root / Informal.PreviewManifest.manifestFilename
  let htmlCachePath := root / Informal.PreviewManifest.htmlCacheFilename
  if !(← root.pathExists) then
    IO.FS.createDirAll root
  IO.FS.writeFile manifestPath (Lean.toJson files.manifest).compress
  IO.FS.writeFile htmlCachePath (Lean.toJson files.htmlCache).compress
  pure manifestPath

/-- info: true -/
#guard_msgs in
#eval
  let cfg := Informal.Slides.withBlueprintSlidesAssets {}
  let cfgAgain := Informal.Slides.withBlueprintSlidesAssets cfg
  let matchingHeads :=
    cfg.extraHead.filter fun html =>
      hasAllSubstr html.asString [
        "<script type=\"module\"",
        Informal.Slides.blueprintSlideRuntimeModulePath
      ]
  matchingHeads.size == 1 &&
    cfgAgain.extraHead.size == cfg.extraHead.size

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let root ← freshSlidesSmokeRoot
    let outDir := root / "slides"
    Informal.PreviewManifest.writeBlueprintRuntimeModules (outDir / "-verso-data")
    Informal.Slides.writeBlueprintSlidesRuntimeModules outDir
    let runtime ← IO.FS.readFile
      (outDir / "-verso-data" / Informal.Slides.blueprintSlideRuntimeModuleFilename)
    let slides ← IO.FS.readFile
      (outDir / "-verso-data" / Informal.Slides.blueprintSlidesModulePath)
    pure <|
      hasAllSubstr runtime [
        "import { createPreview } from \"./api/preview.mjs\";",
        "import { startGraphRuntime } from \"./Commands/graph.mjs\";",
        "import { start as startBlueprintSlides } from \"./Slides/blueprint-slides.mjs\";",
        "startBlueprintSlides(preview)"
      ] &&
      hasAllSubstr slides [
        "export function start(previewUtils",
        "preview.registerPreviewHydrator(\"slideBlueprintLinks\"",
        "preview.hydrate(node)",
        "data-bp-slide-href",
        "data-bp-slide-link"
      ] &&
      lacksAllSubstr slides [
        "window.VersoBlueprint.onRenderReady",
        "window.bpSlideNodeRuntime",
        "window.bpSlideNodeRuntimeConfig"
      ] &&
      (← (outDir / "-verso-data" / "api" / "preview.mjs").pathExists) &&
      (← (outDir / "-verso-data" / "Commands" / "graph.mjs").pathExists)

/-- info: true -/
#guard_msgs in
#eval
  let node := blueprintNode "def:code.preview" "def:code.preview--statement"
  Informal.Graft.BlueprintNode.fromAttrs? node.toAttrs == some node

/-- info: true -/
#guard_msgs in
#eval
  let node := { blueprintNode "def:code.preview" "def:code.preview--statement" with
    displayLabel? := some "Custom slide label" }
  let attrs := node.toAttrs
  Informal.Graft.BlueprintNode.fromAttrs? attrs == some node &&
    attrs.contains ("data-bp-display-label", "Custom slide label") &&
    !(attrs.any (fun attr => attr.1 == "data-bp-title"))

/-- info: true -/
#guard_msgs in
#eval
  let node := { blueprintNode "def:code.preview" "def:code.preview--statement" with
    showHeader := false }
  let attrs := node.toAttrs
  Informal.Graft.BlueprintNode.fromAttrs? attrs == some node &&
    attrs.contains ("data-bp-show-header", "false")

/-- info: true -/
#guard_msgs in
#eval
  let blockEntry := manifestBlockEntry "block" #["a", "b", "c"]
  let file : Informal.PreviewManifest.File := {
    previews := #[
      blockEntry,
      manifestCodeEntry "a",
      manifestCodeEntry "b",
      manifestCodeEntry "c"
    ]
  }
  let cache : Informal.PreviewManifest.HtmlCache.File := {
    entries := #[
      htmlCacheEntry "a" "<pre>same</pre>",
      htmlCacheEntry "b" "<pre>same</pre>",
      htmlCacheEntry "c" "<pre>different</pre>"
    ]
  }
  let index := file.index
  index.codeEntryCount blockEntry == 3 &&
    (index.codeEntries blockEntry).map (·.key) == #["a", "b", "c"] &&
    cache.codeHtmlBodies blockEntry == #["<pre>same</pre>", "<pre>different</pre>"]

/-- info: true -/
#guard_msgs in
#eval
  let cfg := Informal.Slides.withBlueprintSlidesAssets {}
  let cfgAgain := Informal.Slides.withBlueprintSlidesAssets cfg
  cfg.extraCss.any (·.filename == Informal.Slides.blueprintSlidesCssFilename) &&
    cfg.extraHead.any (fun html =>
      hasSubstr html.asString Informal.Slides.blueprintSlideRuntimeModulePath) &&
    cfg.extraJs.isEmpty &&
    cfgAgain.extraCss.size == cfg.extraCss.size &&
    cfgAgain.extraHead.size == cfg.extraHead.size &&
    cfgAgain.extraJs.size == cfg.extraJs.size

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    try
      let _ ← Informal.Slides.slidesMainWithBlueprintPreviews
        { outputDir := ".lake/build/tmp/verso-blueprint-slides-config-collision",
          extraCss := #[dummySlidesCss "dup.css" "one", dummySlidesCss "dup.css" "two"] }
        (previewManifest? := none)
        staticBlueprintNodeSlideFixture.toPart
        (quiet := true)
      pure false
    catch ex =>
      let msg := toString ex
      pure <|
        hasSubstr msg "Filename collision in config" &&
          hasSubstr msg "dup.css" &&
          hasSubstr msg "extraCss" &&
          hasSubstr msg "text"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildPreviewDataFor leanCodeLinkPreviewDoc
    let file := files.manifest
    let cache := files.htmlCache
    let blockKey := Informal.PreviewCache.statementKey (Lean.Name.mkSimple "def:code.preview")
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey `Nat.add
    let some blockEntry := file.previews.find? (fun entry => entry.key == blockKey)
      | return false
    let some blockHtml := cache.findHtml? blockKey
      | return false
    let some codeHtml := cache.findHtml? codeKey
      | return false
    pure <|
        blockEntry.leanCodePreviewKeys.contains codeKey &&
        blockEntry.codeData.isSome &&
        hasSubstr blockHtml "Statement with an associated Lean declaration link" &&
        hasSubstr codeHtml "bp_external_decl_rendered" &&
        blockEntry.displayCaption == some "Definition" &&
        blockEntry.displayLabel.any (fun label => !label.trimAscii.isEmpty) &&
        file.previews.any (fun entry =>
          entry.key == codeKey &&
            match entry.targetKind with
            | .leanDecl => true
            | _ => false)

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildPreviewDataFor usedByPreviewDoc
    let cache := files.htmlCache
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedByPreviewTarget
    let some codeHtml := cache.findHtml? codeKey
      | return false
    pure <|
      hasSubstr codeHtml "class=\"hl lean block\"" &&
        hasSubstr codeHtml "examples" &&
        hasSubstr codeHtml "data-verso-hover=" &&
        !files.htmlCache.hoverDocs.isEmpty &&
        files.htmlCache.hoverDocs.all (fun doc => doc.id >= Informal.PreviewManifest.HtmlCache.hoverIdStart) &&
        !hasSubstr codeHtml "<pre>def "

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildPreviewDataFor usedByPreviewDoc
    let file := files.manifest
    let blockKey := Informal.PreviewCache.statementKey (Lean.Name.mkSimple "def:used.target")
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedByPreviewTarget
    let some blockEntry := file.previews.find? (fun entry => entry.key == blockKey)
      | return false
    pure <| blockEntry.leanCodePreviewKeys.contains codeKey

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildPreviewDataFor leanCodeLinkPreviewDoc
    let key := Informal.PreviewCache.statementKey (Lean.Name.mkSimple "def:code.preview")
    let ctx := Informal.Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)
    let renderedHtml ← Informal.Slides.renderBlueprintSlideNode ctx
      (blueprintNode "def:code.preview" key)
    let rendered := renderedHtml.asString
    pure <|
      hasSubstr rendered "data-bp-rendered=\"static\"" &&
        hasSubstr rendered "bp_slide_node_blueprint" &&
        hasSubstr rendered "bp_extra_slot_code" &&
        hasSubstr rendered "bp_code_panel_wrapper" &&
        hasSubstr rendered "data-bp-site-base=\"blueprint\"" &&
        hasSubstr rendered "href=\"#--informal-preview" &&
        !hasSubstr rendered "Loading Blueprint node"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildPreviewDataFor slideMetadataPanelDoc
    let key := Informal.PreviewCache.statementKey (Lean.Name.mkSimple "def:slide.meta.panel")
    let ctx := Informal.Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)
    let renderedHtml ← Informal.Slides.renderBlueprintSlideNode ctx
      (blueprintNode "def:slide.meta.panel" key)
    let rendered := renderedHtml.asString
    pure <|
      hasSubstr rendered "class=\"bp_metadata_panel\"" &&
        hasSubstr rendered "slides" &&
        hasSubstr rendered "renderer" &&
        hasSubstr rendered "Effort" &&
        hasSubstr rendered "small" &&
        hasSubstr rendered "Priority" &&
        hasSubstr rendered "high"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildPreviewDataFor groupPreviewDoc
    let file := files.manifest
    let key := Informal.PreviewCache.statementKey (Lean.Name.mkSimple "def:group.target")
    let some entry := file.previews.find? (fun entry => entry.key == key)
      | return false
    let groupManifestOk :=
      match entry.group with
      | some group =>
        group.declared &&
          group.entries.size == 2 &&
          !group.entries.any (fun related => related.label == entry.label)
      | none => false
    let usedByManifestOk :=
      match entry.usedBy[0]? with
      | some related =>
        entry.usedBy.size == 1 &&
          related.axes.contains Informal.PreviewManifest.RelationAxis.statement
      | none => false
    let ctx := Informal.Graft.RenderContext.ofPreviewData? (some file) (some files.htmlCache)
    let renderedHtml ← Informal.Slides.renderBlueprintSlideNode ctx
      (blueprintNode "def:group.target" key)
    let rendered := renderedHtml.asString
    pure <|
      groupManifestOk &&
        usedByManifestOk &&
        hasSubstr rendered "bp_extra_slot_group" &&
        hasSubstr rendered "bp_extra_slot_used_by" &&
        hasSubstr rendered "data-bp-slide-panel=\"group\"" &&
        hasSubstr rendered "data-bp-slide-panel=\"used-by\"" &&
        hasSubstr rendered "Group: Preview group title. (2)" &&
        hasSubstr rendered "bp_relation_item_active" &&
        !hasSubstr rendered "Loading Blueprint node"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildPreviewDataFor missingGroupPreviewDoc
    let file := files.manifest
    let key := Informal.PreviewCache.statementKey (Lean.Name.mkSimple "def:group.missing.target")
    let some entry := file.previews.find? (fun entry => entry.key == key)
      | return false
    let groupManifestOk :=
      match entry.group with
      | some group => !group.declared && group.entries.size == 1
      | none => false
    let ctx := Informal.Graft.RenderContext.ofPreviewData? (some file) (some files.htmlCache)
    let renderedHtml ← Informal.Slides.renderBlueprintSlideNode ctx
      (blueprintNode "def:group.missing.target" key)
    let rendered := renderedHtml.asString
    pure <|
      groupManifestOk &&
        hasSubstr rendered "bp_extra_slot_group" &&
        hasSubstr rendered "bp_relation_chip_warn" &&
        hasSubstr rendered "data-bp-slide-panel=\"group\"" &&
        hasSubstr rendered "Undeclared group"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildPreviewDataFor leanCodeLinkPreviewDoc
    let root ← freshSlidesSmokeRoot
    let outDir := root / "slides"
    let manifestPath ← writeSlidesPreviewDataFiles root files
    let rc ← Informal.Slides.slidesMainWithBlueprintPreviews
      { outputDir := outDir }
      (previewManifest? := some manifestPath)
      staticBlueprintNodeSlideFixture.toPart
      (quiet := true)
    if rc != 0 then
      return false
    let indexPath := outDir / "index.html"
    if !(← indexPath.pathExists) then
      return false
    let index ← IO.FS.readFile indexPath
    let copiedManifest := Informal.Slides.blueprintSlidesManifestPath outDir
    let copiedHtmlCache := Informal.Slides.blueprintSlidesHtmlCachePath outDir
    let normalizedKey := Informal.PreviewCache.statementKey (Lean.Name.mkSimple "def:code.preview")
    let slideRuntimePath := outDir / "-verso-data" / Informal.Slides.blueprintSlideRuntimeModuleFilename
    let slideRuntimeModulePath := outDir / "-verso-data" / Informal.Slides.blueprintSlidesModulePath
    pure <|
      (← copiedManifest.pathExists) &&
        (← copiedHtmlCache.pathExists) &&
        (← slideRuntimePath.pathExists) &&
        (← slideRuntimeModulePath.pathExists) &&
        hasSubstr index "data-bp-rendered=\"static\"" &&
        hasSubstr index "bp_slide_node_blueprint" &&
        hasSubstr index "bp_extra_slot_code" &&
        hasSubstr index s!"data-bp-preview-key=\"{normalizedKey}\"" &&
        hasSubstr index "data-bp-site-base=\"blueprint\"" &&
        hasSubstr index s!"src=\"{Informal.Slides.blueprintSlideRuntimeModulePath}\"" &&
        !hasSubstr index "blueprint-slides.js" &&
        hasSubstr index "href=\"#--informal-preview" &&
        !hasSubstr index "Loading Blueprint node"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildPreviewDataFor slideGraftSourceDoc
    let root ← freshSlidesSmokeRoot
    let outDir := root / "slides"
    let manifestPath ← writeSlidesPreviewDataFiles root files
    let rc ← Informal.Slides.slidesMainWithBlueprintPreviews
      { outputDir := outDir }
      (previewManifest? := some manifestPath)
      sideBySideBlueprintNodeSlideFixture.toPart
      (quiet := true)
    if rc != 0 then
      return false
    let indexPath := outDir / "index.html"
    if !(← indexPath.pathExists) then
      return false
    let index ← IO.FS.readFile indexPath
    pure <|
      hasSubstr index "bp_graft_side_by_side" &&
        countSubstr index "data-bp-rendered=\"static\"" == 2 &&
        hasSubstr index "Slide left graft body." &&
        hasSubstr index "Slide right graft body." &&
        !hasSubstr index "Blueprint node not found" &&
        !hasSubstr index "Loading Blueprint node"

end Verso.VersoBlueprintTests.BlueprintSlides
