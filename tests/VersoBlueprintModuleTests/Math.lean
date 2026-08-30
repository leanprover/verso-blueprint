/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Math
meta import VersoBlueprint.Math

namespace VersoBlueprintModuleTests.Math

open Lean
open Lean.Doc
open Informal.Math

local macro "bpMathDataContract" : term => do
  let data : BpMathData := {
    mode := .inline
    source := "x + y"
    texPrelude := "\\newcommand{\\R}{\\mathbb{R}}"
  }
  return quote data

/-- info: true -/
#guard_msgs in
#eval
  let data : BpMathData := bpMathDataContract
  match Lean.fromJson? (α := BpMathData) (Lean.toJson data) with
  | .ok decoded =>
      decoded.source == data.source &&
        decoded.texPrelude == data.texPrelude &&
        match decoded.mode with
        | .inline => true
        | .display => false
  | .error _ => false

end VersoBlueprintModuleTests.Math
