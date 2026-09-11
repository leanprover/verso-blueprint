/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.FacetPlaceholder

open Verso.Genre Informal

#doc (Manual) "Filled statement chapter" =>

:::theorem "filled_facet"
%%%
source := {
  document := "facet-paper"
  spans := #[{ page := "1", pdf := some { path := "source/page-1.pdf" } }]
}
%%%
A completed statement from page one.
:::

```lean "filled_facet"
theorem filledFacetFormal : True := trivial
```
