/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

import VersoBlueprint
meta import VersoBlueprint
-- Ordinary's Provider import is intentionally not public.
import VersoBlueprintBoundaryTests.AutoDeps.Ordinary

open Lean Informal

run_meta do
  unless (← Environment.getNode? (Name.mkSimple "module.auto.private")).isNone do
    throwError "A non-public import unexpectedly re-exported provider metadata"
  let catalog ← Environment.blueprintAttributeLabelsForModule
    `VersoBlueprintBoundaryTests.AutoDeps.Provider
  unless catalog.isEmpty do
    throwError "A non-public import unexpectedly re-exported the provider catalog"

/-- error: Blueprint module include: module 'VersoBlueprintBoundaryTests.AutoDeps.Provider' is not available through this Lean module's imports; add `import VersoBlueprintBoundaryTests.AutoDeps.Provider` -/
#guard_msgs in
#docs (Verso.Genre.Manual) transitiveAttributes "Transitive attributes" :=
:::::::
{includeBlueprintModule VersoBlueprintBoundaryTests.AutoDeps.Provider}
:::::::
