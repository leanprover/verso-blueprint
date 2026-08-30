/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

meta import VersoBlueprint.Attribute

namespace VersoBlueprintModuleTests.Attribute

open Lean
open Informal

/-- Source declaration for the strict module-system attribute contract. -/
@[blueprint "module.attribute.source"]
def source : Nat := 1

/-- Target declaration whose inferred dependency must survive attribute elaboration. -/
@[blueprint "module.attribute.target" (autoDeps := true)]
theorem target : source = 1 := rfl

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let data := Environment.informalExt.getState (← getEnv) |>.data
    let sourceLabel := Name.mkSimple "module.attribute.source"
    let targetLabel := Name.mkSimple "module.attribute.target"
    let some sourceNode := data.get? sourceLabel
      | return false
    let some targetNode := data.get? targetLabel
      | return false
    let some statement := targetNode.statement
      | return false
    pure <|
      sourceNode.kind == .definition &&
        targetNode.kind == .theorem &&
        statement.deps.any fun dep =>
          dep.label == sourceLabel && dep.origin == .automatic

end VersoBlueprintModuleTests.Attribute
