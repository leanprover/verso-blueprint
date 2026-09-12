/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.MarkupProof
import VersoBlueprintTests.BlueprintImportedContributions.OtherMarkup

/--
error: Conflicting imported blueprint contributions for label 'key_theorem'
Label key_theorem already has associated tex external markup in slot 'proof'
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.MarkupProof, VersoBlueprintTests.BlueprintImportedContributions.OtherMarkup, VersoBlueprintTests.BlueprintImportedContributions.Statement
-/
#guard_msgs in
#eval show Lean.CoreM Unit from Informal.Environment.reportImportedConflicts
