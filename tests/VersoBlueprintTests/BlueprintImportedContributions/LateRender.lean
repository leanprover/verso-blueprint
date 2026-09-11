/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.LateAttachment
import VersoBlueprintTests.BlueprintImportedContributions.GraphFreeDoc
import VersoBlueprintTests.Blueprint.Support

open Lean Verso
open Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support

private def graphDoc : Doc.VersoDoc Genre.Manual :=
  .mk (fun _ => %doc VersoBlueprintTests.BlueprintImportedContributions.Doc) "{}"

private def graphFreeDoc : Doc.VersoDoc Genre.Manual :=
  .mk (fun _ => %doc VersoBlueprintTests.BlueprintImportedContributions.GraphFreeDoc) "{}"

private def manualImpls : ExtensionImpls := extension_impls%

def lateBlueprint : Informal.BlueprintDocument := .capture graphDoc.toPart

-- The generator sees the attachment after both documents and their overview
-- commands have been compiled. Every rendered view must use the final semantics.
#eval show IO Unit from do
  let expected : Array Informal.Data.UseRef := #[
    { label := `proof_dep, intent := .technical },
    { label := `statement_dep }
  ]
  for (doc, withGraph) in #[(graphDoc, true), (graphFreeDoc, false)] do
    let files ← buildManualPreviewDataFiles manualImpls doc
    let some statement := files.manifest.findEntry? "key_theorem--statement"
      | throw <| IO.userError "Missing statement preview"
    let some proof := files.manifest.findEntry? "key_theorem--proof"
      | throw <| IO.userError "Missing proof preview"
    unless statement.proofUses == expected && proof.proofUses == expected do
      throw <| IO.userError s!"Late dependency missing from preview: {repr proof.proofUses}"
    unless statement.tags.contains "late" && proof.effort == some "small" do
      throw <| IO.userError "Late metadata missing from previews"
    unless !statement.leanCodePreviewKeys.isEmpty do
      throw <| IO.userError "Late Lean association missing from statement preview"
    let some statementHtml := files.htmlCache.findHtml? statement.key
      | throw <| IO.userError "Missing statement HTML"
    let some proofHtml := files.htmlCache.findHtml? proof.key
      | throw <| IO.userError "Missing proof HTML"
    unless hasSubstr statementHtml "A statement declared in this module." &&
        hasSubstr proofHtml "A proof declared in a different module from its statement." do
      throw <| IO.userError "Refreshing semantics replaced a chapter's body"
    if withGraph then
      let some node := files.manifest.graphs.findSome? fun graph =>
          graph.nodes.find? (·.label == `key_theorem)
        | throw <| IO.userError "Missing graph node"
      unless node.proofUses == proof.proofUses do
        throw <| IO.userError "Graph and preview dependencies disagree"
    else
      unless files.manifest.graphs.isEmpty do
        throw <| IO.userError "A graph-free document acquired a graph"

#eval show CoreM Unit from do
  let some node ← Informal.Environment.getNode? `key_theorem | throwError "Missing node"
  unless node.proof.map (·.deps) == some #[
      { label := `proof_dep, intent := .technical }, { label := `statement_dep }] do
    throwError "Final environment lost the late dependency"

-- Traversal resolves nested occurrences without rewriting their compiled payloads.
#eval show IO Unit from do
  let model : Informal.RenderModel := blueprint_render_model%
  let occurrence : Informal.BlockOccurrence := {
    label := `key_theorem
    isProof := true
    count := 47
    partPrefix := some "Appendix"
    foldProofBlock := true
    sourceLocation := .unavailable "original chapter location"
  }
  let nested : Doc.Block Genre.Manual := .blockquote #[
    .other (Informal.Block.informal occurrence) #[.para #[.text "Nested proof"]]
  ]
  let custom : Doc.Block Genre.Manual :=
    .other (Informal.Commands.Block.graph { graphModel := some {} }) #[]
  let (traversed, state) ← Informal.traverseManualBlocks #[nested, custom]
    (model.withExtensions extension_impls%)
  let .blockquote #[.other container #[.para #[.text "Nested proof"]]] := traversed[0]!
    | throw <| IO.userError "Traversal changed nested document structure"
  unless container.data == toJson occurrence && (container.data.getObjVal? "tags").toOption.isNone do
    throw <| IO.userError "Compiled occurrences acquired copied semantic metadata"
  let some resolved := Informal.TraversalIndex.Nodes.resolve? state occurrence
    | throw <| IO.userError "Missing shared rendering node"
  unless resolved.count == 47 && resolved.partPrefix == some "Appendix" &&
      resolved.foldProofBlock && resolved.sourceLocation == occurrence.sourceLocation &&
      (match resolved.kind with | .proof => true | _ => false) && resolved.tags.contains "late" do
    throw <| IO.userError "Shared rendering data lost occurrence settings or late metadata"
  for entry in Informal.GraphApi.cachedEntries state do
    let .ok entry := entry | throw <| IO.userError "Invalid cached graph"
    unless entry.data.nodes.isEmpty do
      throw <| IO.userError "The project model replaced an explicitly supplied empty graph"

  -- Saved traversal data is sufficient for rendering; no recapture or AST repair is needed.
  let .ok restored := fromJson? (α := Verso.Genre.Manual.TraverseState) (toJson state)
    | throw <| IO.userError "Could not restore the rendering registry"
  let restoredHtml ← Informal.renderManualBlocksHtmlWithState traversed extension_impls% restored
  unless hasSubstr restoredHtml.asString "Nested proof" &&
      (Informal.TraversalIndex.Nodes.data? restored `key_theorem).any (·.tags.contains "late") do
    throw <| IO.userError "Restored traversal lost the captured rendering context"
  let build state := Informal.PreviewManifest.buildPreviewDataFiles extension_impls%
    (fun message => throw <| IO.userError message)
    (Informal.PreviewManifest.PreparedPreviewState.prepare state)
  let files ← build state
  let restoredFiles ← build restored
  unless !files.manifest.previews.isEmpty &&
      toJson (files.manifest, files.htmlCache) == toJson (restoredFiles.manifest, restoredFiles.htmlCache) do
    throw <| IO.userError "Restoring traversal changed the generated manifest or preview cache"

  -- The public cross-reference projection omits unrendered nodes and code-render payloads.
  let xref := Informal.PreviewManifest.buildPublicXrefJson restored
  let .ok contents := do
      let domain ← xref.getObjVal? Informal.TraversalIndex.Nodes.domainName.toString
      domain.getObjVal? "contents"
    | throw <| IO.userError "Missing public node cross-references"
  let .ok #[target] := (contents.getObjVal? "key_theorem").bind Json.getArr?
    | throw <| IO.userError "Missing rendered node cross-reference"
  let .ok data := target.getObjVal? "data"
    | throw <| IO.userError "Missing public node metadata"
  unless (data.getObjValAs? (Array String) "tags").toOption.any (·.contains "late") &&
      (data.getObjVal? "externalRefs").toOption.isNone &&
      (data.getObjVal? "codeData").toOption == some Json.null &&
      (contents.getObjVal? "statement_dep").toOption.isNone do
    throw <| IO.userError "Public cross-references leaked rendering payloads or unrendered nodes"
