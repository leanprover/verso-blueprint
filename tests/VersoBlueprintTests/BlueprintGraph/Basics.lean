/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintGraph.Shared

namespace Verso.VersoBlueprintTests.BlueprintGraph.Basics

open Lean
open Informal
open Informal.Data
open Informal.Environment
open Informal.Graph
open Verso.VersoBlueprintTests.BlueprintGraph.Shared

theorem statusAdmittedHelper : True := by
  sorry

theorem statusConsumer : True := statusAdmittedHelper

def statusSpec : Prop := by sorry

theorem statusAdmitted (_h : statusSpec) : True := by sorry

theorem statusComposed (h : statusSpec) : True := statusAdmitted h

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let env ← getEnv
    let some admitted := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusAdmitted
      | return false
    let some composed := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusComposed
      | return false
    let admittedStatus ← analyzeDeclaration admitted.name
    let composedStatus ← analyzeDeclaration composed.name
    let statementDependency : SorryInfo := { location := .statement, origin := .dependency }
    let proofDirect : SorryInfo := { location := .proof, origin := .direct }
    let proofDependency : SorryInfo := { location := .proof, origin := .dependency }
    return admittedStatus == .incomplete { knownSorry := #[statementDependency, proofDirect] } &&
      composedStatus == .incomplete { knownSorry := #[statementDependency, proofDependency] }

def statusGap : Type := by sorry

structure StatusRecord where
  payload : statusGap

structure StatusCompleteRecord where
  payload : Nat

structure StatusDirectRecord where
  payload : (by sorry : Type)

theorem statusDirectTypeOnly (_h : (by sorry : Prop)) : True := True.intro

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some info := (← getEnv).find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.StatusDirectRecord
      | return false
    let status ← analyzeDeclaration info.name
    let some theoremInfo := (← getEnv).find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusDirectTypeOnly
      | return false
    let typeOnly ← analyzeDeclaration theoremInfo.name
    return status == .incomplete { knownSorry := #[{ location := .statement }] } && typeOnly == status

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let env ← getEnv
    let some record := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.StatusRecord
      | return false
    let some complete := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.StatusCompleteRecord
      | return false
    let recordAxioms ← collectAxioms record.name
    let recordStatus ← analyzeDeclaration record.name
    let completeStatus ← analyzeDeclaration complete.name
    let node : Data.Node := {
      kind := .definition
      literateCodes := #[{ stx := .missing, definedDefs :=
        #[{ name := record.name, provedStatus := recordStatus }] }]
    }
    return recordAxioms.contains ``sorryAx &&
      recordStatus.hasTypeGap && recordStatus.dependsOnSorry &&
      !recordStatus.containsExplicitSorry && !nodeLocalStatementFormalized {} node &&
      statementStatus {} {} `record node != .formalized &&
      proofStatus {} {} `record node == .incomplete &&
      completeStatus.isProved

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let env ← getEnv
    let some helper := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusAdmittedHelper
      | return false
    let some consumer := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusConsumer
      | return false
    let helperStatus ← analyzeDeclaration helper.name
    let consumerStatus ← analyzeDeclaration consumer.name
    let some axiomInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_axiom_decl
      | return false
    let axiomFootprint ← collectAxioms axiomInfo.name
    let accessCases :=
      (match ConstantInfo.blueprintBodyAccess consumer.name consumer #[] with
        | .available _ => true
        | _ => false) &&
      (match ConstantInfo.blueprintBodyAccess axiomInfo.name axiomInfo axiomFootprint with
        | .absent => true
        | _ => false) &&
      (match ConstantInfo.blueprintBodyAccess axiomInfo.name axiomInfo #[] with
        | .unavailable => true
        | _ => false)
    let node : Data.Node := {
      kind := .theorem
      literateCodes := #[{ stx := .missing, definedTheorems :=
        #[{ name := consumer.name, provedStatus := consumerStatus }] }]
    }
    return accessCases && helperStatus.containsExplicitSorry &&
      consumerStatus.dependsOnSorry &&
      !consumerStatus.containsExplicitSorry &&
      consumerStatus.sorryRefCounts == (0, 0) &&
      !nodeLocalProofFormalized {} node

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let env ← getEnv
    let some axiomInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_axiom_decl
      | return false
    let some defInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_def_decl
      | return false
    let axiomStatus ← analyzeDeclaration axiomInfo.name
    let defStatus ← analyzeDeclaration defInfo.name
    pure (
      axiomStatus == .axiomLike &&
      defStatus == .proved
    )

/-- info: true -/
#guard_msgs in
#eval
  let status : Data.ProvedStatus :=
    .incomplete { knownSorry := #[{ location := .statement, refs? := some 2 }, { location := .proof, refs? := some 3 }] }
  Data.NodeKind.definition.isTheoremLike = false &&
  Data.NodeKind.proposition.isTheoremLike &&
  Data.NodeKind.theorem.isTheoremLike &&
  status.sorryLocationText = "in statement and proof" &&
  status.statusLabel = "contains sorry" &&
  status.sorryRefCounts = (2, 3) &&
  status.mergeConservative .proved == status &&
  Data.ProvedStatus.mergeConservative .proved status == status

/-- info: true -/
#guard_msgs in
#eval
  let sorryStatus : Data.ProvedStatus :=
    .incomplete { knownSorry := #[{ location := .proof, refs? := some 1 }] }
  let inheritedStatus : Data.ProvedStatus :=
    .incomplete { knownSorry := #[{ location := .proof, origin := .dependency }] }
  let sorryView := sorryStatus.presentation
  let inheritedView := inheritedStatus.presentation
  let missingView := Data.ProvedStatus.proved.presentation (present := false)
  let axiomView := Data.ProvedStatus.axiomLike.presentation
  sorryView.summaryText == "sorry in proof" &&
    inheritedStatus.statusLabel == "depends on sorry" &&
    inheritedView.summaryText == "depends on sorry in proof" &&
    inheritedView.externalHeaderText == "depends on sorry" &&
    sorryView.externalPanelText == "contains sorry in proof" &&
    sorryView.externalHeaderText == "contains sorry" &&
    sorryView.codeDeclClass == "bp_code_decl_status_warning" &&
    sorryView.externalDeclClass == "bp_external_decl_sorry" &&
    sorryView.codeEntryClassSuffix == "warning" &&
    missingView.summaryText == "missing declaration" &&
    missingView.externalHeaderText == "missing" &&
    missingView.codeEntryClassSuffix == "missing" &&
    axiomView.summaryText == "axiom-like (no body)" &&
    axiomView.codeEntryClassSuffix == "axiom" &&
    axiomView.statusMarkSymbol == "⚠"

/-- info: true -/
#guard_msgs in
#eval
  let statementDirect : SorryInfo := { location := .statement, refs? := some 2 }
  let statementInherited : SorryInfo := { location := .statement, origin := .dependency }
  let proofDirect : SorryInfo := { location := .proof, refs? := some 3 }
  let proofInherited : SorryInfo := { location := .proof, origin := .dependency }
  let unknown : SorryInfo := { location := .unknown, origin := .unknown }
  let a : ProvedStatus := .incomplete { knownSorry := #[statementDirect, proofInherited, unknown] }
  let b : ProvedStatus := .incomplete { knownSorry := #[statementInherited, proofDirect] }
  let merged := a.mergeConservative b
  let emptyMerged := (ProvedStatus.incomplete { knownSorry := #[] }).mergeConservative
    (.incomplete { knownSorry := #[proofInherited] })
  let expected := #[statementDirect, proofInherited, unknown, statementInherited, proofDirect]
  merged == .incomplete { knownSorry := expected } &&
    merged.hasTypeGap && merged.hasProofGap && merged.hasUnlocalizedSorry &&
    merged.containsExplicitSorry && merged.dependsOnSorry &&
    merged.sorryRefCounts == (2, 3) &&
    merged.mergeConservative a == merged && merged.mergeConservative b == merged &&
    merged.mergeConservative merged == merged &&
    ((ProvedStatus.incomplete { knownSorry := #[] }).mergeConservative (.incomplete { knownSorry := #[] })).isIncomplete &&
    emptyMerged.hasUnverifiedCoverage && emptyMerged.dependsOnSorry && emptyMerged.hasProofGap &&
    emptyMerged.blocksStatementCompletion .theorem

/-- info: true -/
#guard_msgs in
#eval
  let unknown : ProvedStatus := .incomplete { knownSorry := #[{ location := .unknown, origin := .unknown }] }
  let node : Node := { kind := .theorem, externalRefs :=
    #[{ (ExternalRef.ofName `hidden) with provedStatus := unknown }] }
  let health := nodeCodeHealth {} node
  unknown.isIncomplete && !unknown.hasTypeGap && !unknown.hasProofGap &&
    !unknown.containsExplicitSorry && !unknown.dependsOnSorry &&
    unknown.statusLabel == "sorry detected" &&
    unknown.presentation.summaryText == "sorry detected location unknown" &&
    unknown.withDirectRefCounts 2 3 == unknown &&
    unknown.blocksStatementCompletion .theorem && unknown.blocksProofCompletion &&
    health.statementAxisCount == 0 && health.proofAxisCount == 0 && health.anyGapCount == 1 &&
    !health.localProofFormalized && !health.localStatementFormalized &&
    (match fromJson? (α := ProvedStatus) (toJson unknown) with
     | .ok roundTrip => roundTrip == unknown
     | .error _ => false)

/-- info: true -/
#guard_msgs in
#eval
  let rejects (location origin : String) :=
    match fromJson? (α := SorryInfo) (Json.mkObj [
      ("location", Json.str location), ("origin", Json.str origin)]) with
    | .error _ => true
    | .ok _ => false
  rejects "invalid" "unknown" && rejects "unknown" "invalid"

/-- info: true -/
#guard_msgs in
#eval
  let status : ProvedStatus := .incomplete { knownSorry := #[{ location := .proof, refs? := some 2 }] }
  let newer : ProvedStatus := .incomplete { knownSorry := #[{ location := .proof, refs? := some 4 }] }
  let inherited : ProvedStatus := .incomplete { knownSorry := #[{ location := .proof, origin := .dependency }] }
  (status.mergeConservative newer).sorryRefCounts == (0, 4) &&
    ((status.mergeConservative inherited).withDirectRefCounts 0 5).sorryRefCounts == (0, 5)

-- A fast positive witness is a partial inspection, never an absence certificate.
-- A clean search still closes its full graph before it can complete.
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let blocked := `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusConsumer
    let (early, _) ← (inspectSorryDependencies #[blocked] (stopAtBlocker := true)).run {}
    let (full, _) ← (inspectSorryDependencies #[blocked]).run {}
    let clean := `Verso.VersoBlueprintTests.BlueprintGraph.Basics.StatusCompleteRecord
    let (verified, _) ← (inspectSorryDependencies #[clean] (stopAtBlocker := true)).run {}
    return early.hasSorry && !early.isComplete && full.hasSorry && !full.isComplete &&
      early.declarations.size < full.declarations.size && verified.isComplete

-- Batch certification covers each root, while mixed batches keep distinct
-- evidence and policy. A blocker in one root must not contaminate a clean root.
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let clean := `Verso.VersoBlueprintTests.BlueprintGraph.Basics.StatusCompleteRecord
    let blocked := `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusConsumer
    let axiomName := `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_axiom_decl
    let cleanResults ← analyzeDeclarations #[clean, ``True.intro]
    let axiomResults ← analyzeDeclarations #[clean, axiomName]
    let mixed ← analyzeDeclarations #[clean, blocked, axiomName, `unknownBatchRoot]
    return cleanResults.size == 2 && cleanResults.all (·.isProved) &&
      axiomResults.size == 2 && axiomResults[0]!.isProved && axiomResults[1]!.isAxiomLike &&
      mixed.size == 4 && mixed[0]!.isProved && mixed[1]!.dependsOnSorry &&
      mixed[2]!.isAxiomLike && mixed[3]!.isUnverified &&
      (← analyzeDeclarations #[]).isEmpty

-- Closed cycles are legitimate. Open boundaries, hidden bodies, missing roots,
-- and holes anywhere in a cycle must all prevent production completion.
/-- info: true -/
#guard_msgs in
#eval
  let a : InspectedDeclaration := { dependencies := #[`b] }
  let b : InspectedDeclaration := { dependencies := #[`a] }
  let closed : InspectedDeclarations := ({} : InspectedDeclarations).insert `a a |>.insert `b b
  let inspect (graph : InspectedDeclarations) : SorryInspection := { roots := #[`a], declarations := graph }
  let hole := closed.insert `b { b with dependencies := #[`a, ``sorryAx] }
    |>.insert ``sorryAx {}
  let hidden := closed.insert `b { b with unverified := some .bodyUnavailable }
  let unchecked := closed.insert `b { b with unverified := some .uncheckedExpression }
  let openGraph := closed.erase `b
  let absent : SorryInspection := { roots := #[`absent], declarations := closed }
  (ProvedStatus.ofInspection (inspect closed) {}).isProved &&
    #[inspect hole, inspect hidden, inspect unchecked, inspect openGraph, absent].all
      (fun inspection => !(ProvedStatus.ofInspection inspection {}).isProved) &&
    !(ProvedStatus.ofInspection (inspect closed) { knownSorry := #[{ location := .unknown }] }).isProved &&
    !(ProvedStatus.ofInspection (inspect closed) { unverified := #[{}] }).isProved

/-- info: true -/
#guard_msgs in
#eval
  let defaultStatus : ProvedStatus := default
  let empty : ProvedStatus := .incomplete {}
  let inherited : ProvedStatus := .incomplete { knownSorry := #[{ location := .proof, origin := .dependency }] }
  let mixed := empty.mergeConservative inherited
  let emptyCode : Node := { kind := .theorem, literateCodes := #[{ stx := .missing }] }
  defaultStatus.isUnverified && !defaultStatus.hasKnownSorry &&
    empty.sorryRefCounts == (0, 0) && !empty.isProved &&
    empty.blocksStatementCompletion .theorem && empty.blocksProofCompletion &&
    mixed.hasKnownSorry && mixed.hasUnverifiedCoverage &&
    mixed.mergeConservative .proved == mixed &&
    !Graph.nodeLocalStatementFormalized {} emptyCode && !Graph.nodeLocalProofFormalized {} emptyCode

/-- info: 'Informal.Data.ProvedStatus.mergeConservative_proved_left' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms ProvedStatus.mergeConservative_proved_left

/-- info: 'Informal.Data.ProvedStatus.mergeConservative_proved_right' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms ProvedStatus.mergeConservative_proved_right

/-- info: 'Informal.Data.ProvedStatus.ofInspection_not_reachable' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms ProvedStatus.ofInspection_not_reachable

end Verso.VersoBlueprintTests.BlueprintGraph.Basics
