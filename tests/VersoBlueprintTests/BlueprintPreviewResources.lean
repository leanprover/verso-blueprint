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

-- Choices carry their own branches: fragments from independent producers can
-- be composed, copied, and resolved repeatedly without a shared mutable session.
#eval show IO Unit from do
  let some keyA := PreviewKey.ofString? (PreviewCache.statementKey `choice_a)
    | throw <| IO.userError "Invalid choice A key"
  let some keyB := PreviewKey.ofString? (PreviewCache.statementKey `choice_b)
    | throw <| IO.userError "Invalid choice B key"
  let a := PreviewResources.deferred keyA (fun _ => .text true "A+") (fun _ => .text true "A-")
  let b := PreviewResources.deferred keyB (fun _ => .text true "B+") (fun _ => .text true "B-")
  let nested := PreviewResources.deferred keyA (fun _ => .seq #[a, b]) (fun _ => b)
  let combined : Output.Html := .seq #[a, b, nested, a]
  let .ok resolved := PreviewResources.finish (· == keyA) combined
    | throw <| IO.userError "Independent choices failed to compose"
  unless resolved.asString == "A+B-A+B-A+" do
    throw <| IO.userError s!"Choice resolved another producer's content: {resolved.asString}"
  let .ok repeated := PreviewResources.finish (fun _ => false) resolved
    | throw <| IO.userError "Resolved HTML could not be finalized again"
  unless repeated.asString == resolved.asString do
    throw <| IO.userError "Finalization changed already resolved HTML"
  let raw := "<verso-blueprint-preview-choice key=\"opaque\">external HTML</verso-blueprint-preview-choice>"
  let .ok rawResult := PreviewResources.finish (fun _ => false) (.text false raw)
    | throw <| IO.userError "Opaque HTML was interpreted as a choice"
  unless rawResult.asString == raw do
    throw <| IO.userError "Finalization rewrote opaque HTML"
  let malformed : Output.Html := .tag "verso-blueprint-preview-choice" #[] .empty
  let emptyKey : Output.Html := .tag "verso-blueprint-preview-choice" #[("key", "")]
    (.seq #[.text true "present", .text true "absent"])
  let presence := PreviewResources.deferred keyA (fun _ => .text true "body") (fun _ => .empty)
  unless !PreviewResources.htmlIsBlank malformed && !PreviewResources.htmlIsBlank presence do
    throw <| IO.userError "Blank-body filtering concealed an invalid choice"
  for (fragment, diagnostic) in #[(malformed, "Malformed"), (emptyKey, "Empty"),
      (presence, "changes body presence")] do
    match PreviewResources.finish (fun _ => true) fragment with
    | .error message =>
      unless hasSubstr message diagnostic do
        throw <| IO.userError s!"Unexpected choice diagnostic: {message}"
    | .ok _ => throw <| IO.userError s!"Invalid choice accepted: {diagnostic}"

-- Manifest-backed shells retain the same empty-status signals as live headers.
-- Proofs keep only their own relation controls.
#eval show IO Unit from do
  let statement : PreviewManifest.Entry := {
    label := `header_policy, key := "header_policy", targetKind := .block
    facet := .statement, kind := some .theorem, title := "Theorem 1" }
  let render := fun entry => PreviewManifest.BlockRender.renderWithRenderedContent {} entry
    { body := .text true "body" } |>.asString
  let statementHtml := render statement
  let proofHtml := render { statement with facet := .proof }
  unless hasSubstr statementHtml "No reverse dependencies" &&
      hasSubstr statementHtml "No associated Lean declarations" &&
      !(hasSubstr proofHtml "No reverse dependencies") &&
      !(hasSubstr proofHtml "No associated Lean declarations") do
    throw <| IO.userError "Manifest-backed header visibility differs from the shared facet policy"

theorem resourceWitness (n : Nat) : n + 0 = n := Nat.add_zero n

#docs (Manual) omittedDoc "Omitted resource" :=
:::::::
:::theorem "resource_omitted"
This known node is deliberately omitted from the selected document.
:::
:::::::

#docs (Manual) nestedDoc "Nested occurrence" :=
:::::::
:::lemma_ "resource_nested" (parent := "resource_group")
Nested relations use {uses "resource_missing" (origin := "automatic") (intent := "technical")}[],
{uses "resource_markup"}[], and {uses "resource_statement"}[].
A custom nested reference: {bpref "resource_missing"}[Nested unavailable target].
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
  -- Compiled occurrences can be nested by document composition even though
  -- authored Blueprint directives prohibit nested registrations.
  let nested : Doc.Block Manual := .concat nestedDoc.toPart.content
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
              .other container (contents.push nested |>.push (.other { name := `resourceProbe } #[]))
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
      let some cached := files.htmlCache.findHtml? availableKey
        | throw <| IO.userError "Missing statement resource"
      unless !(hasSubstr cached s!"data-bp-preview-key=\"{missingKey}\"") &&
          !(hasSubstr cached s!"data-bp-preview-key=\"{markupKey}\"") &&
          hasSubstr cached s!"data-bp-preview-key=\"{availableKey}\"" &&
          hasSubstr cached s!"<a href=\"{href}\" title=\"resource_missing\">Nested unavailable target</a>" do
        throw <| IO.userError "Cached references changed links or retained unavailable previews"
      for entry in files.htmlCache.entries do
        unless !(hasSubstr entry.html "verso-blueprint-preview-choice") do
          throw <| IO.userError "Deferred render marker leaked into a serialized resource"
      for doc in files.htmlCache.hoverDocs do
        unless !(hasSubstr doc.html "verso-blueprint-preview-choice") do
          throw <| IO.userError "Deferred render marker leaked into a hover payload"
      for (label, facet, expected) in #[
          (`resource_statement, PreviewCache.Facet.statement, #["s", "it"]),
          (`resource_statement, .proof, #["p"]),
          (`resource_nested, .statement, #["s", "oa", "it"])] do
        let some entry := files.manifest.findEntry? (PreviewCache.key label facet)
          | throw <| IO.userError s!"Missing relation source: {label}/{repr facet}"
        let some relation := entry.usesForFacet.find? (·.label == `resource_missing)
          | throw <| IO.userError "Manifest lost the unavailable dependency"
        unless relation.badgeCodes == expected do
          throw <| IO.userError s!"Manifest facet badges changed: {relation.badgeCodes}, expected {expected}"
        let .ok data := RenderingResolution.canonical prepared.state label
          | throw <| IO.userError "Missing live relation source"
        let some live := (RelatedPanel.usesEntries prepared.state data (some facet)).find?
            (·.label == `resource_missing)
          | throw <| IO.userError "Live view lost the unavailable dependency"
        unless live.dependencies == relation.dependencies && live.badgeCodes == expected do
          throw <| IO.userError "Live and manifest relation facts disagree"
        let shell := PreviewManifest.BlockRender.renderWithRenderedContent {} { entry with usedBy := #[] }
          { body := .text true "body" } |>.asString
        let mut found := false
        for part in (shell.splitOn "class=\"bp-relation-entries\">").drop 1 do
          let .ok rows := Json.parse (part.splitOn "</script>").head! >>=
              fromJson? (α := Array (Array Json))
            | throw <| IO.userError "Malformed manifest shell relation rows"
          for row in rows do
            if row[2]? == some (.str "resource_missing") then
              found := true
              unless row[4]? == some (toJson expected) do
                throw <| IO.userError "Manifest shell lost badges or mixed statement/proof metadata"
        unless found do
          throw <| IO.userError "Manifest shell omitted the dependency row"
      let mut nestedMissingRows := 0
      let mut nestedBadgeRows := 0
      for part in (cached.splitOn "class=\"bp-relation-entries\">").drop 1 do
        let .ok rows := Json.parse (part.splitOn "</script>").head! >>=
            fromJson? (α := Array (Array Json))
          | throw <| IO.userError "Malformed cached relation panel rows"
        for row in rows do
          if row[2]? == some (.str "resource_missing") then
            nestedMissingRows := nestedMissingRows + 1
            unless row[1]? == some Json.null && row[0]? == some (.str reference.title) &&
                row[3]? == some (.str href) do
              throw <| IO.userError "Cached relation lost metadata or retained an unavailable key"
            if row[4]? == some (toJson #["s", "oa", "it"]) then
              nestedBadgeRows := nestedBadgeRows + 1
      unless nestedMissingRows > 0 && nestedBadgeRows == 1 do
        throw <| IO.userError "Cached nested block did not retain its relation panel"
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
      verbose := true
      destination := root / s!"{modeName}-resumed"
      emitHtmlSingle := if isSingle then .resumeFrom checkpoint else .no
      emitHtmlMulti := if !isSingle then .resumeFrom checkpoint else .no }
    let (messages, code) ← generate resumed
    unless code == 0 && (← renders.get) == 2 && (← seen.get) do
      throw <| IO.userError s!"Resume: code={code}, renders={← renders.get}, seen={← seen.get}: {messages}"
    unless hasSubstr messages "Finalized and serialized" &&
        !(hasSubstr messages "stringify") do
      throw <| IO.userError "Verbose rendering did not report final serialization"
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
