/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Statement

open Lean

-- A sibling extension that supplies metadata without another proof body.
run_cmd do
  discard <| Informal.Environment.contributeRecord
    { id := {
        moduleName := Name.mkSimple "Metadata"
        producer := Name.mkSimple "test.synthetic"
        subject := `key_theorem
        site := 1
        slot := 0 }
      label := `key_theorem
      references := #[]
      priority := some "low"
      source := none } {}
