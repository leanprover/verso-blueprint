/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.LiterateKind
import VersoBlueprintTests.BlueprintImportedContributions.KindBody

#eval show Lean.CoreM Unit from do
  let some node ← Informal.Environment.getNode? `kind_placeholder | throwError "Missing placeholder"
  unless node.kind == .lemma && node.kindIsExplicit && node.literateCodes.size == 1 do
    throwError "Merged literate theorem changed the explicitly authored kind"
