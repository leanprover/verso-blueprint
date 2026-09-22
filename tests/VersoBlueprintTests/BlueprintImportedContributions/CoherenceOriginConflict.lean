/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/

import VersoBlueprintTests.BlueprintImportedContributions.CoherenceOriginConflictA
import VersoBlueprintTests.BlueprintImportedContributions.CoherenceOriginConflictB

open Lean Informal

-- Independent placeholders still conflict even though they share fact-only input.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let state := Environment.informalExt.getState (← getEnv)
  let conflicts ← Environment.importedConflicts
  return (state.pendingNodes.getD `coherent_origin_conflict {}).authoredOriginConflict &&
    (← Environment.getNode? `coherent_origin_conflict).isNone &&
    conflicts.any (fun conflict => conflict.label == `coherent_origin_conflict &&
      conflict.reasons == #["Label coherent_origin_conflict was independently introduced by authored contributions"])

-- Report the import diagnostic before taking the transaction snapshot, just as
-- directive elaboration does. That diagnostic must not be the rejection guard.
/--
error: Conflicting imported blueprint contributions for label 'coherent_origin_conflict'
Label coherent_origin_conflict was independently introduced by authored contributions
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.CoherenceOriginConflictA, VersoBlueprintTests.BlueprintImportedContributions.CoherenceOriginConflictB, VersoBlueprintTests.BlueprintImportedContributions.CoherenceOriginFact
-/
#guard_msgs in
run_cmd Environment.reportImportedConflicts

/-- error: Label coherent_origin_conflict was independently introduced by authored contributions -/
#guard_msgs in
run_cmd do
  let before := Environment.informalExt.getState (← getEnv)
  let result ← Environment.contribute `coherent_origin_conflict { tags := #["later"] }
  let after := Environment.informalExt.getState (← getEnv)
  unless result.isNone && reprStr before == reprStr after do
    throwError "Local registration revived rejected imported evidence"
  unless after.data.get? `coherent_origin_conflict |>.isNone do
    throwError "Rejected imported node became visible"
  unless !(after.leanNameLabels.getD `CoherenceOriginFact.declaration #[]).contains
      `coherent_origin_conflict do
    throwError "Rejected imported declaration was indexed"

open Verso.Genre Lean.Elab.Command in
elab "#check_rejected_origin " command:command : command => do
  let before := Environment.informalExt.getState (← getEnv)
  elabCommand command
  let after := Environment.informalExt.getState (← getEnv)
  unless reprStr before == reprStr after do
    throwError "A directive revived rejected imported evidence"

open Verso.Genre

/-- error: Label coherent_origin_conflict was independently introduced by authored contributions -/
#guard_msgs in
#check_rejected_origin
#docs (Manual) rejectedRecovery "Rejected recovery directive" :=
:::::::
:::theorem "coherent_origin_conflict"
A later body cannot resolve the independent authored origins.
:::
:::::::
