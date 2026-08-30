/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.RustBlock
meta import VersoBlueprint.Informal.RustBlock

namespace VersoBlueprintModuleTests.RustAuthoring

open Lean
open Verso Genre Manual
open Informal

#docs (Manual) rustAuthoringContractDoc "Module Rust Authoring" :=
:::::::
:::definition "module.rust.target"
A statement with an inline Rust witness.
:::

```rust "module.rust.target"
fn module_value() -> usize { 7 }
```
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let target? := state.data.get? (Name.mkSimple "module.rust.target")
    pure <| match target? with
      | some target =>
          target.rustCode.any fun code =>
            code.raw.trimAscii.toString == "fn module_value() -> usize { 7 }"
      | none => false

end VersoBlueprintModuleTests.RustAuthoring
