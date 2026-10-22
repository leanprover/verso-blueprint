/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintAttribute

-- Import the provider and its local extension through another compiled module.
-- Export/replay must preserve both modules' registration order.
/-- info: true -/
#guard_msgs in
#eval show Lean.CoreM Bool from do
  let some node ← Informal.Environment.getNode? (Lean.Name.mkSimple "attr.hybrid.shared")
    | return false
  return node.leanDecls == #[
    `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedFirst,
    `Verso.VersoBlueprintTests.BlueprintAttribute.HybridProvider.hybridSharedSecond,
    `Verso.VersoBlueprintTests.BlueprintAttribute.hybridSharedThird,
    `Verso.VersoBlueprintTests.BlueprintAttribute.hybridSharedFourth]
