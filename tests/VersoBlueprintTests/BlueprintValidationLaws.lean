/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.UseLaws
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

end VersoBlueprintTests.CaptureUseCoverage
