/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Data
import VersoBlueprint.Informal.Block.Model
meta import VersoBlueprint.Data
meta import VersoBlueprint.Informal.Block.Model

namespace VersoBlueprintModuleTests.Data

open Lean
open Informal.Data

local macro "labelContract" : term => do
  let label : Label := ``Nat
  return quote label

local macro "blockDataContract" : term => do
  let block : Informal.BlockData := {
    kind := .statement .theorem
    codeData := some (.external #[ExternalRef.ofName `Contract.declaration])
    label := Name.mkSimple "module.block.model"
    count := 7
    numberingMode := .sub
    subNumberingPrefix := .first
    subNumberingCounter := .document
    statementUses := #[{ label := Name.mkSimple "module.block.source" }]
  }
  return quote block

/-- info: true -/
#guard_msgs in
#eval
  let label : Label := labelContract
  let labelRoundtripOk :=
    match Lean.fromJson? (α := Label) (Lean.toJson label) with
    | .ok decoded => decoded == label
    | .error _ => false
  let labels : LabelMap Nat := Std.TreeMap.empty
  let data : Data := Data.empty
  labelRoundtripOk && labels.isEmpty && data.isEmpty

/-- info: true -/
#guard_msgs in
#eval
  let block : Informal.BlockData := blockDataContract
  let stored := block.toStoredData
  let restored := stored.toBlockData
  stored.label == block.label && stored.count == 7 &&
    stored.statementDeps == #[Name.mkSimple "module.block.source"] &&
    restored.codeData.isNone && restored.numberingMode == .sub &&
    restored.subNumberingPrefix == .first && restored.subNumberingCounter == .document &&
    Informal.NumberingMode.parse? "chapter" == some .sub &&
    Informal.SubNumberingPrefix.parse? "top" == some .first &&
    Informal.SubNumberingCounter.parse? "global" == some .document

end VersoBlueprintModuleTests.Data
