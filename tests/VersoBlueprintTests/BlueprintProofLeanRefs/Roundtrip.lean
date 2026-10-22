/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintProofLeanRefs
import VersoBlueprintTests.BlueprintProofLeanRefs.Provider

open Lean Informal
open Verso.VersoBlueprintTests.BlueprintProofLeanRefs

-- Both direct and transitive imports replay one identified record per producer.
-- Proof-only records remain proof-only; canonical duplicates keep both facets
-- and appear only once in the accepted declaration-to-label index.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let state := Environment.informalExt.getState (← getEnv)
  let label := Name.mkSimple "proof.imported.crossFacet"
  let some node := state.data.get? label | return false
  let records := state.factRecords.filter (·.label == label)
  let proofOnly := state.factRecords.filter (·.label == Name.mkSimple "proof.imported.associations")
  return records.length == 2 &&
    (records.filter fun r => !r.references.isEmpty && r.proofReferences.isEmpty).length == 1 &&
    (records.filter fun r => r.references.isEmpty && !r.proofReferences.isEmpty).length == 1 &&
    proofOnly.length == 2 && proofOnly.all (fun r => r.references.isEmpty && !r.proofReferences.isEmpty) &&
    node.externalRefs.map (·.canonical) == #[``Provider.crossFacetProof] &&
    node.proofExternalRefs.map (·.canonical) == #[``Provider.crossFacetProof] &&
    node.leanDecls == #[``Provider.crossFacetProof] &&
    state.leanNameLabels.getD ``Provider.crossFacetProof #[] == #[label] &&
    (Graph.nodeCodeHealth {} node).totalDecls == 1

/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let some node ← Environment.getNode? (Name.mkSimple "proof.imported.associations")
    | return false
  return node.leanDecls == #[``Provider.firstProof, ``Provider.secondProof] &&
    (← Environment.labelsForLeanDecl ``Provider.firstProof) == #[Name.mkSimple "proof.imported.associations"] &&
    (← Environment.labelsForLeanDecl ``Provider.secondProof) == #[Name.mkSimple "proof.imported.associations"] &&
    (Graph.nodeCodeHealth {} node).localProofFormalized

/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let some node ← Environment.getNode? (Name.mkSimple "proof.imported.repeated")
    | return false
  let labels ← Environment.labelsForLeanDecl ``Provider.admittedProof
  return node.leanDecls == #[``Provider.admittedProof] &&
    node.proofExternalRefs.size == 1 &&
    node.associatedExternalRefs[0]!.provedStatus.isIncomplete &&
    labels.size == 2 && labels.contains (Name.mkSimple "proof.imported.repeated") &&
    labels.contains (Name.mkSimple "proof.inline.overlap") &&
    !(Graph.nodeCodeHealth {} node).localProofFormalized

/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let some node ← Environment.getNode? (Name.mkSimple "proof.inline.overlap")
    | return false
  return node.leanDecls == #[``Provider.admittedProof] &&
    (Graph.nodeCodeHealth {} node).totalDecls == 1 &&
    !(Graph.nodeCodeHealth {} node).localProofFormalized
