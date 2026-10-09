/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.SorryImport.Captured

open Lean Informal Informal.Data
open Verso.VersoBlueprintTests.SorryImport.Captured

-- Exercise persistence of the actual attribute snapshot and the serialized
-- BlueprintDocument capture across a compiled producer/consumer boundary.
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let label := Name.mkSimple "sorry.capture.both"
    let some node := state.data.get? label | return false
    let some ref := node.externalRefs[0]? | return false
    let some captured := statusCaptureBlueprint.model.nodes.find? (·.label == label) | return false
    let some capturedRef := captured.externalRefs[0]? | return false
    let status := Graph.externalDeclProvedStatus {} ref
    let again := status.mergeConservative capturedRef.provedStatus
    return status == ref.provedStatus && again == status &&
      status.hasTypeGap && status.hasProofGap &&
      status.containsExplicitSorry && status.dependsOnSorry &&
      !Graph.nodeLocalProofFormalized {} node &&
      statusCaptureBlueprint.model.summary.sorryDetails.any (fun item =>
        item.label == label && item.status == status)
