/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

import VersoBlueprint
meta import VersoBlueprint
import VersoBlueprintBoundaryTests.AutoDeps.Reexport

open Lean Informal

run_meta do
  let some node ← Environment.getNode? (Name.mkSimple "module.auto.private")
    | throwError "Public re-export lost private declaration's attribute metadata"
  let deps := (node.proof.map (·.deps)).getD #[] |>.map (·.label)
  unless deps == #[Name.mkSimple "module.auto.source"] && node.blueprintAttributeAttachments do
    throwError "Imported contribution lost its dependencies or attachment capability"
  let catalog ← Environment.blueprintAttributeLabelsForModule
    `VersoBlueprintBoundaryTests.AutoDeps.Provider
  unless catalog.contains (Name.mkSimple "module.auto.private") do
    throwError "Public re-export lost the provider catalog"

#docs (Verso.Genre.Manual) reexportedAttributes "Re-exported attributes" :=
:::::::
{includeBlueprintModule VersoBlueprintBoundaryTests.AutoDeps.Provider}
:::::::
