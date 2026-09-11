/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Statement

@[blueprint "placeholder" (uses := ["statement_dep"]) (proofUses := ["proof_dep"])]
theorem importedPlaceholder : True := trivial
