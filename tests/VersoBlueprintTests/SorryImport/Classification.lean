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
  let some info := (← getEnv).find? name | throwError "missing declaration {name}"
  ConstantInfo.blueprintProvedStatus name info

private def checkStatuses (cases : Array (Name × ProvedStatus)) : CoreM Bool := do
  for (name, expected) in cases do
    let actual ← statusOf name
    unless actual == expected do
      throwError "Unexpected status for {name}: {repr actual}; expected {repr expected}"
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
    return status == .containsSorry #[statementDependency, unlocalized] &&
      status.isIncomplete && status.hasTypeGap && !status.hasProofGap &&
      !status.containsExplicitSorry && status.hasUnlocalizedSorry

-- Hidden bodies prove no local source hole. A clean type can isolate the gap
-- to the proof, but the origin of that gap remains unknown.
/-- info: true -/
#guard_msgs in
#eval
  withProvider false <| checkStatuses #[
    (`sorryImportComplete, .proved),
    (`sorryImportCompleteDef, .proved),
    (`sorryImportAdmitted, .containsSorry #[proofUnknown]),
    (`sorryImportNumber, .containsSorry #[proofUnknown]),
    (`sorryImportComposed, .containsSorry #[proofUnknown]),
    (`sorryImportComposedDef, .containsSorry #[proofUnknown]),
    (`sorryImportBoth, .containsSorry #[statementDependency, unlocalized]),
    (`sorryImportHypothesis, .containsSorry #[statementDependency, unlocalized]),
    (`sorryImportAxiom, .axiomLike),
    (`sorryImportOpaqueComplete, .proved),
    (`sorryImportOpaqueAdmitted, .containsSorry #[proofUnknown]),
    (`sorryImportExposed, .containsSorry #[proofDependency]),
    (`sorryImportExposedComplete, .proved),
    (`sorryImportStandardAxioms, .proved),
    (`SorryImportRecord, .containsSorry #[statementDependency]),
    (`SorryImportRecord.mk, .containsSorry #[statementDependency]),
    (`sorryImportRecordHypothesis, .containsSorry #[statementDependency, unlocalized]),
    (`SorryImportNestedRecord, .containsSorry #[statementDependency]),
    (`sorryImportNestedHypothesis, .containsSorry #[statementDependency, unlocalized]),
    (`SorryImportNestedCompleteRecord, .proved),
    (`sorryImportNestedCompleteHypothesis, .proved),
    (`SorryImportCompleteRecord, .proved),
    (`SorryImportCompleteRecord.mk, .proved),
    (``Quot, .proved)
  ]

-- Import-all exposes evidence that an ordinary import cannot justify. In
-- particular, the complete type-only proof stays free of proof-side evidence.
/-- info: true -/
#guard_msgs in
#eval
  withProvider true <| checkStatuses #[
    (`sorryImportComplete, .proved),
    (`sorryImportCompleteDef, .proved),
    (`sorryImportAdmitted, .containsSorry #[proofDirect]),
    (`sorryImportNumber, .containsSorry #[proofDirect]),
    (`sorryImportComposed, .containsSorry #[proofDependency]),
    (`sorryImportComposedDef, .containsSorry #[proofDependency]),
    (`sorryImportTypeOnly, .containsSorry #[statementDependency]),
    (`sorryImportHypothesis, .containsSorry #[statementDependency]),
    (`sorryImportBoth, .containsSorry #[statementDependency, proofDirect, proofDependency]),
    (`sorryImportAxiom, .axiomLike),
    (`sorryImportOpaqueComplete, .proved),
    (`sorryImportOpaqueAdmitted, .containsSorry #[proofDirect]),
    (`SorryImportRecord, .containsSorry #[statementDependency]),
    (`sorryImportRecordHypothesis, .containsSorry #[statementDependency]),
    (`sorryImportNestedHypothesis, .containsSorry #[statementDependency]),
    (`SorryImportNestedCompleteRecord, .proved),
    (`sorryImportNestedCompleteHypothesis, .proved),
    (`SorryImportCompleteRecord, .proved)
  ]

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
      ref.provedStatus == .containsSorry #[statementDependency, unlocalized] &&
      health.statementAxisCount == 1 && health.proofAxisCount == 0 && health.anyGapCount == 1 &&
      !Graph.nodeLocalProofFormalized {} node &&
      Graph.proofStatus {} {} `typeOnly node == .incomplete &&
      Graph.nodeLocalStatementFormalized {} proofNode && !Graph.nodeLocalProofFormalized {} proofNode &&
      Graph.nodeLocalProofFormalized {} completeNode &&
      nestedRef.provedStatus == .containsSorry #[statementDependency, unlocalized] &&
      !missingRef.present && missingRef.provedStatus == .missing

end Verso.VersoBlueprintTests.SorryImport.Classification
