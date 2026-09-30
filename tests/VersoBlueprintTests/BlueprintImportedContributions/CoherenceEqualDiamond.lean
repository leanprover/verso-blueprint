/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/

import VersoBlueprintTests.BlueprintImportedContributions.CoherenceEqual
import VersoBlueprintTests.BlueprintImportedContributions.CoherenceEqualForward

open Lean Informal

-- The forward and reverse paths replay the same two identified facts.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let state := Environment.informalExt.getState (← getEnv)
  let some node ← Environment.getNode? `coherent_equal | return false
  return (← Environment.importedConflicts).isEmpty &&
    node.priority == some "high" && node.externalRefs.size == 2 &&
    (state.factRecords.filter fun record => record.label == `coherent_equal).length == 2 &&
    (state.nodeContributors.getD `coherent_equal #[]).size == 2
