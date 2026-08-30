/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Graph
meta import VersoBlueprint.Commands.Graph

namespace VersoBlueprintModuleTests.GraphAuthoring

open Verso Genre Manual

#docs (Manual) graphAuthoringContractDoc "Module Graph Authoring" :=
:::::::
{blueprint_graph (direction := LR) (pack := false) (preview := hover) (previewPlacement := anchored)}
:::::::

/-- info: true -/
#guard_msgs in
#eval
  let graphData : Informal.Commands.GraphBlockData := default
  let block := Informal.Commands.Block.graph graphData
  graphData.previewMode == .pinned &&
    graphData.previewPlacement == .docked &&
    block.name == `Informal.Commands.Block.graph &&
    block.data.compress == (Lean.toJson graphData).compress

end VersoBlueprintModuleTests.GraphAuthoring
