/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import VersoBlueprint.Data

public section

namespace Informal

structure GroupBlockData where
  label : Data.Label
  header : String := ""
deriving Inhabited, Lean.FromJson, Lean.ToJson, Lean.Quote

end Informal
