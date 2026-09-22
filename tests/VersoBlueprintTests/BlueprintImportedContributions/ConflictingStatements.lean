/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.IndependentA
import VersoBlueprintTests.BlueprintImportedContributions.IndependentB

/--
error: Conflicting imported blueprint contributions for label 'independent_label'
Label independent_label was independently introduced by authored contributions
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.IndependentA, VersoBlueprintTests.BlueprintImportedContributions.IndependentB
-/
#guard_msgs in
#eval show Lean.CoreM Unit from Informal.Environment.reportImportedConflicts
