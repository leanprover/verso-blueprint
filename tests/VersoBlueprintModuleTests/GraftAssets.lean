/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Graft.Assets
meta import VersoBlueprint.Graft.Assets

namespace VersoBlueprintModuleTests.GraftAssets

/-- info: true -/
#guard_msgs in
#eval
  Informal.Graft.cssAssets == [Informal.Graft.css] &&
    Informal.Graft.css.contains "bp_graft_node" &&
    Informal.Graft.css.contains "bp_graft_side_by_side" &&
    Informal.Graft.css.contains "bp_code_progress"

end VersoBlueprintModuleTests.GraftAssets
