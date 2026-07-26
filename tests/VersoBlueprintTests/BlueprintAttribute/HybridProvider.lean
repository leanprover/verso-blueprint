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

@[blueprint "attr.hybrid.body"
  (uses := ["attr.hybrid.verso_docstring"])
  (proofUses := ["attr.hybrid.shared"])]
theorem hybridBodyTheorem : True := by
  trivial

#docs (Genre.Manual) hybridBodySourceDoc "Hybrid attribute body source" :=
:::::::
:::theorem "attr.hybrid.body"
Hybrid statement body persisted with *structural emphasis*, inline mathematics
$`1 + 1 = 2`, and already elaborated Manual blocks.

* First persisted Manual list item.
* Second persisted Manual list item.
:::
:::::::

set_option doc.verso true in
/--
A *structurally emphasized Verso docstring body* that survives Blueprint
conversion. It keeps the child content of the {name}`Nat.succ`
extension and inline mathematics $`2 + 2 = 4`.

* First imported docstring list item.
* Second imported docstring list item.
-/
@[blueprint "attr.hybrid.verso_docstring"]
def hybridVersoDocstring : Nat := 13

@[blueprint "attr.hybrid.shared"]
def hybridSharedFirst : Nat := 17

@[blueprint "attr.hybrid.shared"]
def hybridSharedSecond : Nat := 19

@[blueprint "attr.hybrid.late_docstring"
  (uses := ["attr.hybrid.verso_docstring"])]
def hybridLateDocstringFirst : Nat := 23

/--
A later declaration docstring fills a dependency-only statement payload without
discarding the dependencies registered by the first declaration.
-/
@[blueprint "attr.hybrid.late_docstring"]
def hybridLateDocstringSecond : Nat := 29

end Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider
