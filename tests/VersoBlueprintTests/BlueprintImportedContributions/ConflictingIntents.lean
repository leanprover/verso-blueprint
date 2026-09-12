/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Proof
import VersoBlueprintTests.BlueprintImportedContributions.ManualAttachment

/--
error: Conflicting imported blueprint contributions for label 'key_theorem'
Label key_theorem declares conflicting proof dependency intents for 'proof_dep' (manual): existing 'technical', new 'regular'
Contributing modules: VersoBlueprintTests.BlueprintImportedContributions.ManualAttachment, VersoBlueprintTests.BlueprintImportedContributions.Proof, VersoBlueprintTests.BlueprintImportedContributions.Statement
-/
#guard_msgs in
#eval show Lean.CoreM Unit from Informal.Environment.reportImportedConflicts
