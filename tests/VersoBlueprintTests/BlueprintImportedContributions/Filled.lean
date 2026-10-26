/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.FillPlaceholder

/-- info: true -/
#guard_msgs in
#eval show Lean.CoreM Bool from do
  let some node ← Informal.Environment.getNode? `placeholder | return false
  let some statement := node.proseView `verso `statement | return false
  let some proof := node.proseView `verso `proof | return false
  return (← Informal.Environment.importedConflicts).isEmpty &&
    node.kind == .theorem && node.count == 5 && node.hasAssociatedCode &&
    statement.hasBody && proof.hasBody &&
    (node.usesOn `statement).map (·.label) == #[`statement_dep, `local_dep] &&
    (node.usesOn `proof).map (·.label) == #[`proof_dep]
