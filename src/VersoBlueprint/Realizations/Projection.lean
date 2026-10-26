/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean

namespace Informal.Realizations

/-- Serializable projection of an admitted current capture. This is presentation
output, never an input assertion or persisted source authority. The exact assessed
subjects, contracts, observations and selection diagnostics are in `details`.
No native declarations means unassessed, not a failed or implicitly required proof.
An absent assessment at a consumer means uncaptured; legacy source snapshots must
not supply substitute completion. -/
structure NodeAssessment where
  hasNativeDeclarations : Bool := false
  /-- Fresh provider inventory, not a completion or axiom-acceptance policy. -/
  hasAxiomLike : Bool := false
  /-- Local own-declaration statement checks, before Blueprint prerequisites. -/
  nativeStatementComplete : Bool := false
  /-- Local own-declaration body checks, not proof of an independent expected goal. -/
  nativeProofComplete : Bool := false
  /-- All explicit requirements of the selected ordinary Lean realization. -/
  requiredComplete : Bool := false
  statementDependenciesComplete : Bool := false
  proofDependenciesComplete : Bool := false
  /-- Safe output only: no source bodies, raw contributions or content bindings. -/
  details : Lean.Json := .null
  deriving Inhabited, BEq, Lean.ToJson, Lean.FromJson

instance : Repr NodeAssessment where
  reprPrec value _ := Std.Format.text (Lean.toJson value).compress

def NodeAssessment.fromJsonString! (serialized : String) : NodeAssessment :=
  match Lean.Json.parse serialized >>= Lean.fromJson? with
  | .ok value => value
  | .error message => panic! s!"Invalid captured node assessment: {message}"

instance : Lean.Quote NodeAssessment where
  quote value := Lean.Syntax.mkCApp ``NodeAssessment.fromJsonString!
    #[Lean.quote (Lean.toJson value).compress]

end Informal.Realizations
