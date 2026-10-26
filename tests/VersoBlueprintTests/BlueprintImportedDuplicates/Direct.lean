/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedDuplicates.ProviderA
import VersoBlueprintTests.BlueprintImportedDuplicates.ProviderB
import VersoBlueprint
import VersoBlueprint.Realizations.Capture

open Lean
open Informal
open Elab Command Term
open Informal.Realizations

namespace Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Direct

-- Conflicting imported author/group metadata rejects the whole public capture;
-- there is no partial document model from which to render a misleading summary.
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

-- Independent bodyless attribute facts are assembled once from imported evidence.
/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let label := Name.mkSimple "dup.imported.node"
    let some node ← Informal.Environment.getNode? label | return false
    let labelsA ← Informal.Environment.labelsForLeanDecl
      `Verso.VersoBlueprintTests.BlueprintImportedDuplicates.ProviderA.importedNodeA
    let labelsB ← Informal.Environment.labelsForLeanDecl
      `Verso.VersoBlueprintTests.BlueprintImportedDuplicates.ProviderB.importedNodeB
    pure <| node.leanDecls.contains
        `Verso.VersoBlueprintTests.BlueprintImportedDuplicates.ProviderA.importedNodeA &&
      node.leanDecls.contains
        `Verso.VersoBlueprintTests.BlueprintImportedDuplicates.ProviderB.importedNodeB &&
      labelsA.contains label && labelsB.contains label

end Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Direct
