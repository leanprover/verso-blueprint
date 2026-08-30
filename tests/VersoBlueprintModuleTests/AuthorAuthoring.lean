/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Informal.Author
meta import VersoBlueprint.Informal.Author

namespace VersoBlueprintModuleTests.AuthorAuthoring

open Lean
open Verso Genre Manual
open Informal

#docs (Manual) authorAuthoringContractDoc "Module Author Authoring" :=
:::::::
:::author "module.author"
Ada Module Lovelace
:::

:::author "module.author.explicit" (name := " Grace Hopper ") (url := " https://example.test/grace ") (image_url := " https://example.test/grace.png ")
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let derived? := state.authors.get? (Name.mkSimple "module.author")
    let explicit? := state.authors.get? (Name.mkSimple "module.author.explicit")
    pure <| match derived?, explicit? with
      | some derived, some explicit =>
          derived.displayName == "Ada Module Lovelace" &&
          explicit.displayName == "Grace Hopper" &&
          explicit.url == some "https://example.test/grace" &&
          explicit.imageUrl == some "https://example.test/grace.png"
      | _, _ => false

end VersoBlueprintModuleTests.AuthorAuthoring
