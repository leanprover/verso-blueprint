/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint

open Verso.Genre Informal

/-- This declaration precedes the incremental document. -/
@[blueprint "capture.beforeIncremental"]
def CaptureFenceOwner.precedingDocumented : Nat := 5

#doc (Manual) "Checked incremental fence source" =>

:::definition "capture.incrementalFenceDisplay"
A container for the checked incremental Lean fence.
:::

```lean "capture.incrementalFenceDisplay"
/-- An own comment in an incremental document. -/
@[blueprint "capture.incrementalFencedAttribute"]
def CaptureFenceOwner.incrementalDocumented : Nat := 11
```
