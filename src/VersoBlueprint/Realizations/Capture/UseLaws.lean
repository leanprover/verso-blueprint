/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.DependencyLaws

/-! Coverage of collected uses by the actual scope, reference and context loops.
Target labels survive reference merging; duplicate metadata need not stay identical. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

-- Proof-local access to the original implementation and shared law helpers.
-- No aliases or visibility changes are exported to production consumers.
run_cmd do
  let env ← getEnv
  let some captureOwner := env.getModuleIdxFor? ``evaluate
    | throwError "Capture implementation must be imported"
  let some lawsOwner := env.getModuleIdxFor? ``evaluate_admitted
    | throwError "Capture law helpers must be imported"
  let some recipeOwner := env.getModuleIdxFor? ``finish_uses
    | throwError "Capture recipe helpers must be imported"
  let some creationOwner := env.getModuleIdxFor? ``finish_native_dependency_gate_created
    | throwError "Capture creation helpers must be imported"
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some captureOwner || env.getModuleIdxFor? name == some lawsOwner ||
        env.getModuleIdxFor? name == some recipeOwner || env.getModuleIdxFor? name == some creationOwner then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

private theorem mergeSameLabel_label (current incoming : Data.UseRef)
    (same : current.label = incoming.label) :
    (current.mergeSameLabel incoming).label = current.label := by
  unfold Data.UseRef.mergeSameLabel
  split <;> simp_all

private theorem pushMergeByLabel_labels (current : Array Data.UseRef) (incoming : Data.UseRef)
    (label : Data.Label) :
    label ∈ Data.UseRef.labels (Data.UseRef.pushMergeByLabel current incoming) ↔
      label ∈ Data.UseRef.labels current ∨ label = incoming.label := by
  unfold Data.UseRef.pushMergeByLabel
  split
  · rename_i present
    have mapped : Data.UseRef.labels (current.map fun ref => if ref.label == incoming.label then
        ref.mergeSameLabel incoming else ref) = Data.UseRef.labels current := by
      unfold Data.UseRef.labels
      rw [Array.map_map]
      apply congrArg (fun f => current.map f)
      funext ref
      simp only [Function.comp_apply]
      split
      · rename_i same
        exact mergeSameLabel_label ref incoming (beq_iff_eq.mp same)
      · rfl
    rw [mapped]
    have member : incoming.label ∈ Data.UseRef.labels current := by
      obtain ⟨ref, member, same⟩ := Array.any_eq_true'.mp present
      exact Array.mem_map.mpr ⟨ref, member, beq_iff_eq.mp same⟩
    constructor
    · exact Or.inl
    · rintro (prior | rfl)
      · exact prior
      · exact member
  · simp [Data.UseRef.labels, Array.mem_push]

/-- Reference merging preserves exactly the union of target labels, even when
manual metadata replaces automatic metadata. It does not preserve every payload. -/
theorem useRef_mergeByLabel_labels (current incoming : Array Data.UseRef) (label : Data.Label) :
    label ∈ Data.UseRef.labels (Data.UseRef.mergeByLabel current incoming) ↔
      label ∈ Data.UseRef.labels current ∨ label ∈ Data.UseRef.labels incoming := by
  unfold Data.UseRef.mergeByLabel
  rw [← Array.foldl_toList]
  suffices loop : ∀ entries : List Data.UseRef, ∀ initial,
      label ∈ Data.UseRef.labels (entries.foldl Data.UseRef.pushMergeByLabel initial) ↔
        label ∈ Data.UseRef.labels initial ∨ ∃ ref ∈ entries, ref.label = label by
    simpa [Data.UseRef.labels, Array.mem_map] using loop incoming.toList current
  intro entries
  induction entries with
  | nil => intro initial; simp
  | cons ref rest ih =>
    intro initial
    simp only [List.foldl_cons, ih, pushMergeByLabel_labels, List.mem_cons]
    constructor
    · rintro ((prior | same) | ⟨item, member, same⟩)
      · exact Or.inl prior
      · exact Or.inr ⟨ref, Or.inl rfl, same.symm⟩
      · exact Or.inr ⟨item, Or.inr member, same⟩
    · rintro (prior | ⟨item, member, same⟩)
      · exact Or.inl (Or.inl prior)
      · rcases member with rfl | member
        · exact Or.inl (Or.inr same.symm)
        · exact Or.inr ⟨item, member, same⟩

private theorem mem_unique_fold [BEq α] [LawfulBEq α] (entries initial : Array α) (item : α) :
    item ∈ entries.foldl (fun current entry => if current.contains entry then current else current.push entry) initial ↔
      item ∈ initial ∨ item ∈ entries := by
  rw [← Array.foldl_toList]
  suffices loop : ∀ entries : List α, ∀ initial : Array α,
      item ∈ entries.foldl (fun current entry => if current.contains entry then current else current.push entry) initial ↔
        item ∈ initial ∨ item ∈ entries by
    simpa using loop entries.toList initial
  intro entries
  induction entries with
  | nil => intro initial; simp
  | cons entry entries ih =>
    intro initial
    simp only [List.foldl_cons, ih, List.mem_cons]
    by_cases present : initial.contains entry = true
    · rw [ite_eq_left present]
      have present := Array.contains_iff_mem.mp present
      constructor
      · rintro (prior | later)
        · exact Or.inl prior
        · exact Or.inr (Or.inr later)
      · rintro (prior | rfl | later)
        · exact Or.inl prior
        · exact Or.inl present
        · exact Or.inr later
    · rw [ite_eq_right present, Array.mem_push]
      exact or_assoc

namespace UseSelection

/-- Selection retains the authored source, explicit realization restriction,
facet and target label. Merged reference metadata is intentionally not equated. -/
def Matches (use : UseDeclaration) (edge : SelectedUse) : Prop :=
  edge.source = use.node ∧ edge.realization = use.realization ∧
    edge.facet = use.facet ∧ edge.reference.label = use.reference.label

/-- The selector projects each matching source model's project into a Lean
context. This states the actual policy, including non-native source models. -/
def ContextFor (input : Input) (use : UseDeclaration) (context : Context) : Prop :=
  ∃ model ∈ input.realizations, model.value.key.node = use.node ∧
    (∀ name, use.realization = some name → name = model.value.key.name) ∧
    context = { language := `lean, project := model.value.context.project }

end UseSelection

private theorem mem_selection_contexts (input : Input) (use : UseDeclaration) (context : Context) :
    context ∈ canonical ((input.realizations.filter fun record =>
      record.value.key.node == use.node && use.realization.all (· == record.value.key.name)).map
        fun record => ({ language := `lean, project := record.value.context.project } : Context)) ↔
    UseSelection.ContextFor input use context := by
  simp only [mem_canonical, Array.mem_map, Array.mem_filter, Bool.and_eq_true,
    beq_iff_eq, Option.all_eq_true]
  constructor
  · rintro ⟨model, ⟨member, node, restriction⟩, contextEq⟩
    exact ⟨model, member, node, restriction, contextEq.symm⟩
  · rintro ⟨model, member, node, restriction, contextEq⟩
    exact ⟨model, ⟨member, node, restriction⟩, contextEq.symm⟩

private theorem merged_scope_reference (uses : Array UseDeclaration) (use : UseDeclaration)
    (member : use ∈ uses) :
    ∃ reference ∈ Data.UseRef.mergeByLabel #[] ((uses.filter fun item =>
      item.node == use.node && item.realization == use.realization && item.facet == use.facet).map (·.reference)),
      reference.label = use.reference.label := by
  have labelMember := (useRef_mergeByLabel_labels #[]
    ((uses.filter fun item => item.node == use.node &&
      item.realization == use.realization && item.facet == use.facet).map (·.reference)) use.reference.label).mpr
    (Or.inr (Array.mem_map.mpr ⟨use.reference, Array.mem_map.mpr
      ⟨use, Array.mem_filter.mpr ⟨member, by simp⟩, rfl⟩, rfl⟩))
  exact Array.mem_map.mp labelMember

/-- The actual scope/reference/context loops reach each collected use. The
selected result is exact, including target failures and missing source contexts. -/
private theorem selectUses_covers (collected : Collected) (use : UseDeclaration)
    (member : use ∈ Collected.uses collected) (context : Option Context)
    (choice : match context with
      | some value => UseSelection.ContextFor (Collected.input collected) use value
      | none => ∀ value, ¬ UseSelection.ContextFor (Collected.input collected) use value) :
    ∃ edge ∈ selectUses collected, UseSelection.Matches use edge ∧ edge.context = context ∧
      edge.selected = match context with
        | some value => selectTarget (Collected.input collected) value use.reference.label
        | none => .error { code := "missing-source-context", subject := use.node.toString, message := "Dependency has no stored source project context" } := by
  let property (selected : Array SelectedUse) : Prop :=
    ∃ edge ∈ selected, UseSelection.Matches use edge ∧ edge.context = context ∧
      edge.selected = match context with
        | some value => selectTarget (Collected.input collected) value use.reference.label
        | none => .error { code := "missing-source-context", subject := use.node.toString, message := "Dependency has no stored source project context" }
  unfold selectUses
  simp only [Id.run, bind, pure]
  apply id_array_loop_hits _ property (fun scope => scope = (use.node, use.realization, use.facet))
  · intro scope scopeMember current
    rcases scope with ⟨source, realization, facet⟩
    refine ⟨_, rfl, ?_⟩
    intro prior
    apply id_array_loop_hits _ property (fun reference =>
      (source, realization, facet) = (use.node, use.realization, use.facet) ∧
        reference.label = use.reference.label)
    · intro reference referenceMember current
      apply Classical.byCases (p := _)
      · intro empty
        rw [ite_eq_left empty]
        refine ⟨_, rfl, ?_⟩
        rintro (prior | ⟨sameScope, sameLabel⟩)
        · obtain ⟨edge, member, rest⟩ := prior
          exact ⟨edge, Array.mem_push.mpr (Or.inl member), rest⟩
        · cases sameScope
          cases context with
          | none => exact ⟨_, Array.mem_push.mpr (Or.inr rfl), ⟨rfl, rfl, rfl, sameLabel⟩, rfl, rfl⟩
          | some value =>
            have present := (mem_selection_contexts _ _ _).mpr choice
            have absent := Array.isEmpty_iff.mp empty
            rw [absent] at present
            simp at present
      · intro nonempty
        rw [ite_eq_right nonempty]
        refine ⟨_, rfl, ?_⟩
        intro prior
        apply id_array_loop_hits _ property (fun value =>
          (source, realization, facet) = (use.node, use.realization, use.facet) ∧
            reference.label = use.reference.label ∧ context = some value)
        · intro value valueMember current
          refine ⟨_, rfl, ?_⟩
          rintro (prior | ⟨sameScope, sameLabel, rfl⟩)
          · obtain ⟨edge, member, rest⟩ := prior
            exact ⟨edge, Array.mem_push.mpr (Or.inl member), rest⟩
          · cases sameScope
            exact ⟨_, Array.mem_push.mpr (Or.inr rfl), ⟨rfl, rfl, rfl, sameLabel⟩,
              rfl, by simp only [sameLabel]⟩
        · rcases prior with prior | ⟨sameScope, sameLabel⟩
          · exact Or.inl prior
          · cases sameScope
            cases context with
            | some value =>
              exact Or.inr ⟨value, (mem_selection_contexts _ _ _).mpr choice, rfl, sameLabel, rfl⟩
            | none =>
              have hasContext : ∃ value, UseSelection.ContextFor (Collected.input collected) use value := by
                have notEmpty : (canonical (((Collected.input collected).realizations.filter fun record =>
                    record.value.key.node == use.node && use.realization.all (· == record.value.key.name)).map
                      fun record => ({ language := `lean, project := record.value.context.project } : Context))).isEmpty = false := by
                  simpa using nonempty
                obtain ⟨value, valueMember⟩ := Array.isEmpty_eq_false_iff_exists_mem.mp notEmpty
                exact ⟨value, (mem_selection_contexts _ _ _).mp valueMember⟩
              obtain ⟨value, present⟩ := hasContext
              exact False.elim (choice value present)
    · rcases prior with prior | sameScope
      · exact Or.inl prior
      · cases sameScope
        obtain ⟨reference, referenceMember, sameLabel⟩ := merged_scope_reference (Collected.uses collected) use member
        exact Or.inr ⟨reference, referenceMember, rfl, sameLabel⟩
  · apply Or.inr
    refine ⟨(use.node, use.realization, use.facet), ?_, rfl⟩
    rw [mem_unique_fold]
    exact Or.inr (Array.mem_map.mpr ⟨use, member, rfl⟩)

/-- Every collected use emits its actual target-selection result in every
matching projected project context. Failure results are covered as well. -/
theorem selectUses_in_context (member : use ∈ Collected.uses collected)
    (available : UseSelection.ContextFor (Collected.input collected) use context) :
    ∃ edge ∈ selectUses collected, UseSelection.Matches use edge ∧ edge.context = some context ∧
      edge.selected = selectTarget (Collected.input collected) context use.reference.label :=
  selectUses_covers collected use member (some context) available

/-- Missing source context produces an explicit diagnostic edge; it cannot
silently remove the collected dependency. -/
theorem selectUses_without_context (member : use ∈ Collected.uses collected)
    (missing : ∀ context, ¬ UseSelection.ContextFor (Collected.input collected) use context) :
    ∃ edge ∈ selectUses collected, UseSelection.Matches use edge ∧ edge.context = none ∧
      edge.selected = .error {
        code := "missing-source-context", subject := use.node.toString
        message := "Dependency has no stored source project context" } :=
  selectUses_covers collected use member none missing

/-- Finalization retains each collected use's exact selection result. Context
eligibility can be checked against the final model contributions; target selection
still refers to the actual pre-wiring input, not a re-evaluation after wiring. -/
theorem finish_use_in_context (accepted : finish collected = .ok snapshot)
    (member : use ∈ Collected.uses collected)
    (available : UseSelection.ContextFor snapshot.registry.contributions use context) :
    ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = some context ∧
      edge.selected = selectTarget (Collected.input collected) context use.reference.label := by
  rw [finish_uses accepted]
  apply selectUses_in_context member
  simpa only [UseSelection.ContextFor, (finish_preserves_selection accepted).2.1] using available

/-- The no-context diagnostic survives actual finalization, including its
source identity, optional realization restriction, facet and target label. -/
theorem finish_use_without_context (accepted : finish collected = .ok snapshot)
    (member : use ∈ Collected.uses collected)
    (missing : ∀ context, ¬ UseSelection.ContextFor snapshot.registry.contributions use context) :
    ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = none ∧
      edge.selected = .error {
        code := "missing-source-context", subject := use.node.toString
        message := "Dependency has no stored source project context" } := by
  rw [finish_uses accepted]
  apply selectUses_without_context member
  simpa only [UseSelection.ContextFor, (finish_preserves_selection accepted).2.1] using missing

/-- A collected use matching an accepted native model and facet supplies an
edge in the exact scope consumed by the gate and dependency-justification laws.
No selected-edge existence is assumed. Proof scopes include both facets. -/
theorem finish_use_in_native_scope (accepted : finish collected = .ok snapshot)
    (member : use ∈ Collected.uses collected)
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (native : model.context.language = `lean)
    (source : use.node = model.key.node)
    (restriction : ∀ name, use.realization = some name → name = model.key.name)
    (facet : name = `proof ∨ use.facet = `statement) :
    ∃ edge ∈ DependencySelection.edges snapshot.uses model.key model.context name,
      UseSelection.Matches use edge ∧
      edge.selected = selectTarget (Collected.input collected) model.context use.reference.label := by
  have available : UseSelection.ContextFor snapshot.registry.contributions use model.context := by
    obtain ⟨record, recordMember, value⟩ := Array.mem_map.mp modelMember
    refine ⟨record, recordMember, value ▸ source.symm, ?_, ?_⟩
    · simpa only [value] using restriction
    · simp only [value]
      cases contextEq : model.context
      simp_all
  obtain ⟨edge, edgeMember, aligned, context, selected⟩ := finish_use_in_context accepted member available
  refine ⟨edge, (DependencySelection.mem_edges _ _ _ _ _).mpr
    ⟨edgeMember, aligned.1.trans source, context, ?_, ?_⟩, aligned, selected⟩
  · rw [aligned.2.1]
    cases found : use.realization with
    | none => exact Or.inl rfl
    | some value => exact Or.inr (by rw [restriction value found])
  · rcases facet with proof | statement
    · exact Or.inl proof
    · exact Or.inr (aligned.2.2.1.trans statement)

/-- A collected use of a completed native parent has a successfully selected,
retained target contract whose every returned obligation has fitting original
evidence. This starts before edge selection; it does not assume an emitted edge,
a nonempty selected scope, or a preexisting gate. Earlier producer collection is
still a separate boundary. -/
theorem finish_collected_use_justified
    {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (finished : finish collected = .ok snapshot)
    (useMember : use ∈ Collected.uses collected)
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (native : model.context.language = `lean)
    (declarationMember : declaration ∈ model.declarations)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (parentMember : parent ∈ snapshot.registry.contributions.requirements)
    (parentKey : parent.value.key = ⟨.declaration model.key declaration.object, name⟩)
    (origin : DependencySelection.CollectorOwned parent.origin parent.value.key)
    (expected : parent.value.expected = .check validator)
    (coverage : parent.value.coverage = .dependencyClosure)
    (source : use.node = model.key.node)
    (restriction : ∀ realization, use.realization = some realization → realization = model.key.name)
    (useFacet : name = `proof ∨ use.facet = `statement)
    (complete : (snapshot.registry.resultForRequirement parent.value.key).complete = true) :
    ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = some model.context ∧
      ∃ keys, edge.selected = .ok keys ∧
        TargetSelection.Retained snapshot.registry model.context use.reference.label keys ∧
        ∀ selected ∈ keys, selected ∈ parent.value.prerequisites ∧
          ∃ requirement ∈ snapshot.registry.contributions.requirements,
            ∃ evidence ∈ snapshot.registry.contributions.evidence,
              snapshot.registry.requirement? selected = some requirement.value ∧
              requirement.value.key = selected ∧
              evidence.value.Fits requirement.value ((snapshot.registry.bindingFor selected).getD "") := by
  obtain ⟨edge, edgeMember, aligned, _⟩ := finish_use_in_native_scope finished useMember modelMember
    native source restriction useFacet
  obtain ⟨_, _, _, _, _, justified⟩ := evaluate_native_dependencies_justified evaluated modelMember
    native declarationMember facet parentMember parentKey origin expected coverage
    (Array.isEmpty_eq_false_iff_exists_mem.mpr ⟨edge, edgeMember⟩) complete
  obtain ⟨keys, success, retained, obligations⟩ := justified edge edgeMember
  have scopeFacts := (DependencySelection.mem_edges _ _ _ _ _).mp edgeMember
  refine ⟨edge, scopeFacts.1, aligned, scopeFacts.2.2.1, keys, success, ?_, obligations⟩
  simpa only [aligned.2.2.2] using retained

end Informal.Realizations.Capture
