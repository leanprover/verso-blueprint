/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Graft
meta import VersoBlueprint.Graft

namespace VersoBlueprintModuleTests.GraftAuthoring

open Verso Genre Manual

#docs (Manual) graftAuthoringContractDoc "Module Graft Authoring" :=
:::::::
:::blueprint_side_by_side +boxed
{blueprint_node "module.graft.target" -header +compact}
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  let cfg : Informal.Graft.BlueprintNodeConfig := {
    label := "module.graft.target"
    compact := true
    showHeader := false
  }
  let block := Informal.Graft.Block.blueprintGraftNode cfg
  block.name == `Informal.Graft.Block.blueprintGraftNode &&
    block.data.compress == (Lean.toJson cfg).compress &&
    Informal.Graft.manualGraftAssetBundle.css != []

end VersoBlueprintModuleTests.GraftAuthoring
