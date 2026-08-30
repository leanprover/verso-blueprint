/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.Uses
meta import VersoBlueprint.Informal.Uses

namespace VersoBlueprintModuleTests.UsesAuthoring

open Lean
open Verso Genre Manual
open Informal

#docs (Manual) usesAuthoringContractDoc "Module Uses Authoring" :=
:::::::
:::definition "module.uses.source"
A dependency source.
:::

:::definition "module.uses.prose"
A prose-reference target.
:::

:::theorem "module.uses.target"
The statement uses {uses "module.uses.source" (origin := "automatic") (intent := "technical")}[]
and mentions {bpref "module.uses.prose"}[the prose target].
:::

:::proof "module.uses.target"
The proof uses {uses "module.uses.source" (intent := "auxiliary")}[].
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let target? := state.data.get? (Name.mkSimple "module.uses.target")
    pure <| match target? with
      | some target =>
          target.statement.any fun statement =>
            statement.deps == #[{
              label := Name.mkSimple "module.uses.source"
              origin := .automatic
              intent := .technical
            }] &&
            target.proof.any fun proof =>
              proof.deps == #[{
                label := Name.mkSimple "module.uses.source"
                origin := .manual
                intent := .auxiliary
              }]
      | none => false

end VersoBlueprintModuleTests.UsesAuthoring
