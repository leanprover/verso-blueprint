/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.Statement

run_cmd Informal.Environment.contribute `key_theorem {
  proofUses := #[{ label := `proof_dep, origin := .automatic, intent := .regular }]
}
