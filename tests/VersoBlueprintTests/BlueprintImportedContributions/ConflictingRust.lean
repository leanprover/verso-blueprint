/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.MarkupStatement
import VersoBlueprintTests.BlueprintImportedContributions.OtherRust

/--
error: Conflicting imported blueprint contributions for label 'key_theorem'
Label key_theorem already has associated Rust code
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.MarkupStatement, VersoBlueprintTests.BlueprintImportedContributions.OtherRust, VersoBlueprintTests.BlueprintImportedContributions.Statement
-/
#guard_msgs in
#eval show Lean.CoreM Unit from Informal.Environment.reportImportedConflicts
