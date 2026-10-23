/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Environment

open Lean Informal Lean.Elab.Command

-- Registration returns the complete accepted node, including earlier payloads
-- and selected evidence, and commits matching fields to the environment.
run_cmd do
  let label := `admission_return
  let some initial ← Environment.contribute label { tags := #["earlier"] }
    | throwError "Initial payload registration was rejected"
  unless initial.tags == #["earlier"] do
    throwError "Initial registration returned the wrong payload"
  let fact : Contributions.Record := {
    id := { moduleName := ← getMainModule, producer := `test, subject := label, site := 1, slot := 0 }
    label
    references := #[{ canonical := `acceptedDecl, written := `acceptedDecl, present := true }]
    priority := some "high"
    source := none }
  let some selected ← Environment.contributeRecord fact { tags := #["selected"] }
    | throwError "Selected evidence registration was rejected"
  unless selected.tags == #["earlier", "selected"] && selected.priority == some "high" &&
      selected.leanDecls.contains `acceptedDecl do
    throwError "Registration did not return the complete assembled node"
  let some updated ← Environment.contribute label { tags := #["later"] }
    | throwError "Later payload registration was rejected"
  unless updated.tags == #["earlier", "selected", "later"] && updated.priority == some "high" &&
      updated.leanDecls.contains `acceptedDecl do
    throwError "Payload registration did not retain selected evidence in its return value"
  let state := Environment.informalExt.getState (← getEnv)
  let some stored := state.data.get? label
    | throwError "Accepted node was not committed"
  unless updated.tags == stored.tags && updated.priority == stored.priority &&
      updated.externalRefs == stored.externalRefs && updated.leanDecls == stored.leanDecls do
    throwError "Returned payload and association fields differ from the committed node"
