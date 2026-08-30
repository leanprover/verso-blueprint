/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Summary.Render
meta import VersoBlueprint.Commands.Summary.Render

namespace VersoBlueprintModuleTests.SummaryRender

/-- info: true -/
#guard_msgs in
#eval
  let summary : Informal.Commands.Summary := { totalEntries := 1 }
  let block := Informal.Commands.Block.summary summary
  block.name == `Informal.Commands.Block.summary &&
    block.data.compress == (Lean.toJson summary).compress

end VersoBlueprintModuleTests.SummaryRender
