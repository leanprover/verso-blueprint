/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.Blueprint.Support
import VersoBlueprint.Vbp

namespace Verso.VersoBlueprintTests.BlueprintPreviewResources

open Lean Verso Genre Manual Informal
open Verso.VersoBlueprintTests.Blueprint.Support

theorem resourceWitness (n : Nat) : n + 0 = n := Nat.add_zero n

#docs (Manual) omittedDoc "Omitted resource" :=
:::::::
:::theorem "resource_omitted"
This known node is deliberately omitted from the selected document.
:::
:::::::

#docs (Manual) resourceDoc "Preview resources" :=
:::::::
:::group "resource_group"
Resource group
:::

:::theorem "resource_statement" (lean := "resourceWitness") (parent := "resource_group")
The rendered statement has one preview resource and uses {uses "resource_markup"}[]
and {uses "resource_missing" (intent := "technical")}[].
:::

:::proof "resource_statement"
The proof uses {uses "resource_missing"}[].
:::

:::theorem "resource_missing" (parent := "resource_group")
A synthetic renderer will omit this body. It uses {uses "resource_statement"}[].
:::

:::theorem "resource_single" (parent := "resource_group")
This node has one dependency: {uses "resource_missing"}[].
:::

References: {bpref "resource_statement"}[Available target],
{bpref "resource_missing"}[Unavailable target], {bpref "resource_missing"}[],
{bpref "resource_markup"}[Semantic-only target], and {bpref "resource_omitted"}[].

```md "resource_markup" (slot := statement)
This semantic-only node must remain in the graph without a preview link.
```

{blueprint_graph}
:::::::

private def model : RenderModel := blueprint_render_model%

private def siteDirectory (config : Manual.Config) (mode : Mode) : System.FilePath :=
  config.destination / (match mode with | .single => "html-single" | .multi => "html-multi")

private def readGraphHtml (site : System.FilePath) (mode : Mode) : IO String :=
  IO.FS.readFile (site / (match mode with
    | .single => "index.html"
    | .multi => "Dependency-Graph/index.html"))

private def readFiles (root : System.FilePath) : IO PreviewManifest.PersistedFiles := do
  pure {
    manifest := ← PreviewManifest.readFile (root / "-verso-data" / PreviewManifest.manifestFilename)
    htmlCache := ← PreviewManifest.HtmlCache.readFile (root / "-verso-data" / PreviewManifest.htmlCacheFilename)
  }

-- Exercise actual generation rather than just comparing finalization wrappers.
-- A probe inside the informal body renders once for its resource and once for its page.
-- Export and post-render callbacks must reuse the prepared resources.
#eval show IO Unit from do
  let suffix ← IO.rand 0 1000000000000
  let root := (← IO.currentDir) / ".lake/build/tmp/preview-resources" / toString suffix
  IO.FS.createDirAll root
  let renders ← IO.mkRef 0
  let impls : ExtensionImpls := extension_impls%
  let impls := impls.insertBlock `resourceProbe {
    traverse := fun _ _ _ => pure none
    toHtml := some fun _ _ _ _ _ => do
      renders.modify (· + 1)
      pure (.text false "resource-probe")
    toTeX := none }
  let impls := impls.insertBlock `blankResource {
    traverse := fun _ _ _ => pure none
    toHtml := some fun _ _ _ _ _ => pure .empty
    toTeX := none }
  let text := { resourceDoc.toPart with
    content := resourceDoc.toPart.content.map fun block => block.rewriteOther
      (fun go container contents => .other container (contents.map go))
      (fun _ go container contents =>
        let contents := contents.map go
        if container.name == ``Informal.Block.informal then
          match fromJson? (α := BlockOccurrence) container.data with
          | .ok occurrence =>
            if occurrence.label == `resource_missing then
              .other container #[.other { name := `blankResource } #[]]
            else if occurrence.label == `resource_statement && !occurrence.isProof then
              .other container (contents.push (.other { name := `resourceProbe } #[]))
            else .other container contents
          | .error _ => .other container contents
        else .other container contents) }
  for mode in #[Mode.single, .multi] do
    let isSingle := match mode with | .single => true | .multi => false
    let modeName := match mode with | .single => "single" | .multi => "multi"
    let output := root / modeName
    let cfg : RenderConfig := {
      features := {}
      destination := output
      emitHtmlSingle := if isSingle then .immediately else .no
      emitHtmlMulti := if !isSingle then .immediately else .no }
    let seen ← IO.mkRef false
    let step : PreviewManifest.BlueprintExtraStep := fun prepared => do
      let some files := prepared.previewFiles?
        | throw <| IO.userError "Post-render step did not receive prepared resources"
      let path := siteDirectory prepared.config.toConfig prepared.mode
      let emitted ← readFiles path
      let validationErrors := VersoBlueprint.Vbp.checkGeneratedData emitted
      unless validationErrors.isEmpty do
        throw <| IO.userError s!"Prepared output failed data validation: {validationErrors}"
      unless toJson files.manifest == toJson emitted.manifest &&
          toJson files.htmlCache == toJson emitted.htmlCache do
        throw <| IO.userError "Export rebuilt or changed the prepared resources"
      let page ← IO.FS.readFile (path / "index.html")
      let missingKey := PreviewCache.key `resource_missing .statement
      let markupKey := PreviewSource.externalMarkupKey `resource_markup
      let availableKey := PreviewCache.key `resource_statement .statement
      unless !(hasSubstr page s!"data-bp-preview-key=\"{missingKey}\"") &&
          !(hasSubstr page s!"data-bp-preview-key=\"{markupKey}\"") &&
          hasSubstr page s!"data-bp-preview-key=\"{availableKey}\"" do
        throw <| IO.userError "Page inline references disagree with prepared availability"
      let .ok reference := RenderingResolution.reference prepared.state `resource_missing
        | throw <| IO.userError "Unavailable preview lost its semantic reference"
      let some href := reference.href | throw <| IO.userError "Unavailable preview lost its link"
      unless hasSubstr page s!"<a href=\"{href}\" title=\"resource_missing\">Unavailable target</a>" &&
          hasSubstr page s!"<a href=\"{href}\" title=\"resource_missing\">{reference.title}</a>" &&
          hasSubstr page "resource_omitted" do
        throw <| IO.userError "Unavailable previews changed link text, titles, or omitted-node fallback"
      let mut missingRows := 0
      let mut missingBadges := 0
      for part in (page.splitOn "class=\"bp-relation-entries\">").drop 1 do
        let .ok rows := Json.parse (part.splitOn "</script>").head! >>=
            fromJson? (α := Array (Array Json))
          | throw <| IO.userError "Malformed relation panel rows"
        for row in rows do
          if row[2]? == some (.str "resource_missing") then
            missingRows := missingRows + 1
            unless row[1]? == some Json.null && row[0]? == some (.str reference.title) &&
                row[3]? == some (.str href) do
              throw <| IO.userError "Unavailable preview dropped relation metadata or retained a key"
            if row[4]? != some (toJson (#[] : Array String)) then
              missingBadges := missingBadges + 1
      unless missingRows >= 4 && missingBadges >= 3 do
        throw <| IO.userError s!"Missing uses/used-by/group rows or badges: {missingRows}/{missingBadges}"
      unless (files.manifest.findEntry? missingKey).isNone &&
          (files.htmlCache.findHtml? missingKey).isNone do
        throw <| IO.userError "Blank resource unexpectedly acquired a manifest or cache body"
      seen.set true
    let generate := fun config => IO.FS.withIsolatedStreams <|
      PreviewManifest.blueprintMainWithPreviewData text
        ["--external-markup-render", "none"] impls (config := config)
        (extraSteps := [step]) (model := model)
    renders.set 0
    let (_, code) ← generate cfg
    unless code == 0 && (← renders.get) == 2 && (← seen.get) do
      throw <| IO.userError s!"Immediate {modeName}: code={code}, renders={← renders.get}"
    let site := siteDirectory cfg.toConfig mode
    let files ← readFiles site
    let html ← readGraphHtml site mode
    let some graph := files.manifest.graphs[0]?
      | throw <| IO.userError "Missing graph"
    unless hasSubstr html (toJson graph).compress do
      throw <| IO.userError "Embedded graph differs from the finalized manifest graph"
    let some markup := graph.nodes.find? (·.label == `resource_markup)
      | throw <| IO.userError "Finalization removed a semantic-only graph node"
    let some statement := graph.nodes.find? (·.label == `resource_statement)
      | throw <| IO.userError "Finalization removed the statement node"
    unless markup.previewKey.isNone && statement.previewKey.isSome do
      throw <| IO.userError "Graph preview availability disagrees with rendered resources"
    let markupKey := PreviewSource.externalMarkupKey `resource_markup
    unless (files.manifest.findEntry? markupKey).isSome &&
        (files.htmlCache.findHtml? markupKey).isNone do
      throw <| IO.userError "Semantic-only markup did not retain its manifest-only entry"
    -- Hover data must be merged after page emission, including the cache side table.
    let docs ← IO.FS.readFile (site / "-verso-docs.json")
    let .ok docs := Json.parse docs | throw <| IO.userError "Malformed merged hover docs"
    unless !files.htmlCache.hoverDocs.isEmpty do
      throw <| IO.userError "Hover-transfer regression has no resource hover payloads"
    for hover in files.htmlCache.hoverDocs do
      unless (docs.getObjVal? (toString hover.id)).isOk do
        throw <| IO.userError "Page emission overwrote a resource hover entry"
    let checkpoint := root / s!"{modeName}.json"
    let delayed := { cfg with
      destination := root / s!"{modeName}-delayed"
      emitHtmlSingle := if isSingle then .delay checkpoint else .no
      emitHtmlMulti := if !isSingle then .delay checkpoint else .no }
    renders.set 0
    seen.set false
    let (_, code) ← generate delayed
    unless code == 0 && (← renders.get) == 0 && !(← seen.get) &&
        !(← delayed.destination.pathExists) do
      throw <| IO.userError "Delayed generation prepared or emitted preview resources"
    let resumed := { cfg with
      destination := root / s!"{modeName}-resumed"
      emitHtmlSingle := if isSingle then .resumeFrom checkpoint else .no
      emitHtmlMulti := if !isSingle then .resumeFrom checkpoint else .no }
    let (messages, code) ← generate resumed
    unless code == 0 && (← renders.get) == 2 && (← seen.get) do
      throw <| IO.userError s!"Resume: code={code}, renders={← renders.get}, seen={← seen.get}: {messages}"
    let restored ← readFiles (siteDirectory resumed.toConfig mode)
    let restoredHtml ← readGraphHtml (siteDirectory resumed.toConfig mode) mode
    unless hasSubstr restoredHtml (toJson graph).compress &&
        toJson files.manifest == toJson restored.manifest &&
        toJson files.htmlCache == toJson restored.htmlCache do
      throw <| IO.userError "Immediate and resumed preview resources differ"
    -- Plain generation keeps traversal candidates and does no resource rendering.
    renders.set 0
    let plain := { cfg with destination := root / s!"{modeName}-plain" }
    let (_, code) ← IO.FS.withIsolatedStreams <|
      PreviewManifest.blueprintMain text (extensionImpls := impls)
        (options := []) (config := plain) (model := model)
    unless code == 0 && (← renders.get) == 1 do
      throw <| IO.userError "Plain generation unexpectedly prepared preview resources"
    let plainSite := siteDirectory plain.toConfig mode
    unless !(← (plainSite / "-verso-data" / PreviewManifest.manifestFilename).pathExists) do
      throw <| IO.userError "Plain generation emitted preview data"
    let plainHtml ← readGraphHtml plainSite mode
    unless hasSubstr plainHtml markupKey do
      throw <| IO.userError "Plain generation lost its traversal preview candidate"
    let some afterTag := (plainHtml.splitOn "class=\"bp-graph-data\">")[1]?
      | throw <| IO.userError "Plain generation emitted no graph JSON"
    let rawGraph := (afterTag.splitOn "</script>").head!
    let .ok candidate := Json.parse rawGraph >>= fromJson? (α := Graph.GraphData)
      | throw <| IO.userError "Could not decode the plain generator's graph"
    let index := PreviewManifest.PreviewArtifactIndex.ofPersistedFiles files
    unless !candidate.edges.isEmpty &&
        toJson (candidate.filterPreviewReferences (fun key => index.resolves key.value)) == toJson graph do
      throw <| IO.userError "Resource selection changed graph facts, links, or topology"

end Verso.VersoBlueprintTests.BlueprintPreviewResources
