/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Commands.Summary.Collect
import VersoBlueprint.RenderModel
import VersoBlueprintTests.BlueprintRealizationCapture

open Lean Elab Command Term
open Informal Data Graph Realizations Translations

namespace Verso.VersoBlueprintTests.BlueprintSummaryStatus

set_option linter.defProp false in
@[blueprint "summary.proofDef"]
def proofDef : True := by sorry

@[blueprint "summary.computation"]
def computation : Nat := by sorry

@[blueprint "summary.mixedBodies"]
theorem mixedProof : True := True.intro

@[blueprint "summary.mixedBodies"]
def mixedImplementation : Nat := by sorry

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
  let assessments := snapshot.assessmentMap
  let assessmentFor (label : Name) := assessments.getD label default
  let state := Environment.informalExt.getState (← getEnv)
  let labels := snapshot.registry.nodes.map (·.label)
  let preparedNodes := TraversalIndex.Nodes.capture state (some snapshot) (fun label => assessments.get? label)
  let preparedGraph := Graph.buildModel snapshot labels (assessmentFor := assessmentFor)
  let preparedSummary ← liftM (m := CoreM) (Commands.buildSummary snapshot (assessmentFor := assessmentFor))
  ensure (assessments.toArray.size == labels.size &&
      toJson preparedNodes == toJson (TraversalIndex.Nodes.capture state (some snapshot)) &&
      toJson preparedGraph == toJson (Graph.buildModel snapshot labels) &&
      toJson preparedSummary == toJson summary)
    "Precomputed assessments must produce the same render nodes, graph, and summary as standalone capture"
  ensure (summary.totalEntries == snapshot.registry.nodes.size)
    "Summary inventory must come from admitted realization nodes"
  ensure (summary.pendingInformalEntries.any (·.label == Name.mkSimple "capture.complete"))
    "Optional prose assessment must not erase informational missing-prose coverage"
  ensure (summary.leanDecls > 0 && summary.incompleteDecls > 0)
    "Summary native counts should come from captured declaration requirements"
  ensure (summary.incompleteDetails.any (·.label == Name.mkSimple "capture.admitted"))
    "Detailed native debt should retain the freshly checked provider status"

  let cases : Array (String × Data.NodeKind × Option Bool × ProofStatus) := #[
    ("capture.admitted", .theorem, some false, .incomplete),
    ("summary.proofDef", .definition, some false, .incomplete),
    ("summary.computation", .definition, none, .none)]
  let graph := Graph.buildModel snapshot (cases.map fun c => Name.mkSimple c.1) |>.finish "proof-roles" {}
  for (name, kind, proofComplete, status) in cases do
    let label := Name.mkSimple name
    let some node := graph.nodes.find? (·.label == label)
      | throwError "Missing graph node {label}"
    ensure (node.kind == some kind && node.proofStatus == status &&
      (snapshot.assessmentFor label).proofRoleComplete == proofComplete)
      s!"{label}: graph and capture should distinguish mathematical proofs from computations"
  let mixedLabel := Name.mkSimple "summary.mixedBodies"
  let mixed := snapshot.assessmentFor mixedLabel
  let mixedGraph := Graph.buildModel snapshot #[mixedLabel] |>.finish "mixed-bodies" {}
  let some mixedNode := mixedGraph.nodes.find? (·.label == mixedLabel)
    | throwError "Missing mixed native node"
  ensure (mixed.proofRoleComplete == some true && !mixed.nativeBodyComplete && !mixed.requiredComplete &&
    mixedNode.proofStatus == .none)
    "A passing mathematical proof cannot mark a node with an admitted implementation as formalized"
  let wire := toJson mixed
  ensure ((wire.getObjValAs? Bool "proofRoleComplete").toOption == some true &&
      (wire.getObjValAs? Bool "nativeBodyComplete").toOption == some false)
    "The serialized mixed node must distinguish its checked proof from its unfinished implementation"
  let unfinishedDefinitionProofs := snapshot.registry.nodes.countP fun node =>
    node.kind == .definition && (snapshot.assessmentFor node.label).proofRoleComplete == some false
  ensure (unfinishedDefinitionProofs > 0 && summary.definitionStatus.noProof == unfinishedDefinitionProofs)
    "The summary must count unfinished mathematical proofs among definition nodes"
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
  ensure (complete.nativeBodyComplete && complete.requiredComplete)
    "Native proof and its own realization closure should be counted complete"
  ensure (dependent.nativeBodyComplete && !dependent.requiredComplete)
    "Native proof completion should remain separate from unfinished Blueprint dependencies"
  let wrongExpected := snapshot.assessmentFor (Name.mkSimple "capture.wrongExpected")
  ensure (wrongExpected.nativeStatementComplete && wrongExpected.nativeBodyComplete &&
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

/--
warning: Label «summary.forwardAxiom»: external Lean name 'Verso.VersoBlueprintTests.BlueprintSummaryStatus.declaredLaterAxiom' could not be resolved in current namespace/open declarations; keeping parsed name
-/
#guard_msgs in
#docs (Verso.Genre.Manual) forwardAxiomDoc "Forward axiom attachment" :=
:::::::
:::theorem "summary.forwardAxiom" (lean := "Verso.VersoBlueprintTests.BlueprintSummaryStatus.declaredLaterAxiom")
The declaration is still missing when this attachment is registered.
:::
:::::::

axiom declaredLaterAxiom : True

#docs (Verso.Genre.Manual) resolvedAxiomDoc "Resolved axiom attachment" :=
:::::::
:::theorem "summary.resolvedAxiom" (lean := "declaredLaterAxiom")
This attachment resolves the axiom when registered.
:::
:::::::

run_cmd liftTermElabM do
  let forward := Name.mkSimple "summary.forwardAxiom"
  let resolved := Name.mkSimple "summary.resolvedAxiom"
  let declaration := ``declaredLaterAxiom
  let state := Environment.informalExt.getState (← getEnv)
  let attached (label : Name) (present : Bool) := (state.inventory.get? label).any fun node =>
    (node.nativeRefsOn `statement).any fun ref => ref.canonical == declaration && ref.present == present
  ensure (attached forward false && attached resolved true)
    "The two attachment controls must share a canonical name but differ in registration-time resolution"

  let snapshot ← obtain (← Capture.capture)
  let forwardAssessment := snapshot.assessmentFor forward
  let resolvedAssessment := snapshot.assessmentFor resolved
  ensure (resolvedAssessment.hasAxiomLike && !resolvedAssessment.requiredComplete)
    "The resolved attachment must retain its checked axiom status"
  ensure (forwardAssessment.hasNativeDeclarations && !forwardAssessment.hasAxiomLike &&
      !forwardAssessment.requiredComplete)
    "The forward attachment borrowed the resolved attachment's axiom status"
  let summary ← liftM (m := CoreM) (Commands.buildSummary snapshot)
  ensure ((summary.axiomIndex.filter (·.leanObjects.contains declaration)).map (·.label) == [resolved] &&
      summary.missingLeanDecls.any (fun item => item.label == forward && item.canonical == declaration))
    "The summary must list the resolved axiom once and report the unresolved attachment as missing"

-- A resolved attachment keeps its checked axiom status when its owning source
-- association fails: the source failure is reported, not the axiom hidden.
run_cmd liftTermElabM do
  let forward := Name.mkSimple "summary.forwardAxiom"
  let resolved := Name.mkSimple "summary.resolvedAxiom"
  let declaration := ``declaredLaterAxiom
  let raw := Capture.Raw.ofState (Environment.informalExt.getState (← getEnv))
  let some (_, node) := raw.nodes.find? (·.1 == resolved) | throwError "Missing resolved axiom control"
  let #[association] := node.nativeAssociations | throwError "Expected one resolved axiom attachment"
  let some range := association.reference.range? | throwError "Expected a recorded declaration range"
  -- A stale recorded range fails source preparation, never the native check.
  let stale := { association with reference := { association.reference with
    range? := some { range with charUtf16 := range.charUtf16 + 1 } } }
  let plan := Capture.plan { raw with nodes := raw.nodes.map fun (label, accepted) =>
    (label, if label == resolved then { accepted with nativeAssociations := #[stale] } else accepted) }
  let snapshot ← obtain (Capture.evaluate plan (← obtain (← Capture.observe plan)))
  let failed := (snapshot.nativeRealizationsFor resolved).any fun model => model.declarations.any fun d =>
    d.object.native == declaration.toString && !d.sourceIssues.isEmpty
  ensure (failed && snapshot.sourceDiagnostics.nodes.any fun (label, issue) =>
      label == resolved && issue.code == "source-association-unavailable")
    "The stale attachment must fail its owning source association at this label"
  ensure (snapshot.assessmentFor resolved).hasAxiomLike
    "A failed source association hid the resolved attachment's checked axiom status"
  ensure (!(snapshot.assessmentFor forward).hasAxiomLike)
    "The forward attachment borrowed the resolved attachment's axiom status"

  -- Role disagreement rejects a label's local check while retaining its
  -- required key. An agreeing sibling on the same real Lean axiom must not
  -- lend its accepted check's axiom status to the disagreeing label.
  let siblingAssociation := { association with
    realization := ⟨forward, `lean⟩
    reference := { association.reference with selectionRange? := none } }
  let siblingPlan := Capture.plan { raw with nodes := raw.nodes.map fun (label, accepted) =>
    (label, if label == forward then { accepted with nativeAssociations := #[siblingAssociation] } else accepted) }
  let siblingObs ← obtain (← Capture.observe siblingPlan)
  let disagreeingObs := { siblingObs with
    native := siblingObs.native.map fun entry =>
      if entry.request.name == declaration && entry.request.selectionRange?.isNone then
        { entry with result := entry.result.map fun prepared => { prepared with roles := #[`statement, `proof] } }
      else entry }
  let siblingSnapshot ← obtain (Capture.evaluate siblingPlan disagreeingObs)
  ensure (siblingSnapshot.sourceDiagnostics.nodes.any fun (label, issue) =>
      label == forward && issue.code == "native-role-disagreement")
    "Mutated sibling roles must trigger native-role-disagreement on the disagreeing label"
  ensure (siblingSnapshot.assessmentFor resolved).hasAxiomLike
    "Agreeing sibling must keep its accepted axiom status"
  ensure (!(siblingSnapshot.assessmentFor forward).hasAxiomLike)
    "Disagreeing attachment borrowed its agreeing sibling's axiom status"

end Verso.VersoBlueprintTests.BlueprintSummaryStatus
