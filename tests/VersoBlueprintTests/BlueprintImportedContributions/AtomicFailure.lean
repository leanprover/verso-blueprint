/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Statement

open Lean Informal

run_cmd Environment.contribute `key_theorem { priority := some "high" }

-- A rejected contribution must not leak its otherwise valid proof, tags, code,
-- exports, or declaration-index changes.
/-- error: Label key_theorem declares conflicting priorities: existing 'high', new 'low' -/
#guard_msgs in
#eval show CoreM Unit from do
  let before := Environment.informalExt.getState (← getEnv)
  Environment.contribute `key_theorem {
    priority := some "low"
    tags := #["rejected"]
    proofBody := some { stx := .missing, previewBlocks := #[.para #[.text "Rejected proof"]] }
    leanCode := #[.external #[{ canonical := `rejectedDecl, written := `rejectedDecl, present := true }]]
  }
  let after := Environment.informalExt.getState (← getEnv)
  unless reprStr before.data == reprStr after.data &&
      reprStr before.localContributions == reprStr after.localContributions &&
      before.leanNameLabels.toArray == after.leanNameLabels.toArray &&
      before.nodeOrigins.toArray == after.nodeOrigins.toArray &&
      before.nodeModules.toArray == after.nodeModules.toArray do
    throwError "Rejected contribution changed one of the node stores"

-- Repeating equal single-valued metadata is idempotent and does not warn.
#guard_msgs in
run_cmd Environment.contribute `key_theorem { priority := some "high" }
