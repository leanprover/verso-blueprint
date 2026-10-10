/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support
import VersoBlueprint.Vbp
import VersoBlueprint.PreviewManifest.BlockRender

open Lean Verso Genre Manual Informal
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintProofLeanRefs

#docs (Manual) proofReferencesDoc "Proof references" :=
:::::::
:::lemma_ "proof.helper.owner" (lean := "Nat.add_comm")
A separately owned helper.
:::
:::lemma_ "proof.references" (lean := "Nat.add_assoc")
A statement with its own implementation.
:::
:::proof "proof.references" (lean := "Nat.add_comm, Nat.add_left_comm") (autoDeps := true) (uses := "proof.helper.owner")
A proof using two supporting declarations.
:::
:::lemma_ "proof.helpers.only"
A statement with no associated implementation.
:::
:::proof "proof.helpers.only" (lean := "Nat.add_comm")
Supporting references do not implement this result.
:::
:::lemma_ "proof.without.references" (lean := "Nat.add_assoc")
A statement with implementation metadata.
:::
:::proof "proof.without.references"
A proof with no attached references.
:::
:::::::

/- Registration keeps ownership, dependency inference, and completion independent of helpers. -/
#eval show CoreM Unit from do
  let state := Environment.informalExt.getState (← getEnv)
  let some node := state.data.get? (Name.mkSimple "proof.references")
    | throwError "Missing proof-reference node"
  unless node.externalRefs.map (·.canonical) == #[`Nat.add_assoc] &&
      node.proofExternalRefs.map (·.canonical) == #[`Nat.add_comm, `Nat.add_left_comm] do
    throwError "Proof references merged into statement implementation metadata"
  unless node.proof.any (·.dependencyLabels == #[Name.mkSimple "proof.helper.owner"]) &&
      node.statement.any (·.dependencyLabels.isEmpty) do
    throwError "Supporting references changed authored dependencies"
  unless state.leanNameLabels.getD `Nat.add_comm #[] == #[Name.mkSimple "proof.helper.owner"] do
    throwError "A supporting declaration became owned by the proof node"
  let some helpersOnly := state.data.get? (Name.mkSimple "proof.helpers.only")
    | throwError "Missing helper-only node"
  unless !helpersOnly.hasAssociatedCode && helpersOnly.leanDecls.isEmpty &&
      !(Graph.nodeCodeHealth {} helpersOnly).localProofFormalized &&
      Graph.proofStatus {} state (Name.mkSimple "proof.helpers.only") helpersOnly == .ready do
    throwError "Supporting references conferred proof completeness"
  let withoutHelpers := { node.toNode with proofExternalRefs := #[] }
  unless Graph.proofStatus {} state (Name.mkSimple "proof.references") node ==
      Graph.proofStatus {} state (Name.mkSimple "proof.references") withoutHelpers do
    throwError "Supporting references changed existing proof progress"
  for status in #[Data.ProvedStatus.proved, .axiomLike, .missing,
      .incomplete { knownSorry := #[{ location := .proof }] }] do
    let refs := node.proofExternalRefs.map fun ref =>
      { ref with provedStatus := status, present := status != .missing }
    let changed := { node.toNode with proofExternalRefs := refs }
    unless Graph.proofStatus {} state (Name.mkSimple "proof.references") changed ==
        Graph.proofStatus {} state (Name.mkSimple "proof.references") withoutHelpers &&
        (Graph.nodeWarnings {} state (Name.mkSimple "proof.references") changed).missingExternalDecl ==
          (status == .missing) do
      throwError "A helper's status changed proof completion or hid a missing reference"

/- Page HTML, cached proof previews, manifest facets, and node queries retain the same proof refs. -/
#eval show IO Unit from do
  let (html, state) ← renderManualDocHtmlStringAndState extension_impls% proofReferencesDoc
  unless hasSubstr html "Lean references used in this proof" do
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
  unless hasSubstr rendered.asString "Lean references used in this proof" &&
      hasSubstr rendered.asString "Supporting declaration preview" do
    throw <| IO.userError "Cached proof rendering dropped its supporting declarations"
  let .ok (some query) := VersoBlueprint.Vbp.parseQueryPlan ["node", "proof.references"]
    | throw <| IO.userError "Node query failed to parse"
  let result := query.run files.manifest
  let .ok proofJson := result.getObjVal? "proof"
    | throw <| IO.userError "Node query omitted the proof facet"
  unless (proofJson.getObjVal? "codeData").toOption == some (toJson proof.codeData) do
    throw <| IO.userError "Node query dropped proof reference metadata"

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
