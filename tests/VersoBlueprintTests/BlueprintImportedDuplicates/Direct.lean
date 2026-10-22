/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedDuplicates.ProviderA
import VersoBlueprintTests.BlueprintImportedDuplicates.ProviderB
import VersoBlueprint
import VersoManual

open Lean
open Informal
open Verso
open Verso.Genre.Manual

set_option doc.verso true

namespace Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Direct

/--
error: Duplicate imported blueprint group label '«dup.imported.group»'
---
error: Duplicate imported blueprint author id '«dup.imported.author»'
-/
#guard_msgs in
#docs (Genre.Manual) directImportedDuplicateDoc "Direct Imported Duplicates" :=
:::::::
{blueprint_node "dup.imported.node"}
:::::::

def directImportedDuplicateDocBlueprint : Informal.BlueprintDocument := .capture directImportedDuplicateDoc.toPart

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
