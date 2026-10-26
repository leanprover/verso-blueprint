/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Realizations.Capture
import VersoBlueprintTests.BlueprintRealizationCapture

open Lean Elab Command Term
open Informal Data Graph Realizations Translations

namespace Verso.VersoBlueprintTests.BlueprintGraph.NodeStatus

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error issue => throwError "Capture failed: {repr issue}"

private def label (raw : String) : Name := Name.mkSimple raw

run_cmd liftTermElabM do
  let snapshot ← obtain (← Capture.capture)
  let registry := snapshot.registry
  let complete := snapshot.assessmentFor (label "capture.complete")
  let admitted := snapshot.assessmentFor (label "capture.admitted")
  let dependent := snapshot.assessmentFor (label "capture.dependent")

  ensure (complete.hasNativeDeclarations && complete.nativeStatementComplete &&
    complete.nativeProofComplete && complete.requiredComplete)
    "A checked native theorem should be complete in its own selected realization"
  ensure (admitted.hasNativeDeclarations && admitted.nativeStatementComplete &&
    !admitted.nativeProofComplete && !admitted.requiredComplete)
    "An admitted theorem must remain incomplete"
  ensure (dependent.nativeProofComplete && !dependent.requiredComplete &&
    !dependent.proofDependenciesComplete)
    "A locally checked proof must stay distinct from an unfinished dependency"
  let admittedGraph := Graph.buildModel snapshot #[label "capture.admitted"] |>.finish "admitted" {}
  let some admittedNode := admittedGraph.nodes.find? (·.label == label "capture.admitted")
    | throwError "Missing admitted node"
  ensure (admittedNode.actionableStage? == some "proof")
    "A local proof gap is actionable once its selected prerequisites pass"
  let dependentGraph := Graph.buildModel snapshot #[label "capture.dependent"] |>.finish "dependent" {}
  let some dependentNode := dependentGraph.nodes.find? (·.label == label "capture.dependent")
    | throwError "Missing dependent node"
  ensure dependentNode.actionableStage?.isNone
    "A locally complete proof is not presented as actionable while its prerequisite is unfinished"
  ensure ((dependentNode.visual.tooltip?.getD "").contains "Selected Lean requirements: incomplete")
    "The graph tooltip must distinguish local proof validity from unfinished realization requirements"

  let cycleA := label "capture.cycleA"
  let cycleB := label "capture.cycleB"
  let graph := Graph.buildModel snapshot #[cycleA] |>.finish "captured-cycle" {}
  ensure (graph.nodes.any (·.label == cycleA) && graph.nodes.any (·.label == cycleB))
    "Graph traversal should retain both captured cycle members"
  let hasForward := graph.edges.any fun edge => edge.source == cycleA && edge.target == cycleB &&
    edge.axes.contains .statement
  let hasBackward := graph.edges.any fun edge => edge.source == cycleB && edge.target == cycleA &&
    edge.axes.contains .statement
  ensure (hasForward && hasBackward)
    "Captured forward references should produce the whole cycle topology"
  for name in #[cycleA, cycleB] do
    let some node := graph.nodes.find? (·.label == name) | throwError "Missing cycle graph node"
    ensure (node.assessment.isSome && node.proofStatus == .formalized)
      "A local proof remains visible while selected cyclic prerequisites block closure"
    ensure node.actionableStage?.isNone
      "Cyclic prerequisites block next-step actionability"
  ensure ((registry.resultFor (.realization ⟨cycleA, `lean⟩)).status == .blocked)
    "Graph must use the existing evaluator's blocked cycle result"

  let missing := label "capture.absent"
  let missingGraph := Graph.buildModel snapshot #[label "capture.missing"] |>.finish "missing-use" {}
  ensure (missingGraph.nodes.any fun node => node.label == missing && node.assessment.isNone &&
    node.warnings.unknownRef && node.statementStatus == .unassessed)
    "A missing target stays an unresolved graph endpoint without a fabricated assessment"

end Verso.VersoBlueprintTests.BlueprintGraph.NodeStatus
