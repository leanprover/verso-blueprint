/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment
import VersoBlueprint.Realizations.NativeSource

/-! Capture ordinary, keyed Blueprint sources after their owning modules have
been built. Raw registrations remain the only persistent store. This boundary
collects the complete model, admits it, binds fresh checks to that same snapshot,
and admits the final result. A failed admission never returns a partial registry.
-/

namespace Informal.Realizations.Capture

open Lean Meta Elab Term Validation Translations SourceData

abbrev CaptureM := ExceptT (Array Diagnostic) TermElabM

private def reject (code subject message : String) (origins : Array Origin := #[]) : CaptureM α :=
  ExceptT.mk (pure (.error #[{ code, subject, message, origins := canonical origins }]))

private def one (result : Except Diagnostic α) : CaptureM α :=
  ExceptT.mk (pure (result.mapError (fun issue => #[issue])))

private def full (result : Except (Array Diagnostic) α) : CaptureM α :=
  ExceptT.mk (pure result)

/-- The collector is one producer, with unambiguous typed boundaries for each
semantic slot. Query module/options and registration order are not identities. -/
private def contribution [Repr κ] (family : Name) (key : κ) (value : α) : Contribution α :=
  { origin := {
      id := Name.mkSimple (toJson (reprStr family, reprStr key)).compress
      moduleName := `VersoBlueprint.Realizations.Capture
      source := "ordinary Blueprint source collection" }, value }

private def authoredContribution (origin : Origin) (family : Name) (index : Nat) (value : α) : Contribution α :=
  { origin := { origin with id := Name.mkSimple (toJson (reprStr origin.id, reprStr family, index)).compress }, value }

/-- Resolution failure stays an edge diagnostic, never a manufactured theorem status. -/
structure SelectedUse where
  source : Name
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

private structure Collected where
  input : Input := {}
  observations : Array (Origin × RequirementKey × Observation) := #[]
  diagnostics : Array Diagnostic := #[]
  uses : Array UseDeclaration := #[]

private def observe (collected : Collected) (key : RequirementKey) (observation : Observation) : Collected :=
  { collected with observations := collected.observations.push ((contribution `observation key ()).origin, key, observation) }

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

private def prepareNative (reader : System.FilePath → IO String) (context : Context)
    (name : Name) (associations : Array NativeAssociation) (sources : Array FacetSource) :
    CoreM (Except (Array Diagnostic) NativeSource.Prepared) := do
  let mut prepared := #[]
  let mut issues := #[]
  -- Every association participates. A valid sibling/duplicate cannot hide an
  -- invalid source association for the same selected declaration.
  for association in associations.filter (·.reference.canonical == name) do
    let result ← match ← request context name (some association) none with
      | .error issue => pure (.error issue)
      | .ok request => NativeSource.prepare request reader
    match result with
    | .error issue => issues := issues.push issue
    | .ok value => prepared := prepared.push value
  for source in sources do
    if let .leanInline code := source.payload then
      if (code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)).contains name then
        let result ← match ← request context name none (some source) with
          | .error issue => pure (.error issue)
          | .ok request => NativeSource.prepareInline request code reader
        match result with
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

private def collectOrdinary (reader : System.FilePath → IO String) (state : Environment.State) : CaptureM Collected := do
  let mut collected : Collected := {}
  for (label, accepted) in state.data.toArray do
    let some pending := state.pendingNodes.get? label
      | reject "missing-source-envelope" label.toString "Accepted concept has no retained source registrations"
    if let .error diagnostics := Contributions.resolve label state.factRecords then
      reject "producer-collision" label.toString (reprStr diagnostics)
    let sources := pending.registrations.flatMap (·.sources)
    let records := state.factRecords.reverse.toArray.filter (·.label == label)
    let associations := records.flatMap (·.nativeAssociations)
    let uses := pending.registrations.flatMap (·.uses)
    collected := { collected with
      input.nodes := collected.input.nodes.push (contribution `node label
        (accepted.toNode.toConcept label label.toString))
      uses := collected.uses ++ uses }
    let keys := canonical (sources.map (·.destination.realization) ++ associations.map (·.realization))
    for key in keys do
      let sources := sources.filter (·.destination.realization == key)
      let associations := associations.filter (·.realization == key)
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
      for source in sources do
        let (document, issues) ← readDocument reader source.document
        collected := { collected with
          input.documents := collected.input.documents.push (contribution `document document.key document)
          diagnostics := collected.diagnostics ++ issues }
        if let some reason := source.source.error then
          collected := { collected with diagnostics := collected.diagnostics.push {
            code := "source-association-unavailable", subject := (toJson source.destination).compress, message := reason } }
        if let .prose _ := source.payload then
          -- Attribute prose is associated by the retained producer source site,
          -- not by a nearby comment or a rendered/elaborated docstring payload.
          let owners := records.filter fun record => record.id.producer == `blueprint.attribute &&
            record.source.isSome && record.source == source.source.location
          if !owners.isEmpty then
            let selected := canonical (owners.flatMap (·.nativeAssociations))
            let proseKey : DocumentKey := ⟨source.context,
              source.document.path ++ "#docstring:" ++ (toJson source.destination).compress⟩
            let result ← if selected.size != 1 then pure (.error ({
                code := "ambiguous-docstring", subject := label.toString,
                message := "Attribute prose requires one exact owning native association" } : Diagnostic))
              else do
                let association := selected[0]!
                match ← request association.context association.reference.canonical (some association) none with
                | .error diagnostic => pure (.error diagnostic)
                | .ok request => NativeSource.prepareDocumented request reader
            let text ← match result with
              | .ok documented => pure documented.rawDocstring
              | .error diagnostic =>
                collected := { collected with diagnostics := collected.diagnostics.push diagnostic }
                pure ""
            collected := { collected with
              input.documents := collected.input.documents.push (contribution `document proseKey { key := proseKey, text }) }
            model := { model with facets := model.facets.map fun facet =>
              if facet.name != source.destination.facet then facet else
                { facet with documents := canonical (facet.documents.push proseKey) } }
      for name in names do
        let witness := object name
        let subject := Subject.declaration key witness
        let statementKey : RequirementKey := ⟨subject, `statement⟩
        let proofKey : RequirementKey := ⟨subject, `proof⟩
        let prepared ← prepareNative reader context name associations sources
        let observation : ObjectObservation ← match prepared with
          | .error issues =>
            collected := { collected with diagnostics := collected.diagnostics ++ issues }
            pure { key := witness, resolution := if issues.any (·.code == "missing-declaration") then .missing else .unsupported, explanation := (toJson issues).compress }
          | .ok prepared =>
            collected := { collected with
              diagnostics := collected.diagnostics ++ prepared.semanticDiagnostics
              input.documents := collected.input.documents.push (contribution `document prepared.document.key prepared.document)
              input.bindingInputs := collected.input.bindingInputs ++ prepared.semanticContext.toArray.map fun content =>
                contribution `nativeContext subject { subject, name := NativeLean.sourceContext, content } }
            pure { key := witness, resolution := .resolved, document := some prepared.document.key }
        collected := { collected with
          input.objects := collected.input.objects.push (contribution `object witness observation)
          input.requirements := collected.input.requirements ++ #[
            contribution `requirement statementKey { key := statementKey, expected := .check NativeLean.statementValidator, coverage := .dependencyClosure },
            contribution `requirement proofKey { key := proofKey, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }] }
        model := { model with
          declarations := model.declarations.map fun declaration =>
            if declaration.object == witness then { declaration with required := #[proofKey] } else declaration
          facets := model.facets.map fun facet =>
            if !facet.declarations.contains witness then facet else
              { facet with required := facet.required.push (if facet.name == `statement then statementKey else proofKey) } }
        match ← NativeLean.checkDeclaration context.project witness with
        | .ok checked =>
          collected := (observe collected statementKey (.check checked.statement))
            |> fun value => observe value proofKey (.check checked.body)
        | .error diagnostic =>
          collected := { collected with diagnostics := collected.diagnostics.push diagnostic }
          for (key, validator) in #[(statementKey, NativeLean.statementValidator), (proofKey, NativeLean.bodyValidator)] do
            collected := observe collected key (.check {
              validator, declaration := some witness, outcome := .unavailable, explanation := diagnostic.message })
      collected := { collected with input.realizations := collected.input.realizations.push (contribution `realization key model) }
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

private def collectAuthored (reader : System.FilePath → IO String) (state : Environment.State)
    (collected : Collected) : CaptureM Collected := do
  let mut collected := collected
  let records := state.authoringRecords.foldl (fun out record =>
    if out.any (fun previous => decide (previous = record)) then out else out.push record) #[]
  for record in records do
    for index in [:record.nativeGoals.size] do
      let (node, expected) := record.nativeGoals[index]!
      let key : RealizationKey := ⟨node, `lean⟩
      let models := canonical ((collected.input.realizations.filter (·.value.key == key)).map (·.value))
      unless models.size == 1 && models[0]!.context == ⟨`lean, record.project⟩ && models[0]!.declarations.size == 1 do
        reject "ambiguous-native-expectation" node.toString
          "Node-level expectation requires one ordinary native declaration in its exact stored context" #[record.origin]
      let witness := models[0]!.declarations[0]!.object
      let expectedKey : RequirementKey := ⟨.declaration key witness, `expectedProof⟩
      let (specDoc, issues) ← readDocument reader ⟨witness.context, record.origin.source⟩
      unless issues.isEmpty do full (.error issues)
      ownedDefinition expected record.origin specDoc
      let documents := canonical ((collected.input.objects.filter (·.value.key == witness)).filterMap (·.value.document) |>.push specDoc.key)
      let checked ← one (← NativeLean.check record.project witness (mkCIdent expected) documents)
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
        observations := collected.observations.push ((authoredContribution record.origin `expectedObservation index ()).origin,
          expectedKey, .proof checked.observation) }
    let batch := record.authored
    for index in [:batch.sources.size] do
      let (document, issues) ← readDocument reader batch.sources[index]!
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
  let mut collected := collected
  for model in collected.input.realizations.map (·.value) do
    if model.context.language != `lean then continue
    let relevant := uses.filter fun use => use.source == model.key.node &&
      use.context == some model.context && use.realization.all (· == model.key.name)
    for declaration in model.declarations do
      let subject := Subject.declaration model.key declaration.object
      for name in #[`statement, `proof] do
        let edges := relevant.filter fun use => name == `proof || use.facet == `statement
        let key : RequirementKey := ⟨subject, name⟩
        let mut prerequisites : Array RequirementKey := #[]
        if name == `proof then prerequisites := #[⟨subject, `statement⟩]
        if !edges.isEmpty then
          let selectionKey : RequirementKey := ⟨subject, name ++ `dependencySelection⟩
          let failures := edges.filterMap fun edge => match edge.selected with
            | .error diagnostic => some diagnostic | .ok _ => none
          prerequisites := prerequisites.push selectionKey ++ edges.flatMap fun edge =>
            match edge.selected with | .ok keys => keys | .error _ => #[]
          collected := { collected with input := { collected.input with
            requirements := collected.input.requirements.push (contribution `requirement selectionKey {
              key := selectionKey, expected := .check `blueprint.dependencySelection })
            bindingInputs := collected.input.bindingInputs.push (contribution `dependencySelection selectionKey {
              subject, name := name ++ `selectedUses
              content := (toJson (edges.map fun edge => (edge.source, edge.context, edge.realization,
                edge.facet, edge.reference, edge.selected))).compress }) } }
          collected := observe collected selectionKey (.check {
            validator := `blueprint.dependencySelection
            outcome := if failures.isEmpty then .passed else .unavailable
            explanation := if failures.isEmpty then "Every dependency selected its exact current native contract"
              else (toJson failures).compress })
        collected := { collected with input.requirements := collected.input.requirements.map fun contribution =>
          if contribution.value.key != key then contribution else { contribution with value := {
            contribution.value with prerequisites := canonical (contribution.value.prerequisites ++ prerequisites) } } }
  return collected

private def materialize (reader : System.FilePath → IO String) : CaptureM Snapshot := do
  let state := Environment.informalExt.getState (← getEnv)
  let issues := Environment.authoringRecordIssues state.authoringRecords ++ state.importedConflicts.map fun conflict =>
    ({ code := "imported-conflict", subject := conflict.label.toString, message := conflict.message } : Diagnostic)
  unless issues.isEmpty do full (.error (canonical issues))
  let collected ← collectOrdinary reader state >>= collectAuthored reader state
  let uses := selectUses collected
  let collected := connectUses collected uses
  let candidate ← full (admit collected.input)
  let mut input := collected.input
  for (origin, key, observation) in collected.observations do
    let some binding := candidate.bindingFor key
      | reject "missing-binding" key.name.toString "Complete candidate has no contract binding" #[origin]
    input := { input with evidence := input.evidence.push { origin, value := {
      id := origin.id, requirement := key, binding, observation } } }
  return { registry := ← full (admit input), uses, diagnostics := canonical collected.diagnostics }

/-- One read-only current source snapshot. Restores environment, metavariables and
info state even on exceptions. There is no persisted completion cache. -/
def capture : TermElabM (Except (Array Diagnostic) Snapshot) := do
  let saved ← Term.saveState
  try
    let snapshot ← liftM <| IO.mkRef (#[] : Array (System.FilePath × String))
    let reader (path : System.FilePath) : IO String := do
      let physical ← IO.FS.realPath path
      if let some (_, text) := (← snapshot.get).find? (·.1 == physical) then return text
      let text ← IO.FS.readFile physical
      snapshot.modify (·.push (physical, text))
      return text
    (materialize reader).run
  catch exception =>
    return .error #[{ code := "capture-failed", subject := "Blueprint", message := ← exception.toMessageData.toString }]
  finally
    saved.restore (restoreInfo := true)

end Informal.Realizations.Capture
