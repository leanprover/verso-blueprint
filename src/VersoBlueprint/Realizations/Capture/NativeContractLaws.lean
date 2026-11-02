/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.PlanLaws

/-! Positive ordinary native-contract coverage through the actual capture recipe.
Provider authenticity and planner request correctness remain separate. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

-- Proof-local access to the implementation and existing loop helpers only.
run_cmd do
  let env ← getEnv
  let owners ← #[``evaluate, ``evaluate_admitted, ``finish_uses, ``collectOrdinary_uses].mapM fun name => do
    let some owner := env.getModuleIdxFor? name | throwError "Capture helpers must be imported"
    pure owner
  for (name, _) in env.constants.toList do
    if (env.getModuleIdxFor? name).any owners.contains then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

/-- The two native obligations prescribed by one declaration step. This is a
proof-layer projection, not a second collector. Successful collection checks
that the step's stored source contexts agree before using this context. -/
def RealizationStep.nativeRequirements (step : RealizationStep) : Array (Contribution Requirement) :=
  let contexts := canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context))
  step.declarations.flatMap fun declaration =>
    let subject := Subject.declaration step.key ⟨contexts[0]!, declaration.name.toString⟩
    #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)].map fun (facet, validator) =>
      let key : RequirementKey := ⟨subject, facet⟩
      contribution `requirement (BindingEncoding.requirementKey key)
        { key, expected := .check validator, coverage := .dependencyClosure }

/-- Every successful ordinary collection contains exactly the two native
requirements per declaration step, including unavailable source/check branches.
Order and multiplicity are retained; no raw-input admission premise is needed. -/
theorem collectOrdinary_requirements (providers : Providers Id) (p : Plan)
    (accepted : (collectOrdinary providers p).run = .ok collected) :
    (Collected.input collected).requirements =
      p.ordinary.flatMap (fun node => node.realizations.flatMap (·.nativeRequirements)) := by
  simp only [collectOrdinary, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  have projected := array_loop_appends p.ordinary (fun c => (Collected.input c).requirements)
    (fun node => node.realizations.flatMap (·.nativeRequirements)) _ ?_ loop
  · simpa using projected
  intro node member current result step
  by_cases absent : (!p.raw.pending.contains node.label) = true
  · rw [ite_eq_left absent] at step
    simp only [exceptT_bind_ok_iff] at step
    obtain ⟨_, impossible, _⟩ := step
    cases impossible
  · rw [ite_eq_right absent] at step
    cases resolved : Contributions.resolve node.label p.raw.facts with
    | error diagnostics =>
      rw [resolved] at step
      simp only [exceptT_bind_ok_iff] at step
      obtain ⟨_, impossible, _⟩ := step
      cases impossible
    | ok view =>
      rw [resolved] at step
      simp only [exceptT_bind_ok_iff] at step
      obtain ⟨next, realizations, finished⟩ := step
      have nextRequirements : (Collected.input next).requirements =
          (Collected.input current).requirements ++ node.realizations.flatMap (·.nativeRequirements) := by
        have projected := array_loop_appends node.realizations (fun c => (Collected.input c).requirements)
          (·.nativeRequirements) _ ?_ realizations
        · exact projected
        intro realization member current result step
        apply Classical.byCases (p := _)
        · intro contextValid
          rw [ite_eq_left contextValid] at step
          apply Classical.byCases (p := _)
          · intro sourcesValid
            rw [ite_eq_left sourcesValid] at step
            simp only [exceptT_bind_ok_iff] at step
            obtain ⟨sourced, sources, declared, declarations, finished⟩ := step
            have sourceRequirements : (Collected.input sourced.1).requirements = (Collected.input current).requirements := by
              refine array_loop_invariant realization.sources
                (fun pair => (Collected.input pair.1).requirements = (Collected.input current).requirements) _ rfl ?_ sources
              intro source member pair result prior step
              clear loop realizations sources declarations finished
              repeat' first
                | (cases step; exact prior)
                | (simp only [exceptT_bind_ok_iff] at step; obtain ⟨value, returned, step⟩ := step)
                | split at step
            have declarationRequirements : (Collected.input declared.1).requirements =
                (Collected.input sourced.1).requirements ++ realization.nativeRequirements := by
              unfold RealizationStep.nativeRequirements
              refine array_loop_appends realization.declarations
                (fun pair => (Collected.input pair.1).requirements) _ _ ?_ declarations
              intro declaration member pair result step
              clear loop realizations sources declarations finished
              simp only [exceptT_bind_ok_iff] at step
              obtain ⟨prepared, _, step⟩ := step
              cases prepared <;> simp only [exceptT_bind_ok_iff] at step
              all_goals
                obtain ⟨observation, _, checkedResult, returned, step⟩ := step
                cases checkedResult with
                | ok checked =>
                  cases step
                  refine ⟨_, rfl, ?_⟩
                  simp [recordObservation, Function.comp_def]
                | error diagnostic =>
                  simp only [exceptT_bind_ok_iff] at step
                  obtain ⟨next, unavailable, finished⟩ := step
                  have nextRequirements := array_loop_invariant _
                    (fun next => (Collected.input next).requirements = _)
                    _ (Eq.refl _) (by
                      intro entry member current result prior step
                      cases step
                      exact prior) unavailable
                  cases finished
                  refine ⟨_, rfl, ?_⟩
                  simpa [Function.comp_def] using nextRequirements
            cases finished
            exact ⟨_, rfl, declarationRequirements.trans (congrArg (· ++ realization.nativeRequirements) sourceRequirements)⟩
          · intro sourcesInvalid
            rw [ite_eq_right sourcesInvalid] at step
            simp only [exceptT_bind_ok_iff] at step
            obtain ⟨_, impossible, _⟩ := step
            cases impossible
        · intro contextInvalid
          rw [ite_eq_right contextInvalid] at step
          simp only [exceptT_bind_ok_iff] at step
          obtain ⟨_, impossible, _⟩ := step
          cases impossible
      split at finished
      · cases finished; exact ⟨next, rfl, nextRequirements⟩
      · simp only [exceptT_bind_ok_iff] at finished
        obtain ⟨_, impossible, _⟩ := finished
        cases impossible

/-- Authored enrichment appends obligations without replacing any ordinary
requirement. Later prerequisite wiring has a weaker field-preservation contract. -/
theorem collectAuthored_requirements (providers : Providers Id) (p : Plan)
    (accepted : (collectAuthored providers p initial).run = .ok collected) :
    ∀ record ∈ (Collected.input initial).requirements,
      record ∈ (Collected.input collected).requirements := by
  simp only [collectAuthored, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  refine array_loop_invariant p.authored
    (fun current => ∀ record ∈ (Collected.input initial).requirements,
      record ∈ (Collected.input current).requirements) _ (fun _ member => member) ?_ loop
  intro authored member current result prior step
  simp only [exceptT_bind_ok_iff] at step
  obtain ⟨goals, goalLoop, sourced, sourceLoop, finished⟩ := step
  have goalRequirements : ∀ record ∈ (Collected.input initial).requirements,
      record ∈ (Collected.input goals).requirements := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at goalLoop
    refine list_loop_invariant _
      (fun current => ∀ record ∈ (Collected.input initial).requirements,
        record ∈ (Collected.input current).requirements) _ prior ?_ goalLoop
    intro index member current result prior step
    clear loop goalLoop sourceLoop finished
    apply Classical.byCases (p := _)
    · intro shapeValid
      rw [ite_eq_left shapeValid] at step
      simp only [exceptT_bind_ok_iff] at step
      obtain ⟨document, _, step⟩ := step
      apply Classical.byCases (p := _)
      · intro documentValid
        rw [ite_eq_left documentValid] at step
        simp only [exceptT_bind_ok_iff] at step
        obtain ⟨_, _, _, _, _, _, _, _, finished⟩ := step
        cases finished
        exact fun record member => Array.mem_push_of_mem _ (prior record member)
      · intro documentInvalid
        rw [ite_eq_right documentInvalid] at step
        simp only [exceptT_bind_ok_iff] at step
        obtain ⟨_, impossible, _⟩ := step
        cases impossible
    · intro shapeInvalid
      rw [ite_eq_right shapeInvalid] at step
      simp only [exceptT_bind_ok_iff] at step
      obtain ⟨_, impossible, _⟩ := step
      cases impossible
  have sourceRequirements : ∀ record ∈ (Collected.input initial).requirements,
      record ∈ (Collected.input sourced).requirements := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at sourceLoop
    refine list_loop_invariant _
      (fun current => ∀ record ∈ (Collected.input initial).requirements,
        record ∈ (Collected.input current).requirements) _ goalRequirements ?_ sourceLoop
    intro index member current result prior step
    simp only [exceptT_bind_ok_iff] at step
    obtain ⟨_, _, step⟩ := step
    cases step
    exact prior
  cases finished
  intro record member
  exact Array.mem_append_left _ (sourceRequirements record member)

/-- Every planned native requirement reaches the complete collection. Authored
requirements may add more, so this boundary asserts inclusion, not equality. -/
theorem assemble_nativeRequirements (providers : Providers Id) (p : Plan)
    (accepted : (assemble providers p).run = .ok collected)
    (member : record ∈ p.ordinary.flatMap (fun node => node.realizations.flatMap (·.nativeRequirements))) :
    record ∈ (Collected.input collected).requirements := by
  simp only [assemble] at accepted
  split at accepted
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨ordinary, ordinaryOk, authoredOk⟩ := accepted
    rw [← collectOrdinary_requirements providers p ordinaryOk] at member
    exact collectAuthored_requirements providers p authoredOk record member
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨_, impossible, _⟩ := accepted
    cases impossible

/-- Public evaluation retains each planned obligation's identity, origin,
validator and coverage. Finalization may extend its prerequisites. -/
theorem evaluate_nativeRequirements {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (member : record ∈ p.ordinary.flatMap (fun node => node.realizations.flatMap (·.nativeRequirements))) :
    ∃ retained ∈ snapshot.registry.contributions.requirements,
      retained.origin = record.origin ∧ retained.value.key = record.value.key ∧
      retained.value.expected = record.value.expected ∧ retained.value.coverage = record.value.coverage := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, collected, assembled, finished⟩ := accepted
  obtain ⟨retained, present, origin, key, expected, coverage, _⟩ :=
    (finish_preserves_selection finished).2.2 record (assemble_nativeRequirements _ _ assembled member)
  exact ⟨retained, present, origin, key, expected, coverage⟩

/-- Each declaration step creates both native contracts in its agreed source
context. Neither successful source preparation nor a successful check is assumed. -/
theorem evaluate_native_contract_created {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (declarationMember : declaration ∈ step.declarations)
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context])
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)]) :
    let key : RequirementKey := ⟨.declaration step.key ⟨context, declaration.name.toString⟩, name⟩
    ∃ retained ∈ snapshot.registry.contributions.requirements,
      DependencySelection.CollectorOwned retained.origin key ∧ retained.value.key = key ∧
      retained.value.expected = .check validator ∧ retained.value.coverage = .dependencyClosure := by
  let key : RequirementKey := ⟨.declaration step.key ⟨context, declaration.name.toString⟩, name⟩
  let record : Contribution Requirement := contribution `requirement (BindingEncoding.requirementKey key)
    { key, expected := .check validator, coverage := .dependencyClosure }
  have member : record ∈ p.ordinary.flatMap (fun node => node.realizations.flatMap (·.nativeRequirements)) := by
    apply Array.mem_flatMap.mpr
    refine ⟨node, nodeMember, Array.mem_flatMap.mpr ⟨step, stepMember, ?_⟩⟩
    simp only [RealizationStep.nativeRequirements, contextAgrees]
    apply Array.mem_flatMap.mpr
    refine ⟨declaration, declarationMember, Array.mem_map.mpr ⟨(name, validator), facet, ?_⟩⟩
    simp [record, key]
  obtain ⟨retained, present, origin, same, expected, coverage⟩ := evaluate_nativeRequirements accepted member
  exact ⟨retained, present, origin, same, expected, coverage⟩

/-- A completed planned native obligation justifies its source uses. Its parent
contract is derived from collection, not supplied by the caller. Final model and
declaration coverage, and their correspondence with the plan, remain premises. -/
theorem evaluate_planned_use_justified
    {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (useMember : use ∈ p.ordinary.flatMap (·.accepted.uses))
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedDeclaration : planned ∈ step.declarations)
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[model.context])
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (modelKey : model.key = step.key) (native : model.context.language = `lean)
    (declarationMember : declaration ∈ model.declarations)
    (objectKey : declaration.object = ⟨model.context, planned.name.toString⟩)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (source : use.node = model.key.node)
    (restriction : ∀ realization, use.realization = some realization → realization = model.key.name)
    (useFacet : name = `proof ∨ use.facet = `statement)
    (complete : (snapshot.registry.resultForRequirement ⟨.declaration model.key declaration.object, name⟩).complete = true) :
    ∃ parent ∈ snapshot.registry.contributions.requirements,
      parent.value.key = ⟨.declaration model.key declaration.object, name⟩ ∧
      DependencySelection.CollectorOwned parent.origin parent.value.key ∧
      parent.value.expected = .check validator ∧ parent.value.coverage = .dependencyClosure ∧
      ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = some model.context ∧
        ∃ keys, edge.selected = .ok keys ∧
          TargetSelection.Retained snapshot.registry model.context use.reference.label keys ∧
          ∀ selected ∈ keys, selected ∈ parent.value.prerequisites ∧
            ∃ requirement ∈ snapshot.registry.contributions.requirements,
              ∃ evidence ∈ snapshot.registry.contributions.evidence,
                snapshot.registry.requirement? selected = some requirement.value ∧
                requirement.value.key = selected ∧
                evidence.value.Fits requirement.value ((snapshot.registry.bindingFor selected).getD "") := by
  obtain ⟨parent, parentMember, origin, key, expected, coverage⟩ :=
    evaluate_native_contract_created evaluated nodeMember stepMember plannedDeclaration contextAgrees facet
  have parentKey : parent.value.key = ⟨.declaration model.key declaration.object, name⟩ := by
    simpa only [modelKey, objectKey] using key
  have owned : DependencySelection.CollectorOwned parent.origin parent.value.key := by
    rwa [key]
  refine ⟨parent, parentMember, parentKey, owned, expected, coverage, ?_⟩
  exact evaluate_ordinary_use_justified evaluated useMember modelMember native declarationMember
    facet parentMember parentKey owned expected coverage source restriction useFacet (by rwa [parentKey])

end Informal.Realizations.Capture
