/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.SerializedExtension
meta import VersoBlueprint.Commands.SerializedExtension

namespace VersoBlueprintModuleTests.SerializedExtension

open Lean

meta example [ToJson α] (name : Name) (data : α) :
    Verso.Doc.Elab.PartElabM (TSyntax `term) :=
  Informal.Commands.serializedBlockTerm name data

/-- info: true -/
#guard_msgs in
#eval
  let name := Name.mkSimple "moduleSerialized"
  let block := Informal.Commands.blockFromJsonString! name "{\"count\":7,\"valid\":true}"
  block.name == name &&
    block.data == Json.mkObj [
      ("count", Json.num 7),
      ("valid", Json.bool true)
    ]

end VersoBlueprintModuleTests.SerializedExtension
