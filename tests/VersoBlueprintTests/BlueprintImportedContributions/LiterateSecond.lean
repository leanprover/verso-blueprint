/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.Statement

open Verso.Genre Informal
set_option verso.blueprint.foldCodeBlocks true
set_option verso.blueprint.foldProofs false

#doc (Manual) "Second literate attachment" =>

```lean "key_theorem"
theorem inlineSecond : True := trivial
```
