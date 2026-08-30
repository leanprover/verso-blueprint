/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.Block.Store
meta import VersoBlueprint.Informal.Block.Store

namespace VersoBlueprintModuleTests.BlockStore

open Lean
open Informal
open Informal.Data
open Verso.Genre Manual

local macro "mergedBlockContract" : term => do
  let existing : StoredBlockData := {
    kind := .proof
    label := Name.mkSimple "module.store.block"
    count := 3
    tags := #["existing"]
    statementUses := #[{ label := Name.mkSimple "module.store.source" }]
  }
  let incoming : StoredBlockData := {
    kind := .statement .theorem
    label := existing.label
    count := 99
    tags := #["existing", "incoming"]
    statementUses := #[{ label := Name.mkSimple "module.store.source" }]
  }
  return quote (mergeStoredBlockData existing incoming)

/-- info: true -/
#guard_msgs in
#eval
  let merged : StoredBlockData := mergedBlockContract
  let state : TraverseState := TraverseState.initialize default
  let (first, state) := reservePrefixBlockNumber state "2.4"
  let (second, _) := reservePrefixBlockNumber state "2.4"
  (match merged.kind with
    | .statement .theorem => true
    | _ => false) && merged.count == 3 &&
    merged.tags == #["existing", "incoming"] &&
    merged.statementUses.size == 1 &&
    numberingCounterState == Name.mkSimple "Informal.Block.numberingCounter" &&
    first == 1 && second == 2

end VersoBlueprintModuleTests.BlockStore
