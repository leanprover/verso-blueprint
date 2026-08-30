/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.Code
meta import VersoBlueprint.Informal.Code

namespace VersoBlueprintModuleTests.CodeAuthoring

open Lean
open Verso Genre Manual
open Informal

#docs (Manual) codeAuthoringContractDoc "Module Code Authoring" :=
:::::::
:::definition "module.code.target"
A statement with inline Lean and external Markdown witnesses.
:::

```lean "module.code.target"
def moduleCodeValue : Nat := 7
```

```md "module.code.target" (slot := statement)
Module-system Markdown witness.
```
:::::::

example : moduleCodeValue = 7 := rfl

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let target? := state.data.get? (Name.mkSimple "module.code.target")
    pure <| match target? with
      | some target =>
          ExternalMarkupDisplayMode.parse? "metadata" == some .summary &&
          target.literateCodes.size == 1 &&
          (target.externalMarkup.find? .markdown "statement" |>.any fun markup =>
            markup.raw.trimAscii.toString == "Module-system Markdown witness.")
      | none => false

end VersoBlueprintModuleTests.CodeAuthoring
