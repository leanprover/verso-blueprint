/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Summary.Sections
meta import VersoBlueprint.Commands.Summary.Sections

namespace VersoBlueprintModuleTests.SummarySections

/-- info: true -/
#guard_msgs in
#eval
  let summary : Informal.Commands.Summary := {
    totalEntries := 3
    theorems := 2
  }
  let block := Informal.Commands.Block.summary summary
  block.name == `Informal.Commands.Block.summary &&
    block.data.compress == (Lean.toJson summary).compress

end VersoBlueprintModuleTests.SummarySections
