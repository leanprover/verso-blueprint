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

-- Projection is idempotent, preserves occurrence-specific settings, and leaves custom models alone.
#eval show IO Unit from do
  let snapshot : Informal.DocumentSnapshot := blueprint_snapshot%
  let doc := graphDoc.toPart
  let projected := snapshot.apply doc
  unless snapshot.apply projected == projected do
    throw <| IO.userError "Document projection is not idempotent"

  let occurrence : Informal.BlockData := {
    label := `key_theorem
    kind := .proof
    count := 47
    partPrefix := some "Appendix"
    foldProofBlock := true
    sourceLocation := .unavailable "original chapter location"
  }
  let nested : Doc.Block Genre.Manual := .blockquote #[
    .other (Informal.Block.informal occurrence) #[.para #[.text "Nested proof"]]
  ]
  let .blockquote #[.other container #[.para #[.text "Nested proof"]]] := snapshot.block nested
    | throw <| IO.userError "Projection changed nested document structure"
  let .ok (refreshed : Informal.BlockData) := fromJson? container.data
    | throw <| IO.userError "Projection produced invalid block data"
  unless refreshed.count == 47 && refreshed.partPrefix == some "Appendix" &&
      refreshed.foldProofBlock && refreshed.sourceLocation == occurrence.sourceLocation &&
      (match refreshed.kind with | .proof => true | _ => false) && refreshed.tags.contains "late" do
    throw <| IO.userError "Projection lost occurrence settings or failed to refresh nested metadata"
  let custom : Doc.Block Genre.Manual :=
    .other (Informal.Commands.Block.graph { graphModel := {} }) #[]
  unless snapshot.block custom == custom && ({} : Informal.DocumentSnapshot).apply doc == doc do
    throw <| IO.userError "Projection changed a custom model or an explicitly isolated document"
