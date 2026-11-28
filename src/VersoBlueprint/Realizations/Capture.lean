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

private def useOriginTag : Data.UseOrigin → String
  | .manual => "manual"
  | .automatic => "automatic"

private def useIntentTag : Data.UseIntent → String
  | .regular => "regular"
  | .auxiliary => "auxiliary"
  | .technical => "technical"

/-- Identity-bearing fields of the selected use, including the exact target
contracts. Public display spellings and human-readable diagnostic wording are
excluded from structural bindings. -/
def SelectedUse.bindingData (edge : SelectedUse) : Json :=
  let selection := match edge.selected with
    | .ok keys => Json.arr #[Json.str "selected", Json.arr (keys.map BindingEncoding.requirementKey)]
    | .error d => Json.arr #[Json.str "unresolved", Json.str d.code, Json.arr (d.origins.map fun (origin : Origin) =>
        Json.arr #[Json.str (Vir.nameKey origin.id), Json.str (Vir.nameKey origin.moduleName), Json.str origin.source])]
  Json.arr #[
    Json.str (Vir.nameKey edge.source),
    match edge.context with | some ctx => BindingEncoding.context ctx | none => .null,
    match edge.realization with | some r => Json.str (Vir.nameKey r) | none => .null,
    Json.str (Vir.nameKey edge.role),
    Json.str (Vir.nameKey edge.reference.label),
    Json.str (useOriginTag edge.reference.origin),
    Json.str (useIntentTag edge.reference.intent),
    selection]

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
    let some spec := NativeLean.roleSpec? role | failure
    guard (declaration.object.context == context && declaration.projection == spec.projection)
    return (model, declaration)

/-- The ordinary source producer's native models, derived from the admitted
contributions. Full authored alternatives remain available in `registry`. -/
def Snapshot.nativeRealizationsFor (snapshot : Snapshot) (label : Name) : Array Realization :=
  ordinaryNativeRealizations snapshot.registry.contributions label

/-- One declaration's ordinary native check slot, including unclassified
fallback declarations that have no matching required contract. -/
structure NativeCheckContract where
  realization : RealizationKey
  role : Name
  object : ObjectKey
  required : Option (RequirementKey × NativeLean.RoleSpec)

/-- Find the required native check for each declaration in the selected ordinary
native realizations of a label. -/
def Snapshot.nativeCheckContracts (snapshot : Snapshot) (models : Array Realization) :
    Array NativeCheckContract :=
  models.flatMap fun model => model.declarations.map fun declaration =>
    let key : RequirementKey := ⟨.declaration model.key declaration.object, model.role⟩
    let required := do
      let spec ← NativeLean.roleSpec? model.role
      let requirement ← snapshot.registry.requirement? key
      guard (declaration.required.contains key && requirement.expected == .check spec.validator &&
        requirement.coverage == .dependencyClosure)
      return (key, spec)
    { realization := model.key, role := model.role, object := declaration.object, required }

/-- A fresh check may be shared across labels. Only the exact observation
recorded for this declaration's own contract can supply its displayed status.
The observation may itself report an incomplete proof. -/
def Snapshot.acceptsNativeCheck (snapshot : Snapshot) (contract : NativeCheckContract)
    (checked : NativeLean.CheckedDeclaration) : Bool :=
  contract.object == checked.declaration && contract.required.any fun (key, spec) =>
    let observation := checked.observationFor spec
    (snapshot.registry.evidenceForRequirement key).any (·.observation == .check observation)

/-- Derive a consumer view from the same admitted snapshot. No source/status
fallbacks, new checker invocation or second dependency evaluator occur here. -/
def Snapshot.assessmentFor (snapshot : Snapshot) (label : Name) : NodeAssessment := Id.run do
  let registry := snapshot.registry
  let nativeModels := snapshot.nativeRealizationsFor label
  let declarations := nativeModels.flatMap (·.declarations)
  let objects := canonical (declarations.map (·.object))
  let checks := snapshot.nativeCheckContracts nativeModels
  -- A declaration retained at its fallback placement may have no classified
  -- role. Every selected declaration must have its native contract before a
  -- sibling can contribute to a complete node summary.
  let coversDeclarations := !checks.isEmpty && checks.all (·.required.isSome)
  let locallyComplete (selected : Array NativeCheckContract) :=
    coversDeclarations && !selected.isEmpty &&
      selected.all fun check => check.required.any fun (key, _) => (registry.localResult key).complete
  -- Body checks cover selected proofs and computational implementations.
  let bodyChecks := checks.filter (·.role != `statement)
  let statementComplete := locallyComplete (checks.filter (·.role != `proof))
  let bodyComplete := locallyComplete bodyChecks
  let proofChecks := checks.filter (·.role == `proof)
  let proofRoleComplete := if proofChecks.isEmpty then none else some (locallyComplete proofChecks)
  let requiredComplete := coversDeclarations &&
    checks.all fun check => check.required.any fun (key, _) => (registry.resultForRequirement key).complete
  let uses := snapshot.uses.filter (·.source == label)
  let selects (use : SelectedUse) (model : Realization) :=
    use.context == some model.context &&
      useSelectsRealization use.source use.realization use.role model
  let selected := uses.filter fun use => nativeModels.any (selects use)
  -- Both use axes constrain a computational definition's implementation.
  let statementOwners := nativeModels.filter (·.role != `proof)
  let dependenciesComplete (edges : Array SelectedUse) :=
    edges.all fun use =>
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
    -- Native checks share object identities across labels. Only an attachment
    -- whose own required native check accepted this checked observation reports
    -- its axiom-like status; a failed source range does not withdraw an
    -- accepted check, while a rejected role-disagreement check cannot borrow a
    -- sibling's accepted check.
    hasAxiomLike := snapshot.nativeChecks.any fun checked =>
      checked.status.isAxiomLike && checks.any (snapshot.acceptsNativeCheck · checked)
    nativeStatementComplete := statementComplete
    hasNativeBodyRequirement := !bodyChecks.isEmpty
    nativeBodyComplete := bodyComplete
    proofRoleComplete
    requiredComplete
    selectedLeanUseCount := selected.size
    statementDependenciesComplete := dependenciesComplete (selected.filter fun use => statementOwners.any (selects use))
    proofDependenciesComplete := dependenciesComplete selected
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
  nativeChecks : Std.HashMap ObjectKey NativeLean.CheckedDeclaration := {}

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

/-- A request for a declaration in the compiled environment. Presentation paths are excluded. -/
structure NativeRequest where
  context : Context
  name : Name
  /-- Permissive authoring can retain an unresolved spelling. Only resolved
  associations establish an identity that capture may inspect. -/
  present : Bool := true
  moduleName? : Option Name := none
  /-- An adopted source must still be owned by this imported Lake package. -/
  package? : Option String := none
  range? : Option DeclarationRange := none
  selectionRange? : Option DeclarationRange := none
  deriving Inhabited, BEq

instance : Hashable NativeRequest := ⟨fun request => hash (request.context, request.name, request.moduleName?, request.package?)⟩

def NativeRequest.ofAssociation (context : Context) (association : NativeAssociation) : NativeRequest := {
  context, name := association.reference.canonical, present := association.reference.present
  moduleName? := association.reference.provenance.moduleName?
  range? := association.reference.range?, selectionRange? := association.reference.selectionRange? }

structure CheckRequest where
  witness : ObjectKey
  deriving Inhabited, BEq, Hashable

def CheckRequest.project (request : CheckRequest) : Name :=
  request.witness.context.project

structure SpecificationRequest where
  expected : Name
  origin : Origin
  deriving Inhabited, BEq

instance : Hashable SpecificationRequest := ⟨fun request => hash (request.expected, request.origin.id)⟩

/-- A compiled proposition selected by its owning producer. -/
structure ExpectedRequest where
  node : Name
  project : Name
  specification : SpecificationRequest
  deriving Inhabited

def ExpectedRequest.expected (request : ExpectedRequest) : Name :=
  request.specification.expected

def ExpectedRequest.origin (request : ExpectedRequest) : Origin :=
  request.specification.origin

/-- What an expected-goal answer answers. The recipe resolves its witness and
documents from earlier results, so they belong to its identity. -/
structure ExpectedKey where
  project : Name
  expected : Name
  witness : ObjectKey
  documents : Array DocumentKey
  deriving BEq, Hashable

/-- A compiled registration and its optional docstring request. -/
structure SourceStep where
  source : SourceSelection
  documented : Option (Except Diagnostic NativeRequest) := none
  deriving Inhabited

structure DeclarationStep where
  name : Name
  native : Array NativeRequest := #[]
  check : CheckRequest
  deriving Inhabited

private def DeclarationStep.hasCheck (step : DeclarationStep) : Bool :=
  step.native.any (·.present)

private structure NativeDeclarationResult where
  name : Name
  roles : Array Name := #[]
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
  goals : Array ExpectedRequest

/-- The ordered assembly recipe owns its typed requests. Structural errors are
checked by the recipe at the position where they arise. -/
structure Plan where
  private mk ::
  raw : Raw
  ordinary : Array NodeStep := #[]
  authored : Array AuthoredStep := #[]

private def Plan.realizations (p : Plan) : Array RealizationStep :=
  p.ordinary.flatMap (·.realizations)

private def Plan.sources (p : Plan) : Array SourceStep :=
  p.realizations.flatMap (·.sources)

private def Plan.declarations (p : Plan) : Array DeclarationStep :=
  p.realizations.flatMap (·.declarations)

def Plan.documents (p : Plan) : Array DocumentKey :=
  p.authored.flatMap (·.record.authored.sources)

def Plan.native (p : Plan) : Array NativeRequest :=
  p.declarations.flatMap (·.native)

def Plan.documented (p : Plan) : Array NativeRequest :=
  p.sources.filterMap (fun step => step.documented.bind Except.toOption)

def Plan.checks (p : Plan) : Array CheckRequest :=
  (p.declarations.filter DeclarationStep.hasCheck).map (·.check)

def Plan.expected (p : Plan) : Array ExpectedRequest :=
  p.authored.flatMap (·.goals)

def plan (raw : Raw) : Plan := Id.run do
  let mut ordinary := #[]
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
        let mut documented : Option (Except Diagnostic NativeRequest) := none
        let selectedStatementAssociations (owners : Array Contributions.Record) (canonical : Name) :
            Array NativeAssociation :=
          ((owners.flatMap (·.nativeAssociations)).filter fun association =>
            association.reference.canonical == canonical && association.placement == `statement &&
              association.realization == ⟨label, `lean⟩ &&
              association.context == ⟨`lean, source.context.project⟩).toList.eraseDups.toArray
        if let some adoption := source.adoption then
          let owners := records.filter fun record =>
            record.id.producer == `blueprint.directive && record.id.moduleName == adoption.consumerModule &&
              record.source.isSome && record.source == source.source.location
          let selected := selectedStatementAssociations owners adoption.canonical
          match selected with
          | #[association] =>
            if association.reference.provenance.moduleName? != some adoption.moduleName then
              documented := some (.error {
                code := "source-association-unavailable", subject := label.toString
                message := "Adopted docstring and native attachment disagree on the owning module" })
            else
              documented := some (.ok { NativeRequest.ofAssociation association.context association with
                package? := adoption.package })
          | _ => documented := some (.error {
              code := "ambiguous-docstring", subject := label.toString
              message := "An adopted docstring requires its own directive's unique selected native attachment" })
        else if let some owner := source.ownDocstring then
          let owners := records.filter fun record => record.id.producer == `blueprint.attribute &&
            record.id.moduleName == owner.moduleName && record.id.subject == owner.canonical &&
            record.source.isSome && record.source == source.source.location
          match selectedStatementAssociations owners owner.canonical with
          | #[association] => documented := some (.ok { NativeRequest.ofAssociation association.context association with
              moduleName? := some owner.moduleName })
          | _ =>
            documented := some (.error {
              code := "ambiguous-docstring", subject := label.toString,
              message := "Attribute prose requires one exact owning native association" })
        sourceSteps := sourceSteps.push { source, documented }
      let mut declarations := #[]
      for name in nativeNames associations sources do
        let native := (associations.filter (·.reference.canonical == name)).map
          (NativeRequest.ofAssociation context)
        let inline := sources.filterMap fun source => do
          let .leanInline code := source.payload | none
          guard (code.definedDeclNames.contains name)
          return { context, name, moduleName? := some code.moduleName : NativeRequest }
        declarations := declarations.push {
          name, native := native ++ inline, check := { witness := ⟨context, name.toString⟩ } }
      realizations := realizations.push { key, sources := sourceSteps, associations, declarations }
    ordinary := ordinary.push { label, accepted, realizations }
  let records := raw.authored.foldl (fun out record =>
    if out.any (fun previous => decide (previous = record)) then out else out.push record) #[]
  let authored := records.map fun record => {
    record
    goals := record.nativeGoals.map fun (node, expected) => {
      node, project := record.project
      specification := { expected, origin := record.origin } }
    : AuthoredStep }
  return { raw, ordinary, authored }

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
  documented : Array (ResultEntry NativeRequest (Except Diagnostic NativeSource.Documented)) := #[]
  checks : Array (ResultEntry CheckRequest (Except Diagnostic NativeLean.CheckedDeclaration)) := #[]
  specifications : Array (ResultEntry SpecificationRequest (Except (Array Diagnostic) Unit)) := #[]
  expected : Array (ResultEntry ExpectedKey (Except Diagnostic NativeLean.Checked)) := #[]

/-- The same assembly recipe is interpreted once with real providers and once
with pure table lookups. No admission happens in the provider interpreter. -/
private structure Providers (m : Type → Type) where
  document : DocumentKey → ExceptT (Array Diagnostic) m (Document × Array Diagnostic)
  native : NativeRequest → ExceptT (Array Diagnostic) m (Except Diagnostic NativeSource.Prepared)
  documented : NativeRequest → ExceptT (Array Diagnostic) m (Except Diagnostic NativeSource.Documented)
  check : CheckRequest → ExceptT (Array Diagnostic) m (Except Diagnostic NativeLean.CheckedDeclaration)
  specification : SpecificationRequest → ExceptT (Array Diagnostic) m (Except (Array Diagnostic) Unit)
  expected : ExpectedKey → ExceptT (Array Diagnostic) m (Except Diagnostic NativeLean.Checked)

private def leanArtifactPath (path : String) : Bool :=
  let path := path.toLower
  path.endsWith ".lean" || path.endsWith ".olean" ||
    path.endsWith ".olean.server" || path.endsWith ".olean.private"

private def readDocument (reader : System.FilePath → IO String) (key : DocumentKey) :
    TermElabM (Document × Array Diagnostic) := do
  let path : System.FilePath := key.path
  if key.context.language == `lean || path.isAbsolute || key.path.startsWith "module:" ||
      (key.path.splitOn "/").contains ".." || leanArtifactPath key.path then
    return ({ key, text := "" }, #[{
      code := "invalid-external-source", subject := key.path
      message := "Authored external sources require a relative non-Lean file path" }])
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
  unless job.present do return .error {
    code := "missing-declaration", subject := name.toString
    message := "This attachment did not resolve in its authoring environment" }
  if job.moduleName?.any (·.isAnonymous) then return .error {
    code := "source-association-unavailable", subject := name.toString
    message := "Inline Lean attachment has no owning module" }
  let env ← getEnv
  unless (env.checked.get.find? name).isSome do
    return .error {
      code := "missing-declaration", subject := name.toString
      message := "Declaration is not in the current checked environment" }
  let some owner := ExternalModuleSource.moduleNameForDecl? env name
    | return .error {
      code := "source-association-unavailable", subject := name.toString
      message := "Cannot determine the current declaration owner" }
  if let some moduleName := job.moduleName? then
    if moduleName != owner then return .error {
      code := "source-association-unavailable", subject := name.toString
      message := "Stored native module disagrees with current declaration owner" }
  return .ok {
    project := job.context.project, canonical := name, moduleName := owner
    package? := job.package?, range? := job.range?, selectionRange? := job.selectionRange? }

private def prepareNative [Monad m] (providers : Providers m) (step : DeclarationStep) :
    ExceptT (Array Diagnostic) m (Except (Array Diagnostic) NativeSource.Prepared) := do
  let name := step.name
  let mut prepared := #[]
  let mut issues := #[]
  for job in step.native do
    match ← providers.native job with
    | .error issue => issues := issues.push issue
    | .ok value => prepared := prepared.push value
  if !issues.isEmpty then return .error (canonical issues)
  let some first := prepared[0]?
    | return .error #[{ code := "source-association-unavailable", subject := name.toString, message := "No owning source association" }]
  if prepared.any (fun other => other.ranges.range != first.ranges.range ||
      other.ranges.selectionRange != first.ranges.selectionRange ||
      other.moduleName != first.moduleName || other.declaration != first.declaration ||
      other.roles != first.roles || other.statementContext != first.statementContext ||
      other.semanticContext != first.semanticContext ||
      canonical other.semanticDiagnostics != canonical first.semanticDiagnostics) then
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
  match contexts with
  | #[context] => .ok context
  | _ => .error { code := "source-context-mismatch", subject := label.toString
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
        if declaration.hasCheck then requests := requests.push (declaration.check.project, declaration.check.witness)
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
        let prepared ← prepareNative providers declarationStep
        let checked ← if declarationStep.hasCheck then providers.check declarationStep.check else pure (.error {
          code := "missing-declaration", subject := declarationStep.name.toString
          message := "No resolved native attachment to check" })
        let result : NativeDeclarationResult := { name := declarationStep.name, prepared, checked }
        if let (.ok source, .ok check) := (prepared, checked) then
          if source.roles != check.roles then
            let issue : Diagnostic := {
              code := "native-role-disagreement", subject := declarationStep.name.toString
              message := "Owning-source and native-check classifications disagree" }
            -- Retain the source's intrinsic roles, but no passing check or
            -- usable source selection can be borrowed for this owner.
            declarationResults := declarationResults.push {
              result with prepared := .error #[issue], checked := .error issue, roles := source.roles }
            continue
        if let .ok check := checked then
          collected := { collected with nativeChecks := collected.nativeChecks.insert check.declaration check }
        declarationResults := declarationResults.push { result with roles :=
          (checked.toOption.map (·.roles) <|> prepared.toOption.map (·.roles)).getD #[] }

      let checkedRoles := declarationResults.map fun result => (result.name, result.roles)
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
        if let some reason := source.source.error then
          collected := { collected with sourceDiagnostics := collected.sourceDiagnostics.addNode label #[{
            code := "source-association-unavailable", subject := s!"{label}/{base.name}/{source.destination.role.getD `compiled}", message := reason }] }
        if let some role := source.destination.role then
          let selectedKey := source.selectedDocumentKey
          let selectedText ← match sourceStep.documented with
            | none => pure source.selectedText
            | some (.error diagnostic) =>
              pure (.error diagnostic)
            | some (.ok request) => do
              match ← providers.documented request with
              | .error diagnostic =>
                pure (.error diagnostic)
              | .ok documented =>
                if documented.format != source.context.language then
                  let diagnostic : Diagnostic := {
                    code := "source-format-unavailable"
                    subject := (toJson source.destination.subject).compress
                    message := "Direct native docstring format does not match its authored realization context" }
                  pure (.error diagnostic)
                else pure (.ok documented.content)
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
          sourceDocs := sourceDocs.push (role, selectedKey)
      let mut roleModels : Array Realization := #[]
      for role in roleNames do
        let declarations := declarationResults.filterMap fun result => Id.run do
          let roles := declarationRoles result.name
          unless roles.contains role do return none
          let some spec := NativeLean.roleSpec? role | return none
          let witness := object result.name
          let nativeRoles := rolesForName result.name
          let requirement : RequirementKey := ⟨.declaration (base.forRole role) witness, role⟩
          let selected := !nativeRoles.isEmpty && nativeRoles.contains role
          let required := if selected then #[requirement] else #[]
          return some {
            object := witness,
            projection := spec.projection,
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
                match NativeLean.roleSpec? role with
                | none => #[]
                | some spec =>
                  let (slot, content?) := match spec.projection with
                    | .statement => (`nativeStatementContext, prepared.statementContext)
                    | .implementation => (`nativeContext, prepared.semanticContext)
                  content?.toArray.map fun content => contribution slot
                    (BindingEncoding.subject (Subject.declaration (base.forRole role) witness)) {
                      subject := .declaration (base.forRole role) witness,
                      name := spec.contextName, content } }
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
          let some spec := NativeLean.roleSpec? role | continue
          let key : RequirementKey := ⟨.declaration (base.forRole role) witness, role⟩
          let validator := spec.validator
          let prerequisites := if role == `proof then
            #[⟨.declaration (base.forRole `statement) witness, `statement⟩] else #[]
          collected := { collected with
            input.requirements := collected.input.requirements.push
              (contribution `requirement (BindingEncoding.requirementKey key) {
                key, expected := .check validator, coverage := .dependencyClosure, prerequisites }) }
          match declaration.checked with
          | .ok checked =>
            collected := recordObservation collected key (.check (checked.observationFor spec))
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

private def ownedDefinition (name : Name) (origin : Origin) : CaptureM Unit := do
  let env ← getEnv
  let some (.defnInfo info) := env.checked.get.find? name
    | reject "invalid-expectation" name.toString "Expected a checked owned Prop definition, not an axiom" #[origin]
  unless info.safety == .safe do
    reject "invalid-expectation" name.toString "Expected a safe proposition definition" #[origin]
  unless ExternalModuleSource.moduleNameForDecl? env name == some origin.moduleName do
    reject "wrong-expectation-owner" name.toString "Specification belongs to another module" #[origin]
  unless (← findDeclarationRanges? name).isSome do
    reject "source-association-unavailable" name.toString "Specification has no native declaration ranges" #[origin]

private def collectAuthored [Monad m] (providers : Providers m) (p : Plan)
    (collected : Collected) : ExceptT (Array Diagnostic) m Collected := do
  let mut collected := collected
  for step in p.authored do
    let record := step.record
    for (goalRequest, index) in step.goals.zipIdx do
      let node := goalRequest.node
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
      full (← providers.specification goalRequest.specification)
      let checked ← one (← providers.expected {
        project := goalRequest.project, expected := goalRequest.expected, witness, documents := #[] })
      let input := { collected.input with
        realizations := collected.input.realizations.map fun contribution =>
          if contribution.value == model && isOrdinaryRealization contribution then
            { contribution with value := updated }
          else contribution
        requirements := collected.input.requirements.push (authoredContribution record.origin `expectedRequirement index {
          key := expectedKey, expected := .proof checked.goal witness, coverage := .dependencyClosure })
        bindingInputs := collected.input.bindingInputs ++ (checked.semanticContext.toArray.map fun content =>
          authoredContribution record.origin `expectedContext index {
            subject := expectedKey.subject, name := NativeLean.expectedContextFor expectedKey, content }) }
      collected := { collected with
        input := input
        sourceDiagnostics := collected.sourceDiagnostics.addNode node
          checked.semanticDiagnostics }
      let origin := (authoredContribution record.origin `expectedObservation index ()).origin
      collected := { collected with observations := collected.observations.push (origin, expectedKey, .proof checked.observation) }
    let batch := record.authored
    for (key, index) in batch.sources.zipIdx do
      let (document, issues) ← providers.document key
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
    model.context == context && NativeLean.isNativeRole model.role
  let statements := candidates.filter (·.role == `statement)
  let objects := canonical (candidates.flatMap (·.declarations.map (·.object)))
  if objects.isEmpty then
    return ← fail "missing-native-contract" "Dependency has no ordinary native declarations"
  let owners (role : Name) (object : ObjectKey) : Array (Realization × Declaration) :=
    exactNativeOwners candidates context role (some object)
  let mut required := #[]
  for object in objects do
    let some checked := collected.nativeChecks[object]?
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
    let some spec := NativeLean.roleSpec? role
      | return ← fail "invalid-native-contract" "Dependency declaration has no contract for its selected role"
    let validator := spec.validator
    let key : RequirementKey := ⟨.declaration model.key object, role⟩
    let contracts := canonical ((input.requirements.filter (·.value.key == key)).map (·.value))
    let #[contract] := contracts
      | return ← fail "invalid-native-contract" "Dependency requires its exact selected native role and completeness contract"
    unless checked.roles.contains role &&
        contract.expected == .check validator && contract.coverage == .dependencyClosure &&
        declaration.required.contains key do
      return ← fail "invalid-native-contract" "Dependency requires its exact selected native role and completeness contract"
    if role == `proof then
      let hasStatement := contract.prerequisites.any fun prerequisite =>
        statements.any fun statementModel =>
          prerequisite == ⟨.declaration statementModel.key object, `statement⟩ &&
          statementModel.declarations.any (·.object == object)
      unless hasStatement do
        return ← fail "invalid-native-contract" "A proof role must depend on its selected proposition type"
    required := required.push key
  return canonical required

private def selectUses (collected : Collected) : Array SelectedUse := Id.run do
  let mut selected := #[]
  let scopes := (collected.uses.map fun use => (use.node, use.realization, use.role)).foldl
    pushUnique #[]
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
          record.value.expected.isNativeDeclarationCheck &&
          record.origin == (contribution `requirement (BindingEncoding.requirementKey record.value.key) ()).origin then
        match record.value.expected with
        | .check validator => out.insert record.value.key validator
        | _ => out
      else out
  let mut collected := collected
  let mut additions : Std.HashMap RequirementKey (Array RequirementKey) := {}
  for model in collected.input.realizations.map (·.value) do
    if model.context.language != `lean then continue
    let some spec := NativeLean.roleSpec? model.role | continue
    let relevant := uses.filter fun use => use.context == some model.context &&
      useSelectsRealization use.source use.realization use.role model
    if relevant.isEmpty then continue
    for declaration in model.declarations do
      let subject := Subject.declaration model.key declaration.object
      let name := model.role
      let validator := spec.validator
      let key : RequirementKey := ⟨subject, name⟩
      unless nativeContracts[key]? == some validator do continue
      let selectionKey : RequirementKey := ⟨subject, name ++ `dependencySelection⟩
      let failures := relevant.filterMap fun edge => match edge.selected with
        | .error diagnostic => some diagnostic | .ok _ => none
      additions := additions.insert key (#[selectionKey] ++ relevant.flatMap fun edge =>
        match edge.selected with | .ok keys => keys | .error _ => #[])
      collected := { collected with input := { collected.input with
        requirements := collected.input.requirements.push (contribution `requirement (BindingEncoding.requirementKey selectionKey) {
          key := selectionKey, expected := .check dependencySelectionValidator })
        bindingInputs := collected.input.bindingInputs.push (contribution `dependencySelection (BindingEncoding.requirementKey selectionKey) {
          subject, name := selectedUsesFor selectionKey
          content := (toJson (relevant.map SelectedUse.bindingData)).compress }) } }
      collected := recordObservation collected selectionKey (.check {
        validator := dependencySelectionValidator
        outcome := if failures.isEmpty then .passed else .unavailable
        explanation := if failures.isEmpty then "Every dependency selected its exact current native contract"
          else (toJson failures).compress })
  if additions.isEmpty then return collected
  return { collected with input.requirements := collected.input.requirements.map fun record =>
    match additions[record.value.key]? with
    | none => record
    | some keys => { record with value.prerequisites := canonical (record.value.prerequisites ++ keys) } }

/-- Derive edge-local own-type observations from the real native declaration
checks already run for this capture. This reuses only the underlying checked
fact; `finish later binds each copy to its exact `proves contract. -/
private def attachOwnTypeObservations (collected : Collected) : Collected := Id.run do
  let mut collected := collected
  for requirement in collected.input.requirements do
    let .proves witness := requirement.value.expected | continue
    let observation := match collected.nativeChecks[witness]? with
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

/-- Bind captured observations to the checked structural input and admit the
whole evidence batch atomically. -/
private def finish (collected : Collected) : Except (Array Diagnostic) Snapshot := do
  let labels := collected.input.nodes.map (·.value.label) ++ collected.uses.map (fun use => (show Name from use.reference.label))
  let groups := collected.input.nodes.filterMap fun record =>
    record.value.parent.map (fun label => (show Name from label))
  let labelIssues := publicLabelIssues labels ++ publicLabelIssues groups
  unless labelIssues.isEmpty do throw labelIssues
  let uses := selectUses collected
  let collected := connectUses collected uses
  let collected := attachOwnTypeObservations collected
  let registry ← admitWithEvidence collected.input fun bindingFor =>
    collected.observations.mapM fun (origin, key, observation) => do
      let some binding := bindingFor key
        | throw #[{
            code := "missing-binding", subject := key.name.toString,
            message := "Complete candidate has no contract binding", origins := canonical #[origin] }]
      return { origin, value := { id := origin.id, requirement := key, binding, observation } }
  return {
    registry, uses
    sourceDiagnostics := {
      nodes := canonicalDiagnostics collected.sourceDiagnostics.nodes
      documents := canonicalDiagnostics collected.sourceDiagnostics.documents }
    nativeChecks := (collected.nativeChecks.toArray.qsort fun a b => compare a.1 b.1 == .lt).map (·.2) }

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
  request.present && prepared.canonical == request.name &&
    prepared.declaration == ⟨⟨`lean, request.context.project⟩, request.name.toString⟩ &&
    request.moduleName?.all (fun owner => !owner.isAnonymous && owner == prepared.moduleName) &&
    request.range?.all (· == prepared.ranges.range) &&
    request.selectionRange?.all (· == prepared.ranges.selectionRange)

/-- Evaluate the plan with one request-keyed table per observation family.
Table construction rejects duplicate requests. The recipe looks up each request
it makes and checks that its answer agrees with the request. Production uses
`observe` to obtain fresh facts before evaluation. -/
def evaluate (p : Plan) (observations : Observations) : Except (Array Diagnostic) Snapshot := do
  let documents ← indexResults "document" (·.path) observations.documents
  let native ← indexResults "native" (·.name.toString) observations.native
  let documented ← indexResults "documented" (·.name.toString) observations.documented
  let checks ← indexResults "check" (·.witness.native) observations.checks
  let specifications ← indexResults "specification" (·.expected.toString) observations.specifications
  let expected ← indexResults "expected" (·.expected.toString) observations.expected
  let providers : Providers Id := {
    document := fun request =>
      answerFor "document" request.path documents request (·.1.key == request)
    native := fun request =>
      answerFor "native" request.name.toString native request (whenOk (associatedMatches request))
    documented := fun request =>
      answerFor "documented" request.name.toString documented request
        (whenOk (fun value => associatedMatches request value.toPrepared))
    check := fun request =>
      answerFor "check" request.witness.native checks request (whenOk fun value =>
        value.declaration == request.witness && value.rolesAgree)
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
Physical reads are shared for authored external documents. Lean observations
come from the compiled environment.
Environment, metavariables and info state are restored even on exceptions. -/
def observe (p : Plan) (readFile : System.FilePath → IO String := IO.FS.readFile) :
    TermElabM (Except (Array Diagnostic) Observations) := withObservationState do
    let snapshot ← liftM <| IO.mkRef (#[] : Array (System.FilePath × String))
    let reader (path : System.FilePath) : IO String := do
      let physical ← IO.FS.realPath path
      if leanArtifactPath physical.toString then
        throw (IO.userError "Expected an external source, not a Lean artifact")
      if let some (_, text) := (← snapshot.get).find? (·.1 == physical) then return text
      let text ← readFile physical
      snapshot.modify (·.push (physical, text))
      return text
    let semantics ← NativeLean.newSemanticContext
    let inspection ← Data.newSorryInspectionSession
    let preparedBatch ← liftM <| IO.mkRef false
    let documents ← liftM <| IO.mkRef ({} : Std.HashMap DocumentKey (Document × Array Diagnostic))
    let native ← liftM <| IO.mkRef ({} : Std.HashMap NativeRequest (Except Diagnostic NativeSource.Prepared))
    let documented ← liftM <| IO.mkRef ({} : Std.HashMap NativeRequest (Except Diagnostic NativeSource.Documented))
    let checks ← liftM <| IO.mkRef ({} : Std.HashMap CheckRequest (Except Diagnostic NativeLean.CheckedDeclaration))
    let specifications ← liftM <| IO.mkRef ({} :
      Std.HashMap SpecificationRequest (Except (Array Diagnostic) Unit))
    let expected ← liftM <| IO.mkRef ({} : Std.HashMap ExpectedKey (Except Diagnostic NativeLean.Checked))
    let providers : Providers TermElabM := {
      document := fun key => answerOnce documents key (readDocument reader key)
      native := fun job => answerOnce native job do
        match ← request job with
        | .error issue => pure (.error issue)
        | .ok request => NativeSource.prepare request semantics
      documented := fun job => answerOnce documented job do
        match ← request job with
        | .error issue => pure (.error issue)
        | .ok request => NativeSource.prepareDocumented request semantics
      check := fun job => answerOnce checks job do
        unless ← preparedBatch.get do
          NativeLean.prepareDeclarations inspection p.scheduledChecks
          preparedBatch.set true
        NativeLean.checkDeclaration job.project job.witness (some inspection)
      specification := fun key => answerOnce specifications key
        (ownedDefinition key.expected key.origin).run
      expected := fun key => answerOnce expected key
        (NativeLean.checkSpecification key.project key.witness key.expected key.documents semantics inspection) }
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
        documented := entries (← documented.get)
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
