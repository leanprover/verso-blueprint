/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.Group
meta import VersoBlueprint.Informal.Block.Config
meta import VersoBlueprint.Informal.Group

namespace VersoBlueprintModuleTests.GroupAuthoring

open Lean
open Verso Genre Manual
open Informal

local macro "blockConfigContract" : term => do
  let cfg : Informal.Config := {
    label := Name.mkSimple "module.block.config"
    priority := some "high"
    tags := #["module", "authoring"]
  }
  let contract : Name × Option String × Array String :=
    (cfg.label, cfg.priority, cfg.tags)
  return quote contract

#docs (Manual) groupAuthoringContractDoc "Module Group Authoring" :=
:::::::
:::group "module.group.authoring"
A "quoted" module group.
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    pure <|
      (blockConfigContract : Name × Option String × Array String) ==
        (Name.mkSimple "module.block.config", some "high", #["module", "authoring"]) &&
      state.groups.get? (Name.mkSimple "module.group.authoring") ==
        some "A \"quoted\" module group."

end VersoBlueprintModuleTests.GroupAuthoring
