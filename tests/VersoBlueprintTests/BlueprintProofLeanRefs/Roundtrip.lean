/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintProofLeanRefs

open Lean Informal
open Verso.VersoBlueprintTests.BlueprintProofLeanRefs

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
