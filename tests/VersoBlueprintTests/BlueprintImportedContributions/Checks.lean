/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

open Lean Informal

namespace ImportedContributions

def completeNode (withAttachment : Bool) : CoreM Bool := do
  let state := Environment.informalExt.getState (← getEnv)
  let some node ← Environment.getNode? `key_theorem | return false
  let some statement := node.statement | return false
  let some proof := node.proof | return false
  let labels ← Environment.labelsForLeanDecl `ImportedContributions.attachedTheorem
  return state.importedConflicts.isEmpty && state.pendingNodes.all (fun _ pending => pending.localLegacy.isEmpty) &&
    state.data.size == 3 && node.kind == .theorem && node.count == 3 &&
    statement.hasBody && proof.hasBody &&
    statement.deps == #[{ label := `statement_dep }] &&
    proof.deps == #[{ label := `proof_dep, intent := .technical }] &&
    node.parent == some `split_group && node.owner == some `split_author &&
    node.priority == some "high" && node.tags == #["statement", "proof"] &&
    node.hasAssociatedCode == withAttachment &&
    labels == (if withAttachment then #[`key_theorem] else #[])

end ImportedContributions
