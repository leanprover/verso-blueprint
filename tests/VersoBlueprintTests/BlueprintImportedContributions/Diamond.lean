/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.CombinedReverse
import VersoBlueprintTests.BlueprintImportedContributions.Observe
import VersoBlueprintTests.BlueprintImportedContributions.Combined

-- Re-exports and the shared statement/proof imports must not duplicate entries.
/-- info: true -/
#guard_msgs in
#eval ImportedContributions.completeNode true

-- Provenance belongs to the registered node, and re-exports add no contributors.
#eval show Lean.CoreM Unit from do
  let state := Informal.Environment.informalExt.getState (← Lean.getEnv)
  let some node := state.data.get? `key_theorem | throwError "Missing registered node"
  unless node.origin == `VersoBlueprintTests.BlueprintImportedContributions.Statement &&
      node.modules.size == 3 &&
      node.modules.contains `VersoBlueprintTests.BlueprintImportedContributions.Statement &&
      node.modules.contains `VersoBlueprintTests.BlueprintImportedContributions.Proof &&
      node.modules.contains `VersoBlueprintTests.BlueprintImportedContributions.Attachment do
    throwError "Node provenance changed across diamond imports"
