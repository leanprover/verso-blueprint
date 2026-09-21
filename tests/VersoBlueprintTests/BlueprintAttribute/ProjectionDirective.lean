/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprintTests.BlueprintAttribute.ProjectionProvider

open Informal

namespace Verso.VersoBlueprintTests.BlueprintAttribute.ProjectionDirective

#docs (Verso.Genre.Manual) directiveDocument "Projection directive" :=
:::::::
:::theorem "attr.projection.shared" (lean := "ProjectionProvider.projectionWitness")
This document is deliberately not included by the graft consumer.
:::
:::::::

end Verso.VersoBlueprintTests.BlueprintAttribute.ProjectionDirective
