/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Placeholder

open Verso.Genre Informal

#doc (Manual) "Fill imported placeholders" =>

:::definition "local_dep"
A dependency added alongside the body.
:::

:::theorem "placeholder" (uses := "local_dep")
Fill an imported bodyless statement.
:::

:::proof "placeholder"
Fill an imported bodyless proof.
:::
