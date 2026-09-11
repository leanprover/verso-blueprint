/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Attachment

-- Attribute updates to an imported body must retain code and inferred edges.
/-- info: true -/
#guard_msgs in
#eval show Lean.CoreM Bool from do
  let some node ← Informal.Environment.getNode? `key_theorem | return false
  let some statement := node.statement | return false
  let some proof := node.proof | return false
  let labels ← Informal.Environment.labelsForLeanDecl `ImportedContributions.attachedTheorem
  return (← Informal.Environment.importedConflicts).isEmpty &&
    node.hasAssociatedCode && statement.hasBody && !proof.hasBody &&
    statement.deps == #[{ label := `statement_dep }] &&
    proof.deps == #[{ label := `proof_dep, origin := .automatic }] &&
    labels == #[`key_theorem]
