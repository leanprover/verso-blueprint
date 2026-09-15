/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module
public import Vir.Js.Types
public section

namespace Lean.Vir.JsonValue.Internal

/-- One-node conversion boundary. Child values remain JS resources, not a wire DTO. -/
inductive View where
  | null
  | bool (value : Bool)
  | integer (value : Int)
  | string (value : String)
  | array (children : Array Js.Any)
  | object (fields : Array (String × Js.Any))

end Lean.Vir.JsonValue.Internal
