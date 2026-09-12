/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Proof
import VersoBlueprintTests.BlueprintImportedContributions.CompetingProof

-- Identical text in separate modules is still two competing proof bodies.
/--
error: Conflicting imported blueprint contributions for label 'key_theorem'
Label key_theorem already has a proof
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.CompetingProof, VersoBlueprintTests.BlueprintImportedContributions.Proof, VersoBlueprintTests.BlueprintImportedContributions.Statement
-/
#guard_msgs in
#eval show Lean.CoreM Unit from Informal.Environment.reportImportedConflicts

/-- info: 1 -/
#guard_msgs in
#eval show Lean.CoreM Nat from return (← Informal.Environment.importedConflicts).size
