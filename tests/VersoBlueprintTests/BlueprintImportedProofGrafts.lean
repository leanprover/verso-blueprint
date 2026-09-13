/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintAttribute.ProofProvider
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Informal Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintImportedProofGrafts

private def impls : ExtensionImpls := extension_impls%
private def label : Name := Name.mkSimple "attr.exported.theorem"
private def proofKey := PreviewCache.proofKey label
private def statementKey := PreviewCache.statementKey label

#docs (Genre.Manual) statement "Statement" :=
:::::::
{blueprint_node "attr.exported.theorem"}
:::::::

set_option verso.blueprint.foldProofBlocks true in
#docs (Genre.Manual) folded "Folded proof" :=
:::::::
{blueprint_node "attr.exported.theorem" (facet := "proof")}
:::::::

set_option verso.blueprint.foldProofBlocks false in
#docs (Genre.Manual) expanded "Expanded proof" :=
:::::::
{blueprint_node "attr.exported.theorem" (facet := "proof")}
:::::::

#docs (Genre.Manual) included "Included module" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintAttribute.Provider}
:::::::

#docs (Genre.Manual) missing "No informal proof" :=
:::::::
{blueprint_node "attr.exported.definition" (facet := "proof")}

{blueprint_node "imported.proof.metadata" (facet := "proof")}
:::::::

private def combine (docs : Array (Doc.VersoDoc Genre.Manual)) : Doc.VersoDoc Genre.Manual :=
  .mk (fun _ => { statement.toPart with content := #[], subParts := docs.map (·.toPart) }) "{}"

-- An import makes the proof available, but default/module placements remain
-- statement-only. Missing proof prose does not fall back to a declaration.
#eval show IO Unit from do
  for doc in #[statement, included] do
    let (html, state) ← renderManualDocHtmlStringAndState impls doc
    unless (TraversalIndex.TraversalPreviews.entry? state statementKey).isSome &&
        (TraversalIndex.TraversalPreviews.entry? state proofKey).isNone &&
        !hasSubstr html "imported informal argument" do
      throw <| IO.userError "Default placement materialized an unrequested proof"
  let (html, state) ← renderManualDocHtmlStringAndState impls missing
  unless countSubstr html "Blueprint node not found" == 2 do
    throw <| IO.userError "Missing proof did not retain the unavailable-facet notice"
  for name in #["attr.exported.definition", "imported.proof.metadata"] do
    unless (TraversalIndex.TraversalPreviews.entry? state
        (PreviewCache.proofKey (Name.mkSimple name))).isNone do
      throw <| IO.userError "Missing informal proof acquired a fabricated preview"

-- Graft-only rendering exercises persisted bodies across a transitive import.
-- Repeat and reorder placements, also mixing in the original provider document.
#eval show IO Unit from do
  for docs in #[#[folded], #[expanded], #[statement, folded], #[folded, statement],
      #[folded, expanded], #[expanded, folded], #[included, expanded],
      #[BlueprintAttribute.ProofProvider.proofDocument, expanded],
      #[expanded, BlueprintAttribute.ProofProvider.proofDocument]] do
    let (html, state) ← renderManualDocHtmlStringAndState impls (combine docs)
    let some preview := TraversalIndex.TraversalPreviews.entry? state proofKey
      | throw <| IO.userError "Imported proof was not materialized"
    unless preview.hasRenderedBody && hasSubstr html "<strong>imported informal argument</strong>" do
      throw <| IO.userError "Imported proof lost its structured body"
    let some id := preview.target | throw <| IO.userError "Proof has no destination"
    let some target := state.externalTags[id]?
      | throw <| IO.userError "Proof destination is unregistered"
    unless countSubstr html s!"id=\"{target.htmlId}\"" == 1 do
      throw <| IO.userError "Proof destination is missing or duplicated"
    let some data := TraversalIndex.Nodes.renderedData? state label
      | throw <| IO.userError "Proof lost its semantic node"
    unless data.proofUses.map (·.label) == #[Name.mkSimple "attr.exported.definition"] &&
        data.statementUses.isEmpty && data.globalCount == some 1 do
      throw <| IO.userError "Proof placement changed dependency axes or numbering"
    let files ← PreviewManifest.buildPreviewDataFiles impls (fun e => throw <| IO.userError e)
      (PreviewManifest.PreparedPreviewState.prepare state)
    let some entry := files.manifest.findEntry? proofKey
      | throw <| IO.userError "Missing exported proof"
    let some body := files.htmlCache.findHtml? proofKey
      | throw <| IO.userError "Missing cached proof body"
    unless entry.href == some target.relativeLink &&
        entry.proofUses == data.proofUses && entry.statementUses.isEmpty do
      throw <| IO.userError "Exported proof changed its destination or dependencies"
    if let some statementEntry := files.manifest.findEntry? statementKey then
      unless entry.title == "Proof for " ++ statementEntry.title do
        throw <| IO.userError s!"Statement and proof acquired different numbers: {statementEntry.title}, {entry.title}"
    else
      unless (Resolve.resolveRenderedExternalDeclHref? state label
          ``BlueprintAttribute.Provider.exportedTheorem).isNone &&
          !hasSubstr html "bp_external_decl_item" do
        throw <| IO.userError "Proof-only placement advertised or displayed statement code"
    let node := ({ label := "attr.exported.theorem", facet := some "proof" } : Graft.BlueprintNodeConfig).toNode
    let cached ← Graft.renderNodeFromManifestCache {}
      (Graft.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)) node
    unless hasSubstr body "imported informal argument" &&
        hasSubstr cached.asString "<strong>imported informal argument</strong>" &&
        entry.foldProofBlock == preview.foldProofBlock &&
        hasSubstr cached.asString "<details class=\"bp_wrapper" == entry.foldProofBlock do
      throw <| IO.userError "Direct and cached imported proof disagree"
    let .ok restored := fromJson? (α := TraverseState) (toJson state)
      | throw <| IO.userError "Could not restore imported proof traversal state"
    let restoredFiles ← PreviewManifest.buildPreviewDataFiles impls (fun e => throw <| IO.userError e)
      (PreviewManifest.PreparedPreviewState.prepare restored)
    unless restoredFiles.htmlCache.findHtml? proofKey == some body do
      throw <| IO.userError "Restoring traversal state changed the imported proof body"

-- Occurrence-local folding does not depend on which placement wins selection.
#eval show IO Unit from do
  for docs in #[#[folded, expanded], #[expanded, folded]] do
    let html ← renderManualDocHtmlString impls (combine docs)
    unless countSubstr html "<strong>imported informal argument</strong>" == 2 &&
        countSubstr html "<details class=\"bp_wrapper" == 1 do
      throw <| IO.userError "Repeated proof placements lost local folding"

end Verso.VersoBlueprintTests.BlueprintImportedProofGrafts
