/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support
import VersoBlueprint.Vbp
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprintTests.BlueprintProofLeanRefs.Provider

open Lean Verso Genre Manual Informal
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintProofLeanRefs

@[blueprint "proof.inferred.dep"]
theorem inferredDependency : True := True.intro

theorem attachedResult : True := inferredDependency

theorem admittedAttachedResult : True := by sorry

-- Synthetic status observations exercise the reducer independently of the
-- classifier. Neither facet, input order, batching nor exact replay may discard
-- observed incompleteness before the canonical node projection sees it.
#eval show IO Unit from do
  let good : Data.ExternalRef := { Data.ExternalRef.ofName `Example.repeated with
    present := true, kind := .theorem, provedStatus := .proved }
  let known : Data.ProvedStatus := .incomplete { knownSorry := #[{
    location := .proof, origin := .dependency, refs? := some 2 }] }
  let unverified : Data.ProvedStatus := .incomplete { unverified := #[{
    location := .proof, declaration := good.canonical, reason := .bodyUnavailable }] }
  for isProof in #[false, true] do
    let contribution := fun ref =>
      if isProof then ({ proofExternalRefs := #[ref] } : Data.NodeContribution)
      else { leanCode := #[.external #[ref]] }
    for status in #[known, unverified] do
      let gap := { good with provedStatus := status }
      for refs in #[#[good, gap], #[gap, good]] do
        let inputs := refs.map contribution
        let .ok batched := ({} : Data.Node).applyContributions `repeated inputs
          | throw <| IO.userError "Repeated associations were rejected"
        let .ok incremental := inputs.foldlM
            (fun (node : Data.Node) input => node.applyContributions `repeated #[input]) ({} : Data.Node)
          | throw <| IO.userError "Incremental associations were rejected"
        let .ok replayed := incremental.applyContributions `repeated inputs
          | throw <| IO.userError "Replayed associations were rejected"
        for node in #[batched, incremental, replayed] do
          let refs := node.associatedExternalRefs
          unless refs.size == 1 && refs[0]!.provedStatus == status &&
              node.leanDecls == #[good.canonical] &&
              !(Graph.nodeCodeHealth {} node).localProofFormalized do
            throw <| IO.userError "Same-facet deduplication discarded status evidence"
  for status in #[known, unverified, Data.ProvedStatus.incomplete {}, .missing, .axiomLike] do
    let ref := { good with provedStatus := status, present := status != .missing }
    let code : Data.Code := { stx := .missing, definedTheorems := #[{
      name := good.canonical, provedStatus := .proved }] }
    let node : Data.Node := { kind := .theorem, proofExternalRefs := #[ref], literateCodes := #[code] }
    let health := Graph.nodeCodeHealth {} node
    unless node.summaryExternalRefs.isEmpty && health.totalDecls == 1 &&
        health.hasAnyGaps == (!status.isMissing && status.isIncomplete) &&
        health.hasMissingExternalDecls == status.isMissing &&
        health.hasAxiomLike == status.isAxiomLike && !health.localProofFormalized &&
        health.provedStatus.reportJson == status.reportJson &&
        node.summaryLiterateCodes[0]!.definedTheorems[0]!.provedStatus.reportJson == status.reportJson do
      throw <| IO.userError "Inline display precedence discarded external status evidence"
    let source : BlockCodeData := { externalDecls := #[ref], literateDeclarations := {
      definedTheorems := #[{ name := good.canonical, provedStatus := .proved }] } }
    let panel := Graph.codeHealthOfBlockSource .theorem {} (some source)
    unless source.summaryExternalDecls.isEmpty && panel.totalDecls == 1 &&
        panel.hasAnyGaps == (!status.isMissing && status.isIncomplete) &&
        panel.hasMissingExternalDecls == status.isMissing &&
        panel.hasAxiomLike == status.isAxiomLike && !panel.localProofFormalized &&
        panel.provedStatus.reportJson == status.reportJson do
      throw <| IO.userError "Panel display precedence discarded external status evidence"
    let data : BlockData := { label := `overlap, kind := .theorem, count := 1, codeData := some source }
    let rendered := CodeSummary.renderParts data { source := some source } (fun _ => none)
    unless !hasSubstr rendered.codeEntry.asString "bp_code_decl_status_ok" do
      throw <| IO.userError "Summary preview presented the selected inline declaration as complete"
  let code : Data.Code := { stx := .missing, definedTheorems := #[{
    name := good.canonical, provedStatus := .proved }] }
  let node : Data.Node := { kind := .theorem, proofExternalRefs := #[good], literateCodes := #[code] }
  let external : Graph.ExternalCodeStatus := { provedStatus := fun _ => unverified }
  unless !(Graph.nodeCodeHealth external node).localProofFormalized do
    throw <| IO.userError "Inline display precedence discarded external lookup evidence"

#docs (Manual) proofReferencesDoc "Proof references" :=
:::::::
:::lemma_ "proof.helper.owner" (lean := "Nat.add_comm")
A separately owned helper.
:::
:::lemma_ "proof.references" (lean := "Nat.add_assoc")
A statement with its own implementation.
:::
:::proof "proof.references" (lean := "Nat.add_comm, Nat.add_left_comm") (autoDeps := true) (uses := "proof.helper.owner")
A proof with two associated declarations.
:::
:::lemma_ "proof.attachments.only"
A statement whose Lean association is on the proof.
:::
:::proof "proof.attachments.only" (lean := "attachedResult") (autoDeps := true)
The attached theorem contributes to this node and infers its proof dependency.
:::
:::lemma_ "proof.attachments.admitted"
A statement with an incomplete associated proof.
:::
:::proof "proof.attachments.admitted" (lean := "admittedAttachedResult") (autoDeps := false)
The attached proof hole must remain visible in progress and summaries.
:::
:::lemma_ "proof.attachments.both" (lean := "attachedResult")
The same declaration can be mentioned on both facets.
:::
:::proof "proof.attachments.both" (lean := "attachedResult")
Both mentions retain their facet while contributing one canonical declaration.
:::
:::lemma_ "proof.without.references" (lean := "Nat.add_assoc")
A statement with implementation metadata.
:::
:::proof "proof.without.references"
A proof with no attached references.
:::
:::::::

/- Both facets contribute to node membership, inference, and conservative status. -/
#eval show CoreM Unit from do
  let state := Environment.informalExt.getState (← getEnv)
  let some node := state.data.get? (Name.mkSimple "proof.references")
    | throwError "Missing proof-reference node"
  unless node.externalRefs.map (·.canonical) == #[`Nat.add_assoc] &&
      node.proofExternalRefs.map (·.canonical) == #[`Nat.add_comm, `Nat.add_left_comm] do
    throwError "A declaration lost its authored facet"
  unless node.leanDecls == #[`Nat.add_assoc, `Nat.add_comm, `Nat.add_left_comm] do
    throwError "Proof declarations were excluded from node membership"
  unless node.proof.any (·.dependencyLabels == #[Name.mkSimple "proof.helper.owner"]) &&
      node.statement.any (·.dependencyLabels.isEmpty) do
    throwError "Proof attachments changed authored dependency axes"
  unless state.leanNameLabels.getD `Nat.add_comm #[] ==
      #[Name.mkSimple "proof.helper.owner", Name.mkSimple "proof.references"] do
    throwError "Proof declarations were excluded from the accepted index"
  let some proofOnly := state.data.get? (Name.mkSimple "proof.attachments.only")
    | throwError "Missing proof-only association node"
  unless proofOnly.hasAssociatedCode && proofOnly.leanDecls == #[``attachedResult] &&
      (Graph.nodeCodeHealth {} proofOnly).localProofFormalized &&
      proofOnly.proof.any (·.dependencyLabels == #[Name.mkSimple "proof.inferred.dep"]) &&
      proofOnly.statement.any (·.dependencyLabels.isEmpty) do
    throwError "Proof association did not contribute membership, status, or inferred proof dependencies"
  let some admitted := state.data.get? (Name.mkSimple "proof.attachments.admitted")
    | throwError "Missing admitted proof association"
  unless Graph.proofStatus {} state (Name.mkSimple "proof.attachments.admitted") admitted == .incomplete do
    throwError "An admitted proof association appeared complete"
  let some both := state.data.get? (Name.mkSimple "proof.attachments.both")
    | throwError "Missing shared-facet association"
  unless both.leanDecls == #[``attachedResult] &&
      (Graph.nodeCodeHealth {} both).totalDecls == 1 do
    throwError "The same declaration on two facets was counted twice"
  let proofGap : Data.ProvedStatus := .incomplete {
    knownSorry := #[{ location := .proof, origin := .dependency }] }
  let crossFacetGap := { both.toNode with
    proofExternalRefs := both.proofExternalRefs.map fun ref => { ref with provedStatus := proofGap } }
  unless (Graph.nodeCodeHealth {} crossFacetGap).hasAnyGaps &&
      !(Graph.nodeCodeHealth {} crossFacetGap).localProofFormalized do
    throwError "Canonical deduplication erased proof-facet status evidence"
  for status in #[Data.ProvedStatus.proved, .axiomLike, .missing,
      proofGap, .incomplete { knownSorry := #[{ location := .unknown, origin := .unknown }] },
      .incomplete { unverified := #[{ location := .proof, reason := .bodyUnavailable }] }] do
    let refs := proofOnly.proofExternalRefs.map fun ref =>
      { ref with provedStatus := status, present := status != .missing }
    let changed := { proofOnly.toNode with proofExternalRefs := refs }
    unless (Graph.nodeCodeHealth {} changed).localProofFormalized == status.isProved &&
        (Graph.nodeWarnings {} state (Name.mkSimple "proof.attachments.only") changed).missingExternalDecl ==
          (status == .missing) do
      throwError "Proof association status did not contribute conservatively"

-- Add a second proof association to a compiled imported node. Export only this
-- local contribution and check both associations again after another import.
run_meta do
  let ref ← externalRefSnapshotAtCurrentDir {}
    (Data.ExternalRef.ofName ``Provider.secondProof)
  let some _ ← Environment.contribute (Name.mkSimple "proof.imported.associations") {
    proofExternalRefs := #[ref] }
    | throwError "Could not extend the imported proof associations"
  let some node ← Environment.getNode? (Name.mkSimple "proof.imported.associations")
    | throwError "Missing imported proof node"
  unless node.leanDecls == #[``Provider.firstProof, ``Provider.secondProof] do
    throwError "Local proof association discarded imported membership"

-- Re-observe a compiled admitted proof with a synthetic neutral snapshot.
-- This is a projection/replay control, not a claim about classifier output.
run_meta do
  let ref ← externalRefSnapshotAtCurrentDir {}
    (Data.ExternalRef.ofName ``Provider.admittedProof)
  let neutral := { ref with provedStatus := .proved }
  let some _ ← Environment.contribute (Name.mkSimple "proof.imported.repeated") {
    proofExternalRefs := #[neutral, ref] }
    | throwError "Could not repeat the imported proof association"
  let some node ← Environment.getNode? (Name.mkSimple "proof.imported.repeated")
    | throwError "Missing repeated imported proof node"
  unless node.proofExternalRefs.size == 1 &&
      node.associatedExternalRefs[0]!.provedStatus.isIncomplete &&
      !(Graph.nodeCodeHealth {} node).localProofFormalized do
    throwError "Repeated compiled proof association erased incompleteness"

-- Synthetic neutral inline evidence tests display precedence. The external
-- snapshot supplies the actual admitted proof's classification.
run_meta do
  let ref ← externalRefSnapshotAtCurrentDir {}
    (Data.ExternalRef.ofName ``Provider.admittedProof)
  let code : Data.Code := { stx := .missing, definedTheorems := #[{
    name := ``Provider.admittedProof, provedStatus := .proved }] }
  let some _ ← Environment.contribute (Name.mkSimple "proof.inline.overlap") {
    kind := some .theorem, leanCode := #[.literate code], proofExternalRefs := #[ref] }
    | throwError "Could not register inline/external overlap"

#eval show CoreM Unit from do
  let some node ← Environment.getNode? (Name.mkSimple "proof.inline.overlap")
    | throwError "Missing inline/external overlap"
  unless (Graph.nodeCodeHealth {} node).totalDecls == 1 &&
      !(Graph.nodeCodeHealth {} node).localProofFormalized do
    throwError "Inline/external overlap was counted twice or appeared complete"
  let summary ← Commands.buildSummary
  let details := summary.incompleteDetails.filter (·.label == Name.mkSimple "proof.inline.overlap")
  unless details.length == 1 && details[0]!.status.hasKnownSorry do
    throwError "Summary discarded the proof association's incompleteness"

/- Page HTML, cached proof previews, manifest facets, and node queries retain the same proof refs. -/
#eval show IO Unit from do
  let (html, state) ← renderManualDocHtmlStringAndState extension_impls% proofReferencesDoc
  unless hasSubstr html "Lean declarations attached to this proof" do
    throw <| IO.userError "Proof declaration panel missing from page HTML"
  let files ← PreviewManifest.buildPreviewDataFiles extension_impls%
    (fun message => throw <| IO.userError message)
    (PreviewManifest.PreparedPreviewState.prepare state)
    ({ mode := .none } : ExternalMarkupRender.Config)
  let label := Name.mkSimple "proof.references"
  let some statement := files.manifest.findEntry? (PreviewCache.statementKey label)
    | throw <| IO.userError "Missing statement facet"
  let some proof := files.manifest.findEntry? (PreviewCache.proofKey label)
    | throw <| IO.userError "Missing proof facet"
  unless statement.codeData.any (·.externalDecls.map (·.canonical) == #[`Nat.add_assoc]) &&
      proof.codeData.any (·.externalDecls.map (·.canonical) == #[`Nat.add_comm, `Nat.add_left_comm]) &&
      proof.leanCodePreviewKeys.size == 2 do
    throw <| IO.userError "Manifest borrowed declarations from the other facet"
  let noRefs := Name.mkSimple "proof.without.references"
  unless (files.manifest.findEntry? (PreviewCache.proofKey noRefs)).any
      (fun entry => entry.codeData.isNone && entry.leanCodePreviewKeys.isEmpty) do
    throw <| IO.userError "An unattached proof borrowed statement code"
  let some proofBody := files.htmlCache.findHtml? (PreviewCache.proofKey label)
    | throw <| IO.userError "Missing cached proof HTML"
  let rendered := PreviewManifest.BlockRender.renderWithRenderedContent {} proof {
    body := .text false proofBody
    codeBodies := #[.text false "Supporting declaration preview"]
    codeData := proof.codeData.getD {}
  }
  unless hasSubstr rendered.asString "Lean declarations attached to this proof" &&
      hasSubstr rendered.asString "Supporting declaration preview" do
    throw <| IO.userError "Cached proof rendering dropped its supporting declarations"
  let .ok (some query) := VersoBlueprint.Vbp.parseQueryPlan ["node", "proof.references"]
    | throw <| IO.userError "Node query failed to parse"
  let result := query.run files.manifest
  let .ok proofJson := result.getObjVal? "proof"
    | throw <| IO.userError "Node query omitted the proof facet"
  unless (proofJson.getObjVal? "codeData").toOption == some (toJson proof.codeData) do
    throw <| IO.userError "Node query dropped proof reference metadata"
  let .ok (some codeQuery) := VersoBlueprint.Vbp.parseQueryPlan ["code", "attachedResult"]
    | throw <| IO.userError "Code query failed to parse"
  let .ok matchingLabels := (codeQuery.run files.manifest).getObjValAs? (Array Json) "labels"
    | throw <| IO.userError "Code query omitted its labels"
  unless matchingLabels.any (fun entry => (entry.getObjValAs? String "label").toOption ==
      some "proof.attachments.only") do
    throw <| IO.userError "Code query omitted a proof-only association"
  for (label, complete) in #[("proof.attachments.only", true), ("proof.attachments.admitted", false)] do
    let .ok (some statusQuery) := VersoBlueprint.Vbp.parseQueryPlan ["status", label]
      | throw <| IO.userError "Status query failed to parse"
    let status := statusQuery.run files.manifest
    unless (status.getObjValAs? Bool "complete").toOption == some complete do
      throw <| IO.userError "Status query ignored the proof association"
    let .ok declarations := status.getObjValAs? (Array Json) "declarations"
      | throw <| IO.userError "Status query omitted declarations"
    unless declarations.size == 1 &&
        (declarations[0]!.getObjValAs? String "facet").toOption == some "proof" do
      throw <| IO.userError "Status query lost proof association provenance"

/--
error: Label «proof.duplicate» has duplicate external Lean reference 'Nat.add' (canonical 'Nat.add'); previously declared as 'Nat.add'
-/
#guard_msgs in
#docs (Manual) duplicateProofRefs "Duplicate proof refs" :=
:::::::
:::lemma_ "proof.duplicate"
Statement.
:::
:::proof "proof.duplicate" (lean := "Nat.add, Nat.add")
Proof.
:::
:::::::

/--
error: Label «proof.missing»: external Lean name 'No.Such.ProofHelper' could not be resolved in current namespace/open declarations
-/
#guard_msgs in
set_option verso.blueprint.externalCode.strictResolve true in
#docs (Manual) missingProofRef "Missing proof ref" :=
:::::::
:::lemma_ "proof.missing"
Statement.
:::
:::proof "proof.missing" (lean := "No.Such.ProofHelper")
Proof.
:::
:::::::

end Verso.VersoBlueprintTests.BlueprintProofLeanRefs
