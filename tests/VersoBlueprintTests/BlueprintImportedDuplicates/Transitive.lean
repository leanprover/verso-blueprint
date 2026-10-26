/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedDuplicates.Reexport
import VersoBlueprint
import VersoBlueprint.Realizations.Capture

open Lean
open Informal
open Elab Command Term
open Informal.Realizations

namespace Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Transitive

-- The public consumer now captures the imported source batch atomically. Group
-- and author collisions reject the whole capture; no partial blueprint model
-- is exposed from the otherwise readable document.
run_cmd liftTermElabM do
  match ← Capture.capture with
  | .error diagnostics =>
    unless diagnostics.any (fun diagnostic => diagnostic.code == "imported-conflict" &&
        diagnostic.subject == (Name.mkSimple "dup.imported.group").toString) &&
        diagnostics.any (fun diagnostic => diagnostic.code == "imported-conflict" &&
          diagnostic.subject == (Name.mkSimple "dup.imported.author").toString) do
      throwError "Atomic capture rejection omitted the imported group or author conflict: {repr diagnostics}"
  | .ok _ => throwError "Conflicting imported author/group batch produced a Blueprint document"

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let conflicts ← Informal.Environment.importedConflicts
    pure <|
      !conflicts.any (fun conflict => conflict.kind == .node && conflict.label == Name.mkSimple "dup.imported.node") &&
      conflicts.contains { kind := .group, label := Name.mkSimple "dup.imported.group" } &&
      conflicts.contains { kind := .author, label := Name.mkSimple "dup.imported.author" }

end Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Transitive
