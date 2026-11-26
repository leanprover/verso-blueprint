/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Elab.Term
import Lean.OriginalConstKind
import VersoBlueprint.Validation
import VersoBlueprint.ProvedStatus
import VersoBlueprint.Validation.Semantic
import VersoBlueprint.Validation.BindingEncoding

/-! Explicit native provider. Importing this module installs no completion path.
Independent-goal proof checks require a separately authored expectation; native
own-declaration checks establish neither that goal nor prose correspondence. -/

namespace Informal.Validation.NativeLean

open Lean Meta Elab Term Realizations

structure Checked where
  goal : Goal
  observation : ProofObservation
  status : Option Data.ProvedStatus := none
  semanticContext : Option String := none
  statementContext : Option String := none
  semanticDiagnostics : Array Diagnostic := #[]

private def issue (code : String) (witness : ObjectKey) (message : String) : Diagnostic :=
  { code, subject := witness.native, message }

private def nativeName (project : Name) (witness : ObjectKey) : Except Diagnostic Name := do
  if project.isAnonymous || witness.context != { language := `lean, project } || !witness.valid then
    throw <| issue "wrong-context" witness "Witness is outside the selected Lean project"
  let name := witness.native.toName
  if name.isAnonymous || name.toString != witness.native then
    throw <| issue "unsupported-identity" witness "Native object spelling is not a supported canonical Lean name"
  return name

/-- A provider tied to one immutable checked environment. Scope is explicit. -/
abbrev SemanticContext := ContentScope → Name → Array Name → CoreM (Except Diagnostic String)

/-- Share structural fingerprints only within this observation. -/
def newSemanticContext : CoreM SemanticContext := do
  let session ← Semantic.newSession
  return fun scope project roots => session.context project roots scope

/-- Standalone callers get a fresh session. Compiler/source provenance is not
statement content; native checking remains fresh on each capture. -/
def semanticContext (scope : ContentScope) (project : Name) (roots : Array Name) : CoreM (Except Diagnostic String) := do
  (← newSemanticContext) scope project roots

/-- Current native checking of a declaration's own statement/body. These are
named checks, not proof observations for an independently specified proposition
or an assessment of correspondence with prose. The caller supplies canonical
source association and binds these observations to the complete current model. -/
structure CheckedDeclaration where
  declaration : ObjectKey
  /-- Current checked declaration kind, when classification is available. -/
  kind : Option Data.NodeKind := none
  /-- Direct content roles derived from the checked declaration type. A theorem
  or proof-valued definition supplies a statement and proof; a definition whose
  value is itself a proposition supplies a statement; computational definitions
  supply only an implementation. -/
  roles : Array Name := #[]
  statement : CheckObservation
  body : CheckObservation
  status : Data.ProvedStatus

def CheckedDeclaration.assumptions (checked : CheckedDeclaration) : Array String :=
  checked.body.assumptions

/-- The original declaration kind and its checked type jointly determine roles.
Unavailable original kind information leaves the declaration unclassified. -/
def rolesForDeclarationKind (kind : Option ConstantKind) (proofValued propositionValued : Bool) :
    Array Name :=
  match kind with
  | none => #[]
  | some kind =>
    if proofValued then
      if kind == .axiom then #[`statement] else #[`statement, `proof]
    else if propositionValued then #[`statement] else #[`implementation]

/-- Classify native declaration content from the original checked type. This is
shared by capture and source projection so proof-valued definitions cannot be
mistaken for ordinary computations, and definitions of propositions do not
acquire fictitious proof roles. -/
def declarationRoles (info : Lean.ConstantInfo) : CoreM (Array Name) := do
  -- An ordinary module import may expose a theorem or definition as an axiom
  -- view. Recover its original kind without assuming access to its body.
  let kind ← if info.isAxiom then pure (getOriginalConstKind? (← getEnv) info.name)
    else pure (some (ConstantKind.ofConstantInfo info))
  let some kind := kind | return rolesForDeclarationKind none false false
  let (proofValued, propositionValued) ← Meta.MetaM.run' do
    let proofValued ← Meta.isProp info.type
    let type ← Meta.whnf info.type
    let propositionValued := match type with
      | .sort .zero => true
      | _ => false
    pure (proofValued, propositionValued)
  return rolesForDeclarationKind (some kind) proofValued propositionValued

/-- Prepare shared closure coverage for trusted native candidates. Request
identity, kernel checks, roles and assumptions are still checked separately
for each witness when its provider runs. -/
def prepareDeclarations (session : Data.SorryInspectionSession)
    (requests : Array (Name × ObjectKey)) : CoreM Unit := do
  let env ← getEnv
  let mut seen : NameSet := {}
  let mut roots := #[]
  for (project, witness) in requests do
    let .ok name := nativeName project witness | continue
    if seen.contains name then continue
    let some info := env.checked.get.find? name | continue
    if info.isUnsafe then continue
    if let .axiomInfo _ := info then
      if let .absent := Data.ConstantInfo.blueprintBodyAccess env info then continue
    seen := seen.insert name
    roots := roots.push name
  session.prepare roots

/-- Check the original checked environment, including declaration universes and
conservative reachable-body coverage. No expected goal is synthesized from the
witness; independent-goal proof checking remains `check` below. -/
def checkDeclaration (project : Name) (witness : ObjectKey)
    (session : Option Data.SorryInspectionSession := none) :
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
            validator := statementValidator, declaration := some witness, outcome := .unavailable
            explanation := "missing-declaration: no current checked declaration" }
          body := {
            validator := bodyValidator, declaration := some witness, outcome := .unavailable
            explanation := "missing-declaration: no current checked declaration" }
          status := .missing }
    if info.isUnsafe then
      return .error <| issue "unsafe-declaration" witness "Unsafe declaration cannot supply trusted native validation"
    let constant := Lean.mkConst name (info.levelParams.map Level.param)
    checkWithKernel constant
    let status ← match session with
      | some session => liftM (session.analyzeDeclaration name)
      | none => Data.analyzeDeclaration name
    let assumptions ← collectAxioms name
    let assumptions := assumptions.map Name.toString
    let roles ← liftM <| declarationRoles info
    let proposition := roles.contains `proof
    let kind : Data.NodeKind := if proposition || (status.isAxiomLike && roles.contains `statement) then
        .theorem else .definition
    let statementUnknown := status.hasUnverifiedType || (kind == .definition && status.hasUnverifiedProof)
    let statementGap := status.hasTypeGap || status.hasUnlocalizedSorry ||
      (kind == .definition && status.hasProofGap)
    return .ok {
      declaration := witness, kind := if roles.isEmpty then none else some kind, roles
      statement := {
        validator := statementValidator
        declaration := some witness
        assumptions
        outcome := if !status.blocksStatementCompletion kind then .passed
          else if statementUnknown && !statementGap then .unavailable else .failed
        coverage := if statementUnknown then .subject else .dependencyClosure
        explanation := status.reportJson.compress }
      body := {
        validator := bodyValidator
        declaration := some witness
        proposition
        assumptions
        outcome := if status.isProved then .passed else if status.isUnverified then .unavailable else .failed
        coverage := if status.hasUnverifiedCoverage then .subject else .dependencyClosure
        explanation := status.reportJson.compress }
      status }
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
    (documents : Array DocumentKey := #[])
    (semantics : SemanticContext := semanticContext)
    (session : Option Data.SorryInspectionSession := none) : TermElabM (Except Diagnostic Checked) := do
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
    let session ← match session with
      | some session => pure session
      | none => liftM Data.newSorryInspectionSession
    let dependencies := proposition.getUsedConstants
    unless ← liftM (session.checkDependencies dependencies) do
      return .error <| issue "unverified-expectation" witness
        "Expected proposition has admitted or unavailable dependencies"
    -- This is an opaque structural fingerprint, not the equality algorithm. It
    -- comes from the independently checked expectation, never the witness type.
    let goal : Goal := { context := witness.context, fingerprint := Semantic.fingerprint proposition, documents }
    let semanticResult ← semantics .implementation project (#[name] ++ dependencies)
    let (context, semanticDiagnostics) := match semanticResult with
      | .ok context => (some context, #[])
      | .error diagnostic => (none, #[diagnostic])
    let statementResult ← semantics .statement project (#[name] ++ dependencies)
    let statementContext := statementResult.toOption
    let semanticDiagnostics := (semanticDiagnostics ++ (match statementResult with
      | .ok _ => #[] | .error diagnostic => #[diagnostic])).toList.eraseDups.toArray
    let some info := (← getEnv).checked.get.find? name
      | return .ok { goal, semanticContext := context, statementContext, semanticDiagnostics, observation := {
          witness, outcome := .unavailable
          explanation := "missing-witness: declaration not in checked environment" } }
    let constant ← mkConstWithFreshMVarLevels name
    Meta.check constant
    let actualType ← inferType constant
    unless ← isDefEq actualType proposition do
      return .ok { goal, semanticContext := context, statementContext, semanticDiagnostics, observation := {
        witness, outcome := .failed
        explanation := "wrong-proposition: checked witness type is not definitionally equal to expectation" } }
    let constant ← instantiateMVars constant
    if constant.hasLevelMVar then
      return .error <| issue "open-witness" witness "Witness universe instantiation remains unresolved"
    checkWithKernel constant
    -- Kernel-check the conversion too, beyond Meta's unification decision.
    checkWithKernel <| mkApp (mkLambda `w BinderInfo.default proposition (mkConst ``True.intro)) constant
    let status ← liftM (session.analyzeDeclaration info.name)
    let assumptions ← collectAxioms info.name
    return .ok {
      goal, status := some status, semanticContext := context, statementContext, semanticDiagnostics
      observation := {
        witness
        -- Normalize to the expected descriptor ONLY after actual Lean defeq.
        actualType := some goal
        outcome := if status.isProved then .passed else if status.isUnverified then .unavailable else .failed
        coverage := if status.hasUnverifiedCoverage then .subject else .dependencyClosure
        assumptions := assumptions.map Name.toString
        explanation := status.reportJson.compress } }
  catch ex =>
    return .error <| issue "invalid-expectation-or-witness" witness (← ex.toMessageData.toString)
  finally
    saved.restore (restoreInfo := true)

end Informal.Validation.NativeLean
