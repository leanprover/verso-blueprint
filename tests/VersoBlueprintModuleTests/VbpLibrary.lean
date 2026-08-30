/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Vbp
meta import VersoBlueprint.Vbp

namespace VersoBlueprintModuleTests.VbpLibrary

/-- info: true -/
#guard_msgs in
#eval
  VersoBlueprint.Vbp.querySelectorLines.contains "stats" &&
    (match VersoBlueprint.Vbp.parseQueryPlan ["stats"] with
    | .ok (some plan) => !plan.needsGraphData
    | _ => false) &&
    (match VersoBlueprint.Vbp.parseQueryPlan ["work-queue"] with
    | .ok (some plan) => plan.needsGraphData
    | _ => false) &&
    (match VersoBlueprint.Vbp.parseQueryPlan ["future-selector"] with
    | .error _ => true
    | _ => false)

end VersoBlueprintModuleTests.VbpLibrary
