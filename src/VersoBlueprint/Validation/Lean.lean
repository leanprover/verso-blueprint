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
  semanticContext : Option String := none

private def issue (code : String) (witness : ObjectKey) (message : String) : Diagnostic :=
  { code, subject := witness.native, message }

private def nativeName (project : Name) (witness : ObjectKey) : Except Diagnostic Name := do
  if project.isAnonymous || witness.context != { language := `lean, project } || !witness.valid then
    throw <| issue "wrong-context" witness "Witness is outside the selected Lean project"
  let name := witness.native.toName
  if name.isAnonymous || name.toString != witness.native then
    throw <| issue "unsupported-identity" witness "Native object spelling is not a supported canonical Lean name"
  return name

-- Compile-time source of the actual provider build, not an independently
-- versioned artifact. All included files are already module dependencies.
private def providerSources : Array (String × String) := #[
  ("Validation/Lean.lean", include_str "Lean.lean"),
  ("Validation.lean", include_str "../Validation.lean"),
  ("ProvedStatus.lean", include_str "../ProvedStatus.lean"),
  ("SorryAnalysis.lean", include_str "../SorryAnalysis.lean"),
  ("Data.lean", include_str "../Data.lean"),
  ("ConceptMetadata.lean", include_str "../ConceptMetadata.lean"),
  ("SourcePayload.lean", include_str "../SourcePayload.lean")]

private def declarationShape (info : ConstantInfo) : Json × Array Name :=
  match info with
  | .axiomInfo _ => (toJson "axiom", #[])
  | .thmInfo _ => (toJson "theorem", #[])
  | .opaqueInfo value => (toJson ("opaque", reprStr value.all), value.all.toArray)
  | .defnInfo value =>
    let hints := match value.hints with
      | .abbrev => toJson "abbrev"
      | .opaque => toJson "opaque"
      | .regular height => toJson ("regular", height.toNat)
    let safety := match value.safety with
      | .safe => "safe"
      | .unsafe => "unsafe"
      | .partial => "partial"
    (toJson ("definition", hints, safety, reprStr value.all), value.all.toArray)
  | .inductInfo value =>
    (toJson ("inductive", reprStr value.all, reprStr value.ctors,
      value.numParams, value.numIndices, value.numNested, value.isRec, value.isReflexive),
      value.all.toArray ++ value.ctors.toArray)
  | .ctorInfo value =>
    (toJson ("constructor", reprStr value.induct, value.cidx, value.numParams, value.numFields), #[value.induct])
  | .recInfo value =>
    let rules := value.rules.toArray.map fun rule => (reprStr rule.ctor, rule.nfields, reprStr rule.rhs)
    (toJson ("recursor", reprStr value.all, value.numParams, value.numIndices,
      value.numMotives, value.numMinors, value.k, rules),
      value.all.toArray ++ value.rules.toArray.flatMap (fun rule => #[rule.ctor] ++ rule.rhs.getUsedConstants))
  | .quotInfo value =>
    let kind := match value.kind with
      | .type => "type"
      | .ctor => "constructor"
      | .lift => "lift"
      | .ind => "induction"
    (toJson ("quotient", kind), #[])

/-- Exact current checked type/body closure, compiler identity and provider
source. Imported semantic changes affect this input even when local bytes and
constant names do not change. Hidden bodies yield an explicit unavailable input;
cached footprints never stand in for the missing semantics. -/
def semanticContext (project : Name) (roots : Array Name) : CoreM (Except Diagnostic String) := do
  if project.isAnonymous || roots.isEmpty then
    return .error {
      code := "invalid-semantic-context", subject := "native"
      message := "Semantic capture requires explicit project and declaration roots" }
  let env ← getEnv
  let mut todo := roots
  let mut seen : NameSet := {}
  let mut entries : Array (String × Json) := #[]
  while !todo.isEmpty do
    let name := todo.back!
    todo := todo.pop
    if seen.contains name then continue
    seen := seen.insert name
    let some info := env.checked.get.find? name
      | return .error {
          code := "semantic-context-unavailable", subject := name.toString
          message := "Semantic dependency is not in the current checked environment" }
    let (body, dependencies) ← match Data.ConstantInfo.blueprintBodyAccess env info with
      | .available value => pure (toJson (reprStr value), value.getUsedConstants)
      | .absent => pure (Json.null, #[])
      | .unavailable => return .error {
          code := "semantic-context-unavailable", subject := name.toString
          message := "Imported semantic dependency body is unavailable" }
    let (shape, extra) := declarationShape info
    todo := todo ++ info.type.getUsedConstants ++ dependencies ++ extra
    entries := entries.push (reprStr name, Json.mkObj [
      ("name", toJson (reprStr name)), ("universes", toJson (reprStr info.levelParams)),
      ("type", toJson (reprStr info.type)), ("body", body),
      ("unsafe", toJson info.isUnsafe), ("shape", shape)])
  return .ok <| (Json.mkObj [
    ("project", toJson (reprStr project)), ("compiler", toJson (Lean.versionString, Lean.githash)),
    ("providerSources", toJson providerSources),
    ("declarations", toJson ((entries.qsort (fun a b => a.1 < b.1)).map (·.2)))]).compress

/-- Current native checking of a declaration's own statement/body. These are
named checks, not proof observations for an independently specified proposition
or an assessment of correspondence with prose. The caller supplies canonical
source association and binds these observations to the complete current model. -/
structure CheckedDeclaration where
  declaration : ObjectKey
  statement : CheckObservation
  body : CheckObservation
  status : Data.ProvedStatus

def CheckedDeclaration.assumptions (checked : CheckedDeclaration) : Array String :=
  checked.body.assumptions

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
    let status ← Data.analyzeDeclaration name
    let assumptions ← collectAxioms name
    let assumptions := assumptions.map Name.toString
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
        declaration := some witness
        assumptions
        outcome := if !status.blocksStatementCompletion kind then .passed
          else if statementUnknown && !statementGap then .unavailable else .failed
        coverage := if statementUnknown then .subject else .dependencyClosure
        explanation := status.reportJson.compress }
      body := {
        validator := bodyValidator
        declaration := some witness
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
    let context := (← semanticContext project (#[name] ++ proposition.getUsedConstants)).toOption
    let some info := (← getEnv).checked.get.find? name
      | return .ok { goal, semanticContext := context, observation := {
          witness, outcome := .unavailable
          explanation := "missing-witness: declaration not in checked environment" } }
    let constant ← mkConstWithFreshMVarLevels name
    Meta.check constant
    let actualType ← inferType constant
    unless ← isDefEq actualType proposition do
      return .ok { goal, semanticContext := context, observation := {
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
      goal, status := some status, semanticContext := context
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
