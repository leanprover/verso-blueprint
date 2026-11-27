/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.FacetPlaceholder

open Verso.Genre Informal

open Lean Elab Command in
run_cmd liftTermElabM do
  let .ok snapshot ← Realizations.Capture.capture
    | throwError "Could not capture the imported empty placeholder"
  let prose : Realizations.RealizationKey := ⟨`filled_facet, `verso⟩
  let native : Realizations.RealizationKey := ⟨`filled_facet, `lean⟩
  unless (snapshot.registry.realization? (prose.forRole `statement)).isNone &&
      (snapshot.registry.realization? (native.forRole `statement)).isSome do
    throwError "Empty statement placeholder must retain the native selection without a prose document"

#doc (Manual) "Filled statement chapter" =>

:::theorem "filled_facet"
:::

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
