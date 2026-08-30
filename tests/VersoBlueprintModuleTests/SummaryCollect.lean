/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Summary.Collect
meta import VersoBlueprint.Commands.Summary.Collect

namespace VersoBlueprintModuleTests.SummaryCollect

open Lean

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let summary ← Informal.Commands.buildSummary
    let reverseMap : NameMap (Array Name) :=
      ({} : NameMap (Array Name))
        |>.insert `module.source #[`module.middle]
        |>.insert `module.middle #[`module.target]
    let downstream := Informal.Commands.downstreamUseCount reverseMap [`module.middle]
    pure <|
      summary.totalEntries == 0 &&
      summary.actionablePriorities.isEmpty &&
      downstream == 2

end VersoBlueprintModuleTests.SummaryCollect
