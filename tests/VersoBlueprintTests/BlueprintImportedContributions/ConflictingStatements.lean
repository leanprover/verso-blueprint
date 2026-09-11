/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.IndependentA
import VersoBlueprintTests.BlueprintImportedContributions.IndependentB

/-- error: Duplicate imported blueprint node label 'independent_label' -/
#guard_msgs in
#eval show Lean.CoreM Unit from Informal.Environment.reportImportedConflicts
