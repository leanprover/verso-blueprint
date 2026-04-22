/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Data

namespace Informal

structure GroupBlockData where
  label : Data.Label
  header : String := ""
deriving Inhabited, Lean.Quote

instance : Lean.ToJson GroupBlockData where
  toJson data := .arr #[Lean.ToJson.toJson data.label, Lean.ToJson.toJson data.header]

instance : Lean.FromJson GroupBlockData where
  fromJson? v := do
    let arr ← v.getArr?
    let some label := arr[0]? | throw "expected group label"
    let some header := arr[1]? | throw "expected group header"
    return {
      label := ← Lean.FromJson.fromJson? label
      header := ← Lean.FromJson.fromJson? header
    }

end Informal
