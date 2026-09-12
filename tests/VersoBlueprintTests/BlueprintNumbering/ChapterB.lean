/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint

namespace Verso.VersoBlueprintTests.BlueprintNumbering.ChapterB
open Verso Informal
set_option verso.blueprint.numbering "local"

#docs (Genre.Manual) chapter "Chapter B" :=
:::::::
:::definition "local.B.first"
First ordinary definition in an independently elaborated source.
:::

:::definition "local.B.second"
Second ordinary definition in the same source.
:::
:::::::

end Verso.VersoBlueprintTests.BlueprintNumbering.ChapterB
