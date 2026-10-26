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
  let labels ← node.leanDecls.mapM Informal.Environment.labelsForLeanDecl
  let markup := node.sources.filterMap fun source =>
    match source.payload with | .markup markup => some markup | _ => none
  let hasRust := node.sources.any fun source =>
    match source.payload with | .text _ => true | _ => false
  return (← Informal.Environment.importedConflicts).isEmpty &&
    (node.proseView `verso `statement).any (·.hasBody) &&
    (node.proseView `verso `proof).any (·.hasBody) &&
    node.usesOn `statement == #[{ label := `statement_dep }] &&
    node.usesOn `proof == #[{ label := `proof_dep, intent := .technical }] &&
    node.inlineCodes.size == 1 && labels == #[#[`key_theorem]] &&
    hasRust && markup.size == 2 &&
    markup.any (fun source => source.language == .tex && source.slot == "statement") &&
    markup.any (fun source => source.language == .tex && source.slot == "proof")
