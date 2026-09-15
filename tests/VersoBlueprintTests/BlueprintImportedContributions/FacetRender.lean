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
      let .ok canonical := RenderingResolution.canonical state `filled_facet
        | throw <| IO.userError "Could not resolve canonical facet metadata"
      -- A page occurrence keeps its own presentation and source, even when a
      -- different occurrence supplies the canonical preview. Numbering is shared.
      let requested := { canonical.toOccurrence with
        isProof := true, count := 999, sourceRef := none, sourceLocation := { ok := false },
        foldProofBlock := true, foldCodeBlock := !canonical.foldCodeBlock }
      let .ok occurrence := RenderingResolution.occurrence state requested
        | throw <| IO.userError "Could not resolve a page occurrence"
      unless toJson occurrence.toBlockMetadata == toJson canonical.toBlockMetadata &&
          toJson occurrence.codeData == toJson canonical.codeData &&
          occurrence.sourceRef.isNone && !occurrence.sourceLocation.ok &&
          occurrence.foldProofBlock && occurrence.foldCodeBlock == requested.foldCodeBlock &&
          occurrence.isProof && (occurrence.display state).number? == (canonical.display state).number? do
        throw <| IO.userError "Occurrence resolution lost semantics or borrowed canonical presentation"
      -- Reference presentation must not inherit the page occurrence's proof
      -- facet: ordinary references still name and target the selected statement.
      let .ok ordinary := RenderingResolution.reference state `filled_facet
        | throw <| IO.userError "Could not resolve ordinary reference"
      let fromOccurrence := RenderingResolution.referenceOfData state occurrence
      unless ordinary.title == "Theorem 1" && fromOccurrence.title == ordinary.title &&
          fromOccurrence.href == ordinary.href && fromOccurrence.previewKey == ordinary.previewKey do
        throw <| IO.userError "A proof occurrence supplied the title for a canonical statement reference"
      for facet in #[PreviewCache.Facet.statement, .proof] do
        let .ok explicit := RenderingResolution.reference state `filled_facet (some facet)
          | throw <| IO.userError "Could not resolve explicit facet"
        let fromOccurrence := RenderingResolution.referenceOfData state occurrence (some facet)
        unless fromOccurrence.title == explicit.title && fromOccurrence.href == explicit.href &&
            fromOccurrence.previewKey == explicit.previewKey do
          throw <| IO.userError "Explicit reference presentation depends on the supplied occurrence"
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
        let .ok (some resolved) := RenderingResolution.facetByKey? state key
          | throw <| IO.userError "Could not resolve selected facet"
        let projected := PreviewManifest.blockEntryOfFacet state resolved
        unless toJson resolved.preview == toJson selected &&
            projected.sourceLocation == entry.sourceLocation && projected.sources == entry.sources &&
            projected.href == entry.href && projected.foldCodeBlock == entry.foldCodeBlock &&
            projected.foldProofBlock == entry.foldProofBlock &&
            toJson projected.toBlockMetadata == toJson entry.toBlockMetadata &&
            RenderingResolution.codePreviewKeys state resolved == entry.leanCodePreviewKeys do
          throw <| IO.userError "Facet resolution changed selected content, presentation, or semantic metadata"
        let some id := selected.target | throw <| IO.userError "Missing selected target"
        let some target := state.externalTags[id]? | throw <| IO.userError "Missing selected page anchor"
        unless hasSubstr page.asString body && hasSubstr html body &&
            entry.href == some target.relativeLink &&
            entry.sourceLocation == selected.sourceLocation && entry.sourceLocation.ok &&
            entry.sources.flatMap (·.spans.map (·.page)) == #[some sourcePage] do
          throw <| IO.userError s!"Body, target, location or provenance disagreed for {key}"
        let .ok reference := RenderingResolution.reference state `filled_facet (some facet)
          | throw <| IO.userError "Could not resolve reference"
        let fromData := RenderingResolution.referenceOfData state canonical (some facet)
        unless reference.title == entry.title && reference.href == entry.href &&
            reference.previewKey == PreviewKey.ofString? key &&
            reference.title == fromData.title && reference.href == fromData.href &&
            reference.previewKey == fromData.previewKey &&
            toJson entry.toBlockMetadata == toJson canonical.toBlockMetadata do
          throw <| IO.userError "Reference, resolved metadata, and manifest views disagree"
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
      (#[], none),
      (#[0], some PreviewCache.Facet.statement),
      (#[2], some PreviewCache.Facet.proof),
      (#[0, 2], some PreviewCache.Facet.proof),
      (#[2, 0], some PreviewCache.Facet.proof),
      (#[0, 1, 2], some PreviewCache.Facet.statement)] do
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
    let .ok reference := RenderingResolution.reference state `filled_facet
      | throw <| IO.userError "Could not resolve reference"
    unless hasSubstr html.asString reference.title do
      throw <| IO.userError "Inline rendering did not use the shared reference title"
    let .ok canonical := RenderingResolution.canonical state `filled_facet
      | throw <| IO.userError "Could not resolve canonical reference data"
    let foreignPresentation := { canonical with
      isProof := !canonical.isProof, count := 999, numberingMode := .sub, partPrefix := some "other chapter" }
    let fromData := RenderingResolution.referenceOfData state foreignPresentation
    unless fromData.title == reference.title && fromData.href == reference.href &&
        fromData.previewKey == reference.previewKey do
      throw <| IO.userError "Ordinary reference inherited caller-owned facet or numbering"
    let optionalReference := RenderingResolution.referenceOrLabel state `filled_facet
    unless reference.href == optionalReference.href && reference.previewKey == optionalReference.previewKey do
      throw <| IO.userError "Known relation targets disagree with checked node references"
    let relationState := TraversalIndex.Nodes.saveNode state {
      label := `facet_consumer, statementUses := #[{ label := `filled_facet }, { label := `panel_other }] }
    let .ok resolved := RenderingResolution.facet relationState (PreviewCache.statementKey `facet_consumer)
      (PreviewCache.Entry.ofBlocks `facet_consumer .statement #[])
      | throw <| IO.userError "Could not resolve manifest facet"
    let consumer := PreviewManifest.blockEntryOfFacet relationState resolved
    let some relation := consumer.uses[0]?
      | throw <| IO.userError "Missing manifest relation to selected facet"
    unless relation.title == reference.title && relation.href == reference.href &&
        relation.previewKey == reference.previewKey do
      throw <| IO.userError "Manifest relation target and preview disagree with node references"
    let .ok consumerData := RenderingResolution.canonical relationState `facet_consumer
      | throw <| IO.userError "Missing relation consumer"
    let panel ← renderManualHtmlWithState (pure (RelatedPanel.renderUsesExtra relationState consumerData))
      extension_impls% relationState
    -- Compare the actual live panel's serialized row with the exported relation.
    let rowPrefix := (toJson #[toJson relation.title, toJson relation.previewKey,
      toJson relation.label.toString, toJson relation.href]).compress.dropEnd 1 |>.toString
    unless hasSubstr panel.asString rowPrefix do
      throw <| IO.userError "Live relation panel disagreed with the manifest's canonical reference"
    for facet in #[PreviewCache.Facet.statement, .proof] do
      let .ok requested := RenderingResolution.reference state `filled_facet (some facet)
        | throw <| IO.userError "Could not resolve explicit facet reference"
      let hasBody := order.contains (if facet == .statement then 1 else 2)
      let hasOccurrence := hasBody || (facet == .statement && order.contains 0)
      -- The statement placeholder carries external code; it has a preview even
      -- without prose. The proof facet has no code-only occurrence in this fixture.
      let expectedKey := if hasOccurrence then PreviewKey.ofString? (PreviewCache.key `filled_facet facet) else none
      unless requested.previewKey == expectedKey && requested.href.isSome == hasOccurrence do
        throw <| IO.userError s!"Explicit {repr facet} reference borrowed another facet's target or body"
      if !order.isEmpty then
        let title := if facet == .statement then "Theorem 1" else "Proof for Theorem 1"
        unless requested.title == title do
          throw <| IO.userError "Explicit facet reference borrowed another facet's title"
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
    match expected with
    | none =>
      unless !hasSubstr html.asString "bp_inline_preview_ref" do
        throw <| IO.userError "Omitted facets offered a nonexistent preview"
    | some facet =>
      let key := PreviewCache.key `filled_facet facet
      unless countSubstr html.asString s!"data-bp-preview-key=\"{key}\"" == 2 &&
          (files.htmlCache.findHtml? key).isSome do
        throw <| IO.userError s!"Inline references missed {key} in chapter order {order}"
    unless (← errors.get).isEmpty do
      throw <| IO.userError s!"Partial chapter rendering errors: {← errors.get}"

-- Checkpoint the real mixed-facet document in each layout. The selected bodies,
-- provenance, external anchors, code panels and graph must survive restoration
-- without reinstalling the generator's project model.
#eval show IO Unit from do
  let cfg : Verso.Genre.Manual.RenderConfig := { features := {} }
  let impls := facetBlueprint.model.withExtensions extension_impls%
  let errors ← IO.mkRef (#[] : Array String)
  let logger : Verso.Logger IO := { (default : Verso.Logger IO) with
    log := fun severity message _ =>
      if severity == .error then errors.modify (·.push message) else pure () }
  for mode in #[Verso.Genre.Manual.Mode.single, .multi] do
    let some document ← (HtmlDocument.traverse mode cfg facetBlueprint.text).run impls |>.run logger
      | throw <| IO.userError s!"Mixed-facet traversal rejected: {← errors.get}"
    let files ← PreviewManifest.buildPreviewDataFiles impls (fun message => errors.modify (·.push message))
      (PreviewManifest.PreparedRendererState.prepare document).previewState
    IO.FS.withTempFile fun _ path => do
      document.save path
      let some restored ← (HtmlDocument.load mode cfg path).run extension_impls% |>.run logger
        | throw <| IO.userError s!"Mixed-facet checkpoint rejected: {← errors.get}"
      let restoredFiles ← PreviewManifest.buildPreviewDataFiles impls (fun message => errors.modify (·.push message))
        (PreviewManifest.PreparedRendererState.prepare restored).previewState
      unless toJson files.manifest == toJson restoredFiles.manifest &&
          toJson files.htmlCache == toJson restoredFiles.htmlCache && (← errors.get).isEmpty do
        throw <| IO.userError "Mixed-facet checkpoint changed preview data or emitted errors"
