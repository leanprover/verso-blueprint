/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Vbp
import VersoBlueprintTests.BlueprintAttributeRendering
import VersoBlueprintTests.BlueprintNumbering.ChapterA
import VersoBlueprintTests.BlueprintNumbering.ChapterB
import VersoBlueprintTests.BlueprintImportedContributions.DocstringA
import VersoBlueprintTests.BlueprintImportedContributions.DocstringB

open Lean Verso Informal Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests

namespace Verso.VersoBlueprintTests.BlueprintPlacementContracts

private def impls : ExtensionImpls := extension_impls%

#docs (Genre.Manual) contributorA "First contributor" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintImportedContributions.DocstringA}
:::::::

#docs (Genre.Manual) contributorB "Second contributor" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintImportedContributions.DocstringB}
:::::::

-- Selection is exact-module contribution, while rendering uses the merged node.
#eval show IO Unit from do
  for doc in #[contributorA, contributorB] do
    let html ← renderManualDocHtmlString impls doc
    unless hasSubstr html "docstringAttachmentA" && hasSubstr html "docstringAttachmentB" do
      throw <| IO.userError "Module inclusion lost a sibling's contribution"
  let html ← renderManualDocHtmlString impls contributorB
  unless !hasSubstr html "docstringAuthoredAttachment" do
    throw <| IO.userError "Module inclusion selected another module's distinct label"

set_option verso.blueprint.foldCodeBlocks true in
#docs (Genre.Manual) folded "Folded placement" :=
:::::::
{blueprint_node "attr.exported.theorem"}
:::::::

set_option verso.blueprint.foldCodeBlocks false in
#docs (Genre.Manual) expanded "Expanded placement" :=
:::::::
{blueprint_node "attr.exported.theorem"}
:::::::

#docs (Genre.Manual) compact "Compact placement" :=
:::::::
{blueprint_node "attr.exported.theorem" +compact}
:::::::

private def combine (docs : Array (Doc.VersoDoc Genre.Manual)) : Doc.VersoDoc Genre.Manual :=
  .mk (fun _ => { folded.toPart with content := #[], subParts := docs.map (·.toPart) }) "{}"

-- The advertised declaration link must name exactly one emitted row, including
-- compact-first placement. A compact-only document must not advertise a code row.
#eval show IO Unit from do
  let label := Name.mkSimple "attr.exported.theorem"
  let decl := ``BlueprintAttribute.Provider.exportedTheorem
  for doc in #[BlueprintAttributeRendering.placedAttributeDoc,
      BlueprintAttributeRendering.includedAttributeModuleDoc,
      combine #[folded, expanded], combine #[compact, expanded]] do
    let (html, state) ← renderManualDocHtmlStringAndState impls doc
    let some href := Resolve.resolveInformalDeclHref? state label decl
      | throw <| IO.userError "Missing declaration destination"
    let fragment := (href.splitOn "#").getLast!
    unless countSubstr html s!"id=\"{fragment}\"" == 1 do
      throw <| IO.userError s!"Declaration destination is missing or duplicated: {href}"
    let rows := (html.splitOn "bp_external_decl_item").length
    unless rows > 1 do throw <| IO.userError "Destination has no rendered code"
  let (_, state) ← renderManualDocHtmlStringAndState impls compact
  unless (Resolve.resolveRenderedExternalDeclHref? state label decl).isNone do
    throw <| IO.userError "Compact placement advertised code it does not render"

-- Each occurrence honors its own setting. The selected facet supplies the
-- exported default, independently of the second occurrence's override.
#eval show IO Unit from do
  for (docs, defaultFold) in #[(#[folded, expanded], true), (#[expanded, folded], false)] do
    let doc := combine docs
    let (html, state) ← renderManualDocHtmlStringAndState impls doc
    unless countSubstr html "class=\"bp_code_block bp_code_panel\"" == 2 &&
        countSubstr html "open=\"open\"" == 1 do
      throw <| IO.userError "Repeated placements lost occurrence-local folding"
    let files ← PreviewManifest.buildPreviewDataFiles impls (fun e => throw <| IO.userError e)
      (PreviewManifest.PreparedPreviewState.prepare state)
    let node := ({ label := "attr.exported.theorem" } : Graft.BlueprintNodeConfig).toNode
    let some entry := files.manifest.findEntry? node.key
      | throw <| IO.userError "Missing selected facet"
    let cached ← Graft.renderNodeFromManifestCache {}
      (Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)) node
    unless entry.foldCodeBlock == defaultFold &&
        hasSubstr cached.asString "open=\"open\"" == !defaultFold do
      throw <| IO.userError "Cached presentation disagrees with the selected occurrence"

set_option verso.blueprint.foldProofBlocks false in
#docs (Genre.Manual) statement "Statement" :=
:::::::
:::theorem "presentation.facets"
Statement with an unfolded proof default.
:::
:::::::

set_option verso.blueprint.foldProofBlocks true in
#docs (Genre.Manual) proof "Proof" :=
:::::::
:::proof "presentation.facets"
Proof with its own folded presentation.
:::
:::::::

#docs (Genre.Manual) proofGraft "Proof reuse" :=
:::::::
{blueprint_node "presentation.facets" (facet := "proof")}
:::::::

#eval show IO Unit from do
  for docs in #[#[statement, proof, proofGraft], #[proof, statement, proofGraft]] do
    let doc := combine docs
    let (html, state) ← renderManualDocHtmlStringAndState impls doc
    unless !hasSubstr html "open=\"open\"" do
      throw <| IO.userError "Direct proof and proof graft disagree on folding"
    let files ← PreviewManifest.buildPreviewDataFiles impls (fun e => throw <| IO.userError e)
      (PreviewManifest.PreparedPreviewState.prepare state)
    let node := ({ label := "presentation.facets", facet := some "proof" } : Graft.BlueprintNodeConfig).toNode
    let some entry := files.manifest.findEntry? node.key | throw <| IO.userError "Missing proof cache"
    let cached ← Graft.renderNodeFromManifestCache {}
      (Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)) node
    unless entry.foldProofBlock && !hasSubstr cached.asString "open=\"open\"" &&
        hasSubstr cached.asString "Proof with its own folded presentation." do
      throw <| IO.userError "Exported proof lost its facet-local presentation"

-- These chapters were elaborated independently, not fabricated as completed
-- occurrences. Reordering them or inserting an attribute placement cannot
-- change their positive local counts.
#eval show IO Unit from do
  let a := BlueprintNumbering.ChapterA.chapter
  let b := BlueprintNumbering.ChapterB.chapter
  for docs in #[#[a, b], #[b, a], #[a, expanded, b], #[b, expanded, a]] do
    let (_, state) ← renderManualDocHtmlStringAndState impls (combine docs)
    for chapterName in #["A", "B"] do
      for (suffix, expected) in #[("first", 1), ("second", 2)] do
        let label := Name.mkSimple s!"local.{chapterName}.{suffix}"
        let some data := TraversalIndex.Nodes.renderedData? state label
          | throw <| IO.userError "Missing numbered chapter"
        unless data.count == expected do
          throw <| IO.userError s!"Ordinary source-local count changed for {label}: {data.count}"
  let reordered := Doc.VersoDoc.mk
    (fun _ => { a.toPart with content := a.toPart.content.reverse }) "{}"
  let (_, state) ← renderManualDocHtmlStringAndState impls reordered
  unless (TraversalIndex.Nodes.renderedData? state (Name.mkSimple "local.A.first")).map (·.count) == some 1 do
    throw <| IO.userError "Reordered authored blocks were renumbered"

#docs (Genre.Manual) codeOnlyReferences "Code-only references" :=
:::::::
See {bpref "attr.exported.undocumented"}[code-only reference].

:::lemma_ "code.only.reference.consumer"
By {uses "attr.exported.undocumented"}[code-only dependency].
:::
:::::::

-- Reordering and generated insertion must also compose within ONE source.
-- Exercise every permutation through real traversal, with and without insertion.
#eval show IO Unit from do
  let source := BlueprintAttributeRendering.interleavedLocalAttributePlacementDoc
  let content := source.toPart.content
  unless content.size == 3 do throw <| IO.userError "Unexpected interleaved fixture shape"
  let labels := #["attr.consumer.before.placement", "attr.exported.theorem",
    "attr.consumer.after.placement"].map Name.mkSimple
  let (_, baseline) ← renderManualDocHtmlStringAndState impls source
  let sourcePaths := labels.map fun label =>
    (TraversalIndex.Nodes.renderedData? baseline label).bind (·.sourceLocation.location) |>.map (·.path)
  unless sourcePaths[0]!.isSome && sourcePaths.all (· == sourcePaths[0]!) do
    throw <| IO.userError "Numbering regression must use one source path"
  for order in #[#[0, 1, 2], #[0, 2, 1], #[1, 0, 2], #[1, 2, 0], #[2, 0, 1], #[2, 1, 0],
      #[0, 2], #[2, 0]] do
    let doc := Doc.VersoDoc.mk
      (fun _ => { source.toPart with content := order.map (content[·]!) }) "{}"
    let (_, state) ← renderManualDocHtmlStringAndState impls doc
    let mut counts : Array Nat := #[]
    for i in order do
      let some data := TraversalIndex.Nodes.renderedData? state labels[i]!
        | throw <| IO.userError "Missing reordered occurrence"
      unless data.numberingMode == .local && data.count > 0 && !counts.contains data.count do
        throw <| IO.userError s!"Local numbering collision in {order}: {counts}, {data.count}"
      counts := counts.push data.count
      if !order.contains 1 then
        let some authored := TraversalIndex.Nodes.renderedData? baseline labels[i]!
          | throw <| IO.userError "Missing baseline occurrence"
        -- In the baseline the second authored block follows one generated block.
        let expected := authored.count - if i == 2 then 1 else 0
        unless data.count == expected do
          throw <| IO.userError "Reordering alone changed an authored local number"

-- Inspect traversed prose, excluding generated headers and code/graft renderers.
private partial def proseParagraphs : Doc.Block Genre.Manual → Array (Doc.Block Genre.Manual)
  | .para content => #[.para content]
  | .concat content | .other _ content => content.flatMap proseParagraphs
  | _ => #[]

-- External witnesses change body selection, never the public statement key.
-- Start from both real placement paths and exercise the persisted-data consumer.
#eval show IO Unit from do
  let label := Name.mkSimple "attr.exported.undocumented"
  let node := ({ label := label.toString } : Graft.BlueprintNodeConfig).toNode
  for doc in #[BlueprintAttributeRendering.placedAttributeDoc,
      BlueprintAttributeRendering.includedAttributeModuleDoc] do
    let (blocks, baseline) ← traverseManualDocBlocksAndState impls (combine #[doc, codeOnlyReferences])
    for witness in #[none,
        some ({ language := .markdown, slot := "statement", raw := "**Witness marker**" } : Data.ExternalMarkup),
        some { language := .tex, slot := "statement", raw := "Witness marker" },
        some { language := .markdown, slot := "statement", raw := "   " }] do
      let state := match witness with
        | none => baseline
        | some markup => TraversalIndex.ExternalMarkup.saveData baseline label
            (toJson ({ label, markup := ({} : Data.ExternalMarkupSet).insert markup } : Data.ExternalMarkupData))
      let direct ← renderManualBlocksHtmlWithState blocks impls state
      unless PreviewSource.traversalPreviewCandidateKey? state label == PreviewKey.ofString? node.key &&
          (PreviewSource.traversalEntry? state label).isNone do
        throw <| IO.userError "Code-only preview discovery changed prose-only selection"
      -- Isolate the two reference blocks from placements: graft rendering must
      -- not accidentally satisfy the hover-trigger assertion.
      let references ← renderManualBlocksHtmlWithState
        (blocks.flatMap proseParagraphs) impls state
      unless countSubstr references.asString s!"data-bp-preview-key=\"{node.key}\"" == 2 do
        throw <| IO.userError "Ordinary references did not request the code-only statement preview"
      for mode in #[ExternalMarkupRender.Mode.markdown, .none] do
        let files ← PreviewManifest.buildPreviewDataFiles impls (fun e => throw <| IO.userError e)
          (PreviewManifest.PreparedPreviewState.prepare state) { mode }
        let some entry := files.manifest.findEntry? node.key
          | throw <| IO.userError "External witness removed the standard statement key"
        let some _ := files.htmlCache.findHtml? node.key
          | throw <| IO.userError "External witness removed the standard statement body"
        let alternateKey := PreviewSource.externalMarkupKey label
        unless entry.targetKind == .block && entry.defaultPreview &&
            (files.manifest.findEntry? alternateKey).isNone &&
            (files.htmlCache.findHtml? alternateKey).isNone do
          throw <| IO.userError "A placed witness must publish only the standard statement"
        let hasWitnessBody := (ExternalMarkupRender.previewBody? { mode }
          (witness.toArray)).isSome
        unless entry.codeOnlyPreview == !hasWitnessBody do
          throw <| IO.userError "Code-only hover fallback disagrees with exported body selection"
        let cached ← Graft.renderNodeFromManifestCache {}
          (Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)) node
        unless hasSubstr cached.asString "exportedUndocumentedDefinition" &&
            !entry.leanCodePreviewKeys.isEmpty &&
            !hasSubstr cached.asString "Blueprint node not found" do
          throw <| IO.userError "Witness attachment broke exported graft reuse"
        if mode == .markdown then
          unless hasSubstr direct.asString "Witness marker" == hasSubstr cached.asString "Witness marker" do
            throw <| IO.userError "Direct and exported witness body availability disagree"

-- Register the theorem here so the selected document can include only its proof.
#docs (Genre.Manual) omittedStatement "Omitted statement facet" :=
:::::::
:::theorem "site_node_proof_only" (parent := "site_node_group")
This statement is outside the selected document.
:::
:::::::

#docs (Genre.Manual) siteNodeDoc "Per-label preview resources" :=
:::::::
:::group "site_node_group"
Site node members
:::

:::Informal.proof "site_node_proof_only"
A proof with no statement occurrence on this site.
:::

:::theorem "site_node_bodyless" (parent := "site_node_group")
:::

:::theorem "site_node_inline" (parent := "site_node_group")
:::

```lean "site_node_inline"
theorem siteNodeInlineWitness : True := by trivial
```

:::theorem "site_node_prose_priority" (parent := "site_node_group")
:::

:::Informal.proof "site_node_prose_priority"
This prose proof takes precedence for ordinary previews.
:::

```md "site_node_prose_priority" (slot := statement)
Attached statement witness.
```

```md "site_node_standalone" (slot := statement)
Standalone statement witness.
```
:::::::

#eval show IO Unit from IO.FS.withTempDir fun output => do
  let model : RenderModel := blueprint_render_model%
  let config : RenderConfig := {
    features := {}
    destination := output
    emitHtmlSingle := .immediately
    emitHtmlMulti := .no }
  let (messages, code) ← IO.FS.withIsolatedStreams <|
    PreviewManifest.blueprintMainWithPreviewData siteNodeDoc.toPart [] impls (config := config) (model := model)
  unless code == 0 do
    throw <| IO.userError s!"Site node generation failed: {messages}"
  let path := output / "html-single" / "-verso-data"
  let files : PreviewManifest.PersistedFiles := {
    manifest := ← PreviewManifest.readFile (path / PreviewManifest.manifestFilename)
    htmlCache := ← PreviewManifest.HtmlCache.readFile (path / PreviewManifest.htmlCacheFilename) }
  let errors := VersoBlueprint.Vbp.checkGeneratedData files
  unless errors.isEmpty do
    throw <| IO.userError s!"Generated site node joins failed vbp check: {errors}"

  let inlineKey := PreviewCache.statementKey `site_node_inline
  let proofKey := PreviewCache.proofKey `site_node_proof_only
  let priorityKey := PreviewCache.proofKey `site_node_prose_priority
  let attachedKey := PreviewCache.statementKey `site_node_prose_priority
  let standaloneKey := PreviewSource.externalMarkupKey `site_node_standalone
  let index := files.manifest.index
  let resources := PreviewManifest.PreviewArtifactIndex.ofPersistedFiles files
  let some inlineEntry := index.findEntry? inlineKey
    | throw <| IO.userError "Bodyless theorem lost its inline Lean statement preview"
  let #[codeEntry] := index.codeEntries inlineEntry
    | throw <| IO.userError "Bodyless theorem did not export exactly one included code fragment"
  unless inlineEntry.codeOnlyPreview && inlineEntry.defaultPreview &&
      codeEntry.targetKind == .inlineLeanCode && codeEntry.matchesCode "siteNodeInlineWitness" &&
      resources.resolves codeEntry.key do
    throw <| IO.userError "Inline-only statement lost its declaration, code fragment, or default"

  let parent := `site_node_group
  let some group := index.findGroup? parent | throw <| IO.userError "Missing site node group"
  let expected : Array (Name × Option String × Option String) := #[
    (`site_node_proof_only, some proofKey, some proofKey),
    (`site_node_bodyless, none, none),
    (`site_node_inline, some inlineKey, some inlineKey),
    (`site_node_prose_priority, some attachedKey, some priorityKey)]
  unless group.entries.map (·.label) == expected.map (·.1) do
    throw <| IO.userError "Group must retain each occurrence once in traversal order"
  for (label, primary, defaultKey) in expected do
    let some row := files.manifest.findNodeRow? label.toString
      | throw <| IO.userError s!"Missing site node row for {label}"
    let some metadata := index.nodeMetadata? row
      | throw <| IO.userError s!"Missing occurrence metadata for {label}"
    let actual := group.entries.find? (·.label == label)
    unless row.primaryKey == primary && row.bodyless.isSome == primary.isNone &&
        metadata.parent == some parent && metadata.parentTitle == some group.title &&
        actual.any (fun member => member.previewKey.map (·.value) == defaultKey) do
      throw <| IO.userError s!"Wrong primary resource, group, or default for {label}"
  unless (index.findEntry? (PreviewCache.statementKey `site_node_proof_only)).isNone &&
      (index.findEntry? (PreviewCache.statementKey `site_node_bodyless)).isNone &&
      (index.findEntry? (PreviewCache.proofKey `site_node_bodyless)).isNone do
    throw <| IO.userError "An absent site facet acquired a preview"

  let some attached := index.findEntry? attachedKey
    | throw <| IO.userError "Attached witness lost the statement facet"
  let some standalone := index.findEntry? standaloneKey
    | throw <| IO.userError "Standalone witness lost its external markup resource"
  unless attached.targetKind == .block && !attached.defaultPreview && !attached.codeOnlyPreview &&
      (index.findEntry? priorityKey).any (·.defaultPreview) &&
      (index.findEntry? (PreviewSource.externalMarkupKey `site_node_prose_priority)).isNone &&
      (files.htmlCache.findHtml? attachedKey).any (hasSubstr · "Attached statement witness.") &&
      standalone.targetKind == .externalMarkup && standalone.defaultPreview &&
      (index.findEntry? (PreviewCache.statementKey `site_node_standalone)).isNone &&
      (files.htmlCache.findHtml? standaloneKey).any (hasSubstr · "Standalone statement witness.") &&
      resources.facetKey? `site_node_standalone .statement == PreviewKey.ofString? standaloneKey do
    throw <| IO.userError "Witness fallback displaced prose or published duplicate statements"

-- Apply the same blank-text rule when joining persisted Lean fragments.
#eval show IO Unit from do
  let blank := String.ofList [Char.ofNat 0x00A0, Char.ofNat 0x2003, Char.ofNat 0xFEFF]
  let cache : PreviewManifest.HtmlCache.File := { entries := #[
    { key := "blank", html := blank },
    { key := "visible", html := blank ++ "<code>True</code>" }] }
  let statement : PreviewManifest.Entry := {
    label := `site_node_inline, key := PreviewCache.statementKey `site_node_inline, title := "Lean statement"
    targetKind := .block, facet := .statement, leanCodePreviewKeys := #["blank", "visible"] }
  unless cache.index.codeHtmlEntries statement == #[("visible", blank ++ "<code>True</code>")] do
    throw <| IO.userError "The cache treated Unicode whitespace as a rendered Lean fragment"

-- Persisted Manual blocks round-trip structurally, including an explicitly
-- empty body. Invalid serialized bodies are rejected at elaboration.
#eval show IO Unit from do
  for block in #[Verso.Doc.Block.para #[.bold #[.text "round trip"]], .concat #[]] do
    let json := toJson (block : Doc.Block Genre.Manual)
    let .ok restored := Docstring.decodePersistedManualBlock json.compress
      | throw <| IO.userError "Persisted Manual body failed reconstruction"
    unless toJson restored == json do throw <| IO.userError "Persisted Manual body changed"

open Verso.Doc.Elab in
@[block_command]
meta def malformedPersistedBody : BlockCommandOf Graft.BlueprintNodeConfig
  | _ => liftM <| Docstring.persistedManualBlockTermFromJson "null"

/-- error: Blueprint persisted statement block could not be decoded: object expected -/
#guard_msgs in
#docs (Genre.Manual) rejectedPersistedBody "Rejected persisted body" :=
:::::::
{malformedPersistedBody "unused"}
:::::::

end Verso.VersoBlueprintTests.BlueprintPlacementContracts
