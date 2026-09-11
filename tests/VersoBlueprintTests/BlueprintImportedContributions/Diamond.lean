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
