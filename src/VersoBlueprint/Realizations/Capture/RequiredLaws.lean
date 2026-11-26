/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.DeclarationPlanLaws

/-! Positive native declaration selection through collection and public assessment.
Requirement existence alone does not establish that an assessment selects it. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

run_cmd do
  let env ← getEnv
  let owners ← #[``evaluate, ``evaluate_admitted, ``finish_uses, ``collectOrdinary_modelInventory].mapM fun name => do
    let some owner := env.getModuleIdxFor? name | throwError "Capture helpers must be imported"
    pure owner
  for (name, _) in env.constants.toList do
    if (env.getModuleIdxFor? name).any owners.contains then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

private theorem list_loop_hits (entries : List α) (valid property : β → Prop)
    (hit : α → Prop) (body : α → β → ExceptT ε Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ current result, valid current →
      (body entry current).run = .ok result → ∃ next, result = .yield next ∧ valid next ∧
        (property current ∨ hit entry → property next))
    (initialValid : valid initial) (seed : property initial ∨ ∃ entry ∈ entries, hit entry)
    (accepted : (forIn entries initial body).run = .ok final) : valid final ∧ property final := by
  induction entries generalizing initial with
  | nil => cases accepted; exact ⟨initialValid, by simpa using seed⟩
  | cons entry entries ih =>
    simp only [List.forIn_cons, exceptT_bind_ok_iff] at accepted
    obtain ⟨result, first, rest⟩ := accepted
    obtain ⟨next, rfl, validNext, advance⟩ := step entry (by simp) initial result initialValid first
    apply ih (fun item member => step item (by simp [member])) validNext ?_ rest
    rcases seed with prior | ⟨item, member, focus⟩
    · exact Or.inl (advance (Or.inl prior))
    · rcases List.mem_cons.mp member with rfl | member
      · exact Or.inl (advance (Or.inr focus))
      · exact Or.inr ⟨item, member, focus⟩

private theorem array_loop_hits (entries : Array α) (valid property : β → Prop)
    (hit : α → Prop) (body : α → β → ExceptT ε Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ current result, valid current →
      (body entry current).run = .ok result → ∃ next, result = .yield next ∧ valid next ∧
        (property current ∨ hit entry → property next))
    (initialValid : valid initial) (seed : property initial ∨ ∃ entry ∈ entries, hit entry)
    (accepted : (forIn entries initial body).run = .ok final) : valid final ∧ property final := by
  rw [← Array.forIn_toList] at accepted
  exact list_loop_hits entries.toList valid property hit body
    (fun entry member => step entry (by simpa using member)) initialValid (by simpa using seed) accepted

private def DeclarationRequires (declarations : Array Realizations.Declaration)
    (object : ObjectKey) (required : RequirementKey) : Prop :=
  ∃ declaration ∈ declarations, declaration.object = object ∧ required ∈ declaration.required

/-- A declaration and one of its selected obligations remain paired with the
realization identity. This is a predicate on production records, not a store. -/
def _root_.Informal.Translations.Input.DeclarationRequires (input : Input)
    (key : RealizationKey) (object : ObjectKey) (required : RequirementKey) : Prop :=
  ∃ record ∈ input.realizations, record.value.key = key ∧
    ∃ declaration ∈ record.value.declarations,
      declaration.object = object ∧ required ∈ declaration.required

private theorem declarationRequires_update (declarations : Array Realizations.Declaration)
    (key : RealizationKey) (object witness : ObjectKey)
    (seed : DeclarationRequires declarations object ⟨.declaration key object, `proof⟩ ∨
      (object ∈ declarations.map (·.object) ∧ witness = object)) :
    DeclarationRequires (declarations.map fun declaration =>
      if declaration.object == witness then
        { declaration with required := #[⟨.declaration key witness, `proof⟩] } else declaration)
      object ⟨.declaration key object, `proof⟩ := by
  rcases seed with ⟨declaration, member, same, required⟩ | ⟨member, rfl⟩
  · refine ⟨_, Array.mem_map.mpr ⟨declaration, member, rfl⟩, ?_⟩
    split <;> simp_all
  · obtain ⟨declaration, member, same⟩ := Array.mem_map.mp member
    refine ⟨_, Array.mem_map.mpr ⟨declaration, member, rfl⟩, ?_⟩
    simp [same]

/-- Each source declaration that has a planned check selects its native proof
obligation, even when preparation or checking returns an unavailable result. -/
theorem collectOrdinary_declarationRequired (providers : Providers Id) (p : Plan)
    (accepted : (collectOrdinary providers p).run = .ok collected)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedMember : planned ∈ step.declarations)
    (sourceMember : planned.name ∈ nativeNames step.associations (step.sources.map (·.source)))
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    (Collected.input collected).DeclarationRequires step.key ⟨context, planned.name.toString⟩
      ⟨.declaration step.key ⟨context, planned.name.toString⟩, `proof⟩ := by
  let object : ObjectKey := ⟨context, planned.name.toString⟩
  let required : RequirementKey := ⟨.declaration step.key object, `proof⟩
  let selected := fun c => (Collected.input c).DeclarationRequires step.key object required
  simp only [collectOrdinary, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  refine (array_loop_hits p.ordinary (fun _ => True) selected (· = node) _ ?_ trivial
    (Or.inr ⟨node, nodeMember, rfl⟩) loop).2
  intro entry member current result _ executed
  by_cases absent : (!p.raw.pending.contains entry.label) = true
  · rw [ite_eq_left absent] at executed
    simp only [exceptT_bind_ok_iff] at executed
    obtain ⟨_, impossible, _⟩ := executed
    cases impossible
  · rw [ite_eq_right absent] at executed
    cases resolved : Contributions.resolve entry.label p.raw.facts with
    | error diagnostics =>
      rw [resolved] at executed
      simp only [exceptT_bind_ok_iff] at executed
      obtain ⟨_, impossible, _⟩ := executed
      cases impossible
    | ok view =>
      rw [resolved] at executed
      simp only [exceptT_bind_ok_iff] at executed
      obtain ⟨next, realizations, finished⟩ := executed
      have advance : selected current ∨ entry = node → selected next := by
        intro seed
        refine (array_loop_hits entry.realizations (fun _ => True) selected (· = step) _ ?_ trivial ?_ realizations).2
        · intro realization member current result _ executed
          apply Classical.byCases (p := _)
          · intro contextValid
            rw [ite_eq_left contextValid] at executed
            apply Classical.byCases (p := _)
            · intro sourcesValid
              rw [ite_eq_left sourcesValid] at executed
              simp only [exceptT_bind_ok_iff] at executed
              obtain ⟨sourced, sources, declared, declarations, finished⟩ := executed
              have sourceFields : ((Collected.input sourced.1).realizations, sourced.2.key, sourced.2.declarations) =
                  ((Collected.input current).realizations, realization.key,
                    (nativeNames realization.associations (realization.sources.map (·.source))).map fun name =>
                      { object := ⟨(canonical (realization.sources.map (·.source.context) ++ realization.associations.map (·.context)))[0]!, name.toString⟩ }) := by
                refine array_loop_invariant realization.sources
                  (fun pair => ((Collected.input pair.1).realizations, pair.2.key, pair.2.declarations) =
                    ((Collected.input current).realizations, realization.key,
                      (nativeNames realization.associations (realization.sources.map (·.source))).map fun name =>
                        { object := ⟨(canonical (realization.sources.map (·.source.context) ++ realization.associations.map (·.context)))[0]!, name.toString⟩ }))
                  _ (by simp only [Array.map_map, Function.comp_def]) ?_ sources
                intro source member pair result prior executed
                clear loop realizations sources declarations finished
                repeat' first
                  | (cases executed; exact prior)
                  | (simp only [exceptT_bind_ok_iff] at executed; obtain ⟨value, returned, executed⟩ := executed)
                  | split at executed
              have declarationFields : ((Collected.input declared.1).realizations, declared.2.key,
                  declared.2.declarations.map (·.object)) =
                  ((Collected.input sourced.1).realizations, sourced.2.key, sourced.2.declarations.map (·.object)) := by
                refine array_loop_invariant realization.declarations
                  (fun pair => ((Collected.input pair.1).realizations, pair.2.key, pair.2.declarations.map (·.object)) = _) _ rfl ?_ declarations
                intro declaration member pair result prior executed
                clear loop realizations sources declarations finished
                simp only [exceptT_bind_ok_iff] at executed
                obtain ⟨prepared, _, executed⟩ := executed
                cases prepared <;> simp only [exceptT_bind_ok_iff] at executed
                all_goals
                  obtain ⟨observation, _, checkedResult, _, executed⟩ := executed
                  cases checkedResult with
                  | ok checked => cases executed; simpa only [recordObservation, map_objects_update] using prior
                  | error diagnostic =>
                    simp only [exceptT_bind_ok_iff] at executed
                    obtain ⟨next, unavailable, finished⟩ := executed
                    have unchanged : (Collected.input next).realizations = (Collected.input pair.1).realizations := by
                      refine array_loop_invariant _ (fun next => (Collected.input next).realizations = (Collected.input pair.1).realizations)
                        _ ?_ ?_ unavailable
                      · rfl
                      · intro entry member current result prior executed
                        cases executed
                        exact prior
                    cases finished
                    simpa only [map_objects_update, unchanged] using prior
              cases finished
              refine ⟨_, rfl, trivial, ?_⟩
              intro seed
              rcases seed with prior | sameStep
              · obtain ⟨record, member, key, declaration, declarationMember, same, requiredMember⟩ := prior
                refine ⟨record, Array.mem_push_of_mem _ ?_, key, declaration, declarationMember, same, requiredMember⟩
                have arrays : (Collected.input declared.1).realizations = (Collected.input sourced.1).realizations := congrArg Prod.fst declarationFields
                have sourceArrays : (Collected.input sourced.1).realizations = (Collected.input current).realizations := congrArg Prod.fst sourceFields
                rwa [arrays, sourceArrays]
              · subst realization
                have hasRequired : DeclarationRequires declared.2.declarations object required := by
                  refine (array_loop_hits step.declarations
                    (fun pair => object ∈ pair.2.declarations.map (·.object))
                    (fun pair => DeclarationRequires pair.2.declarations object required)
                    (· = planned) _ ?_ ?_ (Or.inr ⟨planned, plannedMember, rfl⟩) declarations).2
                  · intro declaration member pair result valid executed
                    clear loop realizations sources declarations
                    simp only [exceptT_bind_ok_iff] at executed
                    obtain ⟨prepared, _, executed⟩ := executed
                    cases prepared <;> simp only [exceptT_bind_ok_iff] at executed
                    all_goals
                      obtain ⟨observation, _, checkedResult, _, executed⟩ := executed
                      cases checkedResult with
                      | ok checked =>
                        cases executed
                        refine ⟨_, rfl, ?_, ?_⟩
                        · simpa only [map_objects_update] using valid
                        · intro seed
                          apply declarationRequires_update
                          rcases seed with prior | rfl
                          · exact Or.inl prior
                          · exact Or.inr ⟨valid, by simp [object, Array.map_map, Function.comp_def, contextAgrees]⟩
                      | error diagnostic =>
                        simp only [exceptT_bind_ok_iff] at executed
                        obtain ⟨next, unavailable, finished⟩ := executed
                        cases finished
                        refine ⟨_, rfl, ?_, ?_⟩
                        · simpa only [map_objects_update] using valid
                        · intro seed
                          apply declarationRequires_update
                          rcases seed with prior | rfl
                          · exact Or.inl prior
                          · exact Or.inr ⟨valid, by simp [object, Array.map_map, Function.comp_def, contextAgrees]⟩
                  · have sourceDecls := congrArg (fun fields => fields.2.2) sourceFields
                    dsimp only at sourceDecls
                    rw [sourceDecls, Array.map_map]
                    exact Array.mem_map.mpr ⟨planned.name, sourceMember, by simp [object, contextAgrees]⟩
                obtain ⟨declaration, declarationMember, same, requiredMember⟩ := hasRequired
                refine ⟨_, Array.mem_push_self, ?_, declaration, declarationMember, same, requiredMember⟩
                exact (congrArg (fun fields => fields.2.1) declarationFields).trans
                  (congrArg (fun fields => fields.2.1) sourceFields)
            · intro sourcesInvalid
              rw [ite_eq_right sourcesInvalid] at executed
              simp only [exceptT_bind_ok_iff] at executed
              obtain ⟨_, impossible, _⟩ := executed
              cases impossible
          · intro contextInvalid
            rw [ite_eq_right contextInvalid] at executed
            simp only [exceptT_bind_ok_iff] at executed
            obtain ⟨_, impossible, _⟩ := executed
            cases impossible
        · rcases seed with prior | rfl
          · exact Or.inl prior
          · exact Or.inr ⟨step, stepMember, rfl⟩
      split at finished
      · cases finished; exact ⟨next, rfl, trivial, advance⟩
      · simp only [exceptT_bind_ok_iff] at finished
        obtain ⟨_, impossible, _⟩ := finished
        cases impossible

private theorem declarationRequires_enrich (input : Input) (target : RealizationKey)
    (extra : RequirementKey) (prior : input.DeclarationRequires key object required) :
    ({ input with realizations := input.realizations.map fun (record : Contribution Realization) =>
      if record.value.key != target then record else { record with value := { record.value with
        declarations := record.value.declarations.map fun declaration =>
          { declaration with required := canonical (declaration.required.push extra) } } } } : Input).DeclarationRequires
      key object required := by
  obtain ⟨record, member, same, declaration, declarationMember, objectEq, selected⟩ := prior
  refine ⟨_, Array.mem_map.mpr ⟨record, member, rfl⟩, ?_⟩
  split
  · exact ⟨same, declaration, declarationMember, objectEq, selected⟩
  · refine ⟨same, _, Array.mem_map.mpr ⟨declaration, declarationMember, rfl⟩, objectEq, ?_⟩
    simpa only [mem_canonical] using Array.mem_push_of_mem extra selected

/-- Authored goals extend declaration selections. They cannot remove an existing
required key, change its declaration object, or move it to another realization. -/
theorem collectAuthored_declarationRequired (providers : Providers Id) (p : Plan)
    (accepted : (collectAuthored providers p initial).run = .ok collected)
    (prior : (Collected.input initial).DeclarationRequires key object required) :
    (Collected.input collected).DeclarationRequires key object required := by
  simp only [collectAuthored, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  refine array_loop_invariant p.authored
    (fun current => (Collected.input current).DeclarationRequires key object required) _ prior ?_ loop
  intro authored member current result prior executed
  simp only [exceptT_bind_ok_iff] at executed
  obtain ⟨goals, goalLoop, sourced, sourceLoop, finished⟩ := executed
  have goalsSelected : (Collected.input goals).DeclarationRequires key object required := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at goalLoop
    refine list_loop_invariant _
      (fun current => (Collected.input current).DeclarationRequires key object required) _ prior ?_ goalLoop
    intro index member current result prior executed
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
        exact declarationRequires_enrich _ _ _ prior
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
  have sourcesSelected : (Collected.input sourced).DeclarationRequires key object required := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at sourceLoop
    refine list_loop_invariant _
      (fun current => (Collected.input current).DeclarationRequires key object required) _ goalsSelected ?_ sourceLoop
    intro index member current result prior executed
    simp only [exceptT_bind_ok_iff] at executed
    obtain ⟨_, _, executed⟩ := executed
    cases executed
    exact prior
  cases finished
  obtain ⟨record, member, same, declaration, declarationMember, objectEq, selected⟩ := sourcesSelected
  exact ⟨record, Array.mem_append_left _ member, same, declaration, declarationMember, objectEq, selected⟩

/-- The complete collection recipe preserves the native proof selection through
all authored enrichment. No provider success assumption is added. -/
theorem assemble_declarationRequired (providers : Providers Id) (p : Plan)
    (accepted : (assemble providers p).run = .ok collected)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedMember : planned ∈ step.declarations)
    (sourceMember : planned.name ∈ nativeNames step.associations (step.sources.map (·.source)))
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    (Collected.input collected).DeclarationRequires step.key ⟨context, planned.name.toString⟩
      ⟨.declaration step.key ⟨context, planned.name.toString⟩, `proof⟩ := by
  simp only [assemble] at accepted
  split at accepted
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨ordinary, ordinaryOk, authoredOk⟩ := accepted
    exact collectAuthored_declarationRequired providers p authoredOk
      (collectOrdinary_declarationRequired providers p ordinaryOk nodeMember stepMember plannedMember sourceMember contextAgrees)
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨_, impossible, _⟩ := accepted
    cases impossible

/-- The final registry retains the actual declaration carrying its native proof
key. This is stronger than existence of a requirement with that key. -/
theorem evaluate_declarationRequired {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedMember : planned ∈ step.declarations)
    (sourceMember : planned.name ∈ nativeNames step.associations (step.sources.map (·.source)))
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    snapshot.registry.contributions.DeclarationRequires step.key ⟨context, planned.name.toString⟩
      ⟨.declaration step.key ⟨context, planned.name.toString⟩, `proof⟩ := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, collected, assembled, finished⟩ := accepted
  have selected := assemble_declarationRequired _ _ assembled nodeMember stepMember plannedMember sourceMember contextAgrees
  simpa only [Input.DeclarationRequires, (finish_preserves_selection finished).2.1] using selected

/-- Native declaration obligations enter the public realization query, through
admission's derived index, not an assumed or separately reconstructed cache. -/
theorem evaluate_native_proof_selected {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedMember : planned ∈ step.declarations)
    (sourceMember : planned.name ∈ nativeNames step.associations (step.sources.map (·.source)))
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    ⟨.declaration step.key ⟨context, planned.name.toString⟩, `proof⟩ ∈
      snapshot.registry.requiredFor (.realization step.key) := by
  obtain ⟨record, member, keyEq, declaration, declarationMember, objectEq, selected⟩ :=
    evaluate_declarationRequired accepted nodeMember stepMember plannedMember sourceMember contextAgrees
  have admitted := evaluate_admitted accepted
  have lookup := (admit_realization_lookup_iff admitted).mpr ⟨record, member, rfl, keyEq⟩
  rw [admit_requiredFor_realization admitted lookup]
  simp only [Realization.requirements, List.mem_toArray, List.mem_eraseDups,
    Array.mem_toList_iff, Array.mem_append]
  exact Or.inr (Array.mem_flatMap.mpr ⟨declaration, declarationMember, selected⟩)

/-- Every raw source declaration is selected by the public realization assessment.
All planner and final model witnesses are derived from production execution. -/
theorem evaluate_raw_native_proof_selected
    {raw : Raw} {observations : Observations (plan raw)} {snapshot : Snapshot}
    (evaluated : evaluate (plan raw) observations = .ok snapshot)
    (rawMember : (label, accepted) ∈ raw.nodes)
    (keyMember : key ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization)))
    (sourceDeclaration : declarationName ∈ nativeNames
      (accepted.nativeAssociations.filter (·.realization == key))
      (accepted.sources.filter (·.destination.realization == key)))
    (contextAgrees : canonical ((accepted.sources.filter (·.destination.realization == key)).map (·.context) ++
      (accepted.nativeAssociations.filter (·.realization == key)).map (·.context)) = #[context]) :
    ⟨.declaration key ⟨context, declarationName.toString⟩, `proof⟩ ∈
      snapshot.registry.requiredFor (.realization key) := by
  obtain ⟨node, nodeMember, _, _, step, stepMember, stepKey, sources, associations⟩ :=
    plan_raw_realization raw rawMember keyMember
  have sourceMember : declarationName ∈ nativeNames step.associations (step.sources.map (·.source)) := by
    rwa [sources, associations]
  obtain ⟨planned, plannedMember, plannedName⟩ :=
    (plan_declaration_mem_iff raw nodeMember stepMember declarationName).mpr sourceMember
  have sameContext : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context] := by
    have mapped := congrArg (Array.map (·.context)) sources
    simpa only [Array.map_map, Function.comp_def, associations, ← mapped] using contextAgrees
  simpa only [stepKey, plannedName] using evaluate_native_proof_selected evaluated nodeMember stepMember
    plannedMember (by rwa [plannedName]) sameContext

/-- Main source-facing assessment guarantee: completion covers every declaration
in the accepted native source union, with well-founded justification and original
fitting evidence for it and every transitive prerequisite. No selected-key or
intermediate membership premise is required. Provider authenticity is separate. -/
theorem evaluate_raw_assessment_declaration_justified
    {raw : Raw} {observations : Observations (plan raw)} {snapshot : Snapshot}
    (evaluated : evaluate (plan raw) observations = .ok snapshot)
    (rawMember : (label, accepted) ∈ raw.nodes)
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
      Acc snapshot.registry.Prerequisite key ∧
      ∀ dependency, dependency = key ∨ Relation.TransGen snapshot.registry.Prerequisite dependency key →
        ∃ requirement ∈ snapshot.registry.contributions.requirements,
          ∃ evidence ∈ snapshot.registry.contributions.evidence,
            snapshot.registry.requirement? dependency = some requirement.value ∧
            requirement.value.key = dependency ∧
            evidence.value.Fits requirement.value ((snapshot.registry.bindingFor dependency).getD "") := by
  have selected := evaluate_raw_native_proof_selected evaluated rawMember keyMember sourceDeclaration contextAgrees
  exact ⟨(snapshot.registry.complete_requires_all _ (snapshot.assessment_complete_result complete)).2 _ selected,
    (evaluate_assessment_justified evaluated complete).2 _ selected⟩

end Informal.Realizations.Capture
