/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Elab.Term
import VersoBlueprint.Validation
import VersoBlueprint.ProvedStatus

/-! Explicit native provider. Importing this module installs no completion path.
Independent-goal proof checks require a separately authored expectation; native
own-declaration checks establish neither that goal nor prose correspondence. -/

namespace Informal.Validation.NativeLean

open Lean Meta Elab Term Realizations

structure Checked where
  goal : Goal
  observation : ProofObservation
  status : Option Data.ProvedStatus := none

private def issue (code : String) (witness : ObjectKey) (message : String) : Diagnostic :=
  { code, subject := witness.native, message }

private def nativeName (project : Name) (witness : ObjectKey) : Except Diagnostic Name := do
  if project.isAnonymous || witness.context != { language := `lean, project } || !witness.valid then
    throw <| issue "wrong-context" witness "Witness is outside the selected Lean project"
  let name := witness.native.toName
  if name.isAnonymous || name.toString != witness.native then
    throw <| issue "unsupported-identity" witness "Native object spelling is not a supported canonical Lean name"
  return name

def statementValidator : Name := `lean.declarationStatement
def bodyValidator : Name := `lean.declarationCompleteness

/-- Current native checking of a declaration's own statement/body. These are
named checks, not proof observations for an independently specified proposition
or an assessment of correspondence with prose. The caller supplies canonical
source association and binds these observations to the complete current model. -/
structure CheckedDeclaration where
  declaration : ObjectKey
  statement : CheckObservation
  body : CheckObservation
  status : Data.ProvedStatus
  assumptions : Array String := #[]

/-- Check the original checked environment, including declaration universes and
conservative reachable-body coverage. No expected goal is synthesized from the
witness; independent-goal proof checking remains `check` below. -/
def checkDeclaration (project : Name) (witness : ObjectKey) :
    TermElabM (Except Diagnostic CheckedDeclaration) := do
  let saved ← Term.saveState
  try
    let name ← match nativeName project witness with
      | .ok name => pure name
      | .error diagnostic => return .error diagnostic
    let some info := (← getEnv).checked.get.find? name
      | return .ok {
          declaration := witness
          statement := {
            validator := statementValidator, outcome := .unavailable
            explanation := "missing-declaration: no current checked declaration" }
          body := {
            validator := bodyValidator, outcome := .unavailable
            explanation := "missing-declaration: no current checked declaration" }
          status := .missing }
    if info.isUnsafe then
      return .error <| issue "unsafe-declaration" witness "Unsafe declaration cannot supply trusted native validation"
    let constant := Lean.mkConst name (info.levelParams.map Level.param)
    checkWithKernel constant
    let status ← Data.analyzeDeclaration name
    let assumptions ← collectAxioms name
    let kind : Data.NodeKind := match info with
      | .thmInfo _ => .theorem
      | _ => .definition
    let statementUnknown := status.hasUnverifiedType || (kind == .definition && status.hasUnverifiedProof)
    let statementGap := status.hasTypeGap || status.hasUnlocalizedSorry ||
      (kind == .definition && status.hasProofGap)
    return .ok {
      declaration := witness
      statement := {
        validator := statementValidator
        outcome := if !status.blocksStatementCompletion kind then .passed
          else if statementUnknown && !statementGap then .unavailable else .failed
        coverage := if statementUnknown then .subject else .dependencyClosure
        explanation := status.reportJson.compress }
      body := {
        validator := bodyValidator
        outcome := if status.isProved then .passed else if status.isUnverified then .unavailable else .failed
        coverage := if status.hasUnverifiedCoverage then .subject else .dependencyClosure
        explanation := status.reportJson.compress }
      status, assumptions := assumptions.map Name.toString }
  catch exception =>
    return .error <| issue "invalid-native-declaration" witness (← exception.toMessageData.toString)
  finally
    saved.restore (restoreInfo := true)

/-- Check in the current environment, without retaining elaborator/environment
changes. Only closed, monomorphic expected propositions are supported here;
universe-polymorphic contracts need an explicit later API. Binders *inside* a
closed proposition and concrete universe/package instantiations are preserved.
The logical project is selected by the caller, not inferred from module names. -/
def check (project : Name) (witness : ObjectKey) (expected : Syntax)
    (documents : Array DocumentKey := #[]) : TermElabM (Except Diagnostic Checked) := do
  let saved ← Term.saveState
  try
    let name ← match nativeName project witness with
      | .ok name => pure name
      | .error diagnostic => return .error diagnostic
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
