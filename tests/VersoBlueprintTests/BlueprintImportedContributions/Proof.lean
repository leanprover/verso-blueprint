/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Statement

open Verso.Genre
open Informal

run_cmd Informal.Environment.contribute `key_theorem { tags := #["proof"], priority := some "high" }

#doc (Manual) "Proof chapter" =>

:::proof "key_theorem" (uses := "proof_dep") (uses_intent := "technical")
A proof declared in a different module from its statement.
:::
