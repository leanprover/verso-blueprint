/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprintModuleTests.IncrementalOwner
import VersoBlueprint.Commands.Graph.Data

namespace VersoBlueprintModuleTests.IncrementalAuthoring

/-- A normal-phase consumer of the Graft authoring data surface. -/
def authoringNode : Informal.Graft.BlueprintNode := {
  label := IncrementalOwner.authoringLabel
  key := "module-incremental--statement"
}

/-- Representative use of phase-neutral data from an authoring consumer. -/
def graphData : Informal.Commands.GraphBlockData := default

end VersoBlueprintModuleTests.IncrementalAuthoring
