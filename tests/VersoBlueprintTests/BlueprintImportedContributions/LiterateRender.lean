/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.LiterateDoc
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Informal
open Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support

def literateBlueprint : BlueprintDocument := .capture
  (%doc VersoBlueprintTests.BlueprintImportedContributions.LiterateDoc)

#eval show IO Unit from do
  let forward := literateBlueprint.text
  for part in #[forward, { forward with subParts := forward.subParts.reverse }] do
    let doc : Doc.VersoDoc Genre.Manual := .mk (fun _ => part) "{}"
    let (html, state) ← renderManualDocHtmlStringAndState extension_impls% doc
    let source : Source.Ref := {
      document := "literate-notes"
      spans := #[{ page := "1", text := some {
        path := "source/notes.md", startLine := 1, endLine := 1 } }]
    }
    let state := TraversalIndex.SourceDocuments.saveData state source.document {
      id := source.document, title := "Literate notes", kind := .text }
    let key := PreviewCache.key `key_theorem .statement
    let some preview := TraversalIndex.TraversalPreviews.entry? state key
      | throw <| IO.userError "Missing statement occurrence"
    let state := TraversalIndex.TraversalPreviews.saveData state key (toJson { preview with sourceRef := some source })
    let blocks := TraversalIndex.InlineCode.blocks state `key_theorem
    unless blocks.size == 2 && blocks[0]!.blockId != blocks[1]!.blockId do
      throw <| IO.userError "Literate blocks did not retain distinct identities"
    let files ← PreviewManifest.buildPreviewDataFiles extension_impls%
      (fun message => throw <| IO.userError message)
      (PreviewManifest.PreparedPreviewState.prepare state)
    let some statement := files.manifest.findEntry? "key_theorem--statement"
      | throw <| IO.userError "Missing statement preview"
    unless statement.leanCodePreviewKeys.size == 2 do
      throw <| IO.userError "Statement preview lost a literate block"
    let some code := statement.codeData
      | throw <| IO.userError "Missing literate declaration data"
    unless code.literateDeclarations.declarations.size == 2 do
      throw <| IO.userError "Declaration index lost a literate theorem"
    for decl in #[`inlineAttached, `inlineSecond] do
      let some block := TraversalIndex.InlineCode.forDecl? state `key_theorem decl
        | throw <| IO.userError s!"Missing declaration {decl}"
      let key := TraversalIndex.LeanCodePreviews.lookupInlineKey block.blockId
      let some preview := files.manifest.findEntry? key
        | throw <| IO.userError s!"Missing preview {key}"
      let some cached := files.htmlCache.findHtml? key
        | throw <| IO.userError s!"Missing code HTML {key}"
      unless statement.leanCodePreviewKeys.contains key && preview.sourceLocation.ok &&
          preview.title == "Lean code for key_theorem" && preview.sources == #[source] &&
          (TraversalIndex.InlineCode.href? state block.blockId).isSome &&
          hasSubstr html key && hasSubstr cached decl.toString do
        throw <| IO.userError s!"Literate code links, sources, or previews disagree for {decl}"
      if decl == `inlineSecond then
        unless block.foldCodeBlock && !block.foldProofs do
          throw <| IO.userError "Literate occurrence folding options were lost"


-- Importing a statement does not number a document that renders only its code.
#eval show IO Unit from do
  let part := literateBlueprint.text
  let text := { part with subParts := #[part.subParts[1]!, part.subParts[2]!] }
  let doc : Doc.VersoDoc Genre.Manual := .mk (fun _ => text) "{}"
  let (html, state) ← renderManualDocHtmlStringAndState extension_impls% doc
    (model := literateBlueprint.model)
  unless !TraversalIndex.Nodes.hasRenderedOccurrence state `key_theorem &&
      countSubstr html "Lean code for key_theorem" >= 2 &&
      !hasSubstr html "Lean code for Theorem" do
    throw <| IO.userError "Code-only chapters used an elaboration number as a document number"

-- Project declaration facts survive omitting their entire formalization chapter.
theorem omittedExternalComplete : True := trivial

#docs (Genre.Manual) omittedCodeStatements "Statements without code chapters" :=
:::::::
:::theorem "omitted:literate"
Statement with an omitted literate proof.
:::

:::theorem "omitted:mixed" (lean := "omittedExternalComplete")
Statement with complete external and incomplete literate associations.
:::
:::::::

#guard_msgs (drop warning) in
#docs (Genre.Manual) omittedCodeFormalization "Omitted formalization" :=
:::::::
```lean "omitted:literate"
theorem omittedLiterateSorry : True := by sorry
```

```lean "omitted:mixed"
theorem omittedMixedSorry : True := by sorry
```
:::::::

#eval show IO Unit from do
  let model : RenderModel := blueprint_render_model%
  let errors ← IO.mkRef (#[] : Array String)
  let (blocks, state) ← traverseManualDocBlocksAndState extension_impls% omittedCodeStatements
    (fun error => errors.modify (·.push error)) (model := model)
  let .ok restored := fromJson? (α := Verso.Genre.Manual.TraverseState) (toJson state)
    | throw <| IO.userError "Could not restore omitted-code rendering state"
  for state in #[state, restored] do
    let html ← renderManualBlocksHtmlWithState blocks extension_impls% state
    let files ← PreviewManifest.buildPreviewDataFiles extension_impls%
      (fun error => errors.modify (·.push error)) (PreviewManifest.PreparedPreviewState.prepare state)
    for (label, declaration, expectedCount) in #[
        (`«omitted:literate», `omittedLiterateSorry, 1),
        (`«omitted:mixed», `omittedMixedSorry, 2)] do
      let some data := TraversalIndex.Nodes.capturedData? state label
        | throw <| IO.userError s!"Missing rendering facts for {label}"
      let health := Graph.codeHealthOfBlockSource data.kind {} data.codeData
      let heading := CodeSummary.renderParts data { source := data.codeData } (fun _ => none)
      let some graphNode := model.graph.nodes.find? (·.label == label)
        | throw <| IO.userError "Missing captured graph node"
      unless health.totalDecls == expectedCount && health.anyGapCount == 1 &&
          graphNode.proofStatus == .incomplete &&
          hasSubstr heading.codeEntry.asString "bp_code_link_status_warning" &&
          hasSubstr html.asString declaration.toString &&
          model.summary.sorryDetails.any (·.decl == declaration) do
        throw <| IO.userError s!"Heading, summary, and graph disagree about omitted declaration {declaration}"
      let some entry := files.manifest.findEntry? (PreviewCache.key label .statement)
        | throw <| IO.userError "Missing statement manifest entry"
      unless entry.codeData.any (·.literateDeclarations.declarations.any (·.name == declaration)) &&
          (TraversalIndex.InlineCode.blocks state label).isEmpty &&
          (Resolve.resolveInlineLeanDeclHref? state declaration).isNone &&
          entry.leanCodePreviewKeys.size == expectedCount - 1 do
        throw <| IO.userError "Omitted code lost semantic facts or acquired a document-local panel or preview"
      let context := Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)
      let some content ← context.renderedContent? { label := label.toString, key := entry.key } entry
        | throw <| IO.userError "Missing manifest-backed statement content"
      let panelHealth := Graph.codeHealthOfBlockSource data.kind {} content.codeData.nonempty?
      unless panelHealth.totalDecls == expectedCount - 1 && panelHealth.anyGapCount == 0 do
        throw <| IO.userError "A manifest-backed code panel counted an omitted declaration"
      let shell := (PreviewManifest.BlockRender.renderWithRenderedContent {} entry content).asString
      unless hasSubstr shell "bp_code_link_status_warning" &&
          (expectedCount == 1 || hasSubstr shell "bp_external_status_ok") do
        throw <| IO.userError "Manifest-backed heading and visible panel lost their distinct status scopes"
  unless (← errors.get).isEmpty do
    throw <| IO.userError s!"Omitted-code rendering errors: {← errors.get}"
