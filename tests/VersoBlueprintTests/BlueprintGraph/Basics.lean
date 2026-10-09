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
    let admittedStatus ← ConstantInfo.blueprintProvedStatus admitted.name admitted
    let composedStatus ← ConstantInfo.blueprintProvedStatus composed.name composed
    let statementDependency : SorryInfo := { location := .statement, origin := .dependency }
    let proofDirect : SorryInfo := { location := .proof, origin := .direct }
    let proofDependency : SorryInfo := { location := .proof, origin := .dependency }
    return admittedStatus == .containsSorry #[statementDependency, proofDirect] &&
      composedStatus == .containsSorry #[statementDependency, proofDependency]

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
    let status ← ConstantInfo.blueprintProvedStatus info.name info
    let some theoremInfo := (← getEnv).find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusDirectTypeOnly
      | return false
    let typeOnly ← ConstantInfo.blueprintProvedStatus theoremInfo.name theoremInfo
    return status == .containsSorry #[{ location := .statement }] && typeOnly == status

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
    let recordStatus ← ConstantInfo.blueprintProvedStatus record.name record
    let completeStatus ← ConstantInfo.blueprintProvedStatus complete.name complete
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
    let helperStatus ← ConstantInfo.blueprintProvedStatus helper.name helper
    let consumerStatus ← ConstantInfo.blueprintProvedStatus consumer.name consumer
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
    let axiomStatus ← ConstantInfo.blueprintProvedStatus axiomInfo.name axiomInfo
    let defStatus ← ConstantInfo.blueprintProvedStatus defInfo.name defInfo
    pure (
      axiomStatus == .axiomLike &&
      defStatus == .proved
    )

/-- info: true -/
#guard_msgs in
#eval
  let status : Data.ProvedStatus :=
    .containsSorry #[{ location := .statement, refs? := some 2 }, { location := .proof, refs? := some 3 }]
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
    .containsSorry #[{ location := .proof, refs? := some 1 }]
  let inheritedStatus : Data.ProvedStatus :=
    .containsSorry #[{ location := .proof, origin := .dependency }]
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
  let a : ProvedStatus := .containsSorry #[statementDirect, proofInherited, unknown]
  let b : ProvedStatus := .containsSorry #[statementInherited, proofDirect]
  let merged := a.mergeConservative b
  let emptyMerged := (ProvedStatus.containsSorry #[]).mergeConservative
    (.containsSorry #[proofInherited])
  let expected := #[statementDirect, proofInherited, unknown, statementInherited, proofDirect]
  merged == .containsSorry expected &&
    merged.hasTypeGap && merged.hasProofGap && merged.hasUnlocalizedSorry &&
    merged.containsExplicitSorry && merged.dependsOnSorry &&
    merged.sorryRefCounts == (2, 3) &&
    merged.mergeConservative a == merged && merged.mergeConservative b == merged &&
    merged.mergeConservative merged == merged &&
    ((ProvedStatus.containsSorry #[]).mergeConservative (.containsSorry #[])).isIncomplete &&
    emptyMerged.hasUnlocalizedSorry && emptyMerged.dependsOnSorry && emptyMerged.hasProofGap &&
    emptyMerged.blocksStatementCompletion .theorem

/-- info: true -/
#guard_msgs in
#eval
  let unknown : ProvedStatus := .containsSorry #[{ location := .unknown, origin := .unknown }]
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
  let status : ProvedStatus := .containsSorry #[{ location := .proof, refs? := some 2 }]
  let newer : ProvedStatus := .containsSorry #[{ location := .proof, refs? := some 4 }]
  let inherited : ProvedStatus := .containsSorry #[{ location := .proof, origin := .dependency }]
  (status.mergeConservative newer).sorryRefCounts == (0, 4) &&
    ((status.mergeConservative inherited).withDirectRefCounts 0 5).sorryRefCounts == (0, 5)

/-- info: 'Informal.Data.ProvedStatus.mergeConservative_proved_left' depends on axioms: [propext] -/
#guard_msgs in
#print axioms ProvedStatus.mergeConservative_proved_left

/-- info: 'Informal.Data.ProvedStatus.mergeConservative_proved_right' depends on axioms: [propext] -/
#guard_msgs in
#print axioms ProvedStatus.mergeConservative_proved_right

/-- info: 'Informal.Data.ProvedStatus.ofSorryEvidence_known_incomplete' depends on axioms: [propext] -/
#guard_msgs in
#print axioms ProvedStatus.ofSorryEvidence_known_incomplete

end Verso.VersoBlueprintTests.BlueprintGraph.Basics
