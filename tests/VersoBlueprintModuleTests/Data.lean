/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Data
meta import VersoBlueprint.Data

namespace VersoBlueprintModuleTests.Data

open Lean
open Informal.Data

local macro "labelContract" : term => do
  let label : Label := ``Nat
  return quote label

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

end VersoBlueprintModuleTests.Data
