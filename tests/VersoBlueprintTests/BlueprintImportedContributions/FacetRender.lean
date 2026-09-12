/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.FacetDoc
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Informal
open Verso.Genre
open Verso.VersoBlueprintTests.Blueprint.Support

def facetBlueprint : BlueprintDocument := .capture
  (%doc VersoBlueprintTests.BlueprintImportedContributions.FacetDoc)

-- Each chapter order must select the same bodies and facet provenance, including
-- across the traversal fixed point and a saved-state round trip.
#eval show IO Unit from do
  let part := facetBlueprint.text
  let chapters := part.subParts.extract 0 3
  let overviews := part.subParts.extract 3 part.subParts.size
  for order in #[#[0, 1, 2], #[0, 2, 1], #[1, 0, 2], #[1, 2, 0], #[2, 0, 1], #[2, 1, 0]] do
    let text := { part with subParts := order.map (chapters[·]!) ++ overviews }
    let doc : Doc.VersoDoc Manual := .mk (fun _ => text) "{}"
    let errors ← IO.mkRef (#[] : Array String)
    let (blocks, state) ← traverseManualDocBlocksAndState extension_impls% doc
      (fun error => errors.modify (·.push error)) (model := facetBlueprint.model)
    let .ok restored := fromJson? (α := Verso.Genre.Manual.TraverseState) (toJson state)
      | throw <| IO.userError "Could not restore selected facet state"
    for state in #[state, restored] do
      let page ← renderManualBlocksHtmlWithState blocks extension_impls% state
      let ids := (page.asString.splitOn " id=\"").drop 1 |>.map fun rest =>
        (rest.splitOn "\"").head!
      unless ids.length == ids.eraseDups.length do
        throw <| IO.userError s!"Repeated occurrences emitted duplicate HTML IDs in order {order}"
      let some selected := TraversalIndex.TraversalPreviews.entry? state "filled_facet--statement"
        | throw <| IO.userError "Missing selected statement"
      let some selectedId := selected.target | throw <| IO.userError "Missing statement target"
      let rowIds := TraversalIndex.ExternalDeclAnchors.htmlIdAttrs state selectedId `facetExternal
      let some (_, rowId) := rowIds.find? (·.1 == "id")
        | throw <| IO.userError "Missing selected external row ID"
      let some href := Resolve.resolveInformalDeclHref? state `filled_facet `facetExternal
        | throw <| IO.userError "Missing canonical external declaration link"
      unless href.endsWith ("#" ++ rowId) && countSubstr page.asString s!"id=\"{rowId}\"" == 1 do
        throw <| IO.userError "Canonical external declaration did not target the selected occurrence's unique row"
      let files ← PreviewManifest.buildPreviewDataFiles extension_impls%
        (fun error => errors.modify (·.push error)) (PreviewManifest.PreparedPreviewState.prepare state)
      for (facet, body, sourcePage) in #[
          (PreviewCache.Facet.statement, "A completed statement from page one.", "1"),
          (PreviewCache.Facet.proof, "A completed proof from page two.", "2")] do
        let key := PreviewCache.key `filled_facet facet
        let some entry := files.manifest.findEntry? key
          | throw <| IO.userError s!"Missing filled preview {key} in chapter order {order}"
        let some html := files.htmlCache.findHtml? key
          | throw <| IO.userError s!"Missing filled HTML {key}"
        let some selected := TraversalIndex.TraversalPreviews.entry? state key
          | throw <| IO.userError s!"Missing selected facet {key}"
        let some id := selected.target | throw <| IO.userError "Missing selected target"
        let some target := state.externalTags[id]? | throw <| IO.userError "Missing selected page anchor"
        unless hasSubstr page.asString body && hasSubstr html body &&
            entry.href == some target.relativeLink &&
            entry.sourceLocation == selected.sourceLocation && entry.sourceLocation.ok &&
            entry.sources.flatMap (·.spans.map (·.page)) == #[some sourcePage] do
          throw <| IO.userError s!"Body, target, location or provenance disagreed for {key}"
        let sourceDocument := if facet == .statement then "facet-paper" else "facet-proof-paper"
        unless entry.sources.map (·.document) == #[sourceDocument] &&
            entry.leanCodePreviewKeys.size == 2 do
          throw <| IO.userError "A facet lost its source document or shared code preview"
        for codeKey in entry.leanCodePreviewKeys do
          let some code := files.manifest.findEntry? codeKey
            | throw <| IO.userError "Missing shared Lean code preview"
          unless (code.sources.map (·.document) |>.qsort (· < ·)) ==
              #["facet-paper", "facet-proof-paper"] do
            throw <| IO.userError "Shared Lean code lost one facet's source provenance"
        if facet == .statement then
          unless TraversalIndex.Nodes.href? state `filled_facet == entry.href do
            throw <| IO.userError "The node link still targeted the placeholder"
          let xref := PreviewManifest.buildPublicXrefJson state
          let .ok #[publicTarget] := do
              let domain ← xref.getObjVal? TraversalIndex.Nodes.domainName.toString
              let contents ← domain.getObjVal? "contents"
              contents.getObjValAs? (Array Json) "filled_facet"
            | throw <| IO.userError "The public cross-reference did not select one canonical target"
          let .ok data := publicTarget.getObjValAs? BlockData "data"
            | throw <| IO.userError "Missing public node metadata"
          unless (publicTarget.getObjValAs? String "address").toOption == some target.path.link &&
              (publicTarget.getObjValAs? String "id").toOption == some target.htmlId.toString &&
              data.sourceLocation == selected.sourceLocation && data.sourceRef == selected.sourceRef do
            throw <| IO.userError "Public node target and provenance disagreed with the selected body"
      unless (← errors.get).isEmpty do
        throw <| IO.userError s!"Facet rendering reported errors: {← errors.get}"

-- Captured chapters do not imply rendered bodies. Inline references must follow
-- the selected preview even when the completed statement chapter is omitted.
#eval show IO Unit from do
  let part := facetBlueprint.text
  for (order, expected) in #[
      (#[0], PreviewCache.Facet.statement),
      (#[2], PreviewCache.Facet.proof),
      (#[0, 2], PreviewCache.Facet.proof),
      (#[2, 0], PreviewCache.Facet.proof),
      (#[0, 1, 2], PreviewCache.Facet.statement)] do
    let text := { part with subParts := order.map (part.subParts[·]!) }
    let doc : Doc.VersoDoc Manual := .mk (fun _ => text) "{}"
    let errors ← IO.mkRef (#[] : Array String)
    let (blocks, state) ← traverseManualDocBlocksAndState extension_impls% doc
      (fun error => errors.modify (·.push error)) (model := facetBlueprint.model)
    -- Source declarations belong to the omitted placeholder chapter. Supply
    -- those resources explicitly when exercising the proof chapter alone.
    let state := if order == #[2] then
      TraversalIndex.SourceDocuments.saveData state "facet-proof-paper" {
        id := "facet-proof-paper", title := "Proof source", pdf := some "source/proof-paper.pdf" }
      else state
    -- Root paragraphs contain the authored bpref roles, independently of chapter bodies.
    let references := blocks.filter fun block => match block with | .para _ => true | _ => false
    let html ← renderManualBlocksHtmlWithState references extension_impls% state
    if order == #[2] then
      unless hasSubstr html.asString "Proof for Theorem 1" &&
          !hasSubstr html.asString ">Proof 1<" do
        throw <| IO.userError "Proof-only references lost the theorem kind"
    let files ← PreviewManifest.buildPreviewDataFiles extension_impls%
      (fun error => errors.modify (·.push error)) (PreviewManifest.PreparedPreviewState.prepare state)
    if order == #[2] then
      let some proof := files.manifest.findEntry? "filled_facet--proof"
        | throw <| IO.userError "Missing proof-only manifest entry"
      unless proof.kind == some .theorem && proof.title == "Proof for Theorem 1" do
        throw <| IO.userError "Proof-only manifest lost the mathematical kind"
    if order == #[0] then
      unless (PreviewSource.traversalEntry? state `filled_facet).isNone do
        throw <| IO.userError "A code-backed placeholder acquired an omitted prose body"
    let key := PreviewCache.key `filled_facet expected
    unless countSubstr html.asString s!"data-bp-preview-key=\"{key}\"" == 2 &&
        (files.htmlCache.findHtml? key).isSome do
      throw <| IO.userError s!"Inline references missed {key} in chapter order {order}"
    unless (← errors.get).isEmpty do
      throw <| IO.userError s!"Partial chapter rendering errors: {← errors.get}"
