/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoManual

namespace Verso.VersoBlueprintTests.BlueprintNumbering

open Lean
open Informal
open Verso.Genre Manual

private def emptyState : TraverseState :=
  TraverseState.initialize default

/-- info: true -/
#guard_msgs in
#eval
  let base : BlockData := {
    kind := .statement .definition
    label := `bp.numbering.base
    count := 4
  }
  let localBlock := { base with numberingMode := .local }
  let subBlock := { base with numberingMode := .sub, partPrefix := some "3" }
  let globalBlock := { base with numberingMode := .global, globalCount := some 17 }
  localBlock.displayNumber emptyState == "4" &&
  subBlock.displayNumber emptyState == "3.4" &&
  globalBlock.displayNumber emptyState == "17" &&
  subBlock.displayTitle emptyState == "Definition 3.4"

/-- info: true -/
#guard_msgs in
#eval
  let stored : BlockData := {
    kind := .statement .theorem
    label := `bp.numbering.stored
    count := 5
    numberingMode := .global
    partPrefix := some "2"
    globalCount := some 11
  }
  let state :=
    Informal.TraversalIndex.Nodes.saveData
      (TraverseState.initialize default)
      stored.label
      (toJson stored.toStoredData)
  let proofRef : BlockData := {
    kind := .proof
    label := stored.label
    count := stored.count
  }
  proofRef.displayNumber state == "11" &&
  proofRef.displayTitle state == "Proof 11"

/-- info: true -/
#guard_msgs in
#eval
  let legacy : BlockData := {
    kind := .statement .definition
    codeData := some (.external #[Data.ExternalRef.ofName `Nat.add])
    label := `bp.numbering.legacy
    count := 3
    numberingMode := .sub
    partPrefix := some "7"
  }
  let state :=
    Informal.TraversalIndex.Nodes.saveData
      (TraverseState.initialize default)
      legacy.label
      (toJson legacy)
  match Informal.TraversalIndex.Nodes.storedData? state legacy.label,
      Informal.TraversalIndex.Nodes.data? state legacy.label with
  | some stored, some recovered =>
      stored.label == legacy.label &&
      stored.partPrefix == legacy.partPrefix &&
      stored.globalCount == legacy.globalCount &&
      (match recovered.kind with | .statement .definition => true | _ => false) &&
      recovered.codeData.isNone &&
      recovered.displayNumber state == "7.3"
  | _, _ => false

end Verso.VersoBlueprintTests.BlueprintNumbering
