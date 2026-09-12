/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.KindAttachment
import VersoBlueprintTests.BlueprintImportedContributions.KindBody

#eval show Lean.CoreM Unit from do
  let some node ← Informal.Environment.getNode? `kind_placeholder
    | throwError "Missing merged node"
  unless node.kind == .lemma && node.kindIsExplicit do
    throwError "An attachment replaced the authored lemma kind"
  unless node.statement.any (·.hasBody) && node.externalRefs.size == 2 do
    throwError "The body or one of the Lean associations was lost"
  unless (← Informal.Environment.importedConflicts).isEmpty do
    throwError "Independent body and dependency additions conflicted"
