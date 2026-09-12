/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint

open Lean Verso.Genre Informal

#docs (Manual) docstringPolicyDoc "Docstring attachment policy" :=
:::::::

:::lemma_ "shared_docstring"
:::

:::lemma_ "authored_docstring"
An explicitly authored statement.
:::
:::::::

def checkDocstringAttachments (expected : Nat) : CoreM Unit := do
  let some shared ← Environment.getNode? `shared_docstring | throwError "Missing shared node"
  unless !shared.hasStatementBody && shared.externalRefs.size == expected do
    throwError "A code attachment filled a shared placeholder from its docstring"
  let some authored ← Environment.getNode? `authored_docstring | throwError "Missing authored node"
  unless authored.hasStatementBody && authored.kind == .lemma &&
      (reprStr (authored.statement.map (·.previewBlocks))).contains "An explicitly authored statement." do
    throwError "A code attachment changed authored prose"
