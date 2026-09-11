/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprint.Informal.Block.Store
import VersoManual

namespace Verso.VersoBlueprintTests.BlueprintNumbering

open Lean
open Informal
open Verso.Genre Manual

private def emptyState : TraverseState :=
  TraverseState.initialize default

private def completedOccurrence (data : BlockData) : TraverseState :=
  let (id, state) := (freshId : StateM TraverseState Verso.Multi.InternalId).run emptyState
  let state := Informal.TraversalIndex.Nodes.saveNode state (RenderNode.ofBlockData data)
  Informal.TraversalIndex.Nodes.saveId state data.label id

private def header (title : String) (number? : Option Numbering) : PartHeader := {
  titleString := title
  metadata := number?.map fun number => { ({} : PartMetadata) with assignedNumber := some number }
  properties := {}
}

/-- info: true -/
#guard_msgs in
#eval
  let base : BlockData := {
    kind := .definition
    label := `bp.numbering.base
    count := 4
  }
  let localBlock := { base with numberingMode := .local }
  let subBlock := { base with numberingMode := .sub, partPrefix := some "3" }
  let globalBlock := { base with numberingMode := .global, globalCount := some 17 }
  let propositionBlock := { base with kind := .proposition }
  (localBlock.display (completedOccurrence localBlock)).number? == some "4" &&
  (subBlock.display (completedOccurrence subBlock)).number? == some "3.4" &&
  (globalBlock.display (completedOccurrence globalBlock)).number? == some "17" &&
  subBlock.displayTitle (completedOccurrence subBlock) == "Definition 3.4" &&
  propositionBlock.displayTitle (completedOccurrence propositionBlock) == "Proposition 4"

/-- info: true -/
#guard_msgs in
#eval
  let base : BlockData := {
    kind := .theorem
    label := `bp.numbering.sectionSub
    count := 2
  }
  let subBlock := { base with numberingMode := .sub, partPrefix := some "1.3" }
  (subBlock.display (completedOccurrence subBlock)).number? == some "1.3.2" &&
  subBlock.displayTitle (completedOccurrence subBlock) == "Theorem 1.3.2"

/-- info: true -/
#guard_msgs in
#eval
  let context : TraverseContext := {
    path := #[]
    headers := #[
      header "Root" none,
      header "Chapter" (some (.nat 1)),
      header "Section" (some (.nat 3)),
      header "Appendix" (some (.letter 'A'))
    ]
    blockContext := #[]
    draft := false
  }
  numberedPartPrefix? .full context == some "1.3.A" &&
  numberedPartPrefix? .first context == some "1"

/-- info: true -/
#guard_msgs in
#eval
  let stored : BlockData := {
    kind := .lemma
    label := `bp.numbering.storedSub
    count := 9
    numberingMode := .sub
    partPrefix := some "1.3"
  }
  let state := completedOccurrence stored
  let renderData := { stored with count := 120 }
  (renderData.display state).number? == some "1.3.9" &&
  renderData.displayTitle state == "Lemma 1.3.9"

/-- info: true -/
#guard_msgs in
#eval
  let (first, state) := reservePrefixBlockNumber emptyState "1.3"
  let (second, state) := reservePrefixBlockNumber state "1.3"
  let (other, _) := reservePrefixBlockNumber state "1.4"
  first == 1 &&
  second == 2 &&
  other == 1

/-- info: true -/
#guard_msgs in
#eval
  let data : BlockData := {
    kind := .theorem
    label := `bp.numbering.documentCounter
    count := 42
    numberingMode := .sub
    subNumberingCounter := .document
    partPrefix := some "1"
  }
  let (count, state) := reserveSubBlockNumber emptyState data
  count == 42 &&
  (reservePrefixBlockNumber state "1").fst == 1

/-- info: true -/
#guard_msgs in
#eval
  let stored : BlockData := {
    kind := .theorem
    label := `bp.numbering.stored
    count := 5
    numberingMode := .global
    partPrefix := some "2"
    globalCount := some 11
  }
  let state := completedOccurrence stored
  let proofRef : BlockData := {
    kind := stored.kind
    isProof := true
    label := stored.label
    count := stored.count
  }
  (proofRef.display state).number? == some "11" &&
  proofRef.displayTitle state == "Proof for Theorem 11"

-- Captured metadata may retain an elaboration count, but cannot display it.
#eval show IO Unit from do
  let data : BlockData := { label := `unrendered_number, kind := .theorem, count := 99 }
  let state := Informal.TraversalIndex.Nodes.saveNode emptyState {
    label := data.label, kind := data.kind, initialCount := data.count }
  unless (data.display state).number?.isNone && data.displayTitle state == "unrendered_number" do
    throw <| IO.userError "Captured metadata acquired a document number"

end Verso.VersoBlueprintTests.BlueprintNumbering
