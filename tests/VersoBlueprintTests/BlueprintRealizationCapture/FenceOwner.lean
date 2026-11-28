/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint

open Verso.Genre Informal

namespace CaptureFenceOwner

def unrelatedNative : Nat := 42

#docs (Manual) fenceOwner "Checked fence source" :=
:::::::
:::definition "capture.fenceDisplay"
A container for a checked Lean fence.
:::

```lean "capture.fenceDisplay"
/--
A fenced declaration owns this 𝒫 comment.
-/
@[blueprint "capture.fencedAttribute"]
def documented : Nat := 7
```
:::::::

end CaptureFenceOwner
