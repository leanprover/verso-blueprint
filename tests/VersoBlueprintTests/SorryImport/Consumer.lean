/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module
public import Lean
import VersoBlueprintTests.SorryImport.Provider

open Lean

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let env ← getEnv
    let names := #[`sorryImportAdmitted, `sorryImportComplete, `sorryImportAxiom]
    let infos := names.mapM env.find?
    let some infos := infos | return false
    let hidden := infos.all fun info => match info with
      | .axiomInfo _ => true
      | _ => false
    let admitted ← collectAxioms `sorryImportAdmitted
    let complete ← collectAxioms `sorryImportComplete
    let axiomFootprint ← collectAxioms `sorryImportAxiom
    return hidden && admitted.contains ``sorryAx &&
      complete.isEmpty && axiomFootprint.contains `sorryImportAxiom
