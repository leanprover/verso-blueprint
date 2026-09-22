/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

import VersoBlueprint
meta import VersoBlueprint
import all VersoBlueprintBoundaryTests.AutoDeps.Provider

open Lean Informal
namespace VersoBlueprintBoundaryTests.AutoDeps

@[blueprint "module.auto.all.hidden" (autoDeps := true)]
def allHidden : Nat := hiddenHelper

@[blueprint "module.auto.all.theorem" (autoDeps := true)]
theorem allTheorem : True := proofHelper

/-- error: invalid attribute '[blueprint]', declaration is in an imported module -/
#guard_msgs in
attribute [blueprint "module.auto.all.illegal"] source

run_meta do
  for (label, expected) in #[
      ("module.auto.all.hidden", "module.auto.source"),
      ("module.auto.all.theorem", "module.auto.proof")] do
    let some node ← Environment.getNode? (Name.mkSimple label)
      | throwError "Missing node {label}"
    let actual := (node.proof.map (·.deps)).getD #[] |>.map (·.label)
    unless actual == #[Name.mkSimple expected] do
      throwError "{label}: expected {expected}, got {actual}"

end VersoBlueprintBoundaryTests.AutoDeps
