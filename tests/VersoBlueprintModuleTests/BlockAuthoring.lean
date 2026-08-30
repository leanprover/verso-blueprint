/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.Block
meta import VersoBlueprint.Informal.Block

namespace VersoBlueprintModuleTests.BlockAuthoring

open Lean
open Verso Genre Manual
open Informal

#docs (Manual) blockAuthoringContractDoc "Module Block Authoring" :=
:::::::
:::definition "module.block.source"
A strict-module source statement.
:::

:::theorem "module.block.target" (uses := "module.block.source")
A strict-module target statement.
:::

:::proof "module.block.target" (uses := "module.block.source")
Its strict-module proof.
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let source? := state.data.get? (Name.mkSimple "module.block.source")
    let target? := state.data.get? (Name.mkSimple "module.block.target")
    pure <| match source?, target? with
      | some source, some target =>
          source.kind == .definition &&
          source.statement.isSome &&
          target.kind == .theorem &&
          target.statement.any (·.deps.any (·.label == Name.mkSimple "module.block.source")) &&
          target.proof.any (·.deps.any (·.label == Name.mkSimple "module.block.source"))
      | _, _ => false

end VersoBlueprintModuleTests.BlockAuthoring
