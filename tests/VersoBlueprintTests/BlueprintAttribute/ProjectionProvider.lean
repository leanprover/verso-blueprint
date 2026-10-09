/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

namespace Verso.VersoBlueprintTests.BlueprintAttribute.ProjectionProvider

@[blueprint "attr.projection.shared"]
theorem projectionWitness : True := by trivial

end Verso.VersoBlueprintTests.BlueprintAttribute.ProjectionProvider
