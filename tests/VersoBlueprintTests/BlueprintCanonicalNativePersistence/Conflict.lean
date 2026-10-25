/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalNativePersistence.Malformed
import VersoBlueprintTests.BlueprintCanonicalNativePersistence.Harness

open Lean Informal

run_cmd Lean.Elab.Command.liftCoreM do
  let env ← getEnv
  try
    let label := Name.mkSimple "canonical.native"
    let state := Environment.informalExt.getState env
    let records := state.factRecords.filter (·.label == label)
    let [first, second] := records | throwError "Expected both raw collision variants"
    unless first.id == second.id && first.nativeAssociations != second.nativeAssociations &&
        state.importedConflicts.any (·.label == label) && !state.data.contains label &&
        !(state.leanNameLabels.getD `CanonicalNativePersistence.original #[]).contains label do
      throwError "Conflicting imported native destinations were collapsed or admitted"
    unless state.localFactRecords.isEmpty &&
        state.pendingNodes.all (fun _ pending => pending.localRegistrations.isEmpty) do
      throwError "Malformed imported evidence must remain raw, not become a local export"
    -- Exercise later attachment without conflating diagnostic reporting state
    -- with semantic rollback. Restore this whole test environment on every exit.
    Environment.modify fun state => { state with importedConflictsReported := true }
    let reference := first.nativeAssociations[0]!.reference
    CanonicalNativePersistence.rejected "native destinations" <| Environment.contributeRecord {
      id := ⟨← getMainModule, `test.validLater, label, 1, 0⟩, label
      nativeAssociations := #[{
        realization := ⟨label, `lean⟩, context := ⟨`lean, `blueprintFixtures⟩
        facets := #[`statement], reference }]
      priority := none, source := none } { tags := #["must not restore rejected concept"] }
  finally
    setEnv env
