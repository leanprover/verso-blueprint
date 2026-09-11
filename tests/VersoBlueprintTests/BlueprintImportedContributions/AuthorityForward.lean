/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.AuthorityManual
import VersoBlueprintTests.BlueprintImportedContributions.AuthorityRegular
import VersoBlueprintTests.BlueprintImportedContributions.AuthorityTechnical

#eval show Lean.CoreM Unit from do
  let conflicts ← Informal.Environment.importedConflicts
  unless conflicts.any (fun conflict => conflict.label == `key_theorem &&
      conflict.reasons.any (·.contains "conflicting proof dependency intents")) do
    throwError "Import order hid a conflict between automatic dependency declarations"
