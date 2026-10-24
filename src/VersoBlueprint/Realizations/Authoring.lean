/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Existing

/-! Raw authoring uses the existing Environment extension. Only a query after
normal declaration/import elaboration materializes and admits the complete batch.
No validation observation, binding or derived Registry is persisted. -/

namespace Informal.Realizations.Authoring

open Lean Meta Elab Term Validation Translations NativeSource

private def orThrow (result : Except (Array Diagnostic) Unit) : CoreM Unit := do
  if let .error issues := result then throwError "{repr issues}"

/-- Configure this exact module, without enrolling its importers. -/
def configureProject (project : Name) : CoreM Unit := do
  orThrow (← Environment.configureAuthoringProject project)

/-- Retain a whole source envelope, not an admitted semantic model. -/
def stage (id : Name) (batch : Environment.AuthoredBatch) : CoreM Unit := do
  orThrow (← Environment.stageAuthored id batch)

/-- Name a separately authored proposition definition in this specification module. -/
def expectNative (id node expectedProposition : Name) : CoreM Unit := do
  orThrow (← Environment.stageNativeExpectation id node expectedProposition)

private abbrev MaterializeM := ExceptT (Array Diagnostic) TermElabM

private def reject (code subject message : String) (origins : Array Origin := #[]) : MaterializeM α :=
  ExceptT.mk (pure (.error #[{ code, subject, message, origins := canonical origins }]))

private def one (result : Except Diagnostic α) : MaterializeM α :=
  ExceptT.mk (pure (result.mapError (fun issue => #[issue])))

private def full (result : Except (Array Diagnostic) α) : MaterializeM α :=
  ExceptT.mk (pure result)

private def append (a b : Input) : Input := {
  nodes := a.nodes ++ b.nodes, documents := a.documents ++ b.documents
  objects := a.objects ++ b.objects, realizations := a.realizations ++ b.realizations
  translations := a.translations ++ b.translations, claims := a.claims ++ b.claims
  requirements := a.requirements ++ b.requirements, evidence := a.evidence ++ b.evidence
  bindingInputs := a.bindingInputs ++ b.bindingInputs }

private def contributionAt (origin : Origin) (family : Name) (index : Nat) (value : α) : Contribution α :=
  { origin := { origin with id := .num (origin.id ++ family) index }, value }

private def read (reader : System.FilePath → IO String) (key : DocumentKey)
    (origin : Origin) : MaterializeM Document := do
  let result ← liftM <| (try
    return Except.ok (← reader key.path)
    catch _ => return Except.error ())
  match result with
  | .ok text =>
    if blank text then reject "source-unavailable" key.path "Canonical source is empty" #[origin]
    else return { key, text }
  | .error _ => reject "source-unavailable" key.path "Cannot read canonical source" #[origin]

private def ownedDefinition (name : Name) (origin : Origin) (source : Document) : MaterializeM Unit := do
  let env ← getEnv
  let some (.defnInfo info) := env.checked.get.find? name
    | reject "invalid-expectation" name.toString "Expected a checked owned Prop definition, not an axiom" #[origin]
  unless info.safety == .safe do
    reject "invalid-expectation" name.toString "Expected a safe proposition definition" #[origin]
  let owner := (env.getModuleIdxFor? name).bind (fun index => env.header.moduleNames[index.toNat]?)
    |>.getD env.mainModule
  unless owner == origin.moduleName do
    reject "wrong-expectation-owner" name.toString "Specification belongs to another module" #[origin]
  let some ranges ← findDeclarationRanges? name
    | reject "source-association-unavailable" name.toString "Specification has no native declaration ranges" #[origin]
  let commands ← one (← NativeSource.parseSource name source.key.path source.text)
  unless (NativeSource.declarationAtRanges name source.text ranges.range ranges.selectionRange commands).isOk do
    reject "source-association-unavailable" name.toString "Specification has no unique original source declaration" #[origin]
  -- NativeLean.check below checks that this constant's type is Prop, and rejects
  -- open/concrete-universe/admitted expectations before matching the witness.

private def materialize (reader : System.FilePath → IO String) : MaterializeM Registry := do
  let state := Environment.informalExt.getState (← getEnv)
  let rawIssues := Environment.authoringRecordIssues state.authoringRecords
  let importedIssues := state.importedConflicts.map fun conflict => ({
    code := "imported-conflict", subject := conflict.label.toString, message := conflict.message } : Diagnostic)
  let _ ← full <| if (rawIssues ++ importedIssues).isEmpty then .ok () else .error (canonical (rawIssues ++ importedIssues))
  let records := state.authoringRecords.foldl (fun out record =>
    if out.any (fun previous => decide (previous = record)) then out else out.push record) #[]
  let mut defaults : Array (Environment.AuthoringRecord × Informal.Contributions.Record) := #[]
  for record in records do
    for id in record.defaults do
      let facts := state.factRecords.filter (fun fact => decide (fact.id = id)) |>.eraseDups.toArray
      unless facts.size == 1 do
        reject "default-identity" record.origin.id.toString "Missing or colliding selected default identity" #[record.origin]
      let some fact := facts[0]?
        | reject "default-identity" record.origin.id.toString "Missing selected default identity" #[record.origin]
      let some accepted := state.data.get? fact.label
        | reject "default-unavailable" fact.label.toString "Default node was not accepted" #[record.origin]
      unless fact.references.size == 1 && fact.proofReferences.isEmpty && accepted.externalRefs.size == 1 &&
          fact.id.moduleName == record.origin.moduleName && fact.id.producer == `blueprint.attribute &&
          fact.references[0]!.canonical == fact.id.subject && fact.references[0]!.present &&
          fact.references[0]!.origin == .blueprintAttr && fact.references[0]!.kind == .theorem &&
          accepted.externalRefs[0]!.canonical == fact.references[0]!.canonical &&
          accepted.externalRefs[0]!.provenance == fact.references[0]!.provenance do
        reject "unsupported-default" fact.label.toString "Selected identity does not match the accepted default association" #[record.origin]
      defaults := defaults.push (record, fact)
  for (record, fact) in defaults do
    let competitors := defaults.filter fun (other, selected) =>
      selected.label == fact.label && (other.project != record.project || decide (selected.id ≠ fact.id))
    unless competitors.isEmpty do
      reject "ambiguous-default" fact.label.toString "Competing default references" <|
        #[record.origin] ++ competitors.map (·.1.origin)
  for record in records do
    for (node, _) in record.nativeGoals do
      unless defaults.any (fun (owner, fact) => fact.label == node && owner.project == record.project) do
        reject "missing-native-default" node.toString "Expectation does not name an explicitly enrolled default in its project" #[record.origin]
  let mut input : Input := {}
  let mut observations : Array (Origin × RequirementKey × Observation) := #[]
  for (record, fact) in defaults do
    -- Only the old eligibility gate remains coupled to the old node layout.
    -- Native source/model preparation consumes typed source metadata directly.
    let selected ← one (← Existing.request record.project fact.label)
    unless selected.moduleName == fact.id.moduleName && selected.canonical == fact.id.subject do
      reject "default-identity" fact.label.toString "Source request differs from its selected producer" #[record.origin]
    let source ← one (← NativeSource.prepareDocumented selected reader)
    let some accepted := state.data.get? fact.label
      | reject "default-unavailable" fact.label.toString "Default metadata was not accepted" #[record.origin]
    let p ← one (source.realize record.origin
      (accepted.toNode.toConcept fact.label fact.label.toString) `lean `docstring)
    let specs := records.flatMap fun spec => spec.nativeGoals.mapIdx fun index (node, expected) =>
      (spec, index, node, expected)
    let specs := specs.filter fun (spec, _, node, _) => node == fact.label && spec.project == record.project
    let checked ← one (← NativeLean.checkDeclaration record.project p.witness)
    unless checked.declaration == p.witness do
      reject "wrong-check-object" fact.label.toString "Native observation belongs to another selected declaration" #[record.origin]
    let statementKey : RequirementKey := ⟨.declaration p.leanKey p.witness, `statement⟩
    let proofKey : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩
    let expectedKey : RequirementKey := ⟨.declaration p.leanKey p.witness, `expectedProof⟩
    let required := if specs.isEmpty then #[proofKey] else #[proofKey, expectedKey]
    let prepared := { p.input with
      realizations := p.input.realizations.map fun contribution =>
        if contribution.value.key != p.leanKey then contribution else
          { contribution with value := { contribution.value with
            declarations := #[{ object := p.witness, required }]
            facets := contribution.value.facets.map fun facet =>
              if facet.name == `statement then { facet with required := #[statementKey] }
              else if facet.name == `proof then { facet with required := #[proofKey] } else facet } }
      requirements := #[
        contributionAt record.origin `nativeRequirement 0 {
          key := statementKey, expected := .check NativeLean.statementValidator, coverage := .dependencyClosure },
        contributionAt record.origin `nativeRequirement 1 {
          key := proofKey, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }] }
    input := append input prepared
    observations := observations ++ #[
      ((contributionAt record.origin `nativeObservation 0 ()).origin, statementKey, .check checked.statement),
      ((contributionAt record.origin `nativeObservation 1 ()).origin, proofKey, .check checked.body)]
    for (spec, index, _, expected) in specs do
      let specDoc ← read reader ⟨p.witness.context, spec.origin.source⟩ spec.origin
      ownedDefinition expected spec.origin specDoc
      let (prepared, observation) ← one (← p.prepareValidation (mkCIdent expected) #[specDoc.key])
      -- The source model is already collected once above. Independent goals
      -- add their own contract/inputs; they never replace native validity.
      let prepared : Input := {
        documents := #[contributionAt spec.origin `specification index specDoc]
        requirements := prepared.requirements.mapIdx fun slot requirement =>
          contributionAt spec.origin `nativeRequirement (index + slot) { requirement.value with key := expectedKey }
        bindingInputs := (prepared.bindingInputs.filter (fun input =>
          input.value.name == NativeLean.expectedContextFor proofKey)).mapIdx fun slot input =>
          contributionAt spec.origin `nativeExpectedContext (index + slot)
            { input.value with name := NativeLean.expectedContextFor expectedKey } }
      input := append input prepared
      observations := observations.push ((contributionAt spec.origin `nativeObservation index ()).origin,
        expectedKey, .proof observation)
  for record in records do
    let batch := record.authored
    for index in [:batch.sources.size] do
      let document ← read reader batch.sources[index]! record.origin
      input := { input with documents := input.documents.push (contributionAt record.origin `document index document) }
    input := { input with
      objects := input.objects ++ batch.references.mapIdx (fun index (key, document) =>
        contributionAt record.origin `reference index {
          key, document, resolution := .unsupported
          explanation := "Authored reference: source-native resolver/checker is not connected" })
      realizations := input.realizations ++ batch.realizations.mapIdx (contributionAt record.origin `realization)
      translations := input.translations ++ batch.translations.mapIdx (contributionAt record.origin `translation)
      claims := input.claims ++ batch.claims.mapIdx (contributionAt record.origin `claim)
      requirements := input.requirements ++ batch.requirements.mapIdx (contributionAt record.origin `requirement) }
  let candidate ← full (admit input)
  for (origin, key, observation) in observations do
    let some binding := candidate.bindingFor key
      | reject "missing-binding" key.name.toString "Complete candidate has no native contract binding" #[origin]
    input := { input with evidence := input.evidence.push { origin, value := {
      id := origin.id, requirement := key, binding, observation } } }
  full (admit input)

/-- Materialize a complete current source snapshot and fresh native observations.
No intermediate model escapes; all Environment/elaborator state is restored. -/
def registry : TermElabM (Except (Array Diagnostic) Registry) := do
  let saved ← Term.saveState
  try
    -- This attempt reads each physical source once, even when multiple defaults
    -- or specifications share it. Keys/associations retain their authored paths.
    let snapshot ← liftM <| IO.mkRef (#[] : Array (System.FilePath × String))
    let reader (path : System.FilePath) : IO String := do
      let physical ← IO.FS.realPath path
      if let some (_, text) := (← snapshot.get).find? (·.1 == physical) then return text
      let text ← IO.FS.readFile physical
      snapshot.modify (·.push (physical, text))
      return text
    (materialize reader).run
  catch exception =>
    return .error #[{
      code := "materialization-failed", subject := "authoring"
      message := ← exception.toMessageData.toString }]
  finally
    saved.restore (restoreInfo := true)

end Informal.Realizations.Authoring
