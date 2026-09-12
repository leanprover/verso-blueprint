/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.InlineAttachment
import VersoBlueprintTests.BlueprintImportedContributions.MarkupStatement
import VersoBlueprintTests.BlueprintImportedContributions.MarkupProof
import VersoBlueprintTests.BlueprintImportedContributions.Proof

/-- info: true -/
#guard_msgs in
#eval show Lean.CoreM Bool from do
  let some node ← Informal.Environment.getNode? `key_theorem | return false
  let some statement := node.statement | return false
  let some proof := node.proof | return false
  let labels ← node.leanDecls.mapM Informal.Environment.labelsForLeanDecl
  return (← Informal.Environment.importedConflicts).isEmpty &&
    statement.hasBody && proof.hasBody &&
    statement.deps == #[{ label := `statement_dep }] &&
    proof.deps == #[{ label := `proof_dep, intent := .technical }] &&
    node.literateCodes.size == 1 && labels == #[#[`key_theorem]] &&
    node.rustCode.isSome && node.externalMarkup.toArray.size == 2 &&
    (node.externalMarkup.find? .tex "statement").isSome &&
    (node.externalMarkup.find? .tex "proof").isSome
