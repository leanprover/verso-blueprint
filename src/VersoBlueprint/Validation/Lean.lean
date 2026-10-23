/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Elab.Term
import VersoBlueprint.Validation
import VersoBlueprint.ProvedStatus

/-! Explicit native provider. Importing this module installs no completion path.
The caller authors the expected proposition independently of the witness. -/

namespace Informal.Validation.NativeLean

open Lean Meta Elab Term Realizations

structure Checked where
  goal : Goal
  observation : ProofObservation
  status : Option Data.ProvedStatus := none

private def issue (code : String) (witness : ObjectKey) (message : String) : Diagnostic :=
  { code, subject := witness.native, message }

/-- Check in the current environment, without retaining elaborator/environment
changes. Only closed, monomorphic expected propositions are supported here;
universe-polymorphic contracts need an explicit later API. Binders *inside* a
closed proposition and concrete universe/package instantiations are preserved.
The logical project is selected by the caller, not inferred from module names. -/
def check (project : Name) (witness : ObjectKey) (expected : Syntax)
    (documents : Array DocumentKey := #[]) : TermElabM (Except Diagnostic Checked) := do
  let saved ← Term.saveState
  try
    if project.isAnonymous || witness.context != { language := `lean, project } || !witness.valid then
      return .error <| issue "wrong-context" witness "Witness is outside the selected Lean project"
    let proposition ← withoutErrToSorry <| elabTermEnsuringType expected (some (mkSort .zero))
    synthesizeSyntheticMVarsNoPostponing
    let proposition ← instantiateMVars proposition
    -- Elaboration may introduce auxiliary declarations. This provider accepts
    -- expectations only in the original checked environment, not a transient
    -- extension that disappears when the read-only operation returns.
    setEnv saved.meta.core.env
    if proposition.hasMVar || proposition.hasFVar || proposition.hasLooseBVars ||
        proposition.hasLevelMVar || proposition.hasLevelParam then
      return .error <| issue "open-expectation" witness "Expected proposition must be closed, with concrete universes"
    if proposition.hasSorry then
      return .error <| issue "admitted-expectation" witness "Expected proposition contains an admission"
    checkWithKernel proposition
    unless ← isProp proposition do
      return .error <| issue "non-proposition" witness "Expected term is not a proposition"
    let (inspection, _) ← (Data.inspectSorryDependencies proposition.getUsedConstants).run {}
    unless inspection.isComplete do
      return .error <| issue "unverified-expectation" witness
        "Expected proposition has admitted or unavailable dependencies"
    -- This is an exact structural descriptor, not the equality algorithm. It
    -- comes from the independently checked expectation, never the witness type.
    let goal : Goal := { context := witness.context, proposition := reprStr proposition, documents }
    let name := witness.native.toName
    let some info := (← getEnv).checked.get.find? name
      | return .ok { goal, observation := {
          witness, outcome := .unavailable
          explanation := "missing-witness: declaration not in checked environment" } }
    let constant ← mkConstWithFreshMVarLevels name
    Meta.check constant
    let actualType ← inferType constant
    unless ← isDefEq actualType proposition do
      return .ok { goal, observation := {
        witness, outcome := .failed
        explanation := "wrong-proposition: checked witness type is not definitionally equal to expectation" } }
    let constant ← instantiateMVars constant
    if constant.hasLevelMVar then
      return .error <| issue "open-witness" witness "Witness universe instantiation remains unresolved"
    checkWithKernel constant
    -- Kernel-check the conversion too, beyond Meta's unification decision.
    checkWithKernel <| mkApp (mkLambda `w BinderInfo.default proposition (mkConst ``True.intro)) constant
    let status ← Data.analyzeDeclaration info.name
    let assumptions ← collectAxioms info.name
    return .ok {
      goal, status := some status
      observation := {
        witness
        -- Normalize to the expected descriptor ONLY after actual Lean defeq.
        actualType := some goal
        outcome := if status.isProved then .passed else if status.isUnverified then .unavailable else .failed
        coverage := .dependencyClosure
        assumptions := assumptions.map Name.toString
        explanation := status.reportJson.compress } }
  catch ex =>
    return .error <| issue "invalid-expectation-or-witness" witness (← ex.toMessageData.toString)
  finally
    saved.restore (restoreInfo := true)

end Informal.Validation.NativeLean
