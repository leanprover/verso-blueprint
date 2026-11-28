/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

namespace Informal

/-- Append a new member, preserving the first occurrence of each value. -/
def pushUnique [BEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

/-- Keep the first occurrence of each value in traversal order. -/
def uniqueInOrder [BEq α] (values : Array α) : Array α :=
  values.foldl pushUnique #[]

end Informal
