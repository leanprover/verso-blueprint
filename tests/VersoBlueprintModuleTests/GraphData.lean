/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Commands.Graph.Data
meta import VersoBlueprint.Commands.Graph.Data

namespace VersoBlueprintModuleTests.GraphData

/-- info: true -/
#guard_msgs in
#eval
  let data : Informal.Commands.GraphBlockData := default
  Informal.Commands.parseGraphPreviewMode? " HOVER " == some .hover &&
    Informal.Commands.parseGraphPreviewPlacement? "anchored" == some .anchored &&
    data.graphModel.nodes.isEmpty &&
    data.options.direction == .TB &&
    data.previewMode == .pinned &&
    data.previewPlacement == .docked &&
    (Lean.fromJson? (Lean.toJson data) : Except String Informal.Commands.GraphBlockData).isOk

end VersoBlueprintModuleTests.GraphData
