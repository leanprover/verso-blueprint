/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.FacetPlaceholder

open Verso.Genre Informal

#doc (Manual) "Proof source chapter" =>

:::proof "filled_facet"
%%%
source := {
  document := "facet-proof-paper"
  spans := #[{ page := "2", pdf := some { path := "source/page-2.pdf" } }]
}
%%%
A completed proof from page two.
:::
