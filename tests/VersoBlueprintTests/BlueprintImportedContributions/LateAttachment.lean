/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Doc

@[blueprint "key_theorem" (proofUses := ["statement_dep"])]
theorem lateAttachment : True := trivial

run_cmd Informal.Environment.contribute `key_theorem {
  effort := some "small"
  tags := #["late"]
}
