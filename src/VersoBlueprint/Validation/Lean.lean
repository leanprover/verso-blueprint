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

/-- Intrinsic content and the policy used to check the declaration's statement. -/
structure DeclarationClassification where
  statementKind : Data.NodeKind
  roles : Array Name

def classifyDeclarationKind (originalKind : Option ConstantKind) (proofValued propositionValued : Bool) :
    Option DeclarationClassification := do
  let kind ← originalKind
  if proofValued then
    return ⟨.theorem, if kind == .axiom then #[`statement] else #[`statement, `proof]⟩
  if propositionValued then
    return ⟨if kind == .axiom then .theorem else .definition, #[`statement]⟩
  return ⟨.definition, #[`implementation]⟩

def rolesForDeclarationKind (kind : Option ConstantKind) (proofValued propositionValued : Bool) :
    Array Name :=
  ((classifyDeclarationKind kind proofValued propositionValued).map (·.roles)).getD #[]

private def declarationClassification (info : ConstantInfo) : CoreM (Option DeclarationClassification) := do
  -- Module imports can expose theorems and definitions as axioms.
  let env ← getEnv
  let originalKind := if info.isAxiom then getOriginalConstKind? env info.name
    else some (ConstantKind.ofConstantInfo info)
  if originalKind.isNone then return none
  Meta.MetaM.run' do
    let proofValued ← Meta.isProp info.type
    let type ← Meta.whnf info.type
    return classifyDeclarationKind originalKind proofValued (type matches .sort .zero)

/-- The source projection and capture classify the same checked declaration. -/
def declarationRoles (info : ConstantInfo) : CoreM (Array Name) := do
  return ((← declarationClassification info).map (·.roles)).getD #[]

/-- Check the role inventory before a native answer can supply contracts to the evaluator. -/
def CheckedDeclaration.rolesAgree (value : CheckedDeclaration) : Bool :=
  let hasProof := value.roles.contains `proof
  value.roles.all (fun role => #[`statement, `proof, `implementation].contains role) &&
    value.body.proposition == hasProof && (!hasProof || value.roles.contains `statement) &&
    match value.kind with
    | none => value.roles.isEmpty && value.statement.outcome != .passed && value.body.outcome != .passed
    | some _ => !value.roles.isEmpty

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

/-- An unclassified declaration cannot supply a passing observation, even if a
body inspection succeeded. Keep its inspection and assumptions for diagnostics. -/
def CheckedDeclaration.ofClassification (witness : ObjectKey) (classification : Option DeclarationClassification)
    (status : Data.ProvedStatus) (assumptions : Array String) : CheckedDeclaration := Id.run do
  let some classification := classification | do
    let reason := if status.isMissing then "missing-declaration: no current checked declaration"
      else "unknown-declaration-kind: original declaration kind unavailable"
    let statement : CheckObservation := {
      validator := statementValidator, declaration := some witness, assumptions
      outcome := .unavailable, explanation := reason }
    return { declaration := witness, statement, body := { statement with validator := bodyValidator }, status }
  let kind := classification.statementKind
  let statementUnknown := status.hasUnverifiedType || (kind == .definition && status.hasUnverifiedProof)
  let statementGap := status.hasTypeGap || status.hasUnlocalizedSorry ||
    (kind == .definition && status.hasProofGap)
  return {
    declaration := witness, kind := some kind, roles := classification.roles
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
      proposition := classification.roles.contains `proof
      assumptions
      outcome := if status.isProved then .passed else if status.isUnverified then .unavailable else .failed
      coverage := if status.hasUnverifiedCoverage then .subject else .dependencyClosure
      explanation := status.reportJson.compress }
    status }

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
      | return .ok <| CheckedDeclaration.ofClassification witness none .missing #[]
    if info.isUnsafe then
      return .error <| issue "unsafe-declaration" witness "Unsafe declaration cannot supply trusted native validation"
    let constant := Lean.mkConst name (info.levelParams.map Level.param)
    checkWithKernel constant
    let status ← match session with
      | some session => liftM (session.analyzeDeclaration name)
      | none => Data.analyzeDeclaration name
    let assumptions ← collectAxioms name
    let assumptions := assumptions.map Name.toString
    return .ok <| CheckedDeclaration.ofClassification witness (← liftM <| declarationClassification info)
      status assumptions
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
