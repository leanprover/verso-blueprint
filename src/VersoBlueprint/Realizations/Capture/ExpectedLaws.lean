/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.FacetLaws

/-! Positive expected-goal selection through the production authoring recipe. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

run_cmd do
  let env ← getEnv
  let owners ← #[``evaluate, ``evaluate_admitted, ``finish_uses,
    ``collectOrdinary_declarationRequired, ``plan_raw, ``selectUses_in_context].mapM fun name => do
    let some owner := env.getModuleIdxFor? name | throwError "Capture helpers must be imported"
    pure owner
  for (name, _) in env.constants.toList do
    if (env.getModuleIdxFor? name).any owners.contains then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

/-- The authored goal's checked model identity and singleton declaration remain
paired with the selected expected key. A law predicate, not a separate store. -/
def _root_.Informal.Translations.Input.ExpectedSelected (input : Input) (node project : Name) : Prop :=
  ∃ record ∈ input.realizations, record.value.key = ⟨node, `lean⟩ ∧
    record.value.context = ⟨`lean, project⟩ ∧
    ∃ declaration, record.value.declarations = #[declaration] ∧
      (⟨.declaration ⟨node, `lean⟩ declaration.object, `expectedProof⟩ : RequirementKey) ∈ declaration.required

private theorem expectedSelected_enrich (input : Input) (target : RealizationKey) (extra : RequirementKey)
    (prior : input.ExpectedSelected node project) :
    ({ input with realizations := input.realizations.map fun (record : Contribution Realization) =>
      if record.value.key != target then record else { record with value := { record.value with
        declarations := record.value.declarations.map fun declaration =>
          { declaration with required := canonical (declaration.required.push extra) } } } } : Input).ExpectedSelected node project := by
  obtain ⟨record, member, key, context, declaration, singleton, selected⟩ := prior
  refine ⟨_, Array.mem_map.mpr ⟨record, member, rfl⟩, ?_⟩
  split
  · exact ⟨key, context, declaration, singleton, selected⟩
  · refine ⟨key, context, { declaration with required := canonical (declaration.required.push extra) }, by simp [singleton], ?_⟩
    simpa only [mem_canonical] using Array.mem_push_of_mem extra selected

private theorem expectedSelected_created (input : Input) (node project : Name)
    (valid : let models := canonical ((input.realizations.filter (·.value.key == ⟨node, `lean⟩)).map (·.value))
      (models.size == 1 && models[0]!.context == ⟨`lean, project⟩ && models[0]!.declarations.size == 1) = true) :
    (let models := canonical ((input.realizations.filter (·.value.key == ⟨node, `lean⟩)).map (·.value))
     let required : RequirementKey := ⟨.declaration ⟨node, `lean⟩ models[0]!.declarations[0]!.object, `expectedProof⟩
     { input with realizations := input.realizations.map fun (record : Contribution Realization) =>
      if record.value.key != ⟨node, `lean⟩ then record else { record with value := { record.value with
        declarations := record.value.declarations.map fun declaration =>
          { declaration with required := canonical (declaration.required.push required) } } } } : Input).ExpectedSelected node project := by
  dsimp only at valid ⊢
  simp only [Bool.and_eq_true, beq_iff_eq] at valid
  obtain ⟨⟨size, context⟩, declarationSize⟩ := valid
  obtain ⟨model, singleton⟩ := Array.size_eq_one_iff.mp size
  rw [singleton] at context declarationSize ⊢
  simp at context declarationSize
  obtain ⟨declaration, declarationSingleton⟩ := Array.size_eq_one_iff.mp declarationSize
  have member : model ∈ canonical ((input.realizations.filter (·.value.key == ⟨node, `lean⟩)).map (·.value)) := by
    rw [singleton]; simp
  rw [mem_canonical] at member
  obtain ⟨record, recordMember, modelEq⟩ := Array.mem_map.mp member
  subst model
  obtain ⟨member, key⟩ := Array.mem_filter.mp recordMember
  have keyEq : record.value.key = ⟨node, `lean⟩ := by simpa using key
  refine ⟨_, Array.mem_map.mpr ⟨record, member, rfl⟩, ?_⟩
  simp [keyEq, context, declarationSingleton, mem_canonical]

/-- Every processed authored native goal adds an expected key to the unique
Lean declaration in its checked project. Later goals and authored additions
retain that selection; no final declaration or required-key witness is assumed. -/
theorem collectAuthored_expectedSelected (providers : Providers Id) (p : Plan)
    (accepted : (collectAuthored providers p initial).run = .ok collected)
    (stepMember : focus ∈ p.authored) (goalMember : (node, expectation) ∈ focus.record.nativeGoals) :
    (Collected.input collected).ExpectedSelected node focus.record.project := by
  let selected := fun current => (Collected.input current).ExpectedSelected node focus.record.project
  simp only [collectAuthored, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  refine (array_loop_hits p.authored (fun _ => True) selected (· = focus) _ ?_ trivial
    (Or.inr ⟨focus, stepMember, rfl⟩) loop).2
  intro authored member current result _ executed
  simp only [exceptT_bind_ok_iff] at executed
  obtain ⟨goals, goalLoop, sourced, sourceLoop, finished⟩ := executed
  have goalsSelected : selected current ∨ authored = focus → selected goals := by
    intro seed
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at goalLoop
    refine (list_loop_hits _ (fun _ => True) selected
      (fun index => authored.record.project = focus.record.project ∧ (authored.record.nativeGoals[index]!).1 = node)
      _ ?_ trivial ?_ goalLoop).2
    · intro index member current result _ executed
      clear loop goalLoop sourceLoop finished
      apply Classical.byCases (p := _)
      · intro shapeValid
        rw [ite_eq_left shapeValid] at executed
        simp only [exceptT_bind_ok_iff] at executed
        obtain ⟨document, _, executed⟩ := executed
        apply Classical.byCases (p := _)
        · intro documentValid
          rw [ite_eq_left documentValid] at executed
          simp only [exceptT_bind_ok_iff] at executed
          obtain ⟨_, _, _, _, _, _, _, _, finished⟩ := executed
          cases finished
          refine ⟨_, rfl, trivial, ?_⟩
          rintro (prior | ⟨projectEq, nodeEq⟩)
          · exact expectedSelected_enrich _ _ _ prior
          · have added := expectedSelected_created (Collected.input current)
              (authored.record.nativeGoals[index]!).1 authored.record.project shapeValid
            simpa only [selected, Input.ExpectedSelected, projectEq, nodeEq] using added
        · intro documentInvalid
          rw [ite_eq_right documentInvalid] at executed
          simp only [exceptT_bind_ok_iff] at executed
          obtain ⟨_, impossible, _⟩ := executed
          cases impossible
      · intro shapeInvalid
        rw [ite_eq_right shapeInvalid] at executed
        simp only [exceptT_bind_ok_iff] at executed
        obtain ⟨_, impossible, _⟩ := executed
        cases impossible
    · rcases seed with prior | rfl
      · exact Or.inl prior
      · obtain ⟨index, bound, same⟩ := Array.mem_iff_getElem.mp goalMember
        refine Or.inr ⟨index, ?_, rfl, ?_⟩
        · simpa using bound
        · simp [getElem!_pos, bound, same]
  have sourcesSelected : selected goals → selected sourced := by
    intro prior
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at sourceLoop
    refine list_loop_invariant _ selected _ prior ?_ sourceLoop
    intro index member current result prior executed
    simp only [exceptT_bind_ok_iff] at executed
    obtain ⟨_, _, executed⟩ := executed
    cases executed
    exact prior
  cases finished
  refine ⟨_, rfl, trivial, ?_⟩
  intro seed
  obtain ⟨record, member, key, context, declaration, singleton, required⟩ := sourcesSelected (goalsSelected seed)
  exact ⟨record, Array.mem_append_left _ member, key, context, declaration, singleton, required⟩

/-- The complete recipe processes each planned authored native goal. Native
obligation preservation is provided independently by the declaration-selection laws. -/
theorem assemble_expectedSelected (providers : Providers Id) (p : Plan)
    (accepted : (assemble providers p).run = .ok collected)
    (stepMember : focus ∈ p.authored) (goalMember : (node, expectation) ∈ focus.record.nativeGoals) :
    (Collected.input collected).ExpectedSelected node focus.record.project := by
  simp only [assemble] at accepted
  split at accepted
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨ordinary, _, authoredOk⟩ := accepted
    exact collectAuthored_expectedSelected providers p authoredOk stepMember goalMember
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨_, impossible, _⟩ := accepted
    cases impossible

/-- Finalization retains the checked model context, singleton declaration and
expected-key selection created for a planned authored goal. -/
theorem evaluate_expectedSelected {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (stepMember : focus ∈ p.authored) (goalMember : (node, expectation) ∈ focus.record.nativeGoals) :
    snapshot.registry.contributions.ExpectedSelected node focus.record.project := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, collected, assembled, finished⟩ := accepted
  have selected := assemble_expectedSelected _ _ assembled stepMember goalMember
  simpa only [Input.ExpectedSelected, (finish_preserves_selection finished).2.1] using selected

/-- A planned authored goal reaches both public declaration and realization
queries, for the same singleton declaration in the checked stored project. -/
theorem evaluate_expected_selected {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (stepMember : focus ∈ p.authored) (goalMember : (node, expectation) ∈ focus.record.nativeGoals) :
    ∃ model declaration, snapshot.registry.realization? ⟨node, `lean⟩ = some model ∧
      model.context = ⟨`lean, focus.record.project⟩ ∧ model.declarations = #[declaration] ∧
      (⟨.declaration ⟨node, `lean⟩ declaration.object, `expectedProof⟩ : RequirementKey) ∈
        snapshot.registry.requiredFor (.declaration ⟨node, `lean⟩ declaration.object) ∧
      (⟨.declaration ⟨node, `lean⟩ declaration.object, `expectedProof⟩ : RequirementKey) ∈
        snapshot.registry.requiredFor (.realization ⟨node, `lean⟩) := by
  obtain ⟨record, member, key, context, declaration, singleton, selected⟩ :=
    evaluate_expectedSelected accepted stepMember goalMember
  have admitted := evaluate_admitted accepted
  have lookup := (admit_realization_lookup_iff admitted).mpr ⟨record, member, rfl, key⟩
  refine ⟨record.value, declaration, lookup, context, singleton, ?_, ?_⟩
  · have declarationLookup : record.value.declarations.find? (·.object == declaration.object) = some declaration := by
      simp [singleton]
    rw [admit_requiredFor_declaration admitted lookup declarationLookup]
    exact selected
  · rw [admit_requiredFor_realization admitted lookup]
    apply (mem_realization_requirements _ _).mpr
    exact Or.inr (Or.inr ⟨declaration, by simp [singleton], selected⟩)

/-- Authored records, including native goals and origins, survive the actual
planner after exact-record deduplication. This does not yet establish request-handle correctness. -/
private theorem plan_authored_records (raw : Raw) : (plan raw).authored.map (·.record) =
    raw.authored.foldl (fun out record =>
      if out.any (fun previous => decide (previous = record)) then out else out.push record) #[] := by
  unfold plan
  simp only [Id.run, bind, pure]
  generalize ordinaryEq : forIn (m := Id) raw.nodes ({ raw } : Plan) _ = ordinary
  have ordinaryEmpty : ordinary.authored = #[] := by
    rw [← ordinaryEq]
    apply id_array_loop_invariant raw.nodes (fun p : Plan => p.authored = #[]) _ rfl
    intro entry member current prior
    rcases entry with ⟨label, accepted⟩
    clear ordinaryEq
    apply id_array_loop_invariant _ (fun pair : Plan × Array RealizationStep => pair.1.authored = #[]) _ prior
    intro key member pair prior
    apply id_array_loop_invariant _ (fun pair : Plan × Array DeclarationStep => pair.1.authored = #[]) _ ?_ ?_
    · apply id_array_loop_invariant _ (fun pair : Plan × Array SourceStep => pair.1.authored = #[]) _ prior
      intro source member pair prior
      cases source.payload <;> simp only
      all_goals first
        | exact prior
        | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
    · intro name member pair prior
      apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => pair.1.authored = #[]) _ ?_ ?_
      · apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => pair.1.authored = #[]) _ prior
        intro association member pair prior
        exact prior
      · intro source member pair prior
        cases source.payload <;> simp only
        all_goals first
          | exact prior
          | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
  refine (congrArg Prod.snd (id_array_loop_projects _
    (fun p : Plan => ((), p.authored.map (·.record))) id _ ?_)).trans ?_
  · intro record member current
    clear ordinaryEq
    generalize goalsEq : forIn (m := Id) (α := Name × Name) (β := Plan × Array Nat)
      (_ : Array (Name × Name)) (current, #[]) _ = goals
    have goalsUnchanged : goals.1.authored = current.authored := by
      rw [← goalsEq]
      apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => pair.1.authored = current.authored) _ rfl
      intro goal member pair prior
      exact prior
    generalize documentsEq : forIn (m := Id) (α := DocumentKey) (β := Plan × Array Nat)
      (_ : Array DocumentKey) (goals.1, #[]) _ = documented
    have documentsUnchanged : documented.1.authored = goals.1.authored := by
      rw [← documentsEq]
      apply id_array_loop_invariant (initial := (goals.1, #[])) _
        (fun pair : Plan × Array Nat => pair.1.authored = goals.1.authored) _ rfl
      intro document member pair prior
      exact prior
    refine ⟨_, rfl, ?_⟩
    simp only [Array.map_push, documentsUnchanged, goalsUnchanged, id_eq]
  · simp [ordinaryEmpty]

/-- Planning removes only exact duplicate authored records; it preserves goals,
origins and project identity without assuming anything about request handles. -/
theorem plan_authored_record_mem_iff (raw : Raw) (record : Environment.AuthoringRecord) :
    record ∈ (plan raw).authored.map (·.record) ↔ record ∈ raw.authored := by
  rw [plan_authored_records]
  letI : BEq Environment.AuthoringRecord := ⟨fun a b => decide (a = b)⟩
  letI : LawfulBEq Environment.AuthoringRecord := by
    constructor <;> intros <;> simp_all
  simpa only [Array.contains_iff_mem, Array.any_eq_true', decide_eq_true_eq,
    exists_eq_right, Array.not_mem_empty, false_or] using
    mem_unique_fold raw.authored #[] record

/-- Each raw authored native goal selects its expected key in the actual public
registry. Planner entries and the checked singleton witness are derived. -/
theorem evaluate_raw_expected_selected {raw : Raw} {observations : Observations (plan raw)} {snapshot : Snapshot}
    (accepted : evaluate (plan raw) observations = .ok snapshot)
    (recordMember : record ∈ raw.authored) (goalMember : (node, expectation) ∈ record.nativeGoals) :
    ∃ model declaration, snapshot.registry.realization? ⟨node, `lean⟩ = some model ∧
      model.context = ⟨`lean, record.project⟩ ∧ model.declarations = #[declaration] ∧
      (⟨.declaration ⟨node, `lean⟩ declaration.object, `expectedProof⟩ : RequirementKey) ∈
        snapshot.registry.requiredFor (.declaration ⟨node, `lean⟩ declaration.object) ∧
      (⟨.declaration ⟨node, `lean⟩ declaration.object, `expectedProof⟩ : RequirementKey) ∈
        snapshot.registry.requiredFor (.realization ⟨node, `lean⟩) := by
  have plannedMember := (plan_authored_record_mem_iff raw record).mpr recordMember
  rw [Array.mem_map] at plannedMember
  obtain ⟨focus, member, rfl⟩ := plannedMember
  exact evaluate_expected_selected accepted member goalMember

/-- Rendering completion includes every processed authored expected goal, with
original fitting evidence and a well-founded prerequisite justification. This
asserts selection and evidence soundness, not the truth of provider-reported goals. -/
theorem evaluate_raw_assessment_expected_justified
    {raw : Raw} {observations : Observations (plan raw)} {snapshot : Snapshot}
    (evaluated : evaluate (plan raw) observations = .ok snapshot)
    (recordMember : record ∈ raw.authored) (goalMember : (node, expectation) ∈ record.nativeGoals)
    (complete : (snapshot.assessmentFor node).requiredComplete = true) :
    ∃ model declaration, snapshot.registry.realization? ⟨node, `lean⟩ = some model ∧
      model.context = ⟨`lean, record.project⟩ ∧ model.declarations = #[declaration] ∧
      let required : RequirementKey := ⟨.declaration ⟨node, `lean⟩ declaration.object, `expectedProof⟩
      (snapshot.registry.resultForRequirement required).complete = true ∧
        Acc snapshot.registry.Prerequisite required ∧
        ∀ dependency, dependency = required ∨ Relation.TransGen snapshot.registry.Prerequisite dependency required →
          ∃ requirement ∈ snapshot.registry.contributions.requirements,
            ∃ evidence ∈ snapshot.registry.contributions.evidence,
              snapshot.registry.requirement? dependency = some requirement.value ∧
              requirement.value.key = dependency ∧
              evidence.value.Fits requirement.value ((snapshot.registry.bindingFor dependency).getD "") := by
  obtain ⟨model, declaration, lookup, context, singleton, _, selected⟩ :=
    evaluate_raw_expected_selected evaluated recordMember goalMember
  exact ⟨model, declaration, lookup, context, singleton,
    (snapshot.registry.complete_requires_all _ (snapshot.assessment_complete_result complete)).2 _ selected,
    (evaluate_assessment_justified evaluated complete).2 _ selected⟩

end Informal.Realizations.Capture
