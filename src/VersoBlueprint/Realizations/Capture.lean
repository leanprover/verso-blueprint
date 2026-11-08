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
  role : Name
  reference : Data.UseRef
  selected : Except Diagnostic (Array RequirementKey)
  deriving Repr

/-- Provider errors retain their request's identity independently of the
human-readable diagnostic subject, which may name a transitive dependency.
Shared authored documents are associated after complete model collection. -/
structure SourceDiagnostics where
  nodes : Array (Name × Diagnostic) := #[]
  documents : Array (DocumentKey × Diagnostic) := #[]
  deriving Repr, BEq

private def SourceDiagnostics.addNode (diagnostics : SourceDiagnostics) (label : Name)
    (issues : Array Diagnostic) : SourceDiagnostics :=
  { diagnostics with nodes := diagnostics.nodes ++ issues.map (label, ·) }

private def canonicalDiagnostics [Ord α] [BEq α] (issues : Array (α × Diagnostic)) :
    Array (α × Diagnostic) :=
  letI : Ord (α × Diagnostic) := ⟨fun a b => (compare a.1 b.1).then (compare a.2 b.2)⟩
  canonical issues

structure Snapshot where
  registry : Registry
  uses : Array SelectedUse
  /-- Source/provider diagnostics are distinct from native proof outcomes. -/
  sourceDiagnostics : SourceDiagnostics := {}
  /-- Fresh native classification for inventory only; Registry remains completion authority. -/
  nativeChecks : Array NativeLean.CheckedDeclaration := #[]

/-- Aggregate provider errors, including authored documents not used by a node.
This is a view of the scoped errors, not a separately maintained inventory. -/
def Snapshot.diagnostics (snapshot : Snapshot) : Array Diagnostic :=
  canonical (snapshot.sourceDiagnostics.nodes.map (·.2) ++ snapshot.sourceDiagnostics.documents.map (·.2))

/-- Ordinary native models retain their generated origin; authored alternatives
do not silently join the default native summary or dependency contract. -/
private def ordinaryNativeRealizations (input : Input) (label : Name) : Array Realization :=
  canonical ((input.realizations.filter fun record =>
    record.value.key.node == label && record.value.context.language == `lean &&
      record.origin == (contribution `realization (BindingEncoding.realizationKey record.value.key) ()).origin).map (·.value))

/-- The ordinary source producer's native models, derived from the admitted
contributions. Full authored alternatives remain available in `registry`. -/
def Snapshot.nativeRealizationsFor (snapshot : Snapshot) (label : Name) : Array Realization :=
  ordinaryNativeRealizations snapshot.registry.contributions label

/-- Derive a consumer view from the same admitted snapshot. No source/status
fallbacks, new checker invocation or second dependency evaluator occur here. -/
def Snapshot.assessmentFor (snapshot : Snapshot) (label : Name) : NodeAssessment := Id.run do
  let registry := snapshot.registry
  let nativeModels := snapshot.nativeRealizationsFor label
  let declarations := canonical (nativeModels.flatMap (·.declarations))
  let hasNativeDeclarations := !declarations.isEmpty
  let statementDeclarations := (nativeModels.filter (·.role == `statement)).flatMap fun model =>
    model.declarations.map (fun declaration => (model.key, declaration))
  let proofDeclarations := (nativeModels.filter (·.role == `proof)).flatMap fun model =>
    model.declarations.map (fun declaration => (model.key, declaration))
  let implementationDeclarations := (nativeModels.filter (·.role == `implementation)).flatMap fun model =>
    model.declarations.map (fun declaration => (model.key, declaration))
  let locallyComplete (role validator : Name) (selected : Array (RealizationKey × Declaration)) :=
    !selected.isEmpty && selected.all fun (owner, declaration) =>
      let requirement : RequirementKey := ⟨.declaration owner declaration.object, role⟩
      (registry.realization? owner).any (fun model => model.role == role &&
        model.declarations.any (·.object == declaration.object)) &&
        (registry.requirement? requirement).any (fun value =>
          value.expected == .check validator && value.coverage == .dependencyClosure) &&
        (registry.localResult requirement).complete
  -- The legacy summary's proof field means native body completeness. A
  -- computational definition supplies a value, not a mathematical proof edge.
  let implementationComplete := locallyComplete `implementation NativeLean.bodyValidator implementationDeclarations
  let statementComplete := !(statementDeclarations.isEmpty && implementationDeclarations.isEmpty) &&
    (statementDeclarations.isEmpty || locallyComplete `statement NativeLean.statementValidator statementDeclarations) &&
    (implementationDeclarations.isEmpty || implementationComplete)
  let bodyComplete := !(proofDeclarations.isEmpty && implementationDeclarations.isEmpty) &&
    (proofDeclarations.isEmpty || locallyComplete `proof NativeLean.bodyValidator proofDeclarations) &&
    (implementationDeclarations.isEmpty || implementationComplete)
  let nativeRequirementKeys := canonical (nativeModels.flatMap (·.requirements)) |>.filter fun key =>
    match registry.requirement? key with
    | none => false
    | some requirement =>
      requirement.coverage == .dependencyClosure && (match requirement.expected with
        | .check validator => validator == NativeLean.statementValidator || validator == NativeLean.bodyValidator
        | _ => false)
  let nativeLocalComplete := hasNativeDeclarations && !nativeRequirementKeys.isEmpty &&
    nativeRequirementKeys.all fun key => (registry.resultForRequirement key).complete
  let uses := snapshot.uses.filter (·.source == label)
  let selected := uses.filter fun use => nativeModels.any fun model =>
    use.context == some model.context &&
      useSelectsRealization use.source use.realization use.role model
  let dependenciesComplete (statementOnly : Bool) :=
    (selected.filter fun use => !statementOnly || use.role == `statement).all fun use =>
      match use.selected with
      | .error _ => false
      | .ok keys => !keys.isEmpty && keys.all (fun key => (registry.resultForRequirement key).complete)
  let documentDiagnostics := if snapshot.sourceDiagnostics.documents.isEmpty then #[] else Id.run do
    let nodeModels := registry.realizations.filter (·.key.node == label)
    let nodeObjects := nodeModels.flatMap (·.declarations.map (·.object))
    let sourceDocuments := nodeModels.flatMap (·.documents) ++
      (registry.objects.filter (fun object => nodeObjects.contains object.key)).filterMap (·.document)
    return (snapshot.sourceDiagnostics.documents.filter (fun (document, _) => sourceDocuments.contains document)).map (·.2)
  let objects := canonical (declarations.map (·.object))
  let diagnostics := canonical (
    (snapshot.sourceDiagnostics.nodes.filter (·.1 == label)).map (·.2) ++
    documentDiagnostics)
  return {
    hasNativeDeclarations
    hasAxiomLike := snapshot.nativeChecks.any (fun checked => objects.contains checked.declaration && checked.status.isAxiomLike)
    nativeStatementComplete := statementComplete
    nativeProofComplete := bodyComplete
    requiredComplete := nativeLocalComplete
    selectedLeanUseCount := selected.size
    statementDependenciesComplete := dependenciesComplete true
    proofDependenciesComplete := dependenciesComplete false
    details := Json.mkObj [
      ("assessment", Report.ofNode registry label),
      ("nativeLocalSummary", Json.mkObj [
        ("declarations", toJson objects),
        ("statementComplete", toJson statementComplete),
        ("bodyComplete", toJson bodyComplete),
        ("requiredComplete", toJson nativeLocalComplete)]),
      ("uses", toJson (uses.map fun use => Json.mkObj [
        ("source", toJson use.source), ("targetContext", toJson use.context),
        ("realization", toJson use.realization), ("role", toJson use.role),
        ("reference", toJson use.reference), ("selection", toJson use.selected)])),
      ("sourceDiagnostics", toJson diagnostics)] }

private structure Collected where
  input : Input := {}
  observations : Array (Origin × RequirementKey × Observation) := #[]
  sourceDiagnostics : SourceDiagnostics := {}
  uses : Array UseDeclaration := #[]
  nativeChecks : Array NativeLean.CheckedDeclaration := #[]

private def recordObservation (collected : Collected) (key : RequirementKey) (observation : Observation) : Collected :=
  { collected with observations := collected.observations.push ((contribution `observation (BindingEncoding.requirementKey key) ()).origin, key, observation) }

/-- Lossless view of the fields consumed by capture; not another store. -/
structure Raw where
  nodes : Array (Name × Data.NodeInventory)
  registered : NameSet
  facts : List Contributions.Record
  authored : Array Environment.AuthoringRecord
  initialIssues : Array Diagnostic

def Raw.ofState (state : Environment.State) : Raw := {
  nodes := state.inventory.toArray
  registered := state.nodeRegistrations.toArray.foldl (fun names (name, _) => names.insert name) {}
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
  source : SourceSelection
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
  source : SourceSelection
  document : Nat
  documented : Option (Except Diagnostic Nat) := none
  deriving Inhabited

structure DeclarationStep where
  name : Name
  native : Array Nat := #[]
  inline : Array Nat := #[]
  check : Nat
  deriving Inhabited

private structure NativeDeclarationResult where
  name : Name
  prepared : Except (Array Diagnostic) NativeSource.Prepared
  checked : Except Diagnostic NativeLean.CheckedDeclaration

structure RealizationStep where
  key : RealizationKey
  sources : Array SourceStep
  associations : Array NativeAssociation
  declarations : Array DeclarationStep
  deriving Inhabited

structure NodeStep where
  label : Name
  accepted : Data.NodeInventory
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
    (source : Option SourceSelection) : CoreM (Except Diagnostic NativeSource.Request) := do
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
    if !p.raw.registered.contains label then
      reject "missing-source-envelope" label.toString "Accepted concept has no retained source registrations"
    if let .error diagnostics := Contributions.resolve label p.raw.facts then
      reject "producer-collision" label.toString (reprStr diagnostics)
    let uses := accepted.uses
    collected := { collected with
      input.nodes := collected.input.nodes.push (contribution `node (toJson (Vir.nameKey label))
        (accepted.toConcept label label.toString))
      uses := collected.uses ++ uses }
    for step in node.realizations do
      let base := step.key
      let sources := step.sources.map (·.source)
      let associations := step.associations
      let contexts := canonical (sources.map (·.context) ++ associations.map (·.context))
      unless contexts.size == 1 do
        reject "source-context-mismatch" label.toString "A realization requires one agreed stored source context"
      let context := contexts[0]!
      let object (name : Name) : ObjectKey := ⟨context, name.toString⟩
      let mut declarationResults : Array NativeDeclarationResult := #[]
      for declarationStep in step.declarations do
        let prepared ← prepareNative providers declarationStep
        let checked ← providers.check declarationStep.check
        if let .ok checked := checked then
          collected := { collected with nativeChecks := collected.nativeChecks.push checked }
        if let (.ok prepared, .ok checked) := (prepared, checked) then
          if prepared.roles != checked.roles then
            collected := { collected with sourceDiagnostics := collected.sourceDiagnostics.addNode label #[{
                code := "native-role-disagreement", subject := declarationStep.name.toString,
                message := "Owning-source and native-check classifications disagree" }] }
        declarationResults := declarationResults.push {
          name := declarationStep.name, prepared, checked }
      let checkedRoles := declarationResults.filterMap fun declaration =>
        match declaration.checked, declaration.prepared with
        | .ok checked, _ => some (declaration.name, checked.roles)
        | .error _, .ok prepared => some (declaration.name, prepared.roles)
        | _, _ => none
      let rolesForName (name : Name) : Array Name :=
        (checkedRoles.find? (·.1 == name)).map (·.2) |>.getD #[]
      let declarationRoles (name : Name) : Array Name :=
        SourceData.declarationRoles associations sources (rolesForName name) name
      let sourceRoleNames := sources.filterMap (·.destination.role)
      let roleNames := canonical (sourceRoleNames ++ declarationResults.flatMap fun declaration =>
        declarationRoles declaration.name)
      let mut sourceDocs : Array (Name × DocumentKey) := #[]
      for sourceStep in step.sources do
        let source := sourceStep.source
        let (document, readIssues) ← providers.document sourceStep.document
        collected := { collected with
          input.documents := collected.input.documents.push
            (contribution `document (BindingEncoding.documentKey document.key) document)
          sourceDiagnostics := { collected.sourceDiagnostics with
            documents := collected.sourceDiagnostics.documents ++ readIssues.map (document.key, ·) } }
        if let some reason := source.source.error then
          collected := { collected with sourceDiagnostics := collected.sourceDiagnostics.addNode label #[{
            code := "source-association-unavailable", subject := s!"{label}/{base.name}/{source.destination.role.getD `compiled}", message := reason }] }
        if let .prose _ := source.payload then
          let selectedKey := source.selectedDocumentKey
          let selectedText ← match sourceStep.documented with
            | none => pure (source.selectedText document)
            | some (.error diagnostic) =>
              collected := { collected with sourceDiagnostics := collected.sourceDiagnostics.addNode label #[diagnostic] }
              pure (.error diagnostic)
            | some (.ok handle) => do
              match ← providers.documented handle with
              | .error diagnostic =>
                collected := { collected with sourceDiagnostics := collected.sourceDiagnostics.addNode label #[diagnostic] }
                pure (.error diagnostic)
              | .ok documented =>
                if documented.format != source.context.language then
                  let diagnostic : Diagnostic := {
                    code := "source-format-unavailable"
                    subject := (toJson source.destination.subject).compress
                    message := "Direct native docstring format does not match its authored realization context" }
                  collected := { collected with sourceDiagnostics := collected.sourceDiagnostics.addNode label #[diagnostic] }
                  pure (.error diagnostic)
                else if documented.document.key.path != source.document.path ||
                    documented.document.text != document.text ||
                    documented.document.key.context.project != source.context.project then
                  pure (.error {
                    code := "source-selection-unavailable"
                    subject := (toJson source.destination.subject).compress
                    message := "Native doc comment does not belong to the selected owning source" })
                else
                  -- Attribute syntax locates the producer, not the comment body.
                  -- The native provider has already checked the unique declaration
                  -- and original comment against exact owning-file ranges.
                  pure (.ok documented.rawDocstring)
          let selectedValue ← match selectedText with
            | .ok text => pure text
            | .error diagnostic => do
              collected := { collected with sourceDiagnostics := collected.sourceDiagnostics.addNode label #[diagnostic] }
              pure ""
          let selectedDocument : Document := { key := selectedKey, text := selectedValue }
          let selectedContribution := contribution `document
            (BindingEncoding.documentKey selectedKey) selectedDocument
          collected := { collected with input := { collected.input with
            documents := collected.input.documents.push selectedContribution } }
          if let some role := source.destination.role then
            sourceDocs := sourceDocs.push (role, selectedKey)
        else
          if let some role := source.destination.role then
            sourceDocs := sourceDocs.push (role, source.selectedDocumentKey)
      let mut roleModels : Array Realization := #[]
      for role in roleNames do
        let declarations := declarationResults.filterMap fun result => Id.run do
          let roles := declarationRoles result.name
          unless roles.contains role do return none
          let witness := object result.name
          let nativeRoles := rolesForName result.name
          let requirement : RequirementKey := ⟨.declaration (base.forRole role) witness, role⟩
          let selected := !nativeRoles.isEmpty && nativeRoles.contains role
          let required := if selected then #[requirement] else #[]
          return some {
            object := witness,
            projection := if role == `statement then .statement else .implementation,
            required }
        let documents := canonical (sourceDocs.filterMap fun (sourceRole, document) =>
          if sourceRole == role then some document else none)
        roleModels := roleModels.push {
          key := base.forRole role, context, role, documents, declarations }
      let issues := if context.language == `lean then
          roleModels.flatMap fun model => nativeMembershipIssues label model associations sources checkedRoles
        else roleModels.flatMap fun model =>
          (sources.filter (·.destination.role == some model.role)).flatMap (·.issues label model)
      unless issues.isEmpty do full (.error issues)
      for declaration in declarationResults do
        let witness := object declaration.name
        let nativeRoles := declarationRoles declaration.name
        let objectObservation : ObjectObservation ← match declaration.prepared with
          | .error issues => do
            collected := { collected with sourceDiagnostics := collected.sourceDiagnostics.addNode label issues }
            pure {
              key := witness
              resolution := if issues.any (·.code == "missing-declaration") then .missing else .unsupported
              explanation := (toJson issues).compress }
          | .ok prepared => do
            collected := { collected with
              sourceDiagnostics := collected.sourceDiagnostics.addNode label prepared.semanticDiagnostics
              input.documents := collected.input.documents.push
                (contribution `document (BindingEncoding.documentKey prepared.document.key) prepared.document)
              input.bindingInputs := collected.input.bindingInputs ++ nativeRoles.flatMap fun role =>
                if role == `statement then
                  prepared.statementContext.toArray.map fun content => contribution `nativeStatementContext
                    (BindingEncoding.subject (Subject.declaration (base.forRole role) witness)) {
                      subject := .declaration (base.forRole role) witness,
                      name := NativeLean.statementContext, content }
                else prepared.semanticContext.toArray.map fun content => contribution `nativeContext
                  (BindingEncoding.subject (Subject.declaration (base.forRole role) witness)) {
                    subject := .declaration (base.forRole role) witness,
                    name := NativeLean.sourceContext, content } }
            pure { key := witness, resolution := .resolved, document := some prepared.document.key }
        collected := { collected with
          input.objects := collected.input.objects.push
            (contribution `object (BindingEncoding.objectKey witness) objectObservation) }
        for role in nativeRoles do
          unless (rolesForName declaration.name).contains role do continue
          let key : RequirementKey := ⟨.declaration (base.forRole role) witness, role⟩
          let validator := if role == `statement then NativeLean.statementValidator else NativeLean.bodyValidator
          let prerequisites := if role == `proof then
            #[⟨.declaration (base.forRole `statement) witness, `statement⟩] else #[]
          collected := { collected with
            input.requirements := collected.input.requirements.push
              (contribution `requirement (BindingEncoding.requirementKey key) {
                key, expected := .check validator, coverage := .dependencyClosure, prerequisites }) }
          match declaration.checked with
          | .ok checked =>
            collected := recordObservation collected key
              (.check (if role == `statement then checked.statement else checked.body))
          | .error diagnostic =>
            collected := recordObservation collected key (.check {
              validator, declaration := some witness, outcome := .unavailable,
              explanation := diagnostic.message })
      for model in roleModels do
        collected := { collected with
          input.realizations := collected.input.realizations.push
            (contribution `realization (BindingEncoding.realizationKey model.key) model) }
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
      let key := key.forRole `proof
      let models := canonical ((collected.input.realizations.filter (·.value.key == key)).map (·.value))
      unless models.size == 1 && models[0]!.context == ⟨`lean, record.project⟩ && models[0]!.declarations.size == 1 do
        reject "ambiguous-native-expectation" node.toString
          "Expected proposition requires one exact ordinary proof realization in its stored context" #[record.origin]
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
        bindingInputs := collected.input.bindingInputs ++ (checked.semanticContext.toArray.map fun content =>
          authoredContribution record.origin `expectedContext index {
            subject := expectedKey.subject, name := NativeLean.expectedContextFor expectedKey, content }) ++
          (checked.statementContext.toArray.map fun content => authoredContribution record.origin `expectedStatementContext index {
            subject := expectedKey.subject, name := NativeLean.expectedStatementContextFor expectedKey, content }) }
      collected := { collected with
        input := input
        sourceDiagnostics := collected.sourceDiagnostics.addNode node checked.semanticDiagnostics
        observations := collected.observations.push ((authoredContribution record.origin `expectedObservation index ()).origin,
          expectedKey, .proof checked.observation) }
    let batch := record.authored
    for index in [:batch.sources.size] do
      let (document, issues) ← providers.document step.documents[index]!
      collected := { collected with
        input.documents := collected.input.documents.push (authoredContribution record.origin `document index document)
        sourceDiagnostics := { collected.sourceDiagnostics with
          documents := collected.sourceDiagnostics.documents ++ issues.map (document.key, ·) } }
    collected := { collected with input := { collected.input with
      objects := collected.input.objects ++ batch.references.mapIdx (fun index (key, document) =>
        authoredContribution record.origin `reference index {
          key, document, resolution := .unsupported, explanation := "Authored reference: source-native resolver/checker is not connected" })
      realizations := collected.input.realizations ++ batch.realizations.mapIdx (authoredContribution record.origin `realization)
      translations := collected.input.translations ++ batch.translations.mapIdx (authoredContribution record.origin `translation)
      claims := collected.input.claims ++ batch.claims.mapIdx (authoredContribution record.origin `claim)
      requirements := collected.input.requirements ++ batch.requirements.mapIdx (authoredContribution record.origin `requirement)
      evidence := collected.input.evidence ++ batch.reviews.mapIdx (fun index judgment =>
        authoredContribution record.origin `review index {
          id := judgment.id, requirement := judgment.requirement, binding := judgment.binding,
          observation := .review judgment.observation })
      reviewSelections := collected.input.reviewSelections ++
        batch.reviewSelections.mapIdx (authoredContribution record.origin `reviewSelection) } }
  return collected

/-- Select the complete ordinary native contract, independently of its outcome.
Alternatives are explicit realizations and cannot rescue the default. -/
private def selectTarget (collected : Collected) (context : Context) (target : Name) :
    Except Diagnostic (Array RequirementKey) := do
  let input := collected.input
  let fail (code message : String) : Except Diagnostic (Array RequirementKey) := .error {
    code, subject := target.toString, message }
  unless input.nodes.any (·.value.label == target) do
    return ← fail "missing-target" "No accepted dependency target"
  let candidates := (ordinaryNativeRealizations input target).filter fun model =>
    model.context == context &&
      (model.role == `proof || model.role == `implementation || model.role == `statement)
  let proofs := candidates.filter (·.role == `proof)
  let implementations := candidates.filter (·.role == `implementation)
  let statements := candidates.filter (·.role == `statement)
  if proofs.size > 1 || implementations.size > 1 || (proofs.isEmpty && statements.size > 1) then
    return ← fail "ambiguous-native-contract"
      "Dependency has multiple ordinary native developments and no unique target contract"
  let failModel (code message : String) : Except Diagnostic (Array Realization) := .error {
    code, subject := target.toString, message }
  let proofObjects := proofs.flatMap (·.declarations.map (·.object))
  let extraStatements := (statements.flatMap (·.declarations.map (·.object))).any
    (fun object => !proofObjects.contains object)
  let propositionDefinitions := statements.all fun model => model.declarations.all fun declaration =>
    (collected.nativeChecks.find? (·.declaration == declaration.object)).any (·.roles == #[`statement])
  let modelSelection : Except Diagnostic (Array Realization) :=
    if !proofs.isEmpty && implementations.isEmpty then
      if extraStatements then failModel "ambiguous-native-contract"
        "Dependency includes a proposition definition in addition to its proof target"
      else .ok proofs
    else if proofs.isEmpty && !implementations.isEmpty && statements.isEmpty then .ok implementations
    else if proofs.isEmpty && implementations.isEmpty && !statements.isEmpty then
      if propositionDefinitions then .ok statements
      else failModel "missing-native-contract"
        "A native statement without a proof role is a dependency target only when its checked declaration defines a proposition"
    else failModel (if candidates.isEmpty then "missing-native-contract" else "ambiguous-native-contract")
      "Dependency needs one unambiguous direct native proof, implementation, or proposition definition"
  let models ← modelSelection
  unless !models.isEmpty && models.all (·.context == context) do
    return ← fail "wrong-default-context" "Dependency belongs to another project context"
  let mut required := #[]
  for model in models do
    unless !model.declarations.isEmpty do
      return ← fail "missing-native-contract" "Dependency has no selected native declarations"
    let validator := if model.role == `statement then NativeLean.statementValidator else NativeLean.bodyValidator
    for declaration in model.declarations do
      let key : RequirementKey := ⟨.declaration model.key declaration.object, model.role⟩
      let contracts := canonical ((input.requirements.filter (·.value.key == key)).map (·.value))
      let expectedProjection := if model.role == `statement then .statement else .implementation
      let roleMatches := (collected.nativeChecks.find? (·.declaration == declaration.object)).any
        (·.roles.contains model.role)
      unless roleMatches && declaration.projection == expectedProjection && contracts.size == 1 &&
          contracts[0]!.expected == .check validator && contracts[0]!.coverage == .dependencyClosure &&
          declaration.required.contains key do
        return ← fail "invalid-native-contract" "Dependency requires its exact selected native role and completeness contract"
      if model.role == `proof then
        let hasStatement := contracts[0]!.prerequisites.any fun prerequisite =>
          statements.any fun statementModel =>
            prerequisite == ⟨.declaration statementModel.key declaration.object, `statement⟩ &&
            statementModel.declarations.any (·.object == declaration.object)
        unless hasStatement do
          return ← fail "invalid-native-contract" "A proof role must depend on its selected proposition type"
      required := required ++ declaration.required
    required := required ++ model.required
  return canonical required

private def selectUses (collected : Collected) : Array SelectedUse := Id.run do
  let mut selected := #[]
  let scopes := (collected.uses.map fun use => (use.node, use.realization, use.role)).foldl
    (fun scopes scope => if scopes.contains scope then scopes else scopes.push scope) #[]
  for (source, realization, role) in scopes do
    let uses := Data.UseRef.mergeByLabel #[] <| (collected.uses.filter fun use =>
      use.node == source && use.realization == realization && use.role == role).map (·.reference)
    let models := collected.input.realizations.filter fun contribution =>
      useSelectsRealization source realization role contribution.value
    let contexts := canonical (models.map fun contribution =>
      ({ language := `lean, project := contribution.value.context.project } : Context))
    for reference in uses do
      if contexts.isEmpty then
        selected := selected.push {
          source, realization, role, reference, context := none
          selected := .error {
            code := "missing-source-context", subject := source.toString
            message := "Dependency has no stored source project context" } }
      else
        for context in contexts do
          selected := selected.push {
            source, realization, role, reference, context := some context
            selected := selectTarget collected context reference.label }
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
    if model.context.language != `lean ||
        (model.role != `statement && model.role != `proof && model.role != `implementation) then continue
    let relevant := uses.filter fun use => use.context == some model.context &&
      useSelectsRealization use.source use.realization use.role model
    for declaration in model.declarations do
      let subject := Subject.declaration model.key declaration.object
      let name := model.role
      let validator := if name == `statement then NativeLean.statementValidator else NativeLean.bodyValidator
      let key : RequirementKey := ⟨subject, name⟩
      unless nativeContracts[key]? == some validator do continue
      let edges := relevant
      let mut prerequisites : Array RequirementKey := #[]
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
              edge.role, edge.reference, edge.selected))).compress }) } }
        collected := recordObservation collected selectionKey (.check {
          validator := `blueprint.dependencySelection
          outcome := if failures.isEmpty then .passed else .unavailable
          explanation := if failures.isEmpty then "Every dependency selected its exact current native contract"
            else (toJson failures).compress })
      collected := { collected with input.requirements := collected.input.requirements.map fun contribution =>
        if contribution.value.key != key then contribution else { contribution with value := {
          contribution.value with prerequisites := canonical (contribution.value.prerequisites ++ prerequisites) } } }
  return collected

/-- Derive edge-local own-type observations from the real native declaration
checks already run for this capture. This reuses only the underlying checked
fact; `finish later binds each copy to its exact `proves contract. -/
private def attachOwnTypeObservations (collected : Collected) : Collected := Id.run do
  let mut collected := collected
  for requirement in collected.input.requirements do
    let .proves witness := requirement.value.expected | continue
    let observation := match collected.nativeChecks.find? (·.declaration == witness) with
      | some checked =>
        .check { checked.body with validator := NativeLean.ownTypeValidator }
      | none =>
        .check {
          validator := NativeLean.ownTypeValidator
          declaration := some witness
          outcome := .unavailable
          explanation := "No native declaration check in this capture applies to the selected witness" }
    collected := recordObservation collected requirement.value.key observation
  return collected

private def assemble [Monad m] (providers : Providers m) (p : Plan) : ExceptT (Array Diagnostic) m Collected := do
  unless p.raw.initialIssues.isEmpty do full (.error (canonical p.raw.initialIssues))
  let collected ← collectOrdinary providers p >>= collectAuthored providers p
  let models := collected.input.realizations.map (·.value)
  for node in p.ordinary do
    let issues := node.accepted.uses.flatMap (·.issues node.label models)
    unless issues.isEmpty do full (.error (canonical issues))
  return collected

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
  let collected := attachOwnTypeObservations collected
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
    registry := ← admit input, uses
    sourceDiagnostics := {
      nodes := canonicalDiagnostics collected.sourceDiagnostics.nodes
      documents := canonicalDiagnostics collected.sourceDiagnostics.documents }
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
facts are not authenticated here: production must call `observe freshly. -/
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

/-- Execute the observation phase, converting ordinary exceptions to diagnostics.
Lean runtime resource exceptions and interrupts propagate; they cannot produce
partial observations. Environment, metavariables and info state are restored on
every exit, while traces are retained. This is also the scope used by `observe. -/
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
