/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprintTests.SorryImport.Consumer

open Lean Informal Informal.Data

namespace Verso.VersoBlueprintTests.SorryImport.Classification

private unsafe def withProvider (importAll : Bool) (action : CoreM Bool) : CoreM Bool := do
  liftM enableInitializersExecution
  -- Dynamic imports must use the same cache-in-place artifact map as normal
  -- elaboration. Lake's public setup interface resolves that map without
  -- materializing canonical oleans or changing the selected import visibility.
  let output ← liftM <| IO.Process.output {
    cmd := "./scripts/lean-low-priority"
    args := #["lake", "-q", "query", "-J", "+VersoBlueprintTests.SorryImport.Classification:setup"]
  }
  unless output.exitCode == 0 do throwError "Provider setup failed: {output.stderr}"
  let setup : ModuleSetup ← ofExcept <| Json.parse output.stdout >>= fromJson?
  let env ← liftM <| importModules
    #[{ module := `VersoBlueprintTests.SorryImport.Provider, importAll }]
    {} (loadExts := true) (level := .exported) (arts := setup.importArts)
  withEnv env action

private def statusOf (name : Name) : CoreM ProvedStatus := do
  analyzeDeclaration name

/-- Evidence attribution is independent of coverage; completion controls below
check verification explicitly for each visibility boundary. -/
private def checkSorryEvidence (cases : Array (Name × Array SorryInfo)) : CoreM Bool := do
  for (name, expected) in cases do
    let actual ← statusOf name
    unless actual.sorryEvidence == expected do
      throwError "Unexpected evidence for {name}: {repr actual}; expected {repr expected}"
  return true

private def statementDependency : SorryInfo := { location := .statement, origin := .dependency }
private def proofDependency : SorryInfo := { location := .proof, origin := .dependency }
private def proofDirect : SorryInfo := { location := .proof }
private def proofUnknown : SorryInfo := { location := .proof, origin := .unknown }
private def unlocalized : SorryInfo := { location := .unknown, origin := .unknown }

-- Blueprint itself is still a legacy module. Run its actual classifier in an
-- environment imported at the ordinary module-system visibility level, rather
-- than accidentally testing the legacy import-all view of Provider.
/-- info: true -/
#guard_msgs in
#eval
  withProvider false do
    let status ← statusOf `sorryImportTypeOnly
    return status.sorryEvidence == #[statementDependency, unlocalized] && status.hasUnverifiedCoverage &&
      status.isIncomplete && status.hasTypeGap && !status.hasProofGap &&
      !status.containsExplicitSorry && status.hasUnlocalizedSorry

-- Hidden bodies prove no local source hole. A clean type can isolate the gap
-- to the proof, but the origin of that gap remains unknown.
/-- info: true -/
#guard_msgs in
#eval
  withProvider false <| checkSorryEvidence #[
    (`sorryImportComplete, #[]),
    (`sorryImportCompleteDef, #[]),
    (`sorryImportAdmitted, #[proofUnknown]),
    (`sorryImportNumber, #[proofUnknown]),
    (`sorryImportComposed, #[proofUnknown]),
    (`sorryImportComposedDef, #[proofUnknown]),
    (`sorryImportBoth, #[statementDependency, unlocalized]),
    (`sorryImportHypothesis, #[statementDependency, unlocalized]),
    (`sorryImportAxiom, #[]),
    (`sorryImportOpaqueComplete, #[]),
    (`sorryImportOpaqueAdmitted, #[proofUnknown]),
    (`sorryImportExposed, #[proofDependency]),
    (`sorryImportExposedComplete, #[]),
    (`sorryImportStandardAxioms, #[]),
    (`SorryImportRecord, #[statementDependency]),
    (`SorryImportRecord.mk, #[statementDependency]),
    (`sorryImportRecordHypothesis, #[statementDependency]),
    (`SorryImportNestedRecord, #[statementDependency]),
    (`sorryImportNestedHypothesis, #[statementDependency]),
    (`SorryImportNestedCompleteRecord, #[]),
    (`sorryImportNestedCompleteHypothesis, #[]),
    (`SorryImportCompleteRecord, #[]),
    (`SorryImportCompleteRecord.mk, #[]),
    (``Quot, #[])
  ]

-- Import-all exposes evidence that an ordinary import cannot justify. In
-- particular, the complete type-only proof stays free of proof-side evidence.
/-- info: true -/
#guard_msgs in
#eval
  withProvider true <| checkSorryEvidence #[
    (`sorryImportComplete, #[]),
    (`sorryImportCompleteDef, #[]),
    (`sorryImportAdmitted, #[proofDirect]),
    (`sorryImportNumber, #[proofDirect]),
    (`sorryImportComposed, #[proofDependency]),
    (`sorryImportComposedDef, #[proofDependency]),
    (`sorryImportTypeOnly, #[statementDependency]),
    (`sorryImportHypothesis, #[statementDependency]),
    (`sorryImportBoth, #[statementDependency, proofDirect, proofDependency]),
    (`sorryImportAxiom, #[]),
    (`sorryImportOpaqueComplete, #[]),
    (`sorryImportOpaqueAdmitted, #[proofDirect]),
    (`SorryImportRecord, #[statementDependency]),
    (`sorryImportRecordHypothesis, #[statementDependency]),
    (`sorryImportNestedHypothesis, #[statementDependency]),
    (`SorryImportNestedCompleteRecord, #[]),
    (`sorryImportNestedCompleteHypothesis, #[]),
    (`SorryImportCompleteRecord, #[])
  ]

-- Cached absence cannot authorize completion of hidden declarations, whether
-- the hidden proof is actually complete or hides an omitted constructor hole.
/-- info: true -/
#guard_msgs in
#eval
  withProvider false do
    for name in #[`sorryImportComplete, `sorryImportCompleteDef,
        `sorryImportOpaqueComplete, `sorryImportNestedCompleteHypothesis,
        `sorryImportHiddenHelper] do
      let status ← statusOf name
      unless status.isIncomplete && status.hasUnverifiedCoverage &&
          !status.containsExplicitSorry do return false
    let helper ← statusOf `sorryImportExposedHiddenHelper
    unless (← statusOf `sorryImportAxiom).isAxiomLike do return false
    for name in #[`sorryImportExposedComplete, `SorryImportCompleteRecord,
        `SorryImportCompleteRecord.mk, `SorryImportNestedCompleteRecord, ``Quot] do
      unless (← statusOf name).isProved do
        throwError "Visible complete control remained unverified: {name}"
    let cached ← collectAxioms `sorryImportHiddenHelper
    let exposedCached ← collectAxioms `sorryImportExposedHiddenHelper
    return cached.isEmpty && exposedCached.isEmpty &&
      !helper.isProved && helper.hasUnverifiedCoverage

-- Batching retains independent evidence, hidden-body coverage, and authored
-- theorem kind when ordinary import visibility presents a public axiom view.
/-- info: true -/
#guard_msgs in
#eval
  withProvider false do
    let names := #[`sorryImportExposedComplete, `sorryImportComplete,
      `sorryImportAdmitted, `sorryImportAxiom]
    let statuses ← analyzeDeclarations names
    let individual ← names.mapM statusOf
    let refs ← externalRefSnapshotsAtCurrentDir {} <| names.map fun name =>
      { (ExternalRef.ofName name) with kind := .theorem }
    return statuses == individual && statuses[0]!.isProved &&
      statuses[1]!.isUnverified && statuses[2]!.hasKnownSorry &&
      statuses[3]!.isAxiomLike && refs.map (·.provedStatus) == statuses &&
      refs[1]!.kind == .theorem && refs[2]!.kind == .theorem

-- Independently inspecting actual bodies resolves both clean and omitted-hole
-- cases. Import-all must verify complete controls, not merely lack evidence.
/-- info: true -/
#guard_msgs in
#eval
  withProvider true do
    unless (← statusOf `sorryImportAxiom).isAxiomLike do return false
    let batch ← analyzeDeclarations #[`sorryImportComplete, `sorryImportCompleteDef,
      `sorryImportAxiom]
    unless batch.size == 3 && batch[0]!.isProved && batch[1]!.isProved &&
        batch[2]!.isAxiomLike do return false
    for name in #[`sorryImportComplete, `sorryImportCompleteDef,
        `sorryImportOpaqueComplete, `sorryImportStandardAxioms,
        `SorryImportCompleteRecord, `SorryImportNestedCompleteRecord,
        `sorryImportNestedCompleteHypothesis] do
      unless (← statusOf name).isProved do
        throwError "Complete control remained unverified: {name}"
    let helper ← statusOf `sorryImportHiddenHelper
    let exposed ← statusOf `sorryImportExposedHiddenHelper
    return helper.dependsOnSorry && helper.hasProofGap && !helper.isProved &&
      exposed.dependsOnSorry && !exposed.isProved

/-- info: true -/
#guard_msgs in
#eval
  withProvider false do
    let ref ← externalRefSnapshotAtCurrentDir {} {
      (ExternalRef.ofName `sorryImportTypeOnly) with kind := .theorem }
    let proofRef ← externalRefSnapshotAtCurrentDir {} {
      (ExternalRef.ofName `sorryImportComposed) with kind := .theorem }
    let completeRef ← externalRefSnapshotAtCurrentDir {} {
      (ExternalRef.ofName `sorryImportComplete) with kind := .theorem }
    let missingRef ← externalRefSnapshotAtCurrentDir {} (ExternalRef.ofName `unknownSorryImport)
    let nestedRef ← externalRefSnapshotAtCurrentDir {} {
      (ExternalRef.ofName `sorryImportNestedHypothesis) with kind := .theorem }
    let node : Node := { kind := .theorem, externalRefs := #[ref] }
    let health := Graph.nodeCodeHealth {} node
    let proofNode : Node := { kind := .theorem, externalRefs := #[proofRef] }
    let completeNode : Node := { kind := .theorem, externalRefs := #[completeRef] }
    let renderHasUnknown := match ref.render with
      | .ok html => html.html.contains "depends on sorry"
      | _ => false
    let proofRenderHasUnknown := match proofRef.render with
      | .ok html => html.html.contains "sorry detected" &&
          !html.html.contains "depends on sorry" && !html.html.contains "contains sorry"
      | _ => false
    return ref.present && renderHasUnknown && proofRenderHasUnknown &&
      ref.provedStatus.sorryEvidence == #[statementDependency, unlocalized] && ref.provedStatus.hasUnverifiedCoverage &&
      health.provedStatus == ref.provedStatus && health.hasStatementGaps && health.anyGapCount == 1 &&
      !Graph.nodeLocalProofFormalized {} node &&
      Graph.proofStatus {} {} `typeOnly node == .incomplete &&
      Graph.nodeLocalStatementFormalized {} proofNode && !Graph.nodeLocalProofFormalized {} proofNode &&
      !Graph.nodeLocalProofFormalized {} completeNode && completeRef.provedStatus.isUnverified &&
      nestedRef.provedStatus.sorryEvidence == #[statementDependency] && nestedRef.provedStatus.hasUnverifiedCoverage &&
      !missingRef.present && missingRef.provedStatus == .missing

end Verso.VersoBlueprintTests.SorryImport.Classification
