/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.DocstringA
import VersoBlueprintTests.BlueprintImportedContributions.DocstringB

#eval checkDocstringAttachments 2

/-- A sequential attachment follows the same policy as sibling imports. -/
@[blueprint "shared_docstring"] theorem docstringSequentialAttachment : True := trivial

#eval checkDocstringAttachments 3

/-- The introducing declaration owns this initial informal statement. -/
@[blueprint "owned_docstring"] theorem docstringOwner : True := trivial

#eval show Lean.CoreM Unit from do
  let some node ← Informal.Environment.getNode? `owned_docstring
    | throwError "Missing declaration-owned node"
  unless node.hasStatementBody do
    throwError "The introducing declaration lost its docstring statement"
  let state := Informal.Environment.informalExt.getState (← Lean.getEnv)
  unless state.nextCount == state.data.foldl (fun next _ node => max next (node.count + 1)) 1 do
    throwError "The elaboration counter disagrees with accepted imported and local nodes"
