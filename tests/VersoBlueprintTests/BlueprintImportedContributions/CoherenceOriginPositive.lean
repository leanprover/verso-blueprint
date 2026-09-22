/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/

import VersoBlueprintTests.BlueprintImportedContributions.CoherenceOriginFact
import VersoBlueprintTests.BlueprintImportedContributions.CoherenceOriginAuthor

open Lean Informal

-- A fact-only producer cannot become the origin of a later authored placeholder.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let state := Environment.informalExt.getState (← getEnv)
  let some registered := state.data.get? `coherent_origin | return false
  let node := registered.toNode
  return state.authoredOrigins.get? `coherent_origin ==
      some `VersoBlueprintTests.BlueprintImportedContributions.CoherenceOriginAuthor &&
    registered.origin == `VersoBlueprintTests.BlueprintImportedContributions.CoherenceOriginAuthor &&
    node.externalRefs.map (·.canonical) == #[`CoherenceOriginFact.declaration]
