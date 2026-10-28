/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment
import VersoBlueprint.Realizations.NativeSource
import VersoBlueprint.Realizations.Projection
import VersoBlueprint.Realizations.Report

/-! Capture ordinary, keyed Blueprint sources after their owning modules have
been built. Raw registrations remain the only persistent store. This boundary
collects the complete model, admits it, binds fresh checks to that same snapshot,
and admits the final result. A failed admission never returns a partial registry.
-/

namespace Informal.Realizations.Capture

open Lean Meta Elab Term Validation Translations SourceData

abbrev CaptureM := ExceptT (Array Diagnostic) TermElabM

private def reject [Monad m] (code subject message : String) (origins : Array Origin := #[]) : ExceptT (Array Diagnostic) m α :=
  ExceptT.mk (pure (.error #[{ code, subject, message, origins := canonical origins }]))

private def one [Monad m] (result : Except Diagnostic α) : ExceptT (Array Diagnostic) m α :=
  ExceptT.mk (pure (result.mapError (fun issue => #[issue])))

private def full [Monad m] (result : Except (Array Diagnostic) α) : ExceptT (Array Diagnostic) m α :=
  ExceptT.mk (pure result)

/-- The collector is one producer, with unambiguous typed boundaries for each
semantic slot. Query module/options and registration order are not identities. -/
private def contribution (family : Name) (key : Json) (value : α) : Contribution α :=
  { origin := {
      id := Name.mkSimple (toJson (Vir.nameKey family, key)).compress
      moduleName := `VersoBlueprint.Realizations.Capture
      source := "ordinary Blueprint source collection" }, value }

private def authoredContribution (origin : Origin) (family : Name) (index : Nat) (value : α) : Contribution α :=
  { origin := { origin with id := Name.mkSimple (toJson (Vir.nameKey origin.id, Vir.nameKey family, index)).compress }, value }

/-- Resolution failure stays an edge diagnostic, never a manufactured theorem status. -/
structure SelectedUse where
  source : Name
  /-- Context selected for the native target contract, not the source language. -/
  context : Option Context
  realization : Option Name
  facet : Name
  reference : Data.UseRef
  selected : Except Diagnostic (Array RequirementKey)
  deriving Repr

structure Snapshot where
  registry : Registry
  uses : Array SelectedUse
  /-- Source/provider diagnostics are distinct from native proof outcomes. -/
  diagnostics : Array Diagnostic
  /-- Fresh native classification for inventory only; Registry remains completion authority. -/
  nativeChecks : Array NativeLean.CheckedDeclaration := #[]

/-- Derive a consumer view from the same admitted snapshot. No source/status
fallbacks, new checker invocation or second dependency evaluator occur here. -/
def Snapshot.assessmentFor (snapshot : Snapshot) (label : Name) : NodeAssessment := Id.run do
  let registry := snapshot.registry
  let key : RealizationKey := ⟨label, `lean⟩
  let model := (registry.realization? key).filter (·.context.language == `lean)
  let declarations := model.map (·.declarations) |>.getD #[]
  let hasNativeDeclarations := !declarations.isEmpty
  let locallyComplete (name validator : Name) := hasNativeDeclarations && declarations.all fun declaration =>
    let requirement : RequirementKey := ⟨.declaration key declaration.object, name⟩
    (registry.requirement? requirement).any (fun value =>
      value.expected == .check validator && value.coverage == .dependencyClosure) &&
      (registry.localResult requirement).complete
  let uses := snapshot.uses.filter (·.source == label)
  let selected := uses.filter fun use => use.realization.all (· == `lean) &&
    model.any (fun model => use.context == some model.context)
  let dependenciesComplete (statementOnly : Bool) :=
    (selected.filter fun use => !statementOnly || use.facet == `statement).all fun use =>
      match use.selected with
      | .error _ => false
      | .ok keys => !keys.isEmpty && keys.all (fun key => (registry.resultForRequirement key).complete)
  let sourceDocuments := (registry.realizations.filter (·.key.node == label)).flatMap (·.facets.flatMap (·.documents))
  let sourceSubjects := (registry.realizations.filter (·.key.node == label)).flatMap fun realization =>
    realization.facets.map fun facet =>
      (BindingEncoding.subject (.facet realization.key facet.name)).compress
  let objects := declarations.map (·.object)
  let diagnostics := snapshot.diagnostics.filter fun diagnostic => diagnostic.subject == label.toString ||
    objects.any (·.native == diagnostic.subject) || sourceDocuments.any (·.path == diagnostic.subject) ||
    sourceSubjects.contains diagnostic.subject
  return {
    hasNativeDeclarations
    hasAxiomLike := snapshot.nativeChecks.any (fun checked => objects.contains checked.declaration && checked.status.isAxiomLike)
    nativeStatementComplete := locallyComplete `statement NativeLean.statementValidator
    nativeProofComplete := locallyComplete `proof NativeLean.bodyValidator
    requiredComplete := hasNativeDeclarations && (registry.resultFor (.realization key)).complete
    selectedLeanUseCount := selected.size
    statementDependenciesComplete := dependenciesComplete true
    proofDependenciesComplete := dependenciesComplete false
    details := Json.mkObj [
      ("assessment", Report.ofNode registry label),
      ("uses", toJson (uses.map fun use => Json.mkObj [
        ("source", toJson use.source), ("targetContext", toJson use.context),
        ("realization", toJson use.realization), ("facet", toJson use.facet),
        ("reference", toJson use.reference), ("selection", toJson use.selected)])),
      ("sourceDiagnostics", toJson diagnostics)] }

private structure Collected where
  input : Input := {}
  observations : Array (Origin × RequirementKey × Observation) := #[]
  diagnostics : Array Diagnostic := #[]
  uses : Array UseDeclaration := #[]
  nativeChecks : Array NativeLean.CheckedDeclaration := #[]

private def recordObservation (collected : Collected) (key : RequirementKey) (observation : Observation) : Collected :=
  { collected with observations := collected.observations.push ((contribution `observation (BindingEncoding.requirementKey key) ()).origin, key, observation) }

/-- Lossless view of the fields consumed by capture; not another store. -/
structure Raw where
  nodes : Array (Name × Environment.RegisteredNode)
  pending : NameSet
  facts : List Contributions.Record
  authored : Array Environment.AuthoringRecord
  initialIssues : Array Diagnostic

def Raw.ofState (state : Environment.State) : Raw := {
  nodes := state.data.toArray
  pending := state.pendingNodes.toArray.foldl (fun names (name, _) => names.insert name) {}
  facts := state.factRecords
  authored := state.authoringRecords
  initialIssues := Environment.authoringRecordIssues state.authoringRecords ++ state.importedConflicts.map fun conflict =>
    { code := "imported-conflict", subject := conflict.label.toString, message := conflict.message } }

structure NativeRequest where
  context : Context
  name : Name
  association : NativeAssociation
  deriving Inhabited

structure InlineRequest where
  context : Context
  name : Name
  source : FacetSource
  deriving Inhabited

structure CheckRequest where
  project : Name
  witness : ObjectKey
  deriving Inhabited

structure SpecificationRequest where
  expected : Name
  origin : Origin
  document : Nat
  deriving Inhabited

/-- The goal's documents depend on earlier owning-source results and earlier
authored references. The recipe resolves them at this exact record position. -/
structure ExpectedRequest where
  node : Name
  expected : Name
  project : Name
  origin : Origin
  specification : Nat
  nativeSources : Array Nat
  inlineSources : Array Nat
  priorAuthoredRecords : Nat
  deriving Inhabited

structure SourceStep where
  source : FacetSource
  document : Nat
  documented : Option (Except Diagnostic Nat) := none
  deriving Inhabited

structure DeclarationStep where
  name : Name
  native : Array Nat := #[]
  inline : Array Nat := #[]
  check : Nat
  deriving Inhabited

structure RealizationStep where
  key : RealizationKey
  sources : Array SourceStep
  associations : Array NativeAssociation
  declarations : Array DeclarationStep
  deriving Inhabited

structure NodeStep where
  label : Name
  accepted : Environment.RegisteredNode
  realizations : Array RealizationStep

structure AuthoredStep where
  record : Environment.AuthoringRecord
  goals : Array Nat
  documents : Array Nat

/-- Typed request inventories and an ordered assembly recipe. Handles are local
array positions, never producer identities. Structural errors are deliberately
checked by the recipe, not eagerly returned ahead of earlier provider failures. -/
structure Plan where
  raw : Raw
  documents : Array DocumentKey := #[]
  native : Array NativeRequest := #[]
  inline : Array InlineRequest := #[]
  documented : Array NativeRequest := #[]
  checks : Array CheckRequest := #[]
  specifications : Array SpecificationRequest := #[]
  expected : Array ExpectedRequest := #[]
  ordinary : Array NodeStep := #[]
  authored : Array AuthoredStep := #[]

def plan (raw : Raw) : Plan := Id.run do
  let mut result : Plan := { raw }
  for (label, accepted) in raw.nodes do
    let records := raw.facts.reverse.toArray.filter (·.label == label)
    let mut realizations := #[]
    for key in canonical (accepted.sources.map (·.destination.realization) ++ accepted.nativeAssociations.map (·.realization)) do
      let sources := accepted.sources.filter (·.destination.realization == key)
      let associations := accepted.nativeAssociations.filter (·.realization == key)
      -- Invalid contexts are rejected before any of these jobs execute.
      let context := (canonical (sources.map (·.context) ++ associations.map (·.context)))[0]?.getD default
      let mut sourceSteps := #[]
      for source in sources do
        let document := result.documents.size
        result := { result with documents := result.documents.push source.document }
        let mut documented := none
        if let .prose _ := source.payload then
          let owners := records.filter fun record => record.id.producer == `blueprint.attribute &&
            record.source.isSome && record.source == source.source.location
          if !owners.isEmpty then
            -- Only uniqueness matters here; ambiguous associations are rejected.
            let selected := (owners.flatMap (·.nativeAssociations)).toList.eraseDups.toArray
            if selected.size != 1 then
              documented := some (.error {
                code := "ambiguous-docstring", subject := label.toString,
                message := "Attribute prose requires one exact owning native association" })
            else
              documented := some (.ok result.documented.size)
              let association := selected[0]!
              result := { result with documented := result.documented.push {
                context := association.context, name := association.reference.canonical, association } }
        sourceSteps := sourceSteps.push { source, document, documented }
      let mut declarations := #[]
      for name in nativeNames associations sources do
        let mut native := #[]
        let mut inline := #[]
        for association in associations.filter (·.reference.canonical == name) do
          native := native.push result.native.size
          result := { result with native := result.native.push { context, name, association } }
        for source in sources do
          if let .leanInline code := source.payload then
            if (code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)).contains name then
              inline := inline.push result.inline.size
              result := { result with inline := result.inline.push { context, name, source } }
        declarations := declarations.push { name, native, inline, check := result.checks.size }
        result := { result with checks := result.checks.push { project := context.project, witness := ⟨context, name.toString⟩ } }
      realizations := realizations.push { key, sources := sourceSteps, associations, declarations }
    result := { result with ordinary := result.ordinary.push { label, accepted, realizations } }
  let records := raw.authored.foldl (fun out record =>
    if out.any (fun previous => decide (previous = record)) then out else out.push record) #[]
  for record in records do
    let mut goals := #[]
    for (node, expected) in record.nativeGoals do
      let document := result.documents.size
      result := { result with documents := result.documents.push ⟨⟨`lean, record.project⟩, record.origin.source⟩ }
      let specification := result.specifications.size
      result := { result with specifications := result.specifications.push { expected, origin := record.origin, document } }
      let declarations := (result.ordinary.filter (·.label == node)).flatMap fun node =>
        (node.realizations.filter (·.key.name == `lean)).flatMap (·.declarations)
      goals := goals.push result.expected.size
      result := { result with expected := result.expected.push {
        node, expected, project := record.project, origin := record.origin, specification
        nativeSources := declarations.flatMap (·.native), inlineSources := declarations.flatMap (·.inline)
        priorAuthoredRecords := result.authored.size } }
    let mut documents := #[]
    for document in record.authored.sources do
      documents := documents.push result.documents.size
      result := { result with documents := result.documents.push document }
    result := { result with authored := result.authored.push { record, goals, documents } }
  return result

structure ResultEntry (p : Plan) (request : Type) (α : Type) where
  handle : Nat
  result : α

structure SpecificationResult where
  document : Document
  result : Except (Array Diagnostic) Unit

structure ExpectedResult where
  witness : ObjectKey
  documents : Array DocumentKey
  result : Except Diagnostic NativeLean.Checked

/-- Results are indexed by the exact plan, not portable/reusable receipts.
Pure evaluation checks association and shape, not authenticity of supplied facts. -/
structure Observations (p : Plan) where
  documents : Array (ResultEntry p DocumentKey (Document × Array Diagnostic)) := #[]
  native : Array (ResultEntry p NativeRequest (Except Diagnostic NativeSource.Prepared)) := #[]
  inline : Array (ResultEntry p InlineRequest (Except Diagnostic NativeSource.Prepared)) := #[]
  documented : Array (ResultEntry p NativeRequest (Except Diagnostic NativeSource.Documented)) := #[]
  checks : Array (ResultEntry p CheckRequest (Except Diagnostic NativeLean.CheckedDeclaration)) := #[]
  specifications : Array (ResultEntry p SpecificationRequest SpecificationResult) := #[]
  expected : Array (ResultEntry p ExpectedRequest ExpectedResult) := #[]

/-- The same assembly recipe is interpreted once with real providers and once
with pure table lookups. No admission happens in the provider interpreter. -/
private structure Providers (m : Type → Type) where
  document : Nat → ExceptT (Array Diagnostic) m (Document × Array Diagnostic)
  native : Nat → ExceptT (Array Diagnostic) m (Except Diagnostic NativeSource.Prepared)
  inline : Nat → ExceptT (Array Diagnostic) m (Except Diagnostic NativeSource.Prepared)
  documented : Nat → ExceptT (Array Diagnostic) m (Except Diagnostic NativeSource.Documented)
  check : Nat → ExceptT (Array Diagnostic) m (Except Diagnostic NativeLean.CheckedDeclaration)
  specification : Nat → Document → ExceptT (Array Diagnostic) m (Except (Array Diagnostic) Unit)
  expected : Nat → ObjectKey → Array DocumentKey → ExceptT (Array Diagnostic) m (Except Diagnostic NativeLean.Checked)

private def readDocument (reader : System.FilePath → IO String) (key : DocumentKey) :
    TermElabM (Document × Array Diagnostic) := do
  try
    let text ← reader key.path
    if blank text then
      return ({ key, text }, #[{ code := "source-unavailable", subject := key.path, message := "Canonical source is empty" }])
    return ({ key, text }, #[])
  catch _ =>
    -- An unavailable document is explicit empty content, never invented source.
    -- The pure evaluator blocks a required subject that needs these bytes.
    return ({ key, text := "" }, #[{ code := "source-unavailable", subject := key.path, message := "Cannot read canonical source" }])

private def request (context : Context) (name : Name) (association : Option NativeAssociation)
    (source : Option FacetSource) : CoreM (Except Diagnostic NativeSource.Request) := do
  let fail (message : String) : Except Diagnostic NativeSource.Request := .error {
    code := "source-association-unavailable", subject := name.toString, message }
  let env ← getEnv
  unless (env.checked.get.find? name).isSome do
    return .error {
      code := "missing-declaration", subject := name.toString
      message := "Declaration is not in the current checked environment" }
  let owner := (env.getModuleIdxFor? name).bind (fun index => env.header.moduleNames[index.toNat]?)
    |>.getD env.mainModule
  if let some moduleName := association.bind (·.reference.provenance.moduleName?) then
    if moduleName != owner then return fail "Stored native module disagrees with current declaration owner"
  let path ← match source.map (·.document.path) <|> association.bind (·.reference.provenance.sourcePath?) with
    | some path => pure path
    | none =>
      if owner == env.mainModule then pure (← getFileName)
      else
        let some path ← (← getSrcSearchPath).findModuleWithExt "lean" owner
          | return fail "Owning module source path is unavailable"
        pure path.toString
  return .ok {
    project := context.project, canonical := name, moduleName := owner, sourcePath := path
    range? := association.bind (·.reference.range?)
    selectionRange? := association.bind (·.reference.selectionRange?) }

private def prepareNative [Monad m] (providers : Providers m) (step : DeclarationStep) :
    ExceptT (Array Diagnostic) m (Except (Array Diagnostic) NativeSource.Prepared) := do
  let name := step.name
  let mut prepared := #[]
  let mut issues := #[]
  for handle in step.native do
    match ← providers.native handle with
    | .error issue => issues := issues.push issue
    | .ok value => prepared := prepared.push value
  for handle in step.inline do
    match ← providers.inline handle with
    | .error issue => issues := issues.push issue
    | .ok value => prepared := prepared.push value
  if !issues.isEmpty then return .error (canonical issues)
  let some first := prepared[0]?
    | return .error #[{ code := "source-association-unavailable", subject := name.toString, message := "No owning source association" }]
  if prepared.any (fun other => other.document != first.document || other.ranges.range != first.ranges.range ||
      other.ranges.selectionRange != first.ranges.selectionRange ||
      other.moduleName != first.moduleName || other.declaration != first.declaration) then
    return .error #[{ code := "ambiguous-source", subject := name.toString, message := "Competing owning sources for the same declaration" }]
  return .ok first

private def collectOrdinary [Monad m] (providers : Providers m) (p : Plan) : ExceptT (Array Diagnostic) m Collected := do
  let mut collected : Collected := {}
  for node in p.ordinary do
    let label := node.label
    let accepted := node.accepted
    if !p.raw.pending.contains label then
      reject "missing-source-envelope" label.toString "Accepted concept has no retained source registrations"
    if let .error diagnostics := Contributions.resolve label p.raw.facts then
      reject "producer-collision" label.toString (reprStr diagnostics)
    let uses := accepted.uses
    collected := { collected with
      input.nodes := collected.input.nodes.push (contribution `node (toJson (Vir.nameKey label))
        (accepted.toNode.toConcept label label.toString))
      uses := collected.uses ++ uses }
    for step in node.realizations do
      let key := step.key
      let sources := step.sources.map (·.source)
      let associations := step.associations
      let contexts := canonical (sources.map (·.context) ++ associations.map (·.context))
      unless contexts.size == 1 do
        reject "source-context-mismatch" label.toString "A realization requires one agreed stored source context"
      let context := contexts[0]!
      let names := nativeNames associations sources
      let object (name : Name) : ObjectKey := ⟨context, name.toString⟩
      let facets := canonical (sources.map (·.destination.facet) ++ associations.flatMap (·.facets) ++
        (uses.filter (·.realization == some key.name)).map (·.facet))
      let mut model : Realization := {
        key, context
        facets := facets.map fun facet => {
          name := facet
          documents := canonical ((sources.filter (·.destination.facet == facet)).map (·.document))
          declarations := canonical ((nativeNames (associations.filter (·.facets.contains facet))
            (sources.filter (·.destination.facet == facet))).map object) }
        declarations := names.map fun name => { object := object name } }
      let issues := if context.language == `lean then nativeMembershipIssues label model associations sources
        else sources.flatMap (·.issues label model)
      unless issues.isEmpty do full (.error issues)
      for sourceStep in step.sources do
        let source := sourceStep.source
        let (document, issues) ← providers.document sourceStep.document
        collected := { collected with
          input.documents := collected.input.documents.push (contribution `document (BindingEncoding.documentKey document.key) document)
          diagnostics := collected.diagnostics ++ issues }
        if let some reason := source.source.error then
          collected := { collected with diagnostics := collected.diagnostics.push {
            code := "source-association-unavailable", subject := (BindingEncoding.subject source.destination.subject).compress, message := reason } }
        if let some documented := sourceStep.documented then
            let proseKey : DocumentKey := ⟨source.context,
              source.document.path ++ "#docstring:" ++ (BindingEncoding.subject source.destination.subject).compress⟩
            let result ← match documented with
              | .error issue => pure (.error issue)
              | .ok handle => providers.documented handle
            let text ← match result with
              | .ok documented => pure documented.rawDocstring
              | .error diagnostic =>
                collected := { collected with diagnostics := collected.diagnostics.push diagnostic }
                pure ""
            collected := { collected with
              input.documents := collected.input.documents.push (contribution `document (BindingEncoding.documentKey proseKey) { key := proseKey, text }) }
            model := { model with facets := model.facets.map fun facet =>
              if facet.name != source.destination.facet then facet else
                { facet with documents := canonical (facet.documents.push proseKey) } }
      for declarationStep in step.declarations do
        let name := declarationStep.name
        let witness := object name
        let subject := Subject.declaration key witness
        let statementKey : RequirementKey := ⟨subject, `statement⟩
        let proofKey : RequirementKey := ⟨subject, `proof⟩
        let prepared ← prepareNative providers declarationStep
        let observation : ObjectObservation ← match prepared with
          | .error issues =>
            collected := { collected with diagnostics := collected.diagnostics ++ issues }
            pure { key := witness, resolution := if issues.any (·.code == "missing-declaration") then .missing else .unsupported, explanation := (toJson issues).compress }
          | .ok prepared =>
            collected := { collected with
              diagnostics := collected.diagnostics ++ prepared.semanticDiagnostics
              input.documents := collected.input.documents.push (contribution `document (BindingEncoding.documentKey prepared.document.key) prepared.document)
              input.bindingInputs := collected.input.bindingInputs ++ prepared.semanticContext.toArray.map fun content =>
                contribution `nativeContext (BindingEncoding.subject subject) { subject, name := NativeLean.sourceContext, content } }
            pure { key := witness, resolution := .resolved, document := some prepared.document.key }
        collected := { collected with
          input.objects := collected.input.objects.push (contribution `object (BindingEncoding.objectKey witness) observation)
          input.requirements := collected.input.requirements ++ #[
            contribution `requirement (BindingEncoding.requirementKey statementKey) { key := statementKey, expected := .check NativeLean.statementValidator, coverage := .dependencyClosure },
            contribution `requirement (BindingEncoding.requirementKey proofKey) { key := proofKey, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }] }
        model := { model with
          declarations := model.declarations.map fun declaration =>
            if declaration.object == witness then { declaration with required := #[proofKey] } else declaration
          facets := model.facets.map fun facet =>
            if !facet.declarations.contains witness then facet else
              { facet with required := facet.required.push (if facet.name == `statement then statementKey else proofKey) } }
        match ← providers.check declarationStep.check with
        | .ok checked =>
          collected := { collected with nativeChecks := collected.nativeChecks.push checked }
          collected := (recordObservation collected statementKey (.check checked.statement))
            |> fun value => recordObservation value proofKey (.check checked.body)
        | .error diagnostic =>
          collected := { collected with diagnostics := collected.diagnostics.push diagnostic }
          for (key, validator) in #[(statementKey, NativeLean.statementValidator), (proofKey, NativeLean.bodyValidator)] do
            collected := recordObservation collected key (.check {
              validator, declaration := some witness, outcome := .unavailable, explanation := diagnostic.message })
      collected := { collected with input.realizations := collected.input.realizations.push (contribution `realization (BindingEncoding.realizationKey key) model) }
    let models := collected.input.realizations.map (·.value)
    let issues := uses.flatMap (·.issues label models)
    unless issues.isEmpty do full (.error issues)
  return collected

private def ownedDefinition (name : Name) (origin : Origin) (source : Document) : CaptureM Unit := do
  let env ← getEnv
  let some (.defnInfo info) := env.checked.get.find? name
    | reject "invalid-expectation" name.toString "Expected a checked owned Prop definition, not an axiom" #[origin]
  unless info.safety == .safe do
    reject "invalid-expectation" name.toString "Expected a safe proposition definition" #[origin]
  let owner := (env.getModuleIdxFor? name).bind (fun index => env.header.moduleNames[index.toNat]?) |>.getD env.mainModule
  unless owner == origin.moduleName do
    reject "wrong-expectation-owner" name.toString "Specification belongs to another module" #[origin]
  let some ranges ← findDeclarationRanges? name
    | reject "source-association-unavailable" name.toString "Specification has no native declaration ranges" #[origin]
  let commands ← one (← NativeSource.parseSource name source.key.path source.text)
  discard <| one (NativeSource.declarationAtRanges name source.text ranges.range ranges.selectionRange commands)

private def collectAuthored [Monad m] (providers : Providers m) (p : Plan)
    (collected : Collected) : ExceptT (Array Diagnostic) m Collected := do
  let mut collected := collected
  for step in p.authored do
    let record := step.record
    for index in [:record.nativeGoals.size] do
      let (node, _) := record.nativeGoals[index]!
      let key : RealizationKey := ⟨node, `lean⟩
      let models := canonical ((collected.input.realizations.filter (·.value.key == key)).map (·.value))
      unless models.size == 1 && models[0]!.context == ⟨`lean, record.project⟩ && models[0]!.declarations.size == 1 do
        reject "ambiguous-native-expectation" node.toString
          "Node-level expectation requires one ordinary native declaration in its exact stored context" #[record.origin]
      let witness := models[0]!.declarations[0]!.object
      let expectedKey : RequirementKey := ⟨.declaration key witness, `expectedProof⟩
      let handle := step.goals[index]!
      let goalRequest := p.expected[handle]!
      let specification := p.specifications[goalRequest.specification]!
      let (specDoc, issues) ← providers.document specification.document
      unless issues.isEmpty do full (.error issues)
      full (← providers.specification goalRequest.specification specDoc)
      let documents := canonical ((collected.input.objects.filter (·.value.key == witness)).filterMap (·.value.document) |>.push specDoc.key)
      let checked ← one (← providers.expected handle witness documents)
      let input := { collected.input with
        documents := collected.input.documents.push (authoredContribution record.origin `specification index specDoc)
        realizations := collected.input.realizations.map fun contribution =>
          if contribution.value.key != key then contribution else { contribution with value := { contribution.value with
            declarations := contribution.value.declarations.map fun declaration =>
              { declaration with required := canonical (declaration.required.push expectedKey) } } }
        requirements := collected.input.requirements.push (authoredContribution record.origin `expectedRequirement index {
          key := expectedKey, expected := .proof checked.goal witness, coverage := .dependencyClosure })
        bindingInputs := collected.input.bindingInputs ++ checked.semanticContext.toArray.map fun content =>
          authoredContribution record.origin `expectedContext index {
            subject := expectedKey.subject, name := NativeLean.expectedContextFor expectedKey, content } }
      collected := { collected with
        input := input
        diagnostics := collected.diagnostics ++ checked.semanticDiagnostics
        observations := collected.observations.push ((authoredContribution record.origin `expectedObservation index ()).origin,
          expectedKey, .proof checked.observation) }
    let batch := record.authored
    for index in [:batch.sources.size] do
      let (document, issues) ← providers.document step.documents[index]!
      collected := { collected with
        input.documents := collected.input.documents.push (authoredContribution record.origin `document index document)
        diagnostics := collected.diagnostics ++ issues }
    collected := { collected with input := { collected.input with
      objects := collected.input.objects ++ batch.references.mapIdx (fun index (key, document) =>
        authoredContribution record.origin `reference index {
          key, document, resolution := .unsupported, explanation := "Authored reference: source-native resolver/checker is not connected" })
      realizations := collected.input.realizations ++ batch.realizations.mapIdx (authoredContribution record.origin `realization)
      translations := collected.input.translations ++ batch.translations.mapIdx (authoredContribution record.origin `translation)
      claims := collected.input.claims ++ batch.claims.mapIdx (authoredContribution record.origin `claim)
      requirements := collected.input.requirements ++ batch.requirements.mapIdx (authoredContribution record.origin `requirement) } }
  return collected

/-- Select the complete ordinary native contract, independently of its outcome.
Alternatives are explicit realizations and cannot rescue the default. -/
private def selectTarget (input : Input) (context : Context) (target : Name) :
    Except Diagnostic (Array RequirementKey) := do
  let fail (code message : String) : Except Diagnostic (Array RequirementKey) := .error {
    code, subject := target.toString, message }
  unless input.nodes.any (·.value.label == target) do
    return ← fail "missing-target" "No accepted dependency target"
  let key : RealizationKey := ⟨target, `lean⟩
  let models := canonical ((input.realizations.filter (·.value.key == key)).map (·.value))
  unless models.size == 1 do
    return ← fail (if models.isEmpty then "missing-native-contract" else "ambiguous-native-contract")
      "Dependency requires one ordinary native realization"
  let model := models[0]!
  unless model.context == context do
    return ← fail "wrong-default-context" "Dependency belongs to another project context"
  unless !model.declarations.isEmpty do
    return ← fail "missing-native-contract" "Dependency has no selected native declarations"
  let mut required := #[]
  for declaration in model.declarations do
    let proof : RequirementKey := ⟨.declaration key declaration.object, `proof⟩
    let contracts := canonical ((input.requirements.filter (·.value.key == proof)).map (·.value))
    unless contracts.size == 1 && contracts[0]!.expected == .check NativeLean.bodyValidator &&
        contracts[0]!.coverage == .dependencyClosure && declaration.required.contains proof do
      return ← fail "invalid-native-contract" "Dependency requires its exact native completeness contract"
    required := required ++ declaration.required
  return canonical required

private def selectUses (collected : Collected) : Array SelectedUse := Id.run do
  let mut selected := #[]
  let scopes := (collected.uses.map fun use => (use.node, use.realization, use.facet)).foldl
    (fun scopes scope => if scopes.contains scope then scopes else scopes.push scope) #[]
  for (source, realization, facet) in scopes do
    let uses := Data.UseRef.mergeByLabel #[] <| (collected.uses.filter fun use =>
      use.node == source && use.realization == realization && use.facet == facet).map (·.reference)
    let models := collected.input.realizations.filter fun contribution =>
      contribution.value.key.node == source && realization.all (· == contribution.value.key.name)
    let contexts := canonical (models.map fun contribution =>
      ({ language := `lean, project := contribution.value.context.project } : Context))
    for reference in uses do
      if contexts.isEmpty then
        selected := selected.push {
          source, realization, facet, reference, context := none
          selected := .error {
            code := "missing-source-context", subject := source.toString
            message := "Dependency has no stored source project context" } }
      else
        for context in contexts do
          selected := selected.push {
            source, realization, facet, reference, context := some context
            selected := selectTarget collected.input context reference.label }
  return selected

/-- A mechanical check of contract selection, not a proof checker. Only this
actual selection computation can produce its observation. Target failures remain
inspectable edge diagnostics; the gate makes them block the Blueprint closure
without turning a missing edge into a nonexistent prerequisite key. -/
private def connectUses (collected : Collected) (uses : Array SelectedUse) : Collected := Id.run do
  -- Only ordinary capture owns automatic native prerequisite wiring. Authored
  -- reviews/checks may use the same names and even the same native validators.
  -- Index the generated contracts once, before adding any selection requirements.
  let nativeContracts := collected.input.requirements.foldl
    (init := ({} : Std.HashMap RequirementKey Name)) fun out record =>
      if record.value.coverage == .dependencyClosure &&
          record.origin == (contribution `requirement (BindingEncoding.requirementKey record.value.key) ()).origin then
        match record.value.expected with
        | .check validator =>
          if validator == NativeLean.statementValidator || validator == NativeLean.bodyValidator then
            out.insert record.value.key validator
          else out
        | _ => out
      else out
  let mut collected := collected
  for model in collected.input.realizations.map (·.value) do
    if model.context.language != `lean then continue
    let relevant := uses.filter fun use => use.source == model.key.node &&
      use.context == some model.context && use.realization.all (· == model.key.name)
    for declaration in model.declarations do
      let subject := Subject.declaration model.key declaration.object
      for (name, validator) in #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)] do
        let key : RequirementKey := ⟨subject, name⟩
        unless nativeContracts[key]? == some validator do continue
        let edges := relevant.filter fun use => name == `proof || use.facet == `statement
        let mut prerequisites : Array RequirementKey := #[]
        if name == `proof then prerequisites := #[⟨subject, `statement⟩]
        if !edges.isEmpty then
          let selectionKey : RequirementKey := ⟨subject, name ++ `dependencySelection⟩
          let failures := edges.filterMap fun edge => match edge.selected with
            | .error diagnostic => some diagnostic | .ok _ => none
          prerequisites := prerequisites.push selectionKey ++ edges.flatMap fun edge =>
            match edge.selected with | .ok keys => keys | .error _ => #[]
          collected := { collected with input := { collected.input with
            requirements := collected.input.requirements.push (contribution `requirement (BindingEncoding.requirementKey selectionKey) {
              key := selectionKey, expected := .check `blueprint.dependencySelection })
            bindingInputs := collected.input.bindingInputs.push (contribution `dependencySelection (BindingEncoding.requirementKey selectionKey) {
              subject, name := name ++ `selectedUses
              content := (toJson (edges.map fun edge => (edge.source, edge.context, edge.realization,
                edge.facet, edge.reference, edge.selected))).compress }) } }
          collected := recordObservation collected selectionKey (.check {
            validator := `blueprint.dependencySelection
            outcome := if failures.isEmpty then .passed else .unavailable
            explanation := if failures.isEmpty then "Every dependency selected its exact current native contract"
              else (toJson failures).compress })
        collected := { collected with input.requirements := collected.input.requirements.map fun contribution =>
          if contribution.value.key != key then contribution else { contribution with value := {
            contribution.value with prerequisites := canonical (contribution.value.prerequisites ++ prerequisites) } } }
  return collected

private def assemble [Monad m] (providers : Providers m) (p : Plan) : ExceptT (Array Diagnostic) m Collected := do
  unless p.raw.initialIssues.isEmpty do full (.error (canonical p.raw.initialIssues))
  collectOrdinary providers p >>= collectAuthored providers p

/-- Ordinary captures feed graph JSON and readable CLI selectors. Validate the
complete public label set once; pure registries may still use arbitrary Names. -/
private def publicLabelIssues (labels : Array Name) : Array Diagnostic := Id.run do
  let mut seen : Std.HashMap String Name := {}
  let mut issues := #[]
  for label in labels do
    let spelling := Data.Label.publicString label
    if label.isAnonymous || spelling.trimAscii.isEmpty || label.toString.toName != label then
      issues := issues.push {
        code := "unsupported-public-label", subject := label.toString
        message := "Blueprint public labels must be nonempty and round-trip through Lean name JSON; choose an explicit string label" }
    else
      match seen[spelling]? with
      | some previous =>
        if previous != label then
          issues := issues.push {
            code := "ambiguous-public-label", subject := spelling
            message := s!"Distinct labels '{previous}' and '{label}' share the public spelling '{spelling}'; use distinct explicit labels" }
      | none => seen := seen.insert spelling label
  return canonical issues

/-- Complete candidate admission, same-candidate binding, and final admission.
No caller can obtain an admitted fragment from this operation. -/
private def finish (collected : Collected) : Except (Array Diagnostic) Snapshot := do
  let labels := collected.input.nodes.map (·.value.label) ++ collected.uses.map (fun use => (show Name from use.reference.label))
  let groups := collected.input.nodes.filterMap fun record =>
    record.value.parent.map (fun label => (show Name from label))
  let labelIssues := publicLabelIssues labels ++ publicLabelIssues groups
  unless labelIssues.isEmpty do throw labelIssues
  let uses := selectUses collected
  let collected := connectUses collected uses
  let candidate ← admit collected.input
  let mut input := collected.input
  for (origin, key, observation) in collected.observations do
    let some binding := candidate.bindingFor key
      | throw #[{
          code := "missing-binding", subject := key.name.toString,
          message := "Complete candidate has no contract binding", origins := canonical #[origin] }]
    input := { input with evidence := input.evidence.push { origin, value := {
      id := origin.id, requirement := key, binding, observation } } }
  return {
    registry := ← admit input, uses, diagnostics := canonical collected.diagnostics
    nativeChecks := collected.nativeChecks }

private def batchIssue (code family : String) (handle : Nat) : Array Diagnostic := #[{
  code, subject := s!"{family}[{handle}]", message := "Malformed capture observation batch" }]

private def indexResults {p : Plan} {requestType : Type} (family : String) (size : Nat) (entries : Array (ResultEntry p requestType α)) :
    Except (Array Diagnostic) (Std.HashMap Nat α) := do
  let mut table := {}
  for entry in entries do
    if entry.handle >= size then throw (batchIssue "extraneous-observation" family entry.handle)
    if table.contains entry.handle then throw (batchIssue "duplicate-observation" family entry.handle)
    table := table.insert entry.handle entry.result
  return table

private def lookupResult (family : String) (table : Std.HashMap Nat α) (handle : Nat) :
    ExceptT (Array Diagnostic) Id α :=
  full <| match table.get? handle with
    | some value => .ok value
    | none => .error (batchIssue "missing-observation" family handle)

private def matching (family : String) (handle : Nat) (agrees : Bool) : ExceptT (Array Diagnostic) Id Unit :=
  unless agrees do full (.error (batchIssue "mismatched-observation" family handle))

private def preparedMatches (context : Context) (name : Name) (prepared : NativeSource.Prepared) : Bool :=
  prepared.canonical == name && prepared.declaration == ⟨⟨`lean, context.project⟩, name.toString⟩ &&
    prepared.document.key.context == ⟨`lean, context.project⟩

private def associatedMatches (request : NativeRequest) (prepared : NativeSource.Prepared) : Bool :=
  preparedMatches request.context request.name prepared &&
    request.association.reference.provenance.moduleName?.all (· == prepared.moduleName) &&
    request.association.reference.provenance.sourcePath?.all (· == prepared.document.key.path) &&
    request.association.reference.range?.all (· == prepared.ranges.range) &&
    request.association.reference.selectionRange?.all (· == prepared.ranges.selectionRange)

/-- Pure policy evaluation against exactly the plan that indexes these results.
Table insertion order has no meaning. Duplicate/extra handles are rejected;
missing and mismatched results fail at their recipe checkpoint. The supplied
facts are not authenticated here: production must call `observe` freshly. -/
def evaluate (p : Plan) (observations : Observations p) : Except (Array Diagnostic) Snapshot := do
  let documents ← indexResults "document" p.documents.size observations.documents
  let native ← indexResults "native" p.native.size observations.native
  let inline ← indexResults "inline" p.inline.size observations.inline
  let documented ← indexResults "documented" p.documented.size observations.documented
  let checks ← indexResults "check" p.checks.size observations.checks
  let specifications ← indexResults "specification" p.specifications.size observations.specifications
  let expected ← indexResults "expected" p.expected.size observations.expected
  let providers : Providers Id := {
    document := fun handle => do
      let result ← lookupResult "document" documents handle
      matching "document" handle (p.documents[handle]? == some result.1.key)
      return result
    native := fun handle => do
      let result ← lookupResult "native" native handle
      if let .ok value := result then
        let request := p.native[handle]!
        matching "native" handle (associatedMatches request value)
      return result
    inline := fun handle => do
      let result ← lookupResult "inline" inline handle
      if let .ok value := result then
        let request := p.inline[handle]!
        matching "inline" handle (preparedMatches request.context request.name value &&
          value.document.key.path == request.source.document.path)
      return result
    documented := fun handle => do
      let result ← lookupResult "documented" documented handle
      if let .ok value := result then
        let request := p.documented[handle]!
        matching "documented" handle (associatedMatches request value.toPrepared)
      return result
    check := fun handle => do
      let result ← lookupResult "check" checks handle
      if let .ok value := result then
        let request := p.checks[handle]!
        matching "check" handle (value.declaration == request.witness &&
          value.statement.declaration == some request.witness && value.body.declaration == some request.witness &&
          value.statement.validator == NativeLean.statementValidator && value.body.validator == NativeLean.bodyValidator)
      return result
    specification := fun handle document => do
      let value ← lookupResult "specification" specifications handle
      matching "specification" handle (value.document == document)
      return value.result
    expected := fun handle witness documents => do
      let value ← lookupResult "expected" expected handle
      matching "expected" handle (value.witness == witness && value.documents == documents)
      if let .ok checked := value.result then
        matching "expected" handle (checked.observation.witness == witness && checked.goal.documents == documents &&
          checked.goal.context == witness.context)
      return value.result }
  let collected ← (assemble providers p).run
  finish collected

/-- Execute the observation phase with exception-to-diagnostic conversion and
full elaborator-state restoration. This is also the scope used by `observe`. -/
def withObservationState (action : TermElabM (Except (Array Diagnostic) α)) :
    TermElabM (Except (Array Diagnostic) α) := do
  let saved ← Term.saveState
  try
    action
  catch exception =>
    return .error #[{ code := "capture-failed", subject := "Blueprint", message := ← exception.toMessageData.toString }]
  finally
    saved.restore (restoreInfo := true)

/-- One effect scope for all providers, including dependent expected goals.
The supplied reader is a byte-reading seam for tests, not a native-success hook.
Successful physical reads are shared across every provider family in this call.
Environment, metavariables and info state are restored even on exceptions. -/
def observe (p : Plan) (readFile : System.FilePath → IO String := IO.FS.readFile) :
    TermElabM (Except (Array Diagnostic) (Observations p)) := withObservationState do
    let snapshot ← liftM <| IO.mkRef (#[] : Array (System.FilePath × String))
    let reader (path : System.FilePath) : IO String := do
      let physical ← IO.FS.realPath path
      if let some (_, text) := (← snapshot.get).find? (·.1 == physical) then return text
      let text ← readFile physical
      snapshot.modify (·.push (physical, text))
      return text
    let semantics ← NativeLean.newSemanticContext
    let results ← liftM <| IO.mkRef ({ } : Observations p)
    let providers : Providers TermElabM := {
      document := fun handle => do
        let result ← readDocument reader p.documents[handle]!
        results.modify fun table => { table with documents := table.documents.push ⟨handle, result⟩ }
        return result
      native := fun handle => do
        let job := p.native[handle]!
        let result ← match ← request job.context job.name (some job.association) none with
          | .error issue => pure (.error issue)
          | .ok request => NativeSource.prepare request reader semantics
        results.modify fun table => { table with native := table.native.push ⟨handle, result⟩ }
        return result
      inline := fun handle => do
        let job := p.inline[handle]!
        let result ← match job.source.payload with
          | .leanInline code =>
            match ← request job.context job.name none (some job.source) with
            | .error issue => pure (.error issue)
            | .ok request => NativeSource.prepareInline request code reader semantics
          | _ => pure (.error {
              code := "invalid-inline-request", subject := job.name.toString,
              message := "Inline request has no inline source payload" })
        results.modify fun table => { table with inline := table.inline.push ⟨handle, result⟩ }
        return result
      documented := fun handle => do
        let job := p.documented[handle]!
        let result ← match ← request job.context job.name (some job.association) none with
          | .error issue => pure (.error issue)
          | .ok request => NativeSource.prepareDocumented request reader semantics
        results.modify fun table => { table with documented := table.documented.push ⟨handle, result⟩ }
        return result
      check := fun handle => do
        let job := p.checks[handle]!
        let result ← NativeLean.checkDeclaration job.project job.witness
        results.modify fun table => { table with checks := table.checks.push ⟨handle, result⟩ }
        return result
      specification := fun handle document => do
        let job := p.specifications[handle]!
        let result ← liftM (m := TermElabM) (α := Except (Array Diagnostic) Unit)
          (ownedDefinition job.expected job.origin document).run
        results.modify fun table => { table with specifications := table.specifications.push ⟨handle, { document, result }⟩ }
        return result
      expected := fun handle witness documents => do
        let job := p.expected[handle]!
        let result ← NativeLean.check job.project witness (mkCIdent job.expected) documents semantics
        results.modify fun table => { table with expected := table.expected.push ⟨handle, { witness, documents, result }⟩ }
        return result }
    -- Shared pure recipe resolves dependent arguments and ordered fatal checks.
    -- Its temporary input is not admitted and never escapes this boundary.
    match ← (assemble providers p).run with
    | .error issues => return .error issues
    | .ok _ => return .ok (← results.get)
initialize registerTraceClass `blueprint.capture

/-- Fresh observation followed by pure, atomic evaluation. Timings include the
shared ordered recipe in observe; they are not provider-only microbenchmarks. -/
def capture : TermElabM (Except (Array Diagnostic) Snapshot) := do
  let p := plan (Raw.ofState (Environment.informalExt.getState (← getEnv)))
  let started ← IO.monoMsNow
  let observed ← observe p
  let observedAt ← IO.monoMsNow
  trace[blueprint.capture] "observe: {observedAt - started} ms"
  match observed with
  | .error issues => return .error issues
  | .ok observations =>
    let result := evaluate p observations
    -- Force pure evaluation before sampling the end of the phase.
    let ok := result.isOk
    let evaluatedAt ← IO.monoMsNow
    trace[blueprint.capture] "evaluate: {evaluatedAt - observedAt} ms (success: {ok})"
    return result

end Informal.Realizations.Capture
