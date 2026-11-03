/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.AuthoredRequestLaws
import VersoBlueprint.Translations.SelectionLaws
import VersoBlueprint.Environment.AdmissionLaws

/-! Contract examples for supplied observations. These are explicitly synthetic
checker/reviewer reports, not claims that this test invokes a native provider. -/
namespace VersoBlueprintTests.ValidationLaws
open Lean Informal.Realizations Informal.Validation

private def context : Context := ⟨`lean, `project⟩
private def realization : RealizationKey := ⟨`node, `lean⟩
private def object : ObjectKey := ⟨context, "witness"⟩
private def key : RequirementKey := ⟨.declaration realization object, `body⟩
private def native : Requirement := {
  key, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }
private def checked : CheckObservation := {
  validator := NativeLean.bodyValidator, declaration := some object
  outcome := .passed, coverage := .dependencyClosure }
private def evidence : Evidence := {
  id := `observation, requirement := key, binding := "current", observation := .check checked }

-- Nonvacuity and independent identity/freshness/coverage failures.
#guard evidence.mismatch? native "current" == none
#guard evidence.mismatch? native "changed" == some "stale-content"
#guard ({ evidence with binding := "" }).mismatch? native "" == some "stale-content"
#guard evidence.mismatch? { native with key := { key with name := `other } } "current" ==
  some "wrong-subject"
#guard ({ evidence with observation := .check { checked with coverage := .subject } }).mismatch?
  native "current" == some "insufficient-coverage"

-- Same spelling in another project is a different declaration. A native check
-- also cannot certify a whole realization by omitting its declaration subject.
#guard
  let other := { object with context := ⟨`lean, `otherProject⟩ }
  ({ evidence with observation := .check { checked with declaration := some other } }).mismatch?
    native "current" == some "wrong-check-object"
#guard ({ evidence with observation := .check { checked with declaration := none } }).mismatch?
  native "current" == some "wrong-check-object"
#guard
  let wholeKey := { key with subject := .realization realization }
  ({ evidence with requirement := wholeKey }).mismatch?
    { native with key := wholeKey } "current" == some "wrong-native-subject"

-- Generic named checks deliberately need not identify a declaration.
#guard
  let generic := { native with expected := .check `jointTest }
  ({ evidence with observation := .check {
    checked with validator := `jointTest, declaration := none } }).mismatch? generic "current" == none

private def goal : Goal := ⟨context, "expected proposition fingerprint", #[]⟩
private def proofRequirement : Requirement := {
  key, expected := .proof goal object, coverage := .subject }
private def proofReport : ProofObservation := {
  witness := object, actualType := some goal, outcome := .passed, coverage := .dependencyClosure }
private def proofEvidence : Evidence := { evidence with observation := .proof proofReport }

-- Independent proof contracts require proof evidence with closure coverage even
-- when the requirement asks only for subject coverage.
#guard proofEvidence.mismatch? proofRequirement "current" == none
#guard evidence.mismatch? proofRequirement "current" == some "wrong-evidence-kind"
#guard ({ proofEvidence with observation := .proof { proofReport with coverage := .subject } }).mismatch?
  proofRequirement "current" == some "insufficient-coverage"
#guard ({ proofEvidence with observation := .proof { proofReport with actualType := none } }).mismatch?
  proofRequirement "current" == some "wrong-proof"
#guard
  let other := { goal with fingerprint := "another proposition" }
  ({ proofEvidence with observation := .proof { proofReport with actualType := some other } }).mismatch?
    proofRequirement "current" == some "wrong-proof"
#guard ({ proofEvidence with observation := .proof { proofReport with outcome := .unavailable } }).mismatch?
  proofRequirement "current" == some "validation-unavailable"
#guard ({ proofEvidence with observation := .proof { proofReport with outcome := .notApplicable } }).mismatch?
  proofRequirement "current" == some "not-applicable"

private def reviewRequirement : Requirement := { native with expected := .review `faithful }
private def review : ReviewObservation := {
  criterion := `faithful, reviewer := `reviewer, outcome := .passed, coverage := .dependencyClosure }
#guard ({ evidence with observation := .review review }).mismatch? reviewRequirement "current" == none
#guard ({ evidence with observation := .review { review with reviewer := .anonymous } }).mismatch?
  reviewRequirement "current" == some "wrong-review"
#guard ({ evidence with observation := .review review }).mismatch? proofRequirement "current" ==
  some "wrong-evidence-kind"

-- Consumers obtain logical identity and freshness from successful execution,
-- without an additional naming or provider-correctness premise.
example (e : Evidence) (r : Requirement) (binding : ContentBinding)
    (h : e.mismatch? r binding = none) : e.requirement = r.key ∧ e.binding = binding :=
  ⟨Evidence.accepted_requirement h, (Evidence.accepted_binding h).2⟩

-- Canonicalization changes neither obligation membership nor emptiness.
#guard canonical #[3, 1, 3, 2, 1] == #[1, 2, 3]
example [BEq α] [LawfulBEq α] [Ord α] (xs : Array α) (x : α) :
    x ∈ canonical xs ↔ x ∈ xs := mem_canonical xs x

open Informal.Translations

private def mockContribution (id : Name) (value : α) : Contribution α :=
  { origin := { id, moduleName := `ValidationContractMock }, value }

/-- Synthetic check observations pass through actual admission and binding.
No compiler, native checker or human reviewer is invoked. -/
private def admittedFixture (selected : Array Name) (second : Outcome) : IO Registry := do
  let subject := Subject.realization realization
  let keyFor := fun name => ({ subject, name } : RequirementKey)
  let document : DocumentKey := ⟨context, "synthetic-source"⟩
  let input : Input := {
    nodes := #[mockContribution `node { label := realization.node, title := "Contract fixture" }]
    documents := #[mockContribution `document { key := document, text := "MOCK source bytes" }]
    realizations := #[mockContribution `realization {
      key := realization, context, facets := #[{ name := `body, documents := #[document] }]
      required := selected.map keyFor }]
    requirements := #[`first, `second].map fun name => mockContribution (`requirement ++ name) {
      key := keyFor name, expected := .check `syntheticCheck } }
  let .ok baseline := admit input
    | throw <| IO.userError "Synthetic contract input failed admission"
  let mut evidence := #[]
  for (name, outcome) in #[(`first, Outcome.passed), (`second, second)] do
    let key := keyFor name
    let some binding := baseline.bindingFor key
      | throw <| IO.userError "Synthetic requirement has no binding"
    evidence := evidence.push <| mockContribution (`evidence ++ name) {
      id := name, requirement := key, binding
      observation := Observation.check { validator := `syntheticCheck, outcome } }
  let .ok completed := admit { input with evidence }
    | throw <| IO.userError "Synthetic bound evidence failed admission"
  return completed

#eval show IO Unit from do
  let subject := Subject.realization realization
  let complete ← admittedFixture #[`second, `first, `second] .passed
  unless (complete.resultFor subject).complete &&
      (complete.requiredFor subject).size == 2 do
    throw <| IO.userError "All selected contracts should complete, with duplicates collapsed"
  let unfinished ← admittedFixture #[`first, `second] .failed
  unless !(unfinished.resultFor subject).complete &&
      (unfinished.resultForRequirement ⟨subject, `first⟩).complete do
    throw <| IO.userError "A completed alternative hid an unfinished selected requirement"
  let unselected ← admittedFixture #[`first] .failed
  unless (unselected.resultFor subject).complete do
    throw <| IO.userError "An unselected requirement changed the selected contract"
  let empty ← admittedFixture #[] .passed
  unless (empty.resultFor subject).status == .unassessed do
    throw <| IO.userError "Empty requirements must not certify completion"
  unless !(complete.resultFor (.realization ⟨`missing, `lean⟩)).complete do
    throw <| IO.userError "An unknown subject acquired completion"

example (r : Registry) (subject : Subject) (key : RequirementKey)
    (selected : key ∈ r.requiredFor subject)
    (complete : (r.resultFor subject).complete = true) :
    (r.resultForRequirement key).complete = true :=
  (r.complete_requires_all subject complete).2 key selected

-- The capture bridge composes with prerequisite soundness without assuming a
-- Registry invariant or correctness of the opaque component traversal.
example {p : Capture.Plan} {observations : Capture.Observations p} {snapshot : Capture.Snapshot}
    (evaluated : Capture.evaluate p observations = .ok snapshot)
    (complete : (snapshot.assessmentFor label).requiredComplete = true)
    (selected : key ∈ snapshot.registry.requiredFor (.realization ⟨label, `lean⟩))
    (cycle : Relation.TransGen snapshot.registry.Prerequisite key key) : False := by
  have required := (snapshot.registry.complete_requires_all _
    (snapshot.assessment_complete_result complete)).2 key selected
  have unfinished := admit_cycle_incomplete (Capture.evaluate_admitted evaluated) cycle
  simp [unfinished] at required

-- A failed selected edge cannot disappear as an absent gate. The positive
-- theorem supplies real retained evidence even without any successful selection.
-- This consumer uses public output fields, not collection-loop witnesses, and
-- checks that the unavailable dependency blocks the owning native contract.
example {p : Capture.Plan} {observations : Capture.Observations p} {snapshot : Capture.Snapshot}
    (evaluated : Capture.evaluate p observations = .ok snapshot)
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (nativeContext : model.context.language = `lean)
    (declarationMember : declaration ∈ model.declarations)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (recordMember : record ∈ snapshot.registry.contributions.requirements)
    (key : record.value.key = ⟨.declaration model.key declaration.object, name⟩)
    (origin : Capture.DependencySelection.CollectorOwned record.origin record.value.key)
    (expected : record.value.expected = .check validator)
    (coverage : record.value.coverage = .dependencyClosure)
    (edgeMember : edge ∈ Capture.DependencySelection.edges snapshot.uses model.key model.context name)
    (failed : edge.selected = .error diagnostic) :
    (snapshot.registry.resultForRequirement record.value.key).complete = false ∧
    ∃ evidence ∈ snapshot.registry.contributions.evidence, ∃ observation,
      evidence.value.requirement = ⟨.declaration model.key declaration.object, name ++ `dependencySelection⟩ ∧
      evidence.value.observation = .check observation ∧ observation.outcome = .unavailable := by
  refine ⟨Capture.evaluate_failed_native_dependency_incomplete evaluated modelMember nativeContext
    declarationMember facet recordMember key origin expected coverage edgeMember failed, ?_⟩
  have nonempty := Array.isEmpty_eq_false_iff_exists_mem.mpr ⟨edge, edgeMember⟩
  obtain ⟨_, _, _, _, evidence, member, observation, gate, observed, generated, _⟩ :=
    Capture.evaluate_native_dependency_gate_created evaluated modelMember nativeContext
      declarationMember facet recordMember key origin expected coverage nonempty
  have failure := Capture.DependencySelection.mem_failures _ diagnostic |>.mpr ⟨edge, edgeMember, failed⟩
  have unavailable := Array.isEmpty_eq_false_iff_exists_mem.mpr ⟨diagnostic, failure⟩
  refine ⟨evidence, member, observation, gate, observed, ?_⟩
  rw [generated.2.2.2.2.2, unavailable]
  rfl

-- Successful selection is not enough: a selected obligation without fitting
-- original evidence blocks its native parent even if a selection gate can pass.
example {p : Capture.Plan} {observations : Capture.Observations p} {snapshot : Capture.Snapshot}
    (evaluated : Capture.evaluate p observations = .ok snapshot)
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (nativeContext : model.context.language = `lean)
    (declarationMember : declaration ∈ model.declarations)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (parentMember : parent ∈ snapshot.registry.contributions.requirements)
    (parentKey : parent.value.key = ⟨.declaration model.key declaration.object, name⟩)
    (origin : Capture.DependencySelection.CollectorOwned parent.origin parent.value.key)
    (expected : parent.value.expected = .check validator)
    (coverage : parent.value.coverage = .dependencyClosure)
    (edgeMember : edge ∈ Capture.DependencySelection.edges snapshot.uses model.key model.context name)
    (success : edge.selected = .ok keys) (selectedMember : selected ∈ keys)
    (unsupported : ∀ requirement ∈ snapshot.registry.contributions.requirements,
      ∀ evidence ∈ snapshot.registry.contributions.evidence,
        requirement.value.key = selected →
        ¬ evidence.value.Fits requirement.value ((snapshot.registry.bindingFor selected).getD "")) :
    (snapshot.registry.resultForRequirement parent.value.key).complete = false := by
  cases complete : (snapshot.registry.resultForRequirement parent.value.key).complete with
  | false => rfl
  | true =>
    obtain ⟨_, _, _, _, _, justified⟩ := Capture.evaluate_native_dependencies_justified evaluated
      modelMember nativeContext declarationMember facet parentMember parentKey origin expected coverage
      (Array.isEmpty_eq_false_iff_exists_mem.mpr ⟨edge, edgeMember⟩) complete
    obtain ⟨actual, selectedOk, _, obligations⟩ := justified edge edgeMember
    have same := Except.ok.inj (selectedOk.symm.trans success)
    rw [same] at obligations
    obtain ⟨_, requirement, requirementMember, evidence, evidenceMember, _, key, fits⟩ :=
      obligations selected selectedMember
    exact False.elim (unsupported requirement requirementMember evidence evidenceMember key fits)

end VersoBlueprintTests.ValidationLaws

namespace VersoBlueprintTests.CaptureUseCoverage
open Lean Informal Informal.Realizations Informal.Translations Informal.SourceData

-- Exercise the real private selector with synthetic collected input. No provider
-- reports are fabricated as facts about actual source files or declarations.
run_cmd do
  let env ← getEnv
  let some owner := env.getModuleIdxFor? ``Capture.evaluate
    | throwError "Capture implementation must be imported"
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some owner then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture.Collected).isPrefixOf user ||
            (`Informal.Realizations.Capture.Providers).isPrefixOf user ||
            user == `Informal.Realizations.Capture.assemble ||
            user == `Informal.Realizations.Capture.selectUses then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

private def reference : Data.UseRef := { label := `target }
private def automatic : Data.UseRef := { reference with origin := .automatic, intent := .technical }
private def authoredUse : UseDeclaration := {
  node := `source, facet := `statement, reference }
private def model (name language project : Name) : Contribution Realization := {
  origin := { id := name, moduleName := `UseCoverageFixture }
  value := { key := ⟨`source, name⟩, context := ⟨language, project⟩ } }

-- Both orderings preserve the target while manual metadata supersedes automatic
-- metadata. The coverage theorem deliberately does not promise payload equality.
#guard Data.UseRef.mergeByLabel #[] #[automatic, reference] == #[reference]
#guard Data.UseRef.mergeByLabel #[] #[reference, automatic] == #[reference]

private def collection (uses : Array UseDeclaration) : Collected :=
  Collected.mk { realizations := #[model `first `lean `projectA,
    model `second `rust `projectB, model `third `lean `projectA] } #[] {} uses #[]

#eval show IO Unit from do
  let collected := collection #[{ authoredUse with reference := automatic }, authoredUse, authoredUse]
  let edges := selectUses collected
  unless edges.size == 2 &&
      (edges.map (·.context)).contains (some ⟨`lean, `projectA⟩) &&
      (edges.map (·.context)).contains (some ⟨`lean, `projectB⟩) do
    throw <| IO.userError "A collected use lost a project or duplicated its scope/context"
  for edge in edges do
    unless edge.source == `source && edge.realization == none &&
        edge.facet == `statement && edge.reference == reference do
      throw <| IO.userError "Selection changed the source scope, target, or manual metadata"
    match edge.selected with
    | .ok _ => throw <| IO.userError "An absent target acquired a contract"
    | .error diagnostic =>
      unless diagnostic.code == "missing-target" do
        throw <| IO.userError "An actual target selection failure was dropped"
  let restricted := selectUses (collection #[{ authoredUse with realization := some `second, facet := `proof }])
  let some restrictedEdge := restricted[0]?
    | throw <| IO.userError "The restricted use disappeared"
  unless restricted.size == 1 && restrictedEdge.context == some ⟨`lean, `projectB⟩ &&
      restrictedEdge.realization == some `second && restrictedEdge.facet == `proof do
    throw <| IO.userError "Explicit realization/facet selection changed its scope"
  let missing := selectUses (collection #[{ authoredUse with realization := some `absent }])
  let some missingEdge := missing[0]?
    | throw <| IO.userError "The missing-context use disappeared"
  unless missing.size == 1 && missingEdge.context == none &&
      missingEdge.reference == reference do
    throw <| IO.userError "A use without a matching source context disappeared"
  match missingEdge.selected with
  | .ok _ => throw <| IO.userError "Missing source context acquired a contract"
  | .error diagnostic =>
    unless diagnostic.code == "missing-source-context" && diagnostic.subject == "source" &&
        diagnostic.message == "Dependency has no stored source project context" do
      throw <| IO.userError "Missing source context lost its diagnostic"

private def document : Document := {
  key := ⟨⟨`rust, `projectB⟩, "synthetic-use-source"⟩, text := "MOCK authored source" }
private def usePlan : Capture.Plan := {
  raw := {
    nodes := #[], pending := (({} : NameSet).insert `source).insert `other
    facts := [], authored := #[], initialIssues := #[] }
  documents := #[document.key]
  ordinary := #[{
    label := `source, realizations := #[]
    accepted := {
      origin := `UseCoverageFixture
      uses := #[{ authoredUse with reference := automatic }, authoredUse, authoredUse] } }, {
    label := `other, realizations := #[]
    accepted := {
      origin := `UseCoverageFixture
      uses := #[{ authoredUse with node := `other, facet := `proof }] } }]
  authored := #[{
    record := {
      origin := { id := `authored, moduleName := `UseCoverageFixture }, project := `projectB
      authored := { sources := #[document.key], realizations := #[(model `alternate `rust `projectB).value] } }
    goals := #[], documents := #[0] }] }

-- Only a synthetic document provider is needed. Any accidental new provider
-- invocation fails, rather than manufacturing a successful native observation.
private def unexpected {α} : ExceptT (Array Diagnostic) Id α :=
  .error #[{ code := "unexpected-provider", subject := "fixture", message := "No native requests" }]
private def providers : Providers Id := Providers.mk
  (fun _ => pure (document, #[])) (fun _ => unexpected) (fun _ => unexpected)
  (fun _ => unexpected) (fun _ => unexpected) (fun _ _ => unexpected) (fun _ _ _ => unexpected)

#eval show IO Unit from do
  for nodes in #[usePlan.ordinary, usePlan.ordinary.reverse] do
    let generated := Capture.plan { usePlan.raw with
      nodes := nodes.map (fun step => (step.label, step.accepted))
      authored := usePlan.authored.map (·.record) }
    for p in #[{ usePlan with ordinary := nodes }, generated] do
      let .ok collected := (assemble providers p).run
        | throw <| IO.userError "The source-use collection fixture was rejected"
      unless Collected.uses collected == nodes.flatMap (·.accepted.uses) do
        throw <| IO.userError "Collection changed original use order, duplicates or metadata"
      let .ok snapshot := Capture.evaluate p { documents := #[{ handle := 0, result := (document, #[]) }] }
        | throw <| IO.userError "The ordinary/authored evaluator fixture was rejected"
      unless snapshot.uses.size == 2 && snapshot.registry.documents.contains document do
        throw <| IO.userError "Authored source collection dropped a document or changed use scopes"
      for edge in snapshot.uses do
        unless edge.reference == reference do
          throw <| IO.userError "Original manual target metadata did not reach selection"
        match edge.source, edge.selected with
        | `source, .error diagnostic =>
          unless edge.context == some ⟨`lean, `projectB⟩ && edge.facet == `statement &&
              diagnostic.code == "missing-target" do
            throw <| IO.userError "Authored model context failed to select the original ordinary use"
        | `other, .error diagnostic =>
          unless edge.context == none && edge.facet == `proof &&
              diagnostic.code == "missing-source-context" do
            throw <| IO.userError "A context-free ordinary use disappeared"
        | _, _ => throw <| IO.userError "A use gained an unexpected source or successful selection"
-- A consumer can start at the actual accepted-node lookup. Raw extraction and
-- planning supply the ordinary-entry/use membership; no private witnesses occur.
example {state : Environment.State} {observations : Capture.Observations (Capture.plan (Capture.Raw.ofState state))}
    {snapshot : Capture.Snapshot}
    (evaluated : Capture.evaluate (Capture.plan (Capture.Raw.ofState state)) observations = .ok snapshot)
    (found : state.data.get? label = some node) (useMember : use ∈ node.uses)
    (available : Capture.UseSelection.ContextFor snapshot.registry.contributions use context) :
    ∃ edge ∈ snapshot.uses, Capture.UseSelection.Matches use edge ∧ edge.context = some context :=
  Capture.evaluate_raw_use_in_context evaluated
    ((Capture.Raw.ofState_use_iff state use).mpr ⟨label, node, found, useMember⟩) available

-- Planner-only synthetic sources exercise prose, native and inline requests,
-- plus authored expected goals. They are never presented as checked source code.
#eval show IO Unit from do
  let context : Context := ⟨`lean, `plannerProject⟩
  let location : Data.SourceLocation := { path := "synthetic-planner-source", range := default }
  let source : FacetSource := {
    destination := ⟨⟨`source, `lean⟩, `statement⟩, context
    document := ⟨context, location.path⟩, source := .found location
    payload := .prose { stx := .missing } }
  let association : NativeAssociation := {
    realization := ⟨`source, `lean⟩, context, facets := #[`statement, `proof]
    reference := { written := `fixtureDeclaration, canonical := `fixtureDeclaration } }
  let owner : Contributions.Record := {
    id := ⟨`PlannerFixture, `blueprint.attribute, `source, 7, 0⟩, label := `source
    nativeAssociations := #[association], priority := some "high", source := some location }
  let some first := usePlan.ordinary[0]?
    | throw <| IO.userError "Missing first planner fixture node"
  let some second := usePlan.ordinary[1]?
    | throw <| IO.userError "Missing second planner fixture node"
  let alternative : NativeAssociation := { association with
    realization := ⟨`source, `alternative⟩, context := ⟨`lean, `otherProject⟩
    reference := { written := `alternativeOnly, canonical := `alternativeOnly } }
  let rich : Environment.RegisteredNode := { first.accepted with
    origin := `PlannerOrigin, modules := #[`PlannerOrigin, `PlannerContributor]
    sources := #[source, { source with payload := .leanInline {
      stx := .missing, definedDefs := #[{ name := `inlineDefinition }]
      definedTheorems := #[{ name := `fixtureDeclaration }, { name := `inlineOnly }] } },
      { source with
        destination := ⟨alternative.realization, `statement⟩, context := alternative.context
        document := ⟨alternative.context, location.path⟩
        payload := .leanInline { stx := .missing, definedTheorems := #[{ name := `alternativeInline }] } }]
    nativeAssociations := #[association, association, alternative] }
  let base : Capture.Raw := { usePlan.raw with
    nodes := #[(`source, rich), (`other, second.accepted)]
    authored := usePlan.authored.map fun (step : Capture.AuthoredStep) => { step.record with nativeGoals := #[(`source, `Expected)] }
    initialIssues := #[{ code := "stored-issue", subject := "planner", message := "Preserve for evaluation" }] }
  let competing := { association with reference := { association.reference with canonical := `anotherDeclaration } }
  for facts in #[[], [owner], [{ owner with nativeAssociations := #[association, competing] }]] do
    for nodes in #[base.nodes, base.nodes.reverse, base.nodes.push (`source, rich)] do
      let raw := { base with nodes, facts }
      let p := Capture.plan raw
      let rawView (value : Capture.Raw) :=
        (reprStr value.nodes, value.pending.toArray, value.facts, value.authored, value.initialIssues)
      unless rawView p.raw == rawView raw &&
          reprStr (p.ordinary.map fun step => (step.label, step.accepted)) == reprStr nodes do
        throw <| IO.userError "Planning changed raw data or mixed labels with accepted records"
      unless p.ordinary.flatMap (·.accepted.uses) == nodes.flatMap (·.2.uses) do
        throw <| IO.userError "Planning changed source-use order or duplicate metadata"
      unless !p.native.isEmpty && !p.inline.isEmpty && !p.checks.isEmpty && !p.expected.isEmpty do
        throw <| IO.userError "Planner fixture did not exercise every intended request family"
      unless p.documented.size == (if facts == [owner] then nodes.filter (·.1 == `source) |>.size else 0) do
        throw <| IO.userError "Planner fixture did not distinguish missing, exact and ambiguous prose owners"
      for node in p.ordinary do
        if node.label == `source then
          unless node.realizations.map (·.key) == canonical #[association.realization, alternative.realization] do
            throw <| IO.userError "Planning lost a realization or duplicated its source key"
          for step in node.realizations do
            let expected := if step.key == association.realization then
                #[`fixtureDeclaration, `inlineDefinition, `inlineOnly]
              else #[`alternativeOnly, `alternativeInline]
            unless step.declarations.map (·.name) == expected &&
                reprStr (step.sources.map (·.source)) == reprStr (rich.sources.filter (·.destination.realization == step.key)) &&
                decide (step.associations = rich.nativeAssociations.filter (·.realization == step.key)) do
              throw <| IO.userError "Planning mixed realization sources or changed declaration order/overlap"

end VersoBlueprintTests.CaptureUseCoverage

namespace VersoBlueprintTests.NativeContractCreation
open Lean Informal Informal.Realizations Informal.Translations Informal.SourceData Informal.Validation

-- Public consumers need plan membership and agreed context, not a final parent
-- requirement or any of the private collector witnesses.
example {p : Capture.Plan} {observations : Capture.Observations p} {snapshot : Capture.Snapshot}
    (evaluated : Capture.evaluate p observations = .ok snapshot)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (declarationMember : declaration ∈ step.declarations)
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    ∃ requirement ∈ snapshot.registry.contributions.requirements,
      requirement.value.key = ⟨.declaration step.key ⟨context, declaration.name.toString⟩, `proof⟩ ∧
      requirement.value.expected = .check NativeLean.bodyValidator ∧
      requirement.value.coverage = .dependencyClosure := by
  obtain ⟨requirement, member, _, key, expected, coverage⟩ :=
    Capture.evaluate_native_contract_created evaluated nodeMember stepMember declarationMember
      contextAgrees (name := `proof) (validator := NativeLean.bodyValidator) (by simp)
  exact ⟨requirement, member, key, expected, coverage⟩

-- Synthetic sources/checks exercise all four preparation/check-result branches
-- through the actual planner and evaluator. These reports are not authenticated
-- compiler results. Both facets must survive failure, authored additions, and
-- reversed declaration order. Mixed passing/failing declarations must remain
-- individually selected; neither an alternative nor an expected goal hides failure.
#eval show IO Unit from do
  let context : Context := ⟨`lean, `nativeContractFixture⟩
  let realization : RealizationKey := ⟨`contractNode, `lean⟩
  let issue : Diagnostic := { code := "source-association-unavailable", subject := "fixture", message := "MOCK unavailable" }
  let associations : Array NativeAssociation := #[`firstWitness, `secondWitness].map fun name => {
    realization, context, facets := #[`statement, `proof]
    reference := { written := name, canonical := name } }
  let extra : Requirement := { key := ⟨.realization realization, `authoredExtra⟩, expected := .check `extraValidator }
  let partitioned := associations.map fun association => { association with
    facets := if association.reference.canonical == `firstWitness then #[`statement, `body] else #[`proof, `custom] }
  for associations in #[associations, associations.reverse, associations.extract 0 1, partitioned, partitioned.reverse] do
    let expectedGoal := associations.size == 1
    let specification : Document := { key := ⟨context, "MOCK-specification.lean"⟩, text := "MOCK specification" }
    let extraModel : Realization := { key := ⟨realization.node, `foreign⟩, context := ⟨`rust, `foreignProject⟩ }
    let accepted : Environment.RegisteredNode := {
      origin := `ContractFixture, modules := #[`ContractFixture], nativeAssociations := associations }
    let raw : Capture.Raw := {
      nodes := #[(realization.node, accepted)], pending := ({} : NameSet).insert realization.node
      facts := [], initialIssues := #[]
      authored := #[{
        origin := { id := `authoredExtra, moduleName := `ContractFixture, source := specification.key.path }
        project := context.project, authored := { requirements := #[extra], realizations := #[extraModel] }
        nativeGoals := if expectedGoal then #[(realization.node, `mockExpected)] else #[] }] }
    let p := Capture.plan raw
    let replayed := Capture.plan { raw with authored := raw.authored ++ raw.authored }
    let distinct := { raw.authored[0]! with origin.id := `anotherAuthoredOrigin }
    let extended := Capture.plan { raw with authored := raw.authored.push distinct ++ raw.authored }
    unless decide (replayed.authored.map (·.record) = raw.authored) &&
        decide (extended.authored.map (·.record) = raw.authored.push distinct) &&
        replayed.expected.size == p.expected.size do
      throw <| IO.userError "Authored planning lost provenance or replayed an exact duplicate"
    unless p.native.size == associations.size && p.checks.size == associations.size &&
        p.expected.size == (if expectedGoal then 1 else 0) do
      throw <| IO.userError "Native contract fixture has the wrong request inventory"
    for sourceAvailable in #[true, false] do
      for checkAvailable in #[true, false] do
        for failingName in #[(none : Option String), some "firstWitness", some "secondWitness"] do
          for expectedOutcome in (if expectedGoal then #[(.passed : Outcome), .failed, .unavailable] else #[.passed]) do
            let witness : ObjectKey := ⟨context, associations[0]!.reference.canonical.toString⟩
            let goalDocuments := canonical ((if sourceAvailable then #[({ context, path := witness.native ++ ".lean" } : DocumentKey)] else #[]).push specification.key)
            let goal : Goal := { context, fingerprint := "MOCK expected proposition", documents := goalDocuments }
            let observations : Capture.Observations p := {
              documents := p.documents.mapIdx fun handle _ => ⟨handle, (specification, #[])⟩
              specifications := p.specifications.mapIdx fun handle _ => ⟨handle, { document := specification, result := .ok () }⟩
              expected := p.expected.mapIdx fun handle _ => ⟨handle, {
                witness, documents := goalDocuments, result := .ok {
                  goal, semanticContext := some "MOCK provider/build context"
                  observation := { witness, actualType := some goal, outcome := expectedOutcome, coverage := .dependencyClosure } } }⟩
              native := p.native.mapIdx fun handle request => ⟨handle,
                if !sourceAvailable then .error issue else .ok {
                  canonical := request.name, declaration := ⟨context, request.name.toString⟩
                  kind := .«theorem», moduleName := `ContractFixture
                  document := { key := ⟨context, request.name.toString ++ ".lean"⟩, text := "MOCK source" }
                  ranges := default }⟩
              checks := p.checks.mapIdx fun handle request => ⟨handle,
                if !checkAvailable then .error issue else .ok {
                  declaration := request.witness
                  status := if failingName == some request.witness.native then .incomplete {} else .proved
                  statement := {
                    validator := NativeLean.statementValidator, declaration := some request.witness
                    outcome := .passed, coverage := .dependencyClosure }
                  body := {
                    validator := NativeLean.bodyValidator, declaration := some request.witness
                    outcome := if failingName == some request.witness.native then .failed else .passed, coverage := .dependencyClosure } }⟩ }
            let .ok snapshot := Capture.evaluate p observations
              | throw <| IO.userError "Native contract fixture failed evaluation"
            unless snapshot.registry.contributions.requirements.size == 2 * associations.size + 1 + p.expected.size &&
                snapshot.registry.requirement? extra.key == some extra do
              throw <| IO.userError "Authored enrichment replaced an ordinary contract"
            let some model := snapshot.registry.realization? realization
              | throw <| IO.userError "Ordinary model disappeared during authored enrichment"
            unless model.key == realization && model.context == context &&
                model.declarations.map (·.object) == associations.map (fun association => ⟨context, association.reference.canonical.toString⟩) &&
                snapshot.registry.realization? extraModel.key == some extraModel do
              throw <| IO.userError "Model inventory changed or mixed ordinary and authored identities"
            for declaration in model.declarations do
              let proof : RequirementKey := ⟨.declaration realization declaration.object, `proof⟩
              let expected : RequirementKey := ⟨.declaration realization declaration.object, `expectedProof⟩
              unless declaration.required.contains proof &&
                  (snapshot.registry.requiredFor (.realization realization)).contains proof &&
                  (snapshot.registry.requiredFor (.declaration realization declaration.object)).contains proof &&
                  declaration.required.contains expected == expectedGoal &&
                  (snapshot.registry.requiredFor (.declaration realization declaration.object)).contains expected == expectedGoal &&
                  (snapshot.registry.requiredFor (.realization realization)).contains expected == expectedGoal do
                throw <| IO.userError "Authored goal enrichment lost the ordinary required key"
              let declarationComplete := sourceAvailable && checkAvailable &&
                failingName != some declaration.object.native && (!expectedGoal || expectedOutcome == .passed)
              unless (snapshot.registry.resultFor (.declaration realization declaration.object)).complete == declarationComplete do
                throw <| IO.userError "Declaration completion ignored native or expected obligations"
              if expectedGoal then
                unless (snapshot.registry.resultForRequirement expected).complete ==
                    (sourceAvailable && expectedOutcome == .passed) do
                  throw <| IO.userError "Expected-proof completion ignored its outcome or source availability"
            for association in associations do
              for (facet, validator) in #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)] do
                let key : RequirementKey := ⟨.declaration realization ⟨context, association.reference.canonical.toString⟩, facet⟩
                let some contract := snapshot.registry.requirement? key
                  | throw <| IO.userError "Unavailable source/check erased a native contract"
                unless contract.key == key && contract.expected == .check validator &&
                    contract.coverage == .dependencyClosure do
                  throw <| IO.userError "Native contract changed identity, validator or coverage"
                let shouldComplete := sourceAvailable && checkAvailable &&
                  (facet != `proof || failingName != some association.reference.canonical.toString)
                unless (snapshot.registry.resultForRequirement key).complete == shouldComplete do
                  throw <| IO.userError s!"Native result disagreed with source/check availability: source={sourceAvailable}, check={checkAvailable}, facet={facet}, result={reprStr (snapshot.registry.resultForRequirement key)}"

            for facet in model.facets do
              let selectedAssociations := associations.filter (·.facets.contains facet.name)
              let expectedKeys : Array RequirementKey := selectedAssociations.map fun association =>
                ⟨.declaration realization ⟨context, association.reference.canonical.toString⟩,
                  if facet.name == `statement then `statement else `proof⟩
              unless canonical (snapshot.registry.requiredFor (.facet realization facet.name)) == canonical expectedKeys do
                throw <| IO.userError "Facet query lost, invented, or mixed declaration obligations"
              let facetComplete := sourceAvailable && checkAvailable &&
                selectedAssociations.all (fun association => facet.name == `statement ||
                  failingName != some association.reference.canonical.toString)
              unless (snapshot.registry.resultFor (.facet realization facet.name)).complete == facetComplete do
                throw <| IO.userError s!"Facet completion crossed a source boundary: facet={facet.name}, failing={reprStr failingName}"

            let allComplete := sourceAvailable && checkAvailable &&
              associations.all (fun association => failingName != some association.reference.canonical.toString) &&
              (!expectedGoal || expectedOutcome == .passed)
            unless (snapshot.registry.resultFor (.realization realization)).complete == allComplete &&
                (snapshot.assessmentFor realization.node).requiredComplete == allComplete do
              throw <| IO.userError s!"Unexpected assessment: expected={allComplete}, source={sourceAvailable}, check={checkAvailable}, failing={reprStr failingName}, associations={associations.size}, public={reprStr (snapshot.registry.resultFor (.realization realization))}, assessmentComplete={(snapshot.assessmentFor realization.node).requiredComplete}"

-- The composed guarantee starts at an accepted environment lookup. No plan
-- step, final model/declaration/parent, or selected edge is assumed by the caller.
example {state : Environment.State} {observations : Capture.Observations (Capture.plan (Capture.Raw.ofState state))}
    {snapshot : Capture.Snapshot}
    (evaluated : Capture.evaluate (Capture.plan (Capture.Raw.ofState state)) observations = .ok snapshot)
    (found : state.data.get? label = some accepted) (useMember : use ∈ accepted.uses)
    (keyMember : key ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization)))
    (sourceDeclaration : declarationName ∈ nativeNames
      (accepted.nativeAssociations.filter (·.realization == key))
      (accepted.sources.filter (·.destination.realization == key)))
    (contextAgrees : canonical ((accepted.sources.filter (·.destination.realization == key)).map (·.context) ++
      (accepted.nativeAssociations.filter (·.realization == key)).map (·.context)) = #[context])
    (native : context.language = `lean)
    (source : use.node = key.node)
    (restriction : ∀ realization, use.realization = some realization → realization = key.name)
    (complete : (snapshot.registry.resultForRequirement
      ⟨.declaration key ⟨context, declarationName.toString⟩, `proof⟩).complete = true) :
    ∃ edge ∈ snapshot.uses, Capture.UseSelection.Matches use edge ∧ edge.context = some context ∧
      ∃ keys, edge.selected = .ok keys ∧ Capture.TargetSelection.Retained snapshot.registry context use.reference.label keys := by
  have rawMember : (label, accepted) ∈ (Capture.Raw.ofState state).nodes := by
    simpa only [Capture.Raw.ofState, NameMapLaws.mem_toArray] using found
  have rawUse := (Capture.Raw.ofState_use_iff state use).mpr ⟨label, accepted, found, useMember⟩
  obtain ⟨_, _, _, _, _, _, edge, member, aligned, context, keys, selected, retained, _⟩ :=
    Capture.evaluate_raw_source_use_justified evaluated rawUse rawMember keyMember
      sourceDeclaration contextAgrees native (name := `proof) (validator := NativeLean.bodyValidator)
      (by simp) source restriction (Or.inl rfl) complete
  exact ⟨edge, member, aligned, context, keys, selected, retained⟩

-- Public rendering completion covers an arbitrary declaration from the accepted
-- source union. No intermediate plan, final model, or selected-key premise.
example {state : Environment.State}
    {observations : Capture.Observations (Capture.plan (Capture.Raw.ofState state))}
    {snapshot : Capture.Snapshot}
    (evaluated : Capture.evaluate (Capture.plan (Capture.Raw.ofState state)) observations = .ok snapshot)
    (found : state.data.get? label = some accepted)
    (keyMember : (⟨label, `lean⟩ : RealizationKey) ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization)))
    (sourceDeclaration : declarationName ∈ nativeNames
      (accepted.nativeAssociations.filter (·.realization == ⟨label, `lean⟩))
      (accepted.sources.filter (·.destination.realization == ⟨label, `lean⟩)))
    (contextAgrees : canonical ((accepted.sources.filter (·.destination.realization == ⟨label, `lean⟩)).map (·.context) ++
      (accepted.nativeAssociations.filter (·.realization == ⟨label, `lean⟩)).map (·.context)) = #[context])
    (complete : (snapshot.assessmentFor label).requiredComplete = true) :
    let key : RequirementKey := ⟨.declaration ⟨label, `lean⟩ ⟨context, declarationName.toString⟩, `proof⟩
    (snapshot.registry.resultForRequirement key).complete = true ∧
      ∃ requirement ∈ snapshot.registry.contributions.requirements,
        ∃ evidence ∈ snapshot.registry.contributions.evidence,
          snapshot.registry.requirement? key = some requirement.value ∧
          requirement.value.key = key ∧
          evidence.value.Fits requirement.value ((snapshot.registry.bindingFor key).getD "") := by
  have rawMember : (label, accepted) ∈ (Capture.Raw.ofState state).nodes := by
    simpa only [Capture.Raw.ofState, NameMapLaws.mem_toArray] using found
  obtain ⟨finished, _, justified⟩ := Capture.evaluate_raw_assessment_declaration_justified
    evaluated rawMember keyMember sourceDeclaration contextAgrees complete
  exact ⟨finished, justified _ (Or.inl rfl)⟩

-- Facet completion justifies its own source declarations, with no final facet
-- lookup or selected-key witness supplied by the consumer.
example {state : Environment.State}
    {observations : Capture.Observations (Capture.plan (Capture.Raw.ofState state))}
    {snapshot : Capture.Snapshot}
    (evaluated : Capture.evaluate (Capture.plan (Capture.Raw.ofState state)) observations = .ok snapshot)
    (found : state.data.get? label = some accepted)
    (keyMember : key ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization)))
    (sourceDeclaration : declarationName ∈ nativeNames
      ((accepted.nativeAssociations.filter (·.realization == key)).filter (·.facets.contains name))
      ((accepted.sources.filter (·.destination.realization == key)).filter (·.destination.facet == name)))
    (contextAgrees : canonical ((accepted.sources.filter (·.destination.realization == key)).map (·.context) ++
      (accepted.nativeAssociations.filter (·.realization == key)).map (·.context)) = #[context])
    (complete : (snapshot.registry.resultFor (.facet key name)).complete = true) :
    let required : RequirementKey := ⟨.declaration key ⟨context, declarationName.toString⟩,
      if name == `statement then `statement else `proof⟩
    (snapshot.registry.resultForRequirement required).complete = true ∧
      ∃ requirement ∈ snapshot.registry.contributions.requirements,
        ∃ evidence ∈ snapshot.registry.contributions.evidence,
          snapshot.registry.requirement? required = some requirement.value ∧
          requirement.value.key = required ∧
          evidence.value.Fits requirement.value ((snapshot.registry.bindingFor required).getD "") := by
  have rawMember : (label, accepted) ∈ (Capture.Raw.ofState state).nodes := by
    simpa only [Capture.Raw.ofState, NameMapLaws.mem_toArray] using found
  obtain ⟨finished, _, justified⟩ := Capture.evaluate_raw_facet_declaration_justified
    evaluated rawMember keyMember sourceDeclaration contextAgrees complete
  exact ⟨finished, justified _ (Or.inl rfl)⟩

-- A retained authored goal reaches completion without a caller-supplied model,
-- declaration, plan entry or selected expected key.
example {state : Environment.State}
    {observations : Capture.Observations (Capture.plan (Capture.Raw.ofState state))}
    {snapshot : Capture.Snapshot}
    (evaluated : Capture.evaluate (Capture.plan (Capture.Raw.ofState state)) observations = .ok snapshot)
    (recordMember : record ∈ state.authoringRecords)
    (goalMember : (node, expectation) ∈ record.nativeGoals)
    (complete : (snapshot.assessmentFor node).requiredComplete = true) :
    ∃ model declaration, snapshot.registry.realization? ⟨node, `lean⟩ = some model ∧
      model.context = ⟨`lean, record.project⟩ ∧ model.declarations = #[declaration] ∧
      let required : RequirementKey := ⟨.declaration ⟨node, `lean⟩ declaration.object, `expectedProof⟩
      (snapshot.registry.resultForRequirement required).complete = true ∧
        ∃ requirement ∈ snapshot.registry.contributions.requirements,
          ∃ evidence ∈ snapshot.registry.contributions.evidence,
            snapshot.registry.requirement? required = some requirement.value ∧
            requirement.value.key = required ∧
            evidence.value.Fits requirement.value ((snapshot.registry.bindingFor required).getD "") := by
  obtain ⟨model, declaration, lookup, context, singleton, completed, _, justified⟩ :=
    Capture.evaluate_raw_assessment_expected_justified evaluated recordMember goalMember complete
  exact ⟨model, declaration, lookup, context, singleton, completed, justified _ (Or.inl rfl)⟩

end VersoBlueprintTests.NativeContractCreation

namespace VersoBlueprintTests.CheckRequestPlanning
open Lean Informal Informal.Realizations Informal.Translations Informal.SourceData Informal.Validation

-- Repeated names across nodes and realization projects must not alias handles.
-- These are planner-only synthetic sources, not authenticated native declarations.
#eval show IO Unit from do
  let makeNode (label project : Name) (reverse : Bool) : Environment.RegisteredNode := Id.run do
    let context : Context := ⟨`lean, project⟩
    let alternativeContext : Context := ⟨`lean, project ++ `alternative⟩
    let key : RealizationKey := ⟨label, `lean⟩
    let alternative : RealizationKey := ⟨label, `alternative⟩
    let associations : Array NativeAssociation := #[`sharedWitness, `nativeOnly].map fun name => {
      realization := key, context, facets := #[`proof]
      reference := { written := name, canonical := name } }
    let names := if reverse then #[`inlineOnly, `sharedWitness] else #[`sharedWitness, `inlineOnly]
    let source : FacetSource := {
      destination := ⟨key, `proof⟩, context, document := ⟨context, "MOCK-request-source.lean"⟩
      source := .found { path := "MOCK-request-source.lean", range := default }
      payload := .leanInline { stx := .missing, definedTheorems := names.map fun name => { name } } }
    return {
      origin := `RequestFixture, modules := #[`RequestFixture]
      sources := #[source, { source with
        destination := ⟨alternative, `proof⟩, context := alternativeContext
        document := ⟨alternativeContext, source.document.path⟩ }]
      nativeAssociations := (if reverse then associations.reverse else associations) ++ #[{
        realization := alternative, context := alternativeContext, facets := #[`proof]
        reference := { written := `sharedWitness, canonical := `sharedWitness } }] }
  for reverse in #[false, true] do
    let first := (`first, makeNode `first `firstProject reverse)
    let second := (`second, makeNode `second `secondProject reverse)
    for nodes in #[#[first, second], #[second, first], #[first, second, first]] do
      for withAuthored in #[false, true] do
        let record : Environment.AuthoringRecord := {
          origin := { id := `authored, moduleName := `RequestFixture, source := "MOCK-specification.lean" }
          project := `firstProject, nativeGoals := #[(`first, `Expected)]
          authored := { sources := #[⟨⟨`lean, `firstProject⟩, "MOCK-authored.lean"⟩] } }
        let raw : Capture.Raw := {
          nodes, pending := {}, facts := [], initialIssues := #[]
          authored := if withAuthored then #[record, record] else #[] }
        let p := Capture.plan raw
        let mut handles : Array Nat := #[]
        for node in p.ordinary do
          let project := if node.label == `first then `firstProject else `secondProject
          for step in node.realizations do
            let context : Context := ⟨`lean, if step.key.name == `lean then project else project ++ `alternative⟩
            for declaration in step.declarations do
              let some request := p.checks[declaration.check]?
                | throw <| IO.userError "Planner produced an out-of-bounds check handle"
              unless request.project == context.project &&
                  request.witness == (⟨context, declaration.name.toString⟩ : ObjectKey) do
                throw <| IO.userError "Check handle selected another declaration or project"
              unless declaration.check < p.checks.size &&
                  p.checks[declaration.check]!.project == request.project &&
                  p.checks[declaration.check]!.witness == request.witness do
                throw <| IO.userError "Observer job lookup disagrees with the bounded request"
              handles := handles.push declaration.check
        unless handles == (List.range (5 * nodes.size)).toArray &&
            p.checks.size == handles.size && p.expected.size == (if withAuthored then 1 else 0) do
          throw <| IO.userError "Planning reused a handle, lost a check, or replayed authored work"

-- The production environment lookup and accepted sources suffice. This consumer
-- assumes no planned declaration, valid handle or matching provider request.
example {state : Environment.State} (found : state.data.get? label = some accepted)
    (keyMember : key ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization)))
    (sourceDeclaration : name ∈ nativeNames
      (accepted.nativeAssociations.filter (·.realization == key))
      (accepted.sources.filter (·.destination.realization == key)))
    (contextAgrees : canonical ((accepted.sources.filter (·.destination.realization == key)).map (·.context) ++
      (accepted.nativeAssociations.filter (·.realization == key)).map (·.context)) = #[context]) :
    let p := Capture.plan (Capture.Raw.ofState state)
    ∃ node ∈ p.ordinary, node.label = label ∧ node.accepted = accepted ∧
      ∃ step ∈ node.realizations, step.key = key ∧
        ∃ declaration ∈ step.declarations, declaration.name = name ∧
          declaration.check < p.checks.size ∧ p.checks[declaration.check]? =
            some { project := context.project, witness := ⟨context, name.toString⟩ } := by
  apply Capture.plan_raw_declaration_check _ _ keyMember sourceDeclaration contextAgrees
  simpa only [Capture.Raw.ofState, NameMapLaws.mem_toArray] using found

end VersoBlueprintTests.CheckRequestPlanning

namespace VersoBlueprintTests.AuthoredRequestPlanning
open Lean Informal Informal.Realizations Informal.Translations Informal.SourceData Informal.Validation

-- Multiple goals, including equal goal values, retain their own request positions.
-- Shared names and source paths across projects must preserve exact record origins.
-- These fixtures inspect planning only, not native checker authenticity.
#eval show IO Unit from do
  let first : Environment.AuthoringRecord := {
    origin := { id := `first, moduleName := `FirstModule, source := "MOCK-shared-spec.lean" }
    project := `firstProject
    nativeGoals := #[(`firstNode, `SharedExpected), (`secondNode, `OtherExpected), (`firstNode, `SharedExpected)]
    authored := { sources := #[⟨⟨`lean, `firstProject⟩, "MOCK-extra-one.lean"⟩,
      ⟨⟨`lean, `firstProject⟩, "MOCK-extra-two.lean"⟩] } }
  let second : Environment.AuthoringRecord := {
    origin := { id := `second, moduleName := `SecondModule, source := "MOCK-shared-spec.lean" }
    project := `secondProject, nativeGoals := #[(`firstNode, `SharedExpected), (`thirdNode, `SharedExpected)] }
  let empty : Environment.AuthoringRecord := {
    origin := { id := `empty, moduleName := `OtherModule, source := "MOCK-empty-spec.lean" }
    project := `otherProject
    authored := { sources := #[⟨⟨`lean, `otherProject⟩, "MOCK-extra-three.lean"⟩] } }
  let context : Context := ⟨`lean, `ordinaryProject⟩
  let ordinary : Environment.RegisteredNode := {
    origin := `OrdinaryModule, modules := #[`OrdinaryModule]
    sources := #[{
      destination := ⟨⟨`ordinary, `lean⟩, `statement⟩, context
      document := ⟨context, "MOCK-ordinary.lean"⟩
      source := .found { path := "MOCK-ordinary.lean", range := default }
      payload := .prose { stx := .missing } }] }
  for reverseGoals in #[false, true] do
    let first := if reverseGoals then { first with nativeGoals := first.nativeGoals.reverse } else first
    let second := if reverseGoals then { second with nativeGoals := second.nativeGoals.reverse } else second
    let distinct := { first with origin := { first.origin with id := `distinct, moduleName := `DistinctModule } }
    for (records, count) in #[
        (#[first, second, empty], 5), (#[empty, second, first], 5),
        (#[first, first, empty, second, first, second], 5),
        (#[first, distinct, empty, second], 8), (#[empty], 0)] do
      for withOrdinary in #[false, true] do
        let raw : Capture.Raw := {
          nodes := if withOrdinary then #[(`ordinary, ordinary)] else #[]
          pending := {}, facts := [], initialIssues := #[], authored := records }
        let p := Capture.plan raw
        let mut handles : Array Nat := #[]
        for step in p.authored do
          unless records.any (fun record => decide (record = step.record)) &&
              step.goals.size == step.record.nativeGoals.size do
            throw <| IO.userError "Authored planning invented a record or lost a goal position"
          for index in [:step.record.nativeGoals.size] do
            let (node, expected) := step.record.nativeGoals[index]!
            let some handle := step.goals[index]?
              | throw <| IO.userError "Authored goal has no request handle"
            let some request := p.expected[handle]?
              | throw <| IO.userError "Authored goal handle is out of bounds"
            let some specification := p.specifications[request.specification]?
              | throw <| IO.userError "Expected request has no specification"
            let some document := p.documents[specification.document]?
              | throw <| IO.userError "Specification document handle is out of bounds"
            unless request.node == node && request.expected == expected &&
                request.project == step.record.project && request.origin == step.record.origin &&
                specification.expected == expected && specification.origin == step.record.origin &&
                document == (⟨⟨`lean, step.record.project⟩, step.record.origin.source⟩ : DocumentKey) do
              throw <| IO.userError "Authored request chain mixed goal, project, provenance or document"
            let job := p.expected[step.goals[index]!]!
            let specJob := p.specifications[job.specification]!
            unless job.node == node && job.expected == expected && job.project == step.record.project &&
                job.origin == step.record.origin && specJob.expected == expected &&
                specJob.origin == step.record.origin && p.documents[specJob.document]! == document do
              throw <| IO.userError "Collector/observer lookups disagree with the bounded request chain"
            handles := handles.push handle
        unless handles == (List.range count).toArray &&
            p.expected.size == count && p.specifications.size == count do
          throw <| IO.userError "Authored planning lost/aliased a goal or replayed an exact record"

-- The raw state supplies only the retained record and indexed goal. The planner
-- supplies every handle and the whole project/origin/document chain.
example {state : Environment.State} {index : Nat}
    (recordMember : record ∈ state.authoringRecords)
    (goalFound : record.nativeGoals[index]? = some goal) :
    let p := Capture.plan (Capture.Raw.ofState state)
    ∃ step ∈ p.authored, step.record = record ∧ index < step.goals.size ∧
      Capture.AuthoredRequestChain p record goal step.goals[index]! :=
  Capture.plan_raw_authored_goal_request _ recordMember goalFound

-- The same chain identifies the concrete interpreter arguments and derives bounds.
example (chain : Capture.AuthoredRequestChain p record goal handle) :
    handle < p.expected.size ∧
      let job := p.expected[handle]!
      job.node = goal.1 ∧ job.expected = goal.2 ∧ job.project = record.project ∧
      job.origin = record.origin ∧ job.specification < p.specifications.size ∧
        let specification := p.specifications[job.specification]!
        specification.expected = goal.2 ∧ specification.origin = record.origin ∧
        specification.document < p.documents.size ∧
        p.documents[specification.document]! = ⟨⟨`lean, record.project⟩, record.origin.source⟩ :=
  chain.jobs

end VersoBlueprintTests.AuthoredRequestPlanning
