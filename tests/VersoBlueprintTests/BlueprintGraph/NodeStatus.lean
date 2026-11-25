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

private def nativeProofCheck (node declaration : Name) : RequirementKey :=
  ⟨.declaration ((⟨node, `lean⟩ : RealizationKey).forRole `proof)
    ⟨⟨`lean, `blueprintFixtures⟩, declaration.toString⟩, `proof⟩

@[blueprint "capture.statementOnly"]
def statementOnly : Prop := True

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
  ensure (admittedNode.statementStatus == .formalized && admittedNode.proofStatus == .incomplete &&
    admittedNode.visual.fillcolor == proofBackgroundIncompleteColor &&
    admittedNode.actionableStage? == some "proof")
    "An admitted native proof remains visually incomplete even while completing it is actionable"
  let dependentGraph := Graph.buildModel snapshot #[label "capture.dependent"] |>.finish "dependent" {}
  let some dependentNode := dependentGraph.nodes.find? (·.label == label "capture.dependent")
    | throwError "Missing dependent node"
  ensure dependentNode.actionableStage?.isNone
    "A locally complete proof is not presented as actionable while its prerequisite is unfinished"
  let dependentTooltip := dependentNode.visual.tooltip?.getD ""
  ensure (dependentTooltip.contains "Proof: locally formalized" &&
    dependentTooltip.contains "Native Lean requirements: unfinished" &&
    dependentTooltip.contains "Selected Lean prerequisites unfinished")
    "The graph tooltip must distinguish local proof validity from unfinished Blueprint prerequisites"

  let wrongExpected := label "capture.wrongExpected"
  let statementOnly := label "capture.statementOnly"
  let graph := Graph.buildModel snapshot #[wrongExpected, statementOnly] |>.finish "native-contracts" {}
  let some wrongNode := graph.nodes.find? (·.label == wrongExpected)
    | throwError "Missing theorem with a separate expected proposition"
  let some assessment := wrongNode.assessment | throwError "Missing captured theorem assessment"
  ensure (assessment.requiredComplete && wrongNode.proofStatus == .formalizedWithAncestors &&
    wrongNode.actionableStage?.isNone &&
    (wrongNode.visual.tooltip?.getD "").contains "Native Lean requirements: complete")
    "An independent expected proposition must not change native proof status or actionability"
  let expectedKey := { (nativeProofCheck wrongExpected `RealizationCaptureFixture.wrongExpected) with
    name := `expectedProof }
  let some requirement := registry.requirement? expectedKey
    | throwError "Missing independently authored expected proposition requirement"
  let report ← obtain do
    let contracts ← assessment.details.getObjVal? "assessment"
    contracts.getObjValAs? (Array Json) "requirements"
  ensure (report.any fun row =>
    (row.getObjVal? "value").toOption == some (toJson requirement) &&
      ((row.getObjVal? "result").toOption.any fun result => result.compress.contains "wrong-proposition"))
    "The same graph node must expose the wrong-proposition result on its own expected proof contract"
  let some statementNode := graph.nodes.find? (·.label == statementOnly)
    | throwError "Missing statement-only native proposition"
  ensure (statementNode.assessment.any (fun view => view.requiredComplete && !view.hasNativeBodyRequirement &&
      !view.nativeProofComplete) && statementNode.statementStatus == .formalized &&
      statementNode.proofStatus == .none && statementNode.actionableStage?.isNone &&
      (statementNode.visual.tooltip?.getD "").contains "no native body check")
    "A checked statement-only proposition must not acquire a pending proof or proof-writing task"

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
  let cycleAProof := nativeProofCheck cycleA `RealizationCaptureFixture.cycleA
  let cycleBProof := nativeProofCheck cycleB `RealizationCaptureFixture.cycleB
  for proofCheck in #[cycleAProof, cycleBProof] do
    ensure ((registry.requirement? proofCheck).isSome && (registry.localResult proofCheck).complete)
      "Cycle control must have a real, locally passing native proof requirement"
    let result := registry.resultForRequirement proofCheck
    ensure (result.status == .blocked && result.diagnostics.any (·.code == "requirement-cycle"))
      "The exact native proof requirement must be blocked by the captured validation cycle"

  let missing := label "capture.absent"
  let missingGraph := Graph.buildModel snapshot #[label "capture.missing"] |>.finish "missing-use" {}
  ensure (missingGraph.nodes.any fun node => node.label == missing && node.assessment.isNone &&
    node.warnings.unknownRef && node.statementStatus == .unassessed)
    "A missing target stays an unresolved graph endpoint without a fabricated assessment"

end Verso.VersoBlueprintTests.BlueprintGraph.NodeStatus
