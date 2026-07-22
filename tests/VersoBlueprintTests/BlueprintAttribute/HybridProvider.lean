/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

open Verso
open Verso.Genre.Manual
open Informal

namespace Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider

@[blueprint "attr.hybrid.body"]
theorem hybridBodyTheorem : True := by
  trivial

#docs (Genre.Manual) hybridBodySourceDoc "Hybrid attribute body source" :=
:::::::
:::theorem "attr.hybrid.body"
Hybrid statement body persisted as already elaborated Manual blocks.
:::
:::::::

set_option doc.verso true in
/-- A Verso docstring body that survives Blueprint conversion. -/
@[blueprint "attr.hybrid.verso_docstring"]
def hybridVersoDocstring : Nat := 13

@[blueprint "attr.hybrid.shared"]
def hybridSharedFirst : Nat := 17

@[blueprint "attr.hybrid.shared"]
def hybridSharedSecond : Nat := 19

end Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider
