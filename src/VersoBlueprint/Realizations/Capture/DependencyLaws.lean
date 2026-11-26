/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.CreationLaws
import VersoBlueprint.Realizations.Capture.TargetLaws

/-! Completed native contracts justify their exact scoped dependency obligations.
These compositions use public production laws, without private collector access. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations

namespace DependencySelection

/-- Admission fixes both the parent and the model context of a generated gate.
An existential wiring witness cannot silently select a different contract or scope. -/
theorem Wired.for_contract {origin : Origin} (admitted : admit input = .ok registry)
    (wired : Wired input uses origin gate observation)
    (modelMember : model ∈ input.realizations.map (·.value))
    (parentMember : parent ∈ input.requirements)
    (parentKey : parent.value.key = ⟨.declaration model.key object, name⟩)
    (facetName : name = `statement ∨ name = `proof)
    (gateKey : gate = ⟨.declaration model.key object, name ++ `dependencySelection⟩) :
    GeneratedAt uses model.key model.context object name origin gate observation ∧
      gate ∈ parent.value.prerequisites ∧
      ∀ edge ∈ edges uses model.key model.context name, ∀ keys, edge.selected = .ok keys →
        ∀ key ∈ keys, key ∈ parent.value.prerequisites := by
  obtain ⟨realization, context, declared, facet, validator, generated, _,
    ⟨actualModel, actualMember, modelKey, modelContext⟩,
    actualParent, actualParentMember, actualKey, _, _, _, gateMember, selected⟩ := wired
  have identities := generated.2.2.1.symm.trans gateKey
  have same : realization = model.key ∧ declared = object ∧ facet = name := by
    have pair : realization = model.key ∧ declared = object ∧
        facet ++ `dependencySelection = name ++ `dependencySelection := by
      simpa only [RequirementKey.mk.injEq, Subject.declaration.injEq, and_assoc] using identities
    refine ⟨pair.1, pair.2.1, ?_⟩
    rcases generated.2.1 with sourceName | sourceName <;>
      rcases facetName with targetName | targetName <;>
      simp_all
    all_goals exact absurd identities (by decide)
  rcases same with ⟨rfl, rfl, rfl⟩
  obtain ⟨actualRecord, actualRecordMember, actualEq⟩ := Array.mem_map.mp actualMember
  obtain ⟨modelRecord, modelRecordMember, modelEq⟩ := Array.mem_map.mp modelMember
  have modelsAgree := admit_realizations_agree admitted actualRecordMember modelRecordMember
    (by simpa only [actualEq, modelEq] using modelKey)
  have sameContext : context = model.context := by
    rw [actualEq, modelEq] at modelsAgree
    exact modelContext.symm.trans (congrArg Realization.context modelsAgree)
  have parentsAgree := admit_requirements_agree admitted actualParentMember parentMember
    (actualKey.trans parentKey.symm)
  rw [sameContext] at generated selected
  rw [parentsAgree] at gateMember selected
  exact ⟨generated, gateMember, selected⟩

end DependencySelection

/-- Local evidence for a generated gate proves successful selection in the
requested contract's exact scope. This deliberately needs no completed final
cache entry for the gate: prerequisite soundness supplies local validation. -/
theorem evaluate_local_dependency_selection_for_contract
    {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (parentMember : parent ∈ snapshot.registry.contributions.requirements)
    (parentKey : parent.value.key = ⟨.declaration model.key object, name⟩)
    (facetName : name = `statement ∨ name = `proof)
    (gateKey : gate = ⟨.declaration model.key object, name ++ `dependencySelection⟩)
    (found : snapshot.registry.requirement? gate = some requirement)
    (expected : requirement.expected = .check `blueprint.dependencySelection)
    (complete : (snapshot.registry.localResult gate).complete = true) :
    gate ∈ parent.value.prerequisites ∧
      ∀ edge ∈ DependencySelection.edges snapshot.uses model.key model.context name,
        ∃ keys, edge.selected = .ok keys ∧
          ∀ key ∈ keys, key ∈ parent.value.prerequisites := by
  have admitted := evaluate_admitted evaluated
  obtain ⟨original, _, evidence, member, lookup, originalKey, fits⟩ :=
    admit_local_complete_evidence admitted complete
  have sameRequirement := Option.some.inj (found.symm.trans lookup)
  rw [← sameRequirement] at fits
  have evidenceKey : evidence.value.requirement = gate :=
    fits.1.trans ((congrArg Requirement.key sameRequirement).trans originalKey)
  have suitable := fits.2.2.2
  cases observed : evidence.value.observation with
  | proof observation => simp [observed, Observation.Satisfies, expected] at suitable
  | review observation => simp [observed, Observation.Satisfies, expected] at suitable
  | check observation =>
    simp only [observed, Observation.Satisfies, expected] at suitable
    have wired := evaluate_dependency_selection_wired evaluated member observed suitable.1
    obtain ⟨generated, gateMember, selected⟩ := wired.for_contract admitted modelMember
      parentMember parentKey facetName (evidenceKey.trans gateKey)
    have passed := suitable.2.2.2
    rw [generated.2.2.2.2.2] at passed
    have noFailures : (DependencySelection.failures
        (DependencySelection.edges snapshot.uses model.key model.context name)).isEmpty = true := by
      change (if _ then Outcome.passed else Outcome.unavailable) = .passed at passed
      split at passed
      · assumption
      · cases passed
    refine ⟨evidenceKey ▸ gateMember, ?_⟩
    intro edge edgeMember
    obtain ⟨keys, success⟩ := (DependencySelection.failures_empty_iff _).mp noFailures edge edgeMember
    exact ⟨keys, success, selected edge edgeMember keys success⟩

/-- Completing a collector-owned native contract justifies all obligations of
every selected dependency in its exact model/facet scope. The gate is created,
not assumed. Targets retain their actual definitions, and each selected key is a
parent prerequisite with original fitting evidence at its own current binding.
This does not claim final cached completion for the gate or targets. -/
theorem evaluate_native_dependencies_justified
    {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (native : model.context.language = `lean)
    (declarationMember : declaration ∈ model.declarations)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (parentMember : parent ∈ snapshot.registry.contributions.requirements)
    (parentKey : parent.value.key = ⟨.declaration model.key declaration.object, name⟩)
    (origin : DependencySelection.CollectorOwned parent.origin parent.value.key)
    (expected : parent.value.expected = .check validator)
    (coverage : parent.value.coverage = .dependencyClosure)
    (nonempty : (DependencySelection.edges snapshot.uses model.key model.context name).isEmpty = false)
    (complete : (snapshot.registry.resultForRequirement parent.value.key).complete = true) :
    let gate : RequirementKey := ⟨.declaration model.key declaration.object, name ++ `dependencySelection⟩
    ∃ gateRequirement, snapshot.registry.requirement? gate = some gateRequirement ∧
      gateRequirement.expected = .check `blueprint.dependencySelection ∧
      gate ∈ parent.value.prerequisites ∧ (snapshot.registry.localResult gate).complete = true ∧
      ∀ edge ∈ DependencySelection.edges snapshot.uses model.key model.context name,
        ∃ keys, edge.selected = .ok keys ∧
          TargetSelection.Retained snapshot.registry model.context edge.reference.label keys ∧
          ∀ selected ∈ keys, selected ∈ parent.value.prerequisites ∧
            ∃ requirement ∈ snapshot.registry.contributions.requirements,
              ∃ evidence ∈ snapshot.registry.contributions.evidence,
                snapshot.registry.requirement? selected = some requirement.value ∧
                requirement.value.key = selected ∧
                evidence.value.Fits requirement.value ((snapshot.registry.bindingFor selected).getD "") := by
  have admitted := evaluate_admitted evaluated
  have parentFound := (admit_requirement_lookup_iff admitted).mpr ⟨parent, parentMember, rfl, rfl⟩
  have facetName : name = `statement ∨ name = `proof := by
    simp at facet
    rcases facet with ⟨rfl, _⟩ | ⟨rfl, _⟩ <;> simp
  obtain ⟨gateRequirement, found, gateKey, gateExpected,
    evidence, member, observation, evidenceKey, observed, generated, _⟩ :=
    evaluate_native_dependency_gate_created evaluated modelMember native declarationMember facet
      parentMember parentKey origin expected coverage nonempty
  have wired := evaluate_dependency_selection_wired evaluated member observed
    (DependencySelection.Source.validator ⟨_, _, _, _, generated⟩)
  have gateMember := (wired.for_contract admitted modelMember parentMember parentKey facetName evidenceKey).2.1
  rw [evidenceKey] at gateMember
  have localGate := admit_complete_prerequisites_local admitted complete _
    (.single ⟨parent.value, parentFound, gateMember⟩)
  obtain ⟨_, selected⟩ := evaluate_local_dependency_selection_for_contract evaluated
    modelMember parentMember parentKey facetName rfl found gateExpected localGate
  refine ⟨gateRequirement, found, gateExpected, gateMember, localGate, ?_⟩
  intro edge edgeMember
  obtain ⟨keys, success, prerequisites⟩ := selected edge edgeMember
  have scopeFacts := (DependencySelection.mem_edges _ _ _ _ _).mp edgeMember
  obtain ⟨context, contextEq, _, retained⟩ := evaluate_use_target_retained evaluated scopeFacts.1 success
  have sameContext := Option.some.inj (contextEq.symm.trans scopeFacts.2.2.1)
  refine ⟨keys, success, sameContext ▸ retained, ?_⟩
  intro key keyMember
  have prerequisite := prerequisites key keyMember
  exact ⟨prerequisite, admit_complete_prerequisites_evidence admitted complete
    (.single ⟨parent.value, parentFound, prerequisite⟩)⟩

/-- Any failed selected edge in the native contract's scope blocks completion.
The failed edge itself supplies nonemptiness; no preexisting gate is assumed. -/
theorem evaluate_failed_native_dependency_incomplete
    {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (native : model.context.language = `lean)
    (declarationMember : declaration ∈ model.declarations)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (parentMember : parent ∈ snapshot.registry.contributions.requirements)
    (parentKey : parent.value.key = ⟨.declaration model.key declaration.object, name⟩)
    (origin : DependencySelection.CollectorOwned parent.origin parent.value.key)
    (expected : parent.value.expected = .check validator)
    (coverage : parent.value.coverage = .dependencyClosure)
    (edgeMember : edge ∈ DependencySelection.edges snapshot.uses model.key model.context name)
    (failed : edge.selected = .error diagnostic) :
    (snapshot.registry.resultForRequirement parent.value.key).complete = false := by
  cases complete : (snapshot.registry.resultForRequirement parent.value.key).complete with
  | false => rfl
  | true =>
    obtain ⟨_, _, _, _, _, justified⟩ := evaluate_native_dependencies_justified evaluated
      modelMember native declarationMember facet parentMember parentKey origin expected coverage
      (Array.isEmpty_eq_false_iff_exists_mem.mpr ⟨edge, edgeMember⟩) complete
    obtain ⟨keys, success, _⟩ := justified edge edgeMember
    rw [failed] at success
    cases success

end Informal.Realizations.Capture
