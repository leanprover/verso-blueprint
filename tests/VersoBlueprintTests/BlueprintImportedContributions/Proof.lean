/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Statement

open Verso.Genre
open Lean Informal

run_cmd do
  discard <| Informal.Environment.contributeRecord
    { id := {
        moduleName := Name.mkSimple "Proof"
        producer := Name.mkSimple "test.synthetic"
        subject := `key_theorem
        site := 1
        slot := 0 }
      label := `key_theorem
      references := #[]
      priority := some "high"
      source := none } { tags := #["proof"] }

#doc (Manual) "Proof chapter" =>

:::proof "key_theorem" (uses := "proof_dep") (uses_intent := "technical")
A proof declared in a different module from its statement.
:::
