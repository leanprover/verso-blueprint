/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.NativeContractLaws

/-! Ordinary model identities survive collection and authored enrichment.
These are projections of production data, not a parallel model or evaluator. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

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

/-- Joint identity projection. Documents and required-key arrays may be enriched;
the original producer, model identity and declaration objects stay together. -/
def _root_.Informal.Translations.Input.modelInventory (input : Input) : Array (Origin × RealizationKey × Context × Array ObjectKey) :=
  input.realizations.map fun record =>
    (record.origin, record.value.key, record.value.context, record.value.declarations.map (·.object))

/-- The ordinary model inventory prescribed by a realization's stored sources.
Successful collection validates the agreed context before constructing the model. -/
def RealizationStep.modelInventory (step : RealizationStep) : Origin × RealizationKey × Context × Array ObjectKey :=
  let context := (canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)))[0]!
  ((contribution `realization (BindingEncoding.realizationKey step.key) ()).origin,
    step.key, context, (nativeNames step.associations (step.sources.map (·.source))).map fun name => ⟨context, name.toString⟩)

private theorem map_objects_update (declarations : Array Realizations.Declaration)
    (witness : ObjectKey) (required : Array RequirementKey) :
    (declarations.map fun declaration =>
      if declaration.object == witness then { declaration with required } else declaration).map (·.object) =
      declarations.map (·.object) := by
  simp only [Array.map_map]
  congr 1
  funext declaration
  simp only [Function.comp_def]
  split <;> rfl

/-- Ordinary collection preserves exactly the joint planned model inventory,
including producer origins and declaration order/multiplicity. Provider failures
can affect observations and documents, but cannot delete these identities. -/
theorem collectOrdinary_modelInventory (providers : Providers Id) (p : Plan)
    (accepted : (collectOrdinary providers p).run = .ok collected) :
    (Collected.input collected).modelInventory =
      p.ordinary.flatMap (fun node => node.realizations.map (·.modelInventory)) := by
  simp only [collectOrdinary, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  have projected := array_loop_appends p.ordinary (fun c => (Collected.input c).modelInventory)
    (fun node => node.realizations.map (·.modelInventory)) _ ?_ loop
  · simpa [Input.modelInventory] using projected
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
      have nextInventory : (Collected.input next).modelInventory =
          (Collected.input current).modelInventory ++ node.realizations.map (·.modelInventory) := by
        have projected := array_loop_appends node.realizations (fun c => (Collected.input c).modelInventory)
          (fun step => #[step.modelInventory]) _ ?_ realizations
        · simpa only [Input.modelInventory, ← Array.map_eq_flatMap] using projected
        intro realization member current result step
        apply Classical.byCases (p := _)
        · intro contextValid
          rw [ite_eq_left contextValid] at step
          apply Classical.byCases (p := _)
          · intro sourcesValid
            rw [ite_eq_left sourcesValid] at step
            simp only [exceptT_bind_ok_iff] at step
            obtain ⟨sourced, sources, declared, declarations, finished⟩ := step
            let inventory := fun pair : Collected × Realization =>
              ((Collected.input pair.1).modelInventory,
                pair.2.key, pair.2.context, pair.2.declarations.map (·.object))
            have sourceInventory : inventory sourced =
                ((Collected.input current).modelInventory,
                  realization.modelInventory.2) := by
              refine array_loop_invariant realization.sources
                (fun pair => inventory pair = ((Collected.input current).modelInventory, realization.modelInventory.2)) _ ?_ ?_ sources
              · simp [inventory, RealizationStep.modelInventory, Array.map_map, Function.comp_def]
              · intro source member pair result prior step
                clear loop realizations sources declarations finished
                repeat' first
                  | (cases step; exact prior)
                  | (simp only [exceptT_bind_ok_iff] at step; obtain ⟨value, returned, step⟩ := step)
                  | split at step
            have declarationInventory : inventory declared = inventory sourced := by
              refine array_loop_invariant realization.declarations
                (fun pair => inventory pair = inventory sourced) _ rfl ?_ declarations
              intro declaration member pair result prior step
              clear loop realizations sources declarations finished
              simp only [exceptT_bind_ok_iff] at step
              obtain ⟨prepared, _, step⟩ := step
              cases prepared <;> simp only [exceptT_bind_ok_iff] at step
              all_goals
                obtain ⟨observation, _, checkedResult, returned, step⟩ := step
                cases checkedResult with
                | ok checked =>
                  cases step
                  simpa only [inventory, recordObservation, Input.modelInventory, map_objects_update] using prior
                | error diagnostic =>
                  simp only [exceptT_bind_ok_iff] at step
                  obtain ⟨next, unavailable, finished⟩ := step
                  have unchanged : (Collected.input next).modelInventory = (Collected.input pair.1).modelInventory := by
                    refine array_loop_invariant _
                      (fun next => (Collected.input next).modelInventory = (Collected.input pair.1).modelInventory)
                      _ ?_ ?_ unavailable
                    · rfl
                    · intro entry member current result prior step
                      cases step
                      exact prior
                  cases finished
                  simpa only [inventory, map_objects_update, unchanged] using prior
            cases finished
            refine ⟨_, rfl, ?_⟩
            have same := declarationInventory.trans sourceInventory
            simp only [inventory, Input.modelInventory, Prod.mk.injEq] at same
            simp only [Input.modelInventory, Array.map_push, contribution]
            rw [same.1, same.2]
            exact Array.push_eq_append
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
      · cases finished; exact ⟨next, rfl, nextInventory⟩
      · simp only [exceptT_bind_ok_iff] at finished
        obtain ⟨_, impossible, _⟩ := finished
        cases impossible

private theorem modelInventory_enrich (input : Input) (key : RealizationKey) (required : RequirementKey) :
    (input.realizations.map fun (record : Contribution Realization) =>
      if record.value.key != key then record else { record with value := { record.value with
        declarations := record.value.declarations.map fun declaration =>
          { declaration with required := canonical (declaration.required.push required) } } }).map
      (fun record => (record.origin, record.value.key, record.value.context, record.value.declarations.map (·.object))) =
      input.modelInventory := by
  simp only [Input.modelInventory, Array.map_map]
  congr 1
  funext record
  simp only [Function.comp_def]
  split
  · rfl
  · simp [Array.map_map, Function.comp_def]

/-- Authored goals can extend required keys, but cannot detach or discard a
prior model's origin, identity, context or ordered declaration inventory. -/
theorem collectAuthored_modelInventory (providers : Providers Id) (p : Plan)
    (accepted : (collectAuthored providers p initial).run = .ok collected) :
    ∀ entry ∈ (Collected.input initial).modelInventory,
      entry ∈ (Collected.input collected).modelInventory := by
  simp only [collectAuthored, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  refine array_loop_invariant p.authored
    (fun current => ∀ entry ∈ (Collected.input initial).modelInventory,
      entry ∈ (Collected.input current).modelInventory) _ (fun _ member => member) ?_ loop
  intro authored member current result prior step
  simp only [exceptT_bind_ok_iff] at step
  obtain ⟨goals, goalLoop, sourced, sourceLoop, finished⟩ := step
  have goalInventory : ∀ entry ∈ (Collected.input initial).modelInventory,
      entry ∈ (Collected.input goals).modelInventory := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at goalLoop
    refine list_loop_invariant _
      (fun current => ∀ entry ∈ (Collected.input initial).modelInventory,
        entry ∈ (Collected.input current).modelInventory) _ prior ?_ goalLoop
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
        intro entry member
        simp only [Input.modelInventory]
        rw [modelInventory_enrich]
        exact prior entry member
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
  have sourceInventory : ∀ entry ∈ (Collected.input initial).modelInventory,
      entry ∈ (Collected.input sourced).modelInventory := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at sourceLoop
    refine list_loop_invariant _
      (fun current => ∀ entry ∈ (Collected.input initial).modelInventory,
        entry ∈ (Collected.input current).modelInventory) _ goalInventory ?_ sourceLoop
    intro index member current result prior step
    simp only [exceptT_bind_ok_iff] at step
    obtain ⟨_, _, step⟩ := step
    cases step
    exact prior
  cases finished
  intro entry member
  simp only [Input.modelInventory, Array.map_append]
  exact Array.mem_append_left _ (sourceInventory entry member)

/-- The complete recipe retains every ordinary model inventory, even when
subsequent authored records enrich those models or add other realizations. -/
theorem assemble_modelInventory (providers : Providers Id) (p : Plan)
    (accepted : (assemble providers p).run = .ok collected)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations) :
    step.modelInventory ∈ (Collected.input collected).modelInventory := by
  simp only [assemble] at accepted
  split at accepted
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨ordinary, ordinaryOk, authoredOk⟩ := accepted
    apply collectAuthored_modelInventory providers p authoredOk
    rw [collectOrdinary_modelInventory providers p ordinaryOk]
    exact Array.mem_flatMap.mpr ⟨node, nodeMember, Array.mem_map.mpr ⟨step, stepMember, rfl⟩⟩
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨_, impossible, _⟩ := accepted
    cases impossible

/-- Planned ordinary model identity reaches the final admitted registry. -/
theorem evaluate_modelInventory {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations) :
    step.modelInventory ∈ snapshot.registry.contributions.modelInventory := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, collected, assembled, finished⟩ := accepted
  have member := assemble_modelInventory _ _ assembled nodeMember stepMember
  simpa only [Input.modelInventory, (finish_preserves_selection finished).2.1] using member

/-- Successful evaluation creates the ordinary model with exact source declaration
objects and producer origin. This same model is returned by the public lookup. -/
theorem evaluate_model_created {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    ∃ record ∈ snapshot.registry.contributions.realizations,
      record.origin = (contribution `realization (BindingEncoding.realizationKey step.key) ()).origin ∧
      record.value.key = step.key ∧ record.value.context = context ∧
      record.value.declarations.map (·.object) =
        (nativeNames step.associations (step.sources.map (·.source))).map (fun name => ⟨context, name.toString⟩) ∧
      snapshot.registry.realization? step.key = some record.value := by
  have inventory := evaluate_modelInventory accepted nodeMember stepMember
  obtain ⟨record, member, same⟩ := Array.mem_map.mp inventory
  simp only [RealizationStep.modelInventory, contextAgrees] at same
  simp only [Prod.mk.injEq] at same
  refine ⟨record, member, same.1, same.2.1, same.2.2.1, same.2.2.2, ?_⟩
  exact (admit_realization_lookup_iff (evaluate_admitted accepted)).mpr
    ⟨record, member, rfl, same.2.1⟩

/-- Completion of a planned native declaration justifies its source uses without
assuming any final model, declaration or parent record. The supplied plan must
name the declaration both in its source union and in its declaration steps;
correctness of planner-generated correspondence is a separate boundary. -/
theorem evaluate_declared_use_justified
    {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (useMember : use ∈ p.ordinary.flatMap (·.accepted.uses))
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedDeclaration : planned ∈ step.declarations)
    (sourceDeclaration : planned.name ∈ nativeNames step.associations (step.sources.map (·.source)))
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context])
    (native : context.language = `lean)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (source : use.node = step.key.node)
    (restriction : ∀ realization, use.realization = some realization → realization = step.key.name)
    (useFacet : name = `proof ∨ use.facet = `statement)
    (complete : (snapshot.registry.resultForRequirement
      ⟨.declaration step.key ⟨context, planned.name.toString⟩, name⟩).complete = true) :
    ∃ parent ∈ snapshot.registry.contributions.requirements,
      parent.value.key = ⟨.declaration step.key ⟨context, planned.name.toString⟩, name⟩ ∧
      DependencySelection.CollectorOwned parent.origin parent.value.key ∧
      parent.value.expected = .check validator ∧ parent.value.coverage = .dependencyClosure ∧
      ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = some context ∧
        ∃ keys, edge.selected = .ok keys ∧
          TargetSelection.Retained snapshot.registry context use.reference.label keys ∧
          ∀ selected ∈ keys, selected ∈ parent.value.prerequisites ∧
            ∃ requirement ∈ snapshot.registry.contributions.requirements,
              ∃ evidence ∈ snapshot.registry.contributions.evidence,
                snapshot.registry.requirement? selected = some requirement.value ∧
                requirement.value.key = selected ∧
                evidence.value.Fits requirement.value ((snapshot.registry.bindingFor selected).getD "") := by
  obtain ⟨record, modelMember, _, modelKey, modelContext, objects, _⟩ :=
    evaluate_model_created evaluated nodeMember stepMember contextAgrees
  have objectMember : (⟨context, planned.name.toString⟩ : ObjectKey) ∈ record.value.declarations.map (·.object) := by
    rw [objects]
    exact Array.mem_map.mpr ⟨planned.name, sourceDeclaration, rfl⟩
  obtain ⟨declaration, declarationMember, objectKey⟩ := Array.mem_map.mp objectMember
  have result := evaluate_planned_use_justified evaluated useMember nodeMember stepMember plannedDeclaration
    (by rwa [modelContext]) (Array.mem_map.mpr ⟨record, modelMember, rfl⟩) modelKey
    (by rwa [modelContext]) declarationMember (by rwa [modelContext]) facet
    (by rwa [modelKey]) (by rwa [modelKey]) useFacet (by rwa [modelKey, objectKey])
  simpa only [modelKey, modelContext, objectKey] using result

end Informal.Realizations.Capture
