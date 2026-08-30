/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.DependencyAnalysis
meta import VersoBlueprint.DependencyAnalysis

namespace VersoBlueprintModuleTests.DependencyAnalysis

open Lean
open Informal

/-- info: true -/
#guard_msgs in
#eval
  let deps : DependencyAnalysis.InferredDeps := {
    statement := #[`demo.b, `demo.a]
    proof := #[`demo.c, `demo.a]
  }
  let refs := deps.toUseRefs
  refs.statement.map (·.label) == #[`demo.a, `demo.b] &&
    refs.proof.map (·.label) == #[`demo.c] &&
    refs.statement.all (·.origin == .automatic) &&
    refs.proof.all (·.origin == .automatic)

/-- info: true -/
#guard_msgs in
#eval
  show Lean.CoreM Bool from do
    let deps ← DependencyAnalysis.inferDecl? `No.Such.Declaration
    let state := Environment.informalExt.getState (← getEnv)
    pure <| deps.statement.isEmpty && deps.proof.isEmpty && state.stack.isEmpty

end VersoBlueprintModuleTests.DependencyAnalysis
