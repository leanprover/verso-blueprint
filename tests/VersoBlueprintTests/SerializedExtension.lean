/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary

namespace Verso.VersoBlueprintTests.SerializedExtension

/-- info: true -/
#guard_msgs in
#eval
  let graphData : Informal.Commands.GraphBlockData := default
  let direct := Informal.Commands.Block.graph graphData
  let serialized := Informal.Commands.blockFromJsonString!
    `Informal.Commands.Block.graph (Lean.toJson graphData).compress
  direct.name == serialized.name && direct.data.compress == serialized.data.compress

/-- info: true -/
#guard_msgs in
#eval
  let summary : Informal.Commands.Summary := { totalEntries := 3, theorems := 2 }
  let direct := Informal.Commands.Block.summary summary
  let serialized := Informal.Commands.blockFromJsonString!
    `Informal.Commands.Block.summary (Lean.toJson summary).compress
  direct.name == serialized.name && direct.data.compress == serialized.data.compress

end Verso.VersoBlueprintTests.SerializedExtension
