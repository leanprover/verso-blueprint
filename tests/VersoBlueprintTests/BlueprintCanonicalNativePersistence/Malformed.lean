/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalNativePersistence.Owner

/-! Deliberately malformed raw export fixture, bypassing public registration.
It models conflicting producer envelopes from imports, not accepted source or
fabricated native checking. Ordinary producer APIs reject this collision. -/

open Lean Informal

run_cmd Lean.Elab.Command.liftCoreM do
  let label := Name.mkSimple "canonical.native"
  let state := Environment.informalExt.getState (← getEnv)
  let some record := state.factRecords.find? (·.label == label)
    | throwError "Missing real original native source record"
  let variant := { record with nativeAssociations := record.nativeAssociations.map fun association =>
    { association with realization := ⟨label, `differentDestination⟩ } }
  Environment.modify fun state => { state with
    pendingNodes := state.pendingNodes.insert label {
      state.pendingNodes.getD label {} with localRegistrations := #[{}] }
    localFactRecords := [record, variant] }
