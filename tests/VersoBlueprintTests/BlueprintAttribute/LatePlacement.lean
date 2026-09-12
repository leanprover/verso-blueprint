/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute.Provider

namespace Verso.VersoBlueprintTests.BlueprintAttribute.LatePlacement

set_option verso.blueprint.foldCodeBlocks true
set_option verso.blueprint.numbering "global"

-- Both placement forms are compiled before the generator's extra contributions.
#docs (Genre.Manual) placedDoc "Compiled attribute placements" :=
:::::::
{blueprint_node "attr.exported.theorem"}

{blueprint_node "attr.exported.definition"}

{blueprint_node "attr.exported.undocumented"}

{blueprint_summary}

{blueprint_graph}
:::::::

#docs (Genre.Manual) includedDoc "Compiled attribute module" :=
:::::::
{includeBlueprintModule VersoBlueprintTests.BlueprintAttribute.Provider}

{blueprint_summary}

{blueprint_graph}
:::::::

-- An explicitly captured document must remain isolated from later imports.
def frozen : Informal.BlueprintDocument := .capture includedDoc.toPart

end Verso.VersoBlueprintTests.BlueprintAttribute.LatePlacement
