/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.RequiredLaws

/-! Native facet selections survive the production capture recipe. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

run_cmd do
  let env ← getEnv
  let owners ← #[``evaluate, ``evaluate_admitted, ``finish_uses, ``collectOrdinary_declarationRequired].mapM fun name => do
    let some owner := env.getModuleIdxFor? name | throwError "Capture helpers must be imported"
    pure owner
  for (name, _) in env.constants.toList do
    if (env.getModuleIdxFor? name).any owners.contains then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

private theorem names_loop_mem (entries : List Name) (seen : Std.HashSet Name) (names : Array Name)
    (consistent : ∀ name, name ∈ seen ↔ name ∈ names) :
    ∀ name, name ∈ (forIn (m := Id) entries (seen, names) fun name pair =>
      if pair.1.contains name then pure (.yield pair) else pure (.yield (pair.1.insert name, pair.2.push name))).2 ↔
      name ∈ names ∨ name ∈ entries := by
  induction entries generalizing seen names with
  | nil => simp [pure]
  | cons first rest ih =>
    simp only [pure] at ih
    simp only [List.forIn_cons, bind, pure]
    by_cases present : seen.contains first = true
    · simp only [ite_eq_left present]
      intro name
      rw [ih seen names consistent]
      have member := (consistent first).mp (Std.HashSet.contains_iff_mem.mp present)
      simp only [List.mem_cons]
      constructor
      · exact fun h => h.elim Or.inl (fun h => Or.inr (Or.inr h))
      · rintro (h | rfl | h)
        · exact Or.inl h
        · exact Or.inl member
        · exact Or.inr h
    · simp only [ite_eq_right present]
      have next : ∀ name, name ∈ seen.insert first ↔ name ∈ names.push first := by
        intro name
        simp only [Std.HashSet.mem_insert, beq_iff_eq, consistent, Array.mem_push]
        exact or_comm.trans (or_congr Iff.rfl eq_comm)
      intro name
      rw [ih (seen.insert first) (names.push first) next]
      simp [Array.mem_push, or_assoc]

/-- The actual native union deduplicates names without losing or inventing source
membership. Typed names are retained; no parsing or scope-erasure claim is made. -/
theorem nativeNames_mem_iff (associations : Array NativeAssociation) (sources : Array FacetSource) (name : Name) :
    name ∈ nativeNames associations sources ↔
      name ∈ associations.map (·.reference.canonical) ++ sources.flatMap (fun source =>
        match source.payload with
        | .leanInline code => code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)
        | _ => #[]) := by
  unfold nativeNames
  simp only [Id.run, bind, pure]
  rw [← Array.forIn_toList]
  generalize allEq : (associations.map (·.reference.canonical) ++ sources.flatMap (fun source =>
    match source.payload with
    | .leanInline code => code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)
    | _ => #[])) = all
  simpa only [pure, Array.not_mem_empty, false_or, Array.mem_toList_iff] using
    names_loop_mem all.toList {} #[] (by simp) name

/-- Filtering to a facet cannot introduce a declaration absent from the full
realization. This relates source enumeration, not rendered code panels. -/
theorem nativeNames_filter_subset (associations : Array NativeAssociation) (sources : Array FacetSource)
    (associationFilter : NativeAssociation → Bool) (sourceFilter : FacetSource → Bool)
    (member : name ∈ nativeNames (associations.filter associationFilter) (sources.filter sourceFilter)) :
    name ∈ nativeNames associations sources := by
  rw [nativeNames_mem_iff] at member ⊢
  simp only [Array.mem_append, Array.mem_map, Array.mem_flatMap] at member ⊢
  rcases member with ⟨association, member, same⟩ | ⟨source, member, inner⟩
  · exact Or.inl ⟨association, (Array.mem_filter.mp member).1, same⟩
  · exact Or.inr ⟨source, (Array.mem_filter.mp member).1, inner⟩

private theorem find_facet_map (facets : Array Facet) (transform : Facet → Facet)
    (names : ∀ facet, (transform facet).name = facet.name) :
    (facets.map transform).find? (·.name == name) = (facets.find? (·.name == name)).map transform := by
  rw [Array.find?_map]
  congr 2
  funext facet
  simp [names]

private def FacetContains (facets : Array Facet) (name : Name) (object : ObjectKey) : Prop :=
  ∃ facet, facets.find? (·.name == name) = some facet ∧ object ∈ facet.declarations

private def FacetRequires (facets : Array Facet) (name : Name) (required : RequirementKey) : Prop :=
  ∃ facet, facets.find? (·.name == name) = some facet ∧ required ∈ facet.required

/-- The actual facet lookup and one selected key remain paired with their
realization. This law-only predicate adds no persistent data. -/
def _root_.Informal.Translations.Input.FacetRequires (input : Input)
    (key : RealizationKey) (name : Name) (required : RequirementKey) : Prop :=
  ∃ record ∈ input.realizations, record.value.key = key ∧
    ∃ facet, record.value.facets.find? (·.name == name) = some facet ∧ required ∈ facet.required

private theorem facetContains_map (facets : Array Facet) (transform : Facet → Facet)
    (names : ∀ facet, (transform facet).name = facet.name)
    (declarations : ∀ facet, (transform facet).declarations = facet.declarations)
    (prior : FacetContains facets name object) : FacetContains (facets.map transform) name object := by
  obtain ⟨facet, found, member⟩ := prior
  exact ⟨transform facet, by rw [find_facet_map facets transform names, found]; rfl, by rwa [declarations]⟩

private theorem facetContains_of_members (facets : Array Facet)
    (existsFacet : ∃ facet ∈ facets, facet.name = name)
    (contains : ∀ facet ∈ facets, facet.name = name → object ∈ facet.declarations) :
    FacetContains facets name object := by
  cases found : facets.find? (·.name == name) with
  | none =>
    obtain ⟨facet, member, same⟩ := existsFacet
    have impossible := Array.find?_eq_none.mp found facet member
    simp [same] at impossible
  | some facet =>
    exact ⟨facet, found, contains facet (Array.mem_of_find?_eq_some found)
      (by simpa using (Array.find?_eq_some_iff_getElem.mp found).1)⟩

private theorem facetRequires_update (facets : Array Facet) (key : RealizationKey) (witness : ObjectKey)
    (seed : FacetRequires facets name required ∨
      (FacetContains facets name witness ∧ required = ⟨.declaration key witness, if name == `statement then `statement else `proof⟩)) :
    FacetRequires (facets.map fun facet =>
      if !facet.declarations.contains witness then facet else
        { facet with required := facet.required.push (if facet.name == `statement then ⟨.declaration key witness, `statement⟩ else ⟨.declaration key witness, `proof⟩) })
      name required := by
  have names (facet : Facet) :
      (if !facet.declarations.contains witness then facet else
        { facet with required := facet.required.push (if facet.name == `statement then ⟨.declaration key witness, `statement⟩ else ⟨.declaration key witness, `proof⟩) }).name = facet.name := by
    split <;> rfl
  rcases seed with ⟨facet, found, selected⟩ | ⟨⟨facet, found, member⟩, rfl⟩
  · unfold FacetRequires
    rw [find_facet_map _ _ names, found]
    refine ⟨_, rfl, ?_⟩
    dsimp only
    split
    · exact selected
    · exact Array.mem_push_of_mem _ selected
  · have same : facet.name = name := by simpa using (Array.find?_eq_some_iff_getElem.mp found).1
    unfold FacetRequires
    rw [find_facet_map _ _ names, found]
    refine ⟨_, rfl, ?_⟩
    simp only [Array.contains_iff_mem.mpr member, Bool.not_true, Bool.false_eq_true, ↓reduceIte, same]
    split <;> exact Array.mem_push_self

/-- Each facet selects its declaration contracts: statement keys for the statement
facet, proof keys for every other name. Provider failure cannot erase selection. -/
theorem collectOrdinary_facetRequired (providers : Providers Id) (p : Plan)
    (accepted : (collectOrdinary providers p).run = .ok collected)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedMember : planned ∈ step.declarations)
    (facetMember : name ∈ canonical (step.sources.map (·.source.destination.facet) ++ step.associations.flatMap (·.facets)))
    (sourceMember : planned.name ∈ nativeNames (step.associations.filter (·.facets.contains name))
      ((step.sources.map (·.source)).filter (·.destination.facet == name)))
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    (Collected.input collected).FacetRequires step.key name
      ⟨.declaration step.key ⟨context, planned.name.toString⟩, if name == `statement then `statement else `proof⟩ := by
  let object : ObjectKey := ⟨context, planned.name.toString⟩
  let required : RequirementKey := ⟨.declaration step.key object, if name == `statement then `statement else `proof⟩
  let selected := fun c => (Collected.input c).FacetRequires step.key name required
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
              have sourceFields : ((Collected.input sourced.1).realizations, sourced.2.key) =
                  ((Collected.input current).realizations, realization.key) := by
                refine array_loop_invariant realization.sources
                  (fun pair => ((Collected.input pair.1).realizations, pair.2.key) = _) _ rfl ?_ sources
                intro source member pair result prior executed
                clear loop realizations sources declarations finished
                repeat' first
                  | (cases executed; exact prior)
                  | (simp only [exceptT_bind_ok_iff] at executed; obtain ⟨value, returned, executed⟩ := executed)
                  | split at executed
              have declarationFields : ((Collected.input declared.1).realizations, declared.2.key) =
                  ((Collected.input sourced.1).realizations, sourced.2.key) := by
                refine array_loop_invariant realization.declarations
                  (fun pair => ((Collected.input pair.1).realizations, pair.2.key) = _) _ rfl ?_ declarations
                intro declaration member pair result prior executed
                clear loop realizations sources declarations finished
                simp only [exceptT_bind_ok_iff] at executed
                obtain ⟨prepared, _, executed⟩ := executed
                cases prepared <;> simp only [exceptT_bind_ok_iff] at executed
                all_goals
                  obtain ⟨observation, _, checkedResult, _, executed⟩ := executed
                  cases checkedResult with
                  | ok checked => cases executed; exact prior
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
                    simpa only [unchanged] using prior
              cases finished
              refine ⟨_, rfl, trivial, ?_⟩
              intro seed
              rcases seed with prior | sameStep
              · obtain ⟨record, member, key, facet, found, requiredMember⟩ := prior
                refine ⟨record, Array.mem_push_of_mem _ ?_, key, facet, found, requiredMember⟩
                have arrays : (Collected.input declared.1).realizations = (Collected.input sourced.1).realizations := congrArg Prod.fst declarationFields
                have sourceArrays : (Collected.input sourced.1).realizations = (Collected.input current).realizations := congrArg Prod.fst sourceFields
                rwa [arrays, sourceArrays]
              · subst realization
                have sourceContains : FacetContains sourced.2.facets name object := by
                  refine array_loop_invariant step.sources (fun pair => FacetContains pair.2.facets name object) _ ?_ ?_ sources
                  · apply facetContains_of_members
                    · refine ⟨_, Array.mem_map.mpr ⟨name, ?_, rfl⟩, rfl⟩
                      rw [mem_canonical] at facetMember ⊢
                      simpa only [Array.map_map, Function.comp_def] using Array.mem_append_left _ facetMember
                    · intro facet member same
                      obtain ⟨facetName, _, rfl⟩ := Array.mem_map.mp member
                      dsimp only at same
                      subst facetName
                      rw [mem_canonical]
                      exact Array.mem_map.mpr ⟨planned.name, sourceMember, by
                        simp [object, Array.map_map, Function.comp_def, contextAgrees]⟩
                  · intro source member pair result prior executed
                    clear loop realizations sources declarations
                    repeat' first
                      | (cases executed; first
                          | exact prior
                          | exact facetContains_map _ _ (fun facet => by split <;> rfl)
                              (fun facet => by split <;> rfl) prior)
                      | (simp only [exceptT_bind_ok_iff] at executed; obtain ⟨value, returned, executed⟩ := executed)
                      | split at executed
                have hasRequired : FacetRequires declared.2.facets name required := by
                  refine (array_loop_hits step.declarations
                    (fun pair => FacetContains pair.2.facets name object)
                    (fun pair => FacetRequires pair.2.facets name required)
                    (· = planned) _ ?_ sourceContains (Or.inr ⟨planned, plannedMember, rfl⟩) declarations).2
                  intro declaration member pair result valid executed
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
                      · exact facetContains_map _ _ (fun facet => by split <;> rfl)
                          (fun facet => by split <;> rfl) valid
                      · intro seed
                        apply facetRequires_update
                        rcases seed with prior | rfl
                        · exact Or.inl prior
                        · apply Or.inr
                          simpa [object, required, Array.map_map, Function.comp_def, contextAgrees] using valid
                    | error diagnostic =>
                      simp only [exceptT_bind_ok_iff] at executed
                      obtain ⟨next, unavailable, finished⟩ := executed
                      cases finished
                      refine ⟨_, rfl, ?_, ?_⟩
                      · exact facetContains_map _ _ (fun facet => by split <;> rfl)
                          (fun facet => by split <;> rfl) valid
                      · intro seed
                        apply facetRequires_update
                        rcases seed with prior | rfl
                        · exact Or.inl prior
                        · apply Or.inr
                          simpa [object, required, Array.map_map, Function.comp_def, contextAgrees] using valid
                obtain ⟨facet, found, requiredMember⟩ := hasRequired
                refine ⟨_, Array.mem_push_self, ?_, facet, found, requiredMember⟩
                exact (congrArg Prod.snd declarationFields).trans (congrArg Prod.snd sourceFields)
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


/-- Authored enrichment retains the facet lookup and its selected keys. -/
theorem collectAuthored_facetRequired (providers : Providers Id) (p : Plan)
    (accepted : (collectAuthored providers p initial).run = .ok collected)
    (prior : (Collected.input initial).FacetRequires key name required) :
    (Collected.input collected).FacetRequires key name required := by
  simp only [collectAuthored, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  refine array_loop_invariant p.authored
    (fun current => (Collected.input current).FacetRequires key name required) _ prior ?_ loop
  intro authored member current result prior executed
  simp only [exceptT_bind_ok_iff] at executed
  obtain ⟨goals, goalLoop, sourced, sourceLoop, finished⟩ := executed
  have goalsSelected : (Collected.input goals).FacetRequires key name required := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at goalLoop
    refine list_loop_invariant _
      (fun current => (Collected.input current).FacetRequires key name required) _ prior ?_ goalLoop
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
        obtain ⟨record, member, same, facet, found, requiredMember⟩ := prior
        refine ⟨_, Array.mem_map.mpr ⟨record, member, rfl⟩, ?_⟩
        split <;> exact ⟨same, facet, found, requiredMember⟩
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
  have sourcesSelected : (Collected.input sourced).FacetRequires key name required := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at sourceLoop
    refine list_loop_invariant _
      (fun current => (Collected.input current).FacetRequires key name required) _ goalsSelected ?_ sourceLoop
    intro index member current result prior executed
    simp only [exceptT_bind_ok_iff] at executed
    obtain ⟨_, _, executed⟩ := executed
    cases executed
    exact prior
  cases finished
  obtain ⟨record, member, same, facet, found, selected⟩ := sourcesSelected
  exact ⟨record, Array.mem_append_left _ member, same, facet, found, selected⟩

/-- The complete collection recipe preserves the facet selection through
all authored enrichment. No provider success assumption is added. -/
theorem assemble_facetRequired (providers : Providers Id) (p : Plan)
    (accepted : (assemble providers p).run = .ok collected)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedMember : planned ∈ step.declarations)
    (facetMember : name ∈ canonical (step.sources.map (·.source.destination.facet) ++ step.associations.flatMap (·.facets)))
    (sourceMember : planned.name ∈ nativeNames (step.associations.filter (·.facets.contains name))
      ((step.sources.map (·.source)).filter (·.destination.facet == name)))
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    (Collected.input collected).FacetRequires step.key name
      ⟨.declaration step.key ⟨context, planned.name.toString⟩, if name == `statement then `statement else `proof⟩ := by
  simp only [assemble] at accepted
  split at accepted
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨ordinary, ordinaryOk, authoredOk⟩ := accepted
    exact collectAuthored_facetRequired providers p authoredOk
      (collectOrdinary_facetRequired providers p ordinaryOk nodeMember stepMember plannedMember facetMember sourceMember contextAgrees)
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨_, impossible, _⟩ := accepted
    cases impossible

/-- The final registry retains the actual facet carrying its selected declaration
key. This is stronger than existence of a requirement with that key. -/
theorem evaluate_facetRequired {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedMember : planned ∈ step.declarations)
    (facetMember : name ∈ canonical (step.sources.map (·.source.destination.facet) ++ step.associations.flatMap (·.facets)))
    (sourceMember : planned.name ∈ nativeNames (step.associations.filter (·.facets.contains name))
      ((step.sources.map (·.source)).filter (·.destination.facet == name)))
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    snapshot.registry.contributions.FacetRequires step.key name
      ⟨.declaration step.key ⟨context, planned.name.toString⟩, if name == `statement then `statement else `proof⟩ := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, collected, assembled, finished⟩ := accepted
  have selected := assemble_facetRequired _ _ assembled nodeMember stepMember plannedMember facetMember sourceMember contextAgrees
  simpa only [Input.FacetRequires, (finish_preserves_selection finished).2.1] using selected

/-- The native key reaches both public queries: the selected facet and its whole
realization. Admission supplies the derived-index agreement. -/
theorem evaluate_native_facet_selected {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (nodeMember : node ∈ p.ordinary) (stepMember : step ∈ node.realizations)
    (plannedMember : planned ∈ step.declarations)
    (facetMember : name ∈ canonical (step.sources.map (·.source.destination.facet) ++ step.associations.flatMap (·.facets)))
    (sourceMember : planned.name ∈ nativeNames (step.associations.filter (·.facets.contains name))
      ((step.sources.map (·.source)).filter (·.destination.facet == name)))
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    let required : RequirementKey := ⟨.declaration step.key ⟨context, planned.name.toString⟩,
      if name == `statement then `statement else `proof⟩
    required ∈ snapshot.registry.requiredFor (.facet step.key name) ∧
      required ∈ snapshot.registry.requiredFor (.realization step.key) := by
  obtain ⟨record, member, keyEq, facet, found, selected⟩ :=
    evaluate_facetRequired accepted nodeMember stepMember plannedMember facetMember sourceMember contextAgrees
  have admitted := evaluate_admitted accepted
  have lookup := (admit_realization_lookup_iff admitted).mpr ⟨record, member, rfl, keyEq⟩
  refine ⟨(admit_requiredFor_facet_mem_iff admitted lookup found).mpr selected, ?_⟩
  rw [admit_requiredFor_realization admitted lookup]
  simp only [Realization.requirements, List.mem_toArray, List.mem_eraseDups,
    Array.mem_toList_iff, Array.mem_append]
  exact Or.inl (Or.inr (Array.mem_flatMap.mpr ⟨facet, Array.mem_of_find?_eq_some found, selected⟩))

private theorem nativeNames_facet_mem (associations : Array NativeAssociation) (sources : Array FacetSource)
    (member : declaration ∈ nativeNames (associations.filter (·.facets.contains name))
      (sources.filter (·.destination.facet == name))) :
    name ∈ canonical (sources.map (·.destination.facet) ++ associations.flatMap (·.facets)) := by
  rw [nativeNames_mem_iff] at member
  rw [mem_canonical]
  rcases Array.mem_append.mp member with external | inline
  · obtain ⟨association, member, _⟩ := Array.mem_map.mp external
    obtain ⟨member, selected⟩ := Array.mem_filter.mp member
    exact Array.mem_append_right _ (Array.mem_flatMap.mpr
      ⟨association, member, Array.contains_iff_mem.mp selected⟩)
  · obtain ⟨source, member, _⟩ := Array.mem_flatMap.mp inline
    obtain ⟨member, selected⟩ := Array.mem_filter.mp member
    exact Array.mem_append_left _ (Array.mem_map.mpr ⟨source, member, by simpa using selected⟩)

/-- A raw facet's source declaration reaches the correct public selection.
Facet existence and planner membership follow from the source union, rather than
being assumed as final model or query witnesses. -/
theorem evaluate_raw_native_facet_selected
    {raw : Raw} {observations : Observations (plan raw)} {snapshot : Snapshot}
    (evaluated : evaluate (plan raw) observations = .ok snapshot)
    (rawMember : (label, accepted) ∈ raw.nodes)
    (keyMember : key ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization)))
    (sourceDeclaration : declarationName ∈ nativeNames
      ((accepted.nativeAssociations.filter (·.realization == key)).filter (·.facets.contains name))
      ((accepted.sources.filter (·.destination.realization == key)).filter (·.destination.facet == name)))
    (contextAgrees : canonical ((accepted.sources.filter (·.destination.realization == key)).map (·.context) ++
      (accepted.nativeAssociations.filter (·.realization == key)).map (·.context)) = #[context]) :
    let required : RequirementKey := ⟨.declaration key ⟨context, declarationName.toString⟩,
      if name == `statement then `statement else `proof⟩
    required ∈ snapshot.registry.requiredFor (.facet key name) ∧
      required ∈ snapshot.registry.requiredFor (.realization key) := by
  obtain ⟨node, nodeMember, _, _, step, stepMember, stepKey, sources, associations⟩ :=
    plan_raw_realization raw rawMember keyMember
  have sourceMember : declarationName ∈ nativeNames (step.associations.filter (·.facets.contains name))
      ((step.sources.map (·.source)).filter (·.destination.facet == name)) := by
    rwa [sources, associations]
  have facetMember := nativeNames_facet_mem _ _ sourceMember
  have fullMember := nativeNames_filter_subset _ _ _ _ sourceMember
  obtain ⟨planned, plannedMember, plannedName⟩ :=
    (plan_declaration_mem_iff raw nodeMember stepMember declarationName).mpr fullMember
  have sameContext : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context] := by
    have mapped := congrArg (Array.map (·.context)) sources
    simpa only [Array.map_map, Function.comp_def, associations, ← mapped] using contextAgrees
  have facetMember' : name ∈ canonical (step.sources.map (·.source.destination.facet) ++ step.associations.flatMap (·.facets)) := by
    simpa only [Array.map_map, Function.comp_def] using facetMember
  simpa only [stepKey, plannedName] using evaluate_native_facet_selected evaluated nodeMember stepMember
    plannedMember facetMember' (by rwa [plannedName]) sameContext

/-- Completion of a public facet justifies every declaration selected by its raw
sources: the appropriate native contract is complete and has fitting original
evidence throughout a well-founded prerequisite chain. -/
theorem evaluate_raw_facet_declaration_justified
    {raw : Raw} {observations : Observations (plan raw)} {snapshot : Snapshot}
    (evaluated : evaluate (plan raw) observations = .ok snapshot)
    (rawMember : (label, accepted) ∈ raw.nodes)
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
      Acc snapshot.registry.Prerequisite required ∧
      ∀ dependency, dependency = required ∨ Relation.TransGen snapshot.registry.Prerequisite dependency required →
        ∃ requirement ∈ snapshot.registry.contributions.requirements,
          ∃ evidence ∈ snapshot.registry.contributions.evidence,
            snapshot.registry.requirement? dependency = some requirement.value ∧
            requirement.value.key = dependency ∧
            evidence.value.Fits requirement.value ((snapshot.registry.bindingFor dependency).getD "") := by
  have selected := (evaluate_raw_native_facet_selected evaluated rawMember keyMember sourceDeclaration contextAgrees).1
  have completed := (snapshot.registry.complete_requires_all _ complete).2 _ selected
  have admitted := evaluate_admitted evaluated
  refine ⟨completed, admit_complete_accessible admitted completed, ?_⟩
  intro dependency reachable
  rcases reachable with rfl | path
  · exact admit_complete_requirement_evidence admitted completed
  · exact admit_complete_prerequisites_evidence admitted completed path

end Informal.Realizations.Capture
