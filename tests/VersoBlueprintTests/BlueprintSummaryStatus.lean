/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Commands.Summary.Collect
import VersoBlueprintTests.BlueprintRealizationCapture

open Lean Elab Command Term
open Informal Data Graph Realizations Translations

namespace Verso.VersoBlueprintTests.BlueprintSummaryStatus

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error issue => throwError "Capture failed: {repr issue}"

run_cmd liftTermElabM do
  let counts : Commands.EntryStatusCounts := { completedDepsNo := 1 }
  ensure ((Commands.statusCountsText counts).contains "native checks complete, prerequisites unfinished: 1")
    "Summary text must identify the selected Blueprint prerequisites tracked by this count"
  let snapshot ← obtain (← Capture.capture)
  let summary ← liftM (m := CoreM) (Commands.buildSummary snapshot)
  ensure (summary.totalEntries == snapshot.registry.nodes.size)
    "Summary inventory must come from admitted realization nodes"
  ensure (summary.pendingInformalEntries.any (·.label == Name.mkSimple "capture.complete"))
    "Optional prose assessment must not erase informational missing-prose coverage"
  ensure (summary.leanDecls > 0 && summary.incompleteDecls > 0)
    "Summary native counts should come from captured declaration requirements"
  ensure (summary.incompleteDetails.any (·.label == Name.mkSimple "capture.admitted"))
    "Detailed native debt should retain the freshly checked provider status"

  let complete := snapshot.assessmentFor (Name.mkSimple "capture.complete")
  let dependent := snapshot.assessmentFor (Name.mkSimple "capture.dependent")
  let proseStatement := (⟨Name.mkSimple "capture.complete", `markdown⟩ : RealizationKey).forRole `statement
  ensure ((snapshot.registry.realization? proseStatement).isSome &&
    (snapshot.registry.resultFor (.realization proseStatement)).status == .unassessed)
    "The real docstring must remain present and unassessed without an authored review"
  let missingProse := snapshot.registry.realization?
    ((⟨Name.mkSimple "capture.complete", `verso⟩ : RealizationKey).forRole `proof)
  ensure missingProse.isNone
    "Missing optional prose argument must not manufacture a realization or a validation obligation"
  ensure (complete.nativeProofComplete && complete.requiredComplete)
    "Native proof and its own realization closure should be counted complete"
  ensure (dependent.nativeProofComplete && !dependent.requiredComplete)
    "Native proof completion should remain separate from unfinished Blueprint dependencies"
  let wrongExpected := snapshot.assessmentFor (Name.mkSimple "capture.wrongExpected")
  ensure (wrongExpected.nativeStatementComplete && wrongExpected.nativeProofComplete &&
    wrongExpected.requiredComplete && wrongExpected.proofDependenciesComplete)
    "The native summary must remain independent of a separately authored expected proposition"
  let expectedKey : RequirementKey := ⟨.declaration
    ((⟨Name.mkSimple "capture.wrongExpected", `lean⟩ : RealizationKey).forRole `proof)
    ⟨⟨`lean, `blueprintFixtures⟩, "RealizationCaptureFixture.wrongExpected"⟩, `expectedProof⟩
  ensure ((snapshot.registry.requirement? expectedKey).isSome &&
    !(snapshot.registry.resultForRequirement expectedKey).complete)
    "The exact independent expectation must remain present and unfinished"
  ensure (!summary.incompleteDetails.any (·.label == Name.mkSimple "capture.wrongExpected"))
    "A separate expected proposition mismatch must not enter the native code debt list"
  let completeRequirements := snapshot.registry.nodes.countP fun node =>
    (snapshot.assessmentFor node.label).requiredComplete
  ensure (summary.coverageSplit.requirementsComplete == completeRequirements &&
    summary.totalStatus.completed == completeRequirements)
    "The native requirements counters must include the locally complete wrongExpected node"
  let localCompletePendingRequirements := snapshot.registry.nodes.foldl (init := 0) fun total node =>
    let assessment := snapshot.assessmentFor node.label
    if assessment.nativeLocallyComplete && !assessment.requiredComplete then total + 1 else total
  ensure (summary.coverageSplit.nativeCompleteRequirementsPending == localCompletePendingRequirements)
    "The summary bucket must count unfinished ordinary native requirements"

end Verso.VersoBlueprintTests.BlueprintSummaryStatus
