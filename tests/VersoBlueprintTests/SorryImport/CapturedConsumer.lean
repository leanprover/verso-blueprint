/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.SorryImport.Captured

open Lean Informal Informal.Data
open Verso.VersoBlueprintTests.SorryImport.Captured

-- Compare the deferred attribute registration with the serialized
-- BlueprintDocument capture across a compiled producer/consumer boundary.
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let label := Name.mkSimple "sorry.capture.both"
    let some node := state.inventory.get? label | return false
    let some ref := (node.nativeRefsOn `statement)[0]? | return false
    let some captured := statusCaptureBlueprint.model.nodes.find? (·.label == label) | return false
    let some code := captured.toBlockData.codeData | return false
    let some capturedRef := code.displayExternalDecls[0]? | return false
    let some assessment := captured.assessment | return false
    let some graphNode := statusCaptureBlueprint.model.graph.nodes.find? (·.label == label) | return false
    let some (_, some status) := captured.statementExternalChecks.find? (·.1 == ref.canonical) | return false
    let expectedStatuses := Graph.statusesForAssessment assessment
    return ref.present && ref.provedStatus.isNone && capturedRef.provedStatus == some status &&
      status.hasTypeGap && status.hasProofGap &&
      status.containsExplicitSorry && status.dependsOnSorry &&
      assessment.hasNativeDeclarations && !assessment.nativeBodyComplete &&
      graphNode.assessment == some assessment &&
      graphNode.statementStatus == expectedStatuses.1 && graphNode.proofStatus == expectedStatuses.2 &&
      statusCaptureBlueprint.model.summary.incompleteDetails.any (fun item =>
        item.label == label && item.status == status)
