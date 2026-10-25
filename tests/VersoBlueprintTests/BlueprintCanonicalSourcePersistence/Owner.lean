/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint

open Verso.Genre Informal

namespace CanonicalSourcePersistence

/-- A real native dependency with its own prose. -/
@[blueprint "storage.native"]
def dependency : Nat := 7

end CanonicalSourcePersistence

#docs (Manual) storageOwner "Source storage" :=
:::::::
:::definition "storage.source" (uses := "storage.forward")
A source with Unicode 𝒫 and several realizations.
{uses "storage.tagged" (origin := "automatic") (intent := "auxiliary")}[Authored reference].
:::

```lean "storage.source" (autoDeps := true)
def storedInline : Nat := CanonicalSourcePersistence.dependency
```

```rust "storage.source"
fn example() -> &'static str { "𝒫::bad»name" }
```

```tex "storage.source" (slot := "body.with.dot") (path := "paper.tex") (start_line := 2) (start_character := 3) (end_line := 2) (end_character := 12)
\forall x,\;𝒫(x)
```

```md "storage.source" (slot := "body.with.dot")
**𝒫** and `foreign::name.with.dot»tail`
```
:::::::
