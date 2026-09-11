/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.KindBase

open _root_.Lean Verso.Genre Informal

#docs (Manual) literateKindDoc "Inferred kind from a literate theorem" :=
:::::::
```lean "kind_placeholder"
theorem kindLiterateTheorem : True := trivial
```
:::::::

#eval show CoreM Unit from do
  let some node ← Environment.getNode? `kind_placeholder | throwError "Missing placeholder"
  unless node.kind == .theorem && !node.kindIsExplicit do
    throwError "Literate theorem did not promote the inferred definition kind"
