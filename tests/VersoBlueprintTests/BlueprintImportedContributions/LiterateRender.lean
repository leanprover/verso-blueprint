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
    unless code.inlineBlocks.declarations.size == 2 do
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
