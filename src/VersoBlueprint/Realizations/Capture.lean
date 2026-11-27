/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment
import VersoBlueprint.ExternalModuleSource
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

/-- Identity-bearing fields of the selected use, including the exact target
contracts. Public display spellings are insufficient for structural bindings. -/
def SelectedUse.bindingData (edge : SelectedUse) : Json :=
  let selection := match edge.selected with
    | .ok keys => toJson ("selected", keys.map BindingEncoding.requirementKey)
    | .error d => toJson ("unresolved", d.code, d.subject, d.message, d.origins.map fun (origin : Origin) =>
        (Vir.nameKey origin.id, Vir.nameKey origin.moduleName, origin.source))
  toJson (Vir.nameKey edge.source, edge.context.map BindingEncoding.context,
    edge.realization.map Vir.nameKey, Vir.nameKey edge.role, Vir.nameKey edge.reference.label,
    edge.reference.origin, edge.reference.intent, selection)

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
private def isOrdinaryRealization (record : Contribution Realization) : Bool :=
  record.origin == (contribution `realization (BindingEncoding.realizationKey record.value.key) ()).origin

private def ordinaryNativeRealizations (input : Input) (label : Name) : Array Realization :=
  canonical ((input.realizations.filter fun record =>
    record.value.key.node == label && record.value.context.language == `lean &&
      isOrdinaryRealization record).map (·.value))

/-- Look up a declaration in the selected ordinary models. A node-level request
without an object must select a singleton realization. An exact dependency can
select a member of an ordinary realization with multiple declarations. -/
private def exactNativeOwners (models : Array Realization) (context : Context) (role : Name)
    (object : Option ObjectKey) : Array (Realization × Declaration) :=
  models.filterMap fun model => do
    guard (model.context == context && model.role == role)
    let declaration ← match object with
      | some object => model.declaration? object
      | none => match model.declarations with
        | #[declaration] => some declaration
        | _ => none
    let projection := if role == `statement then ContentScope.statement else .implementation
    guard (declaration.object.context == context && declaration.projection == projection)
    return (model, declaration)

/-- The ordinary source producer's native models, derived from the admitted
contributions. Full authored alternatives remain available in `registry`. -/
def Snapshot.nativeRealizationsFor (snapshot : Snapshot) (label : Name) : Array Realization :=
  ordinaryNativeRealizations snapshot.registry.contributions label

private def nativeValidator (role : Name) : Name :=
  if role == `statement then NativeLean.statementValidator else NativeLean.bodyValidator

/-- Derive a consumer view from the same admitted snapshot. No source/status
fallbacks, new checker invocation or second dependency evaluator occur here. -/
def Snapshot.assessmentFor (snapshot : Snapshot) (label : Name) : NodeAssessment := Id.run do
  let registry := snapshot.registry
  let nativeModels := snapshot.nativeRealizationsFor label
  let objects := canonical (nativeModels.flatMap fun model => model.declarations.map (·.object))
  let checks := nativeModels.flatMap fun model => model.declarations.map fun declaration =>
    let key : RequirementKey := ⟨.declaration model.key declaration.object, model.role⟩
    let contract := (registry.requirement? key).filter fun value =>
      declaration.required.contains key && value.expected == .check (nativeValidator model.role) &&
        value.coverage == .dependencyClosure
    (model.role, contract.map (·.key))
  -- A declaration retained at its fallback placement may have no classified
  -- role. Every selected declaration must have its native contract before a
  -- sibling can contribute to a complete node summary.
  let coversDeclarations := !checks.isEmpty && checks.all (·.2.isSome)
  let locallyComplete (selected : Array (Name × Option RequirementKey)) :=
    coversDeclarations && !selected.isEmpty &&
      selected.all fun (_, key) => key.any fun key => (registry.localResult key).complete
  -- The legacy summary's proof field means native body completeness. A
  -- computational definition supplies a value, not a mathematical proof edge.
  let bodyChecks := checks.filter (·.1 != `statement)
  let statementComplete := locallyComplete (checks.filter (·.1 != `proof))
  let bodyComplete := locallyComplete bodyChecks
  let proofChecks := checks.filter (·.1 == `proof)
  let proofRoleComplete := if proofChecks.isEmpty then none else some (locallyComplete proofChecks)
  let requiredComplete := coversDeclarations &&
    checks.all fun (_, key) => key.any fun key => (registry.resultForRequirement key).complete
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
  let diagnostics := canonical (
    (snapshot.sourceDiagnostics.nodes.filter (·.1 == label)).map (·.2) ++
    documentDiagnostics)
  return {
    hasNativeDeclarations := !objects.isEmpty
    hasAxiomLike := snapshot.nativeChecks.any (fun checked => objects.contains checked.declaration && checked.status.isAxiomLike)
    nativeStatementComplete := statementComplete
    hasNativeBodyRequirement := bodyChecks.any (·.2.isSome)
    nativeProofComplete := bodyComplete
    proofRoleComplete
    requiredComplete
    selectedLeanUseCount := selected.size
    statementDependenciesComplete := dependenciesComplete true
    proofDependenciesComplete := dependenciesComplete false
    details := Json.mkObj [
      ("assessment", Report.ofNode registry label),
      ("nativeLocalSummary", Json.mkObj [
        ("declarations", toJson objects),
        ("statementComplete", toJson statementComplete),
        ("bodyComplete", toJson bodyComplete),
        ("requiredComplete", toJson requiredComplete)]),
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

/-- A native source request is identified by what it asks: the declaration in
its context and the owning-source facts recorded with it. The association's
retained presentation snapshots are not part of the request. A plain native
declaration is answered from the environment; only the doc-comment and inline
families read the file at `sourcePath?`. -/
structure NativeRequest where
  context : Context
  name : Name
  moduleName? : Option Name := none
  sourcePath? : Option String := none
  /-- An adopted source must still be owned by this imported Lake package. -/
  package? : Option String := none
  range? : Option DeclarationRange := none
  selectionRange? : Option DeclarationRange := none
  deriving Inhabited, BEq

instance : Hashable NativeRequest := ⟨fun request => hash (request.context, request.name, request.sourcePath?)⟩

def NativeRequest.ofAssociation (context : Context) (association : NativeAssociation) : NativeRequest := {
  context, name := association.reference.canonical
  moduleName? := association.reference.provenance.moduleName?
  sourcePath? := association.reference.provenance.sourcePath?
  range? := association.reference.range?, selectionRange? := association.reference.selectionRange? }

/-- Only a checked occurrence can request a shared native association. Equality
includes the original source buffer and the selected literal's byte range. -/
structure InlineRequest where
  native : NativeRequest
  block : NativeSource.InlineBlock
  deriving Inhabited, BEq

instance : Hashable InlineRequest := ⟨fun request => hash request.native⟩

structure CheckRequest where
  project : Name
  witness : ObjectKey
  deriving Inhabited, BEq, Hashable

structure SpecificationRequest where
  expected : Name
  origin : Origin
  document : Nat
  deriving Inhabited

/-- What a specification answer answers, including the bytes the recipe read. -/
structure SpecificationKey where
  expected : Name
  origin : Origin
  document : Document
  deriving BEq

instance : Hashable SpecificationKey := ⟨fun key => hash (key.expected, key.document.key)⟩

/-- The goal's documents depend on its specification and on the documents of
earlier observations of its witness; a native declaration's observation carries
none. The recipe resolves them at this exact record position. -/
structure ExpectedRequest where
  node : Name
  expected : Name
  project : Name
  origin : Origin
  specification : Nat
  deriving Inhabited

/-- What an expected-goal answer answers. The recipe resolves its witness and
documents from earlier results, so they belong to its identity. -/
structure ExpectedKey where
  project : Name
  expected : Name
  witness : ObjectKey
  documents : Array DocumentKey
  deriving BEq, Hashable

/-- Prose takes its text from the stored syntax and requests no document. -/
structure SourceStep where
  source : SourceSelection
  document : Option Nat := none
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

/-- Typed request inventories and an ordered assembly recipe. The recipe refers
to its requests by local array position; positions identify neither producers
nor answers. Structural errors are deliberately checked by the recipe, not
eagerly returned ahead of earlier provider failures. -/
structure Plan where
  raw : Raw
  documents : Array DocumentKey := #[]
  native : Array NativeRequest := #[]
  inline : Array (Except Diagnostic InlineRequest) := #[]
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
        let mut document := none
        unless source.payload matches .prose _ do
          document := some result.documents.size
          result := { result with documents := result.documents.push source.document }
        let mut documented : Option (Except Diagnostic Nat) := none
        if let some adoption := source.adoption then
          let owners := records.filter fun record =>
            record.id.producer == `blueprint.directive && record.id.moduleName == adoption.consumerModule &&
              record.source.isSome && record.source == source.source.location
          let selected := (owners.flatMap (·.nativeAssociations)).filter fun association =>
            association.reference.canonical == adoption.canonical && association.placement == `statement &&
              association.realization == ⟨label, `lean⟩ &&
              association.context == ⟨`lean, source.context.project⟩
          let selected := selected.toList.eraseDups.toArray
          match adoption.owner, selected, adoption.package with
          | .error diagnostic, _, _ => documented := some (.error diagnostic)
          | .ok (path, _), #[association], some pkg =>
            if association.reference.provenance.moduleName? != some adoption.moduleName then
              documented := some (.error {
                code := "source-association-unavailable", subject := label.toString
                message := "Adopted docstring and native attachment disagree on the owning module" })
            else
              documented := some (.ok result.documented.size)
              let job := { NativeRequest.ofAssociation association.context association with
                sourcePath? := some path, package? := some pkg }
              result := { result with documented := result.documented.push job }
          | _, _, _ => documented := some (.error {
              code := "ambiguous-docstring", subject := label.toString
              message := "An adopted docstring requires its own directive's unique selected native attachment" })
        else if let some owner := source.ownDocstring then
          let owners := records.filter fun record => record.id.producer == `blueprint.attribute &&
            record.id.moduleName == owner.moduleName && record.id.subject == owner.canonical &&
            record.source.isSome && record.source == source.source.location
          let selected : Array NativeAssociation := (owners.flatMap (·.nativeAssociations)).filter fun association =>
            association.reference.canonical == owner.canonical && association.placement == `statement &&
              association.realization == ⟨label, `lean⟩ &&
              association.context == ⟨`lean, source.context.project⟩
          match selected.toList.eraseDups.toArray with
          | #[association] =>
            documented := some (.ok result.documented.size)
            let request := NativeRequest.ofAssociation association.context association
            result := { result with documented := result.documented.push request }
          | _ =>
            documented := some (.error {
              code := "ambiguous-docstring", subject := label.toString,
              message := "Attribute prose requires one exact owning native association" })
        sourceSteps := sourceSteps.push { source, document, documented }
      let mut declarations := #[]
      for name in nativeNames associations sources do
        let mut native := #[]
        let mut inline := #[]
        for association in associations.filter (·.reference.canonical == name) do
          native := native.push result.native.size
          result := { result with native := result.native.push (NativeRequest.ofAssociation context association) }
        for source in sources do
          if let .leanInline code := source.payload then
            if (code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)).contains name then
              inline := inline.push result.inline.size
              let job := (NativeSource.selectInline name code (source.source.location.map (·.range))).map fun block => {
                native := { context, name, sourcePath? := some source.document.path }, block : InlineRequest }
              result := { result with inline := result.inline.push job }
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
      goals := goals.push result.expected.size
      result := { result with expected := result.expected.push {
        node, expected, project := record.project, origin := record.origin, specification } }
    let mut documents := #[]
    for document in record.authored.sources do
      documents := documents.push result.documents.size
      result := { result with documents := result.documents.push document }
    result := { result with authored := result.authored.push { record, goals, documents } }
  return result

/-- An answer owns the identity of the request it answers. -/
structure ResultEntry (request : Type) (α : Type) where
  request : request
  result : α

/-- Answers identified by the request they answer, not by a position in a plan,
so any plan asking the same requests can use them. Answers that no request asks
for are ignored. Pure evaluation checks association and shape, not authenticity
of supplied facts. -/
structure Observations where
  documents : Array (ResultEntry DocumentKey (Document × Array Diagnostic)) := #[]
  native : Array (ResultEntry NativeRequest (Except Diagnostic NativeSource.Prepared)) := #[]
  inline : Array (ResultEntry InlineRequest (Except Diagnostic NativeSource.Prepared)) := #[]
  documented : Array (ResultEntry NativeRequest (Except Diagnostic NativeSource.Documented)) := #[]
  checks : Array (ResultEntry CheckRequest (Except Diagnostic NativeLean.CheckedDeclaration)) := #[]
  specifications : Array (ResultEntry SpecificationKey (Except (Array Diagnostic) Unit)) := #[]
  expected : Array (ResultEntry ExpectedKey (Except Diagnostic NativeLean.Checked)) := #[]

/-- The same assembly recipe is interpreted once with real providers and once
with pure table lookups. No admission happens in the provider interpreter. -/
private structure Providers (m : Type → Type) where
  document : DocumentKey → ExceptT (Array Diagnostic) m (Document × Array Diagnostic)
  native : NativeRequest → ExceptT (Array Diagnostic) m (Except Diagnostic NativeSource.Prepared)
  inline : InlineRequest → ExceptT (Array Diagnostic) m (Except Diagnostic NativeSource.Prepared)
  documented : NativeRequest → ExceptT (Array Diagnostic) m (Except Diagnostic NativeSource.Documented)
  check : CheckRequest → ExceptT (Array Diagnostic) m (Except Diagnostic NativeLean.CheckedDeclaration)
  specification : SpecificationKey → ExceptT (Array Diagnostic) m (Except (Array Diagnostic) Unit)
  expected : ExpectedKey → ExceptT (Array Diagnostic) m (Except Diagnostic NativeLean.Checked)

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

private def request (job : NativeRequest) : CoreM (Except Diagnostic NativeSource.Request) := do
  let name := job.name
  let env ← getEnv
  unless (env.checked.get.find? name).isSome do
    return .error {
      code := "missing-declaration", subject := name.toString
      message := "Declaration is not in the current checked environment" }
  let owner := (env.getModuleIdxFor? name).bind (fun index => env.header.moduleNames[index.toNat]?)
    |>.getD env.mainModule
  if let some moduleName := job.moduleName? then
    if moduleName != owner then return .error {
      code := "source-association-unavailable", subject := name.toString
      message := "Stored native module disagrees with current declaration owner" }
  return .ok {
    project := job.context.project, canonical := name, moduleName := owner
    range? := job.range?, selectionRange? := job.selectionRange? }

/-- The owning source file, for the providers that read it: the recorded path,
or the owning module's source on the search path. A plain native declaration
never asks, so a dependency shipped without sources does not affect it. -/
private def sourcePath (job : NativeRequest) (request : NativeSource.Request) : CoreM (Except Diagnostic String) := do
  if let some pkg := job.package? then
    let env ← getEnv
    if let some idx := env.getModuleIdxFor? job.name then
      if let some owner ← ExternalModuleSource.find? env idx then
        if owner.package == pkg && owner.module == request.moduleName && job.sourcePath? == some owner.path.toString then
          return .ok owner.path.toString
    return .error {
      code := "source-association-unavailable", subject := job.name.toString
      message := "Adopted docstring no longer belongs to the selected upstream package, module and file" }
  if let some path := job.sourcePath? then return .ok path
  if request.moduleName == (← getEnv).mainModule then return .ok (← getFileName)
  let some path ← (← getSrcSearchPath).findModuleWithExt "lean" request.moduleName
    | return .error {
        code := "source-association-unavailable", subject := job.name.toString
        message := "Owning module source path is unavailable" }
  return .ok path.toString

private def prepareNative [Monad m] (providers : Providers m) (p : Plan) (step : DeclarationStep) :
    ExceptT (Array Diagnostic) m (Except (Array Diagnostic) NativeSource.Prepared) := do
  let name := step.name
  let mut prepared := #[]
  let mut issues := #[]
  for handle in step.native do
    match ← providers.native p.native[handle]! with
    | .error issue => issues := issues.push issue
    | .ok value => prepared := prepared.push value
  for handle in step.inline do
    let result ← match p.inline[handle]! with
      | .error issue => pure (.error issue)
      | .ok job => providers.inline job
    match result with
    | .error issue => issues := issues.push issue
    | .ok value => prepared := prepared.push value
  if !issues.isEmpty then return .error (canonical issues)
  let some first := prepared[0]?
    | return .error #[{ code := "source-association-unavailable", subject := name.toString, message := "No owning source association" }]
  if prepared.any (fun other => other.ranges.range != first.ranges.range ||
      other.ranges.selectionRange != first.ranges.selectionRange ||
      other.moduleName != first.moduleName || other.declaration != first.declaration) then
    return .error #[{ code := "ambiguous-source", subject := name.toString, message := "Competing owning sources for the same declaration" }]
  return .ok first

private def ordinaryNodeIssue (raw : Raw) (node : NodeStep) : Option Diagnostic :=
  if !raw.registered.contains node.label then
    some { code := "missing-source-envelope", subject := node.label.toString
           message := "Accepted concept has no retained source registrations" }
  else if let .error diagnostics := Contributions.resolve node.label raw.facts then
    some { code := "producer-collision", subject := node.label.toString, message := reprStr diagnostics }
  else none

private def realizationContext (label : Name) (step : RealizationStep) : Except Diagnostic Context :=
  let contexts := canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context))
  if contexts.size == 1 then .ok contexts[0]!
  else .error { code := "source-context-mismatch", subject := label.toString
                message := "A realization requires one agreed stored source context" }

/-- Schedule only the prefix that the ordinary recipe can reach. The recipe
still emits structural diagnostics at their original positions. -/
private def Plan.scheduledChecks (p : Plan) : Array (Name × ObjectKey) := Id.run do
  let mut requests := #[]
  for node in p.ordinary do
    if (ordinaryNodeIssue p.raw node).isSome then return requests
    for step in node.realizations do
      unless (realizationContext node.label step).isOk do return requests
      for declaration in step.declarations do
        if let some check := p.checks[declaration.check]? then
          requests := requests.push (check.project, check.witness)
  return requests

private def collectOrdinary [Monad m] (providers : Providers m) (p : Plan) : ExceptT (Array Diagnostic) m Collected := do
  let mut collected : Collected := {}
  let mut associationsByObject : Std.HashMap ObjectKey (Except (Array Diagnostic) Unit) := {}
  for node in p.ordinary do
    let label := node.label
    let accepted := node.accepted
    if let some issue := ordinaryNodeIssue p.raw node then
      full (.error #[issue])
    let uses := accepted.uses
    collected := { collected with
      input.nodes := collected.input.nodes.push (contribution `node (toJson (Vir.nameKey label))
        (accepted.toConcept label label.toString))
      uses := collected.uses ++ uses }
    for step in node.realizations do
      let base := step.key
      let sources := step.sources.map (·.source)
      let associations := step.associations
      let context ← one (realizationContext label step)
      let object (name : Name) : ObjectKey := ⟨context, name.toString⟩
      let mut declarationResults : Array NativeDeclarationResult := #[]
      for declarationStep in step.declarations do
        let prepared ← prepareNative providers p declarationStep
        let checked ← providers.check p.checks[declarationStep.check]!
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
        if let some handle := sourceStep.document then
          let (document, readIssues) ← providers.document p.documents[handle]!
          let (document, readIssues) := if source.fence.isSome then
              let key := source.selectedDocumentKey
              if !readIssues.isEmpty then ({ key, text := "" }, readIssues) else
                match source.selectedFenceText document with
                | .ok text => ({ key, text }, #[])
                | .error issue => ({ key, text := "" }, #[issue])
            else (document, readIssues)
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
            | none => pure source.selectedText
            | some (.error diagnostic) =>
              pure (.error diagnostic)
            | some (.ok handle) => do
              match ← providers.documented p.documented[handle]! with
              | .error diagnostic =>
                pure (.error diagnostic)
              | .ok documented =>
                if documented.format != source.context.language then
                  let diagnostic : Diagnostic := {
                    code := "source-format-unavailable"
                    subject := (toJson source.destination.subject).compress
                    message := "Direct native docstring format does not match its authored realization context" }
                  pure (.error diagnostic)
                else if let some adoption := source.adoption then
                  if adoption.owner.toOption == some (documented.document.key.path, SHA256.text documented.document.text) &&
                      documented.canonical == adoption.canonical &&
                      documented.moduleName == adoption.moduleName &&
                      documented.document.key.context.project == source.context.project then
                    pure (.ok documented.rawDocstring)
                  else
                    pure (.error {
                      code := "source-selection-unavailable", subject := adoption.canonical.toString
                      message := "External docstring owner or exact source bytes changed since consumer registration" })
                else
                  -- Attribute syntax locates the producer, not the comment body.
                  -- The native provider has already checked the unique declaration
                  -- and original comment against exact owning-file ranges.
                  if (source.ownDocstring.any fun owner =>
                      documented.canonical == owner.canonical && documented.moduleName == owner.moduleName) &&
                      documented.document.key.path == source.document.path &&
                      some documented.document.text == source.proseBuffer? &&
                      documented.document.key.context.project == source.context.project then
                    pure (.ok documented.rawDocstring)
                  else
                    pure (.error {
                      code := "source-selection-unavailable"
                      subject := (toJson source.destination.subject).compress
                      message := "Native doc comment does not belong to the selected owning source" })
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
            required, sourceIssues := match result.prepared with
              | .error issues => issues
              | .ok _ => #[] }
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
        let association : Except (Array Diagnostic) Unit ← match declaration.prepared with
          | .error issues => do
            collected := { collected with sourceDiagnostics := collected.sourceDiagnostics.addNode label issues }
            pure (.error issues)
          | .ok prepared => do
            collected := { collected with
              sourceDiagnostics := collected.sourceDiagnostics.addNode label prepared.semanticDiagnostics
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
            pure (.ok ())
        -- Any successful association resolves the shared object. The owned
        -- selection keeps its own failure even if a sibling succeeds.
        let combined := match associationsByObject[witness]?, association with
          | some (.ok ()), _ => .ok ()
          | some (.error prior), .error issues => .error (prior ++ issues)
          | _, current => current
        associationsByObject := associationsByObject.insert witness combined
        for role in nativeRoles do
          unless (rolesForName declaration.name).contains role do continue
          let key : RequirementKey := ⟨.declaration (base.forRole role) witness, role⟩
          let validator := nativeValidator role
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
  let objects := associationsByObject.toArray.map fun (key, association) =>
    let value : ObjectObservation := match association with
      | .ok () => { key, resolution := .resolved }
      | .error issues => {
        key, resolution := if issues.any (·.code == "missing-declaration") then .missing else .unsupported
        explanation := (toJson (canonical issues)).compress }
    contribution `object (BindingEncoding.objectKey key) value
  return { collected with input.objects := objects }

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
  -- The checked, owned definition still identifies the goal if its source
  -- cannot be read. Capture then records the authored validation as unavailable.
  if blank source.text then return
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
      let models := (ordinaryNativeRealizations collected.input node).filter (·.key == key)
      let noOwner : ExceptT (Array Diagnostic) m Unit :=
        reject "ambiguous-native-expectation" node.toString
          "Expected proposition requires one exact ordinary proof realization in its stored context" #[record.origin]
      let #[(model, declaration)] := exactNativeOwners models ⟨`lean, record.project⟩ `proof none
        | noOwner
      let witness := declaration.object
      let expectedKey : RequirementKey := ⟨.declaration key witness, `expectedProof⟩
      let some updated := model.attachDeclarationRequirement? expectedKey | noOwner
      let goalRequest := p.expected[step.goals[index]!]!
      let specification := p.specifications[goalRequest.specification]!
      let (specDoc, issues) ← providers.document p.documents[specification.document]!
      full (← providers.specification {
        expected := specification.expected, origin := specification.origin, document := specDoc })
      let documents := canonical ((collected.input.objects.filter (·.value.key == witness)).filterMap (·.value.document) |>.push specDoc.key)
      let checked ← one (← providers.expected {
        project := goalRequest.project, expected := goalRequest.expected, witness, documents })
      let unavailable := (issues[0]?.map (·.message)).getD "Canonical source is empty"
      let observation := if issues.isEmpty && !blank specDoc.text then checked.observation else
        { checked.observation with
          outcome := .unavailable, coverage := .subject
          explanation := s!"{unavailable} for expected proposition '{goalRequest.expected}'" }
      let input := { collected.input with
        documents := collected.input.documents.push (authoredContribution record.origin `specification index specDoc)
        realizations := collected.input.realizations.map fun contribution =>
          if contribution.value == model && isOrdinaryRealization contribution then
            { contribution with value := updated }
          else contribution
        requirements := collected.input.requirements.push (authoredContribution record.origin `expectedRequirement index {
          key := expectedKey, expected := .proof checked.goal witness, coverage := .dependencyClosure })
        bindingInputs := collected.input.bindingInputs ++ (checked.semanticContext.toArray.map fun content =>
          authoredContribution record.origin `expectedContext index {
            subject := expectedKey.subject, name := NativeLean.expectedContextFor expectedKey, content }) ++
          (checked.statementContext.toArray.map fun content => authoredContribution record.origin `expectedStatementContext index {
            subject := expectedKey.subject, name := NativeLean.expectedStatementContextFor expectedKey, content }) }
      collected := { collected with
        input := input
        sourceDiagnostics := collected.sourceDiagnostics.addNode node (issues ++ checked.semanticDiagnostics)
        observations := collected.observations.push ((authoredContribution record.origin `expectedObservation index ()).origin,
          expectedKey, .proof observation) }
    let batch := record.authored
    for index in [:batch.sources.size] do
      let (document, issues) ← providers.document p.documents[step.documents[index]!]!
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

/-- Select the native contracts a use requires of its target, independently of
their outcomes. A label's ordinary Lean declarations form one development, and a
use requires all of them. The use's authored axis decides which contract of each
declaration it requires: a data definition's implementation and a proposition
definition's statement on either axis; a theorem's proof on the proof axis, and
only its statement on the statement axis, since a statement mentioning a theorem
is meaningful once that theorem is stated. Alternatives are explicit
realizations and cannot rescue the default. -/
private def selectTarget (collected : Collected) (context : Context) (axis : Name) (target : Name) :
    Except Diagnostic (Array RequirementKey) := do
  let input := collected.input
  let fail (code message : String) : Except Diagnostic (Array RequirementKey) := .error {
    code, subject := target.toString, message }
  unless input.nodes.any (·.value.label == target) do
    return ← fail "missing-target" "No accepted dependency target"
  let candidates := (ordinaryNativeRealizations input target).filter fun model =>
    model.context == context &&
      (model.role == `proof || model.role == `implementation || model.role == `statement)
  let statements := candidates.filter (·.role == `statement)
  let objects := canonical (candidates.flatMap (·.declarations.map (·.object)))
  if objects.isEmpty then
    return ← fail "missing-native-contract" "Dependency has no ordinary native declarations"
  let owners (role : Name) (object : ObjectKey) : Array (Realization × Declaration) :=
    exactNativeOwners candidates context role (some object)
  let mut required := #[]
  for object in objects do
    let some checked := collected.nativeChecks.find? (·.declaration == object)
      | return ← fail "unavailable-native-contract" s!"No current checked classification for '{object.native}'"
    if checked.status.isMissing then
      return ← fail "missing-declaration" s!"'{object.native}' is absent from the current checked environment"
    let role := if !(owners `implementation object).isEmpty then `implementation
      else if axis == `proof && !(owners `proof object).isEmpty then `proof
      else `statement
    let selectedOwners := owners role object
    if selectedOwners.size > 1 then
      return ← fail "ambiguous-native-contract"
        "Dependency declaration belongs to several ordinary native realizations of the selected role"
    let some (model, declaration) := selectedOwners[0]?
      | return ← fail "invalid-native-contract" "Dependency declaration has no contract for its selected role"
    let validator := nativeValidator role
    let key : RequirementKey := ⟨.declaration model.key object, role⟩
    let contracts := canonical ((input.requirements.filter (·.value.key == key)).map (·.value))
    unless checked.roles.contains role && contracts.size == 1 &&
        contracts[0]!.expected == .check validator && contracts[0]!.coverage == .dependencyClosure &&
        declaration.required.contains key do
      return ← fail "invalid-native-contract" "Dependency requires its exact selected native role and completeness contract"
    if role == `proof then
      let hasStatement := contracts[0]!.prerequisites.any fun prerequisite =>
        statements.any fun statementModel =>
          prerequisite == ⟨.declaration statementModel.key object, `statement⟩ &&
          statementModel.declarations.any (·.object == object)
      unless hasStatement do
        return ← fail "invalid-native-contract" "A proof role must depend on its selected proposition type"
    required := required ++ declaration.required ++ model.required
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
            code := "missing-use-owner", subject := Data.Label.publicString source
            message := if role == `proof then
              s!"'{Data.Label.publicString source}' has no proof or implementation to own the proof dependency on '{Data.Label.publicString reference.label}'. Attach a proof or use the statement axis for a dependency of the statement."
            else s!"'{Data.Label.publicString source}' has no {role} or implementation to own the dependency on '{Data.Label.publicString reference.label}'." } }
      else
        for context in contexts do
          selected := selected.push {
            source, realization, role, reference, context := some context
            selected := selectTarget collected context role reference.label }
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
      let validator := nativeValidator name
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
            key := selectionKey, expected := .check dependencySelectionValidator })
          bindingInputs := collected.input.bindingInputs.push (contribution `dependencySelection (BindingEncoding.requirementKey selectionKey) {
            subject, name := selectedUsesFor selectionKey
            content := (toJson (edges.map SelectedUse.bindingData)).compress }) } }
        collected := recordObservation collected selectionKey (.check {
          validator := dependencySelectionValidator
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

private def batchIssue (code family subject : String) : Array Diagnostic := #[{
  code, subject := s!"{family}:{subject}", message := "Malformed capture observation batch" }]

/-- Index answers by the request they answer. Insertion order has no meaning;
two answers to one request are rejected. -/
private def indexResults [BEq κ] [Hashable κ] (family : String) (subject : κ → String)
    (entries : Array (ResultEntry κ α)) : Except (Array Diagnostic) (Std.HashMap κ α) := do
  let mut table := {}
  for entry in entries do
    if table.contains entry.request then
      throw (batchIssue "duplicate-observation" family (subject entry.request))
    table := table.insert entry.request entry.result
  return table

/-- The answer to `request`, which must agree with the request by content. -/
private def answerFor [BEq κ] [Hashable κ] (family subject : String) (table : Std.HashMap κ α)
    (request : κ) (agrees : α → Bool := fun _ => true) : ExceptT (Array Diagnostic) Id α := do
  let some result := table.get? request
    | full (.error (batchIssue "missing-observation" family subject))
  unless agrees result do full (.error (batchIssue "mismatched-observation" family subject))
  return result

/-- Content checks apply to successful answers; provider failures carry no content. -/
private def whenOk (agrees : α → Bool) : Except ε α → Bool
  | .ok value => agrees value
  | .error _ => true

private def associatedMatches (request : NativeRequest) (prepared : NativeSource.Prepared) : Bool :=
  prepared.canonical == request.name &&
    prepared.declaration == ⟨⟨`lean, request.context.project⟩, request.name.toString⟩ &&
    request.moduleName?.all (· == prepared.moduleName) &&
    request.range?.all (· == prepared.ranges.range) &&
    request.selectionRange?.all (· == prepared.ranges.selectionRange)

/-- Pure policy evaluation of the plan against answers found by the request
they answer. Table insertion order has no meaning, and answers to requests this
plan does not make are ignored. Duplicate answers are rejected; missing and
mismatched answers fail at their recipe checkpoint. The supplied facts are not
authenticated here: production must call `observe freshly. -/
def evaluate (p : Plan) (observations : Observations) : Except (Array Diagnostic) Snapshot := do
  let documents ← indexResults "document" (·.path) observations.documents
  let native ← indexResults "native" (·.name.toString) observations.native
  let inline ← indexResults "inline" (·.native.name.toString) observations.inline
  let documented ← indexResults "documented" (·.name.toString) observations.documented
  let checks ← indexResults "check" (·.witness.native) observations.checks
  let specifications ← indexResults "specification" (·.expected.toString) observations.specifications
  let expected ← indexResults "expected" (·.expected.toString) observations.expected
  let providers : Providers Id := {
    document := fun request =>
      answerFor "document" request.path documents request (·.1.key == request)
    native := fun request =>
      answerFor "native" request.name.toString native request (whenOk (associatedMatches request))
    inline := fun request =>
      answerFor "inline" request.native.name.toString inline request (whenOk (associatedMatches request.native))
    documented := fun request =>
      answerFor "documented" request.name.toString documented request
        (whenOk fun value => associatedMatches request value.toPrepared &&
          value.document.key.context == ⟨`lean, request.context.project⟩ &&
          request.sourcePath?.all (· == value.document.key.path))
    check := fun request =>
      answerFor "check" request.witness.native checks request (whenOk fun value =>
        value.declaration == request.witness &&
          value.statement.declaration == some request.witness && value.body.declaration == some request.witness &&
          value.statement.validator == NativeLean.statementValidator && value.body.validator == NativeLean.bodyValidator &&
          value.rolesAgree)
    specification := fun request =>
      answerFor "specification" request.expected.toString specifications request
    expected := fun request =>
      answerFor "expected" request.expected.toString expected request (whenOk fun checked =>
        checked.observation.witness == request.witness && checked.goal.documents == request.documents &&
          checked.goal.context == request.witness.context) }
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

/-- Answer each distinct request once. A request the plan lists several times
shares its one answer, so the answers hold at most one entry per request. -/
private def answerOnce [Monad m] [MonadLiftT (ST IO.RealWorld) m] [BEq κ] [Hashable κ]
    (answers : IO.Ref (Std.HashMap κ α)) (request : κ) (provide : m α) : m α := do
  if let some result := (← answers.get)[request]? then return result
  let result ← provide
  answers.modify (·.insert request result)
  return result

private def entries [BEq κ] [Hashable κ] (answers : Std.HashMap κ α) : Array (ResultEntry κ α) :=
  answers.toArray.map fun (request, result) => { request, result }

initialize registerTraceClass `blueprint.capture.inspection

/-- One effect scope for all providers, including dependent expected goals.
The supplied reader is a byte-reading seam for tests, not a native-success hook.
Successful physical reads are shared across every provider family in this call.
Plain native declarations are prepared from the environment and read nothing.
Environment, metavariables and info state are restored even on exceptions. -/
def observe (p : Plan) (readFile : System.FilePath → IO String := IO.FS.readFile) :
    TermElabM (Except (Array Diagnostic) Observations) := withObservationState do
    let snapshot ← liftM <| IO.mkRef (#[] : Array (System.FilePath × String))
    let reader (path : System.FilePath) : IO String := do
      let physical ← IO.FS.realPath path
      if let some (_, text) := (← snapshot.get).find? (·.1 == physical) then return text
      let text ← readFile physical
      snapshot.modify (·.push (physical, text))
      return text
    let semantics ← NativeLean.newSemanticContext
    let inspection ← Data.newSorryInspectionSession
    let preparedBatch ← liftM <| IO.mkRef false
    let parse ← NativeSource.newSourceParser
    let documents ← liftM <| IO.mkRef ({} : Std.HashMap DocumentKey (Document × Array Diagnostic))
    let native ← liftM <| IO.mkRef ({} : Std.HashMap NativeRequest (Except Diagnostic NativeSource.Prepared))
    let inline ← liftM <| IO.mkRef ({} : Std.HashMap InlineRequest (Except Diagnostic NativeSource.Prepared))
    let documented ← liftM <| IO.mkRef ({} : Std.HashMap NativeRequest (Except Diagnostic NativeSource.Documented))
    let checks ← liftM <| IO.mkRef ({} : Std.HashMap CheckRequest (Except Diagnostic NativeLean.CheckedDeclaration))
    let specifications ← liftM <| IO.mkRef ({} : Std.HashMap SpecificationKey (Except (Array Diagnostic) Unit))
    let expected ← liftM <| IO.mkRef ({} : Std.HashMap ExpectedKey (Except Diagnostic NativeLean.Checked))
    let providers : Providers TermElabM := {
      document := fun key => answerOnce documents key (readDocument reader key)
      native := fun job => answerOnce native job do
        match ← request job with
        | .error issue => pure (.error issue)
        | .ok request => NativeSource.prepare request semantics
      inline := fun job => answerOnce inline job do
        match ← request job.native with
        | .error issue => pure (.error issue)
        | .ok request =>
          match ← sourcePath job.native request with
          | .error issue => pure (.error issue)
          | .ok path => NativeSource.prepareInlineBlock request path job.block reader semantics
      documented := fun job => answerOnce documented job do
        match ← request job with
        | .error issue => pure (.error issue)
        | .ok request =>
          match ← sourcePath job request with
          | .error issue => pure (.error issue)
          | .ok path => NativeSource.prepareDocumented request path reader semantics parse
      check := fun job => answerOnce checks job do
        unless ← preparedBatch.get do
          NativeLean.prepareDeclarations inspection p.scheduledChecks
          preparedBatch.set true
        NativeLean.checkDeclaration job.project job.witness (some inspection)
      specification := fun key => answerOnce specifications key
        (ownedDefinition key.expected key.origin key.document).run
      expected := fun key => answerOnce expected key
        (NativeLean.check key.project key.witness (mkCIdent key.expected) key.documents semantics (some inspection)) }
    -- Shared pure recipe resolves dependent arguments and ordered fatal checks.
    -- Its temporary input is not admitted and never escapes this boundary.
    match ← (assemble providers p).run with
    | .error issues => return .error issues
    | .ok _ =>
      if ← isTracingEnabledFor `blueprint.capture.inspection then
        let work ← inspection.work
        trace[blueprint.capture.inspection] "Declaration inspections: {work.declarationInspections}; dependency edge visits: {work.edgeVisits}; certificate scans: {work.certificateScans}"
      return .ok {
        documents := entries (← documents.get), native := entries (← native.get)
        inline := entries (← inline.get), documented := entries (← documented.get)
        checks := entries (← checks.get), specifications := entries (← specifications.get)
        expected := entries (← expected.get) }
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
