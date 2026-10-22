/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/

import VersoBlueprintTests.BlueprintImportedContributions.CoherenceEqualA
import VersoBlueprintTests.BlueprintImportedContributions.CoherenceEqualB

open Lean Informal

/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let some node ← Environment.getNode? `coherent_equal | return false
  let labelsA ← Environment.labelsForLeanDecl `CoherenceEqualA.declaration
  let labelsB ← Environment.labelsForLeanDecl `CoherenceEqualB.declaration
  return (← Environment.importedConflicts).isEmpty &&
    node.priority == some "high" &&
    node.externalRefs.any (·.canonical == `CoherenceEqualA.declaration) &&
    node.externalRefs.any (·.canonical == `CoherenceEqualB.declaration) &&
    labelsA == #[`coherent_equal] && labelsB == #[`coherent_equal]
