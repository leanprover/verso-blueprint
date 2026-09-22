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
  return state.authoredOriginConflicts.contains `coherent_origin_conflict &&
    (← Environment.getNode? `coherent_origin_conflict).isNone &&
    conflicts.any (fun conflict => conflict.label == `coherent_origin_conflict &&
      conflict.reasons == #["Label coherent_origin_conflict was independently introduced by authored contributions"])
