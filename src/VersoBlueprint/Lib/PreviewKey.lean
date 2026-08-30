/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.Data.Json

public section

namespace Informal

open Lean

/-- Non-empty serialized preview-key value. -/
structure PreviewKey where
  private mk ::
  /-- Serialized preview key value. -/
  value : String
deriving Repr, BEq

namespace PreviewKey

def ofString? (raw : String) : Option PreviewKey :=
  let value := raw.trimAscii.toString
  if value.isEmpty then none else some { value }

instance : ToString PreviewKey where
  toString key := key.value

instance : Lean.ToJson PreviewKey where
  toJson key := Lean.Json.str key.value

instance : Quote PreviewKey where
  quote key := Syntax.mkCApp ``PreviewKey.mk #[quote key.value]

instance : Lean.FromJson PreviewKey where
  fromJson? json := do
    let raw ← Lean.fromJson? (α := String) json
    match ofString? raw with
    | some key => pure key
    | none => .error "expected non-empty preview key"

end PreviewKey

end Informal
