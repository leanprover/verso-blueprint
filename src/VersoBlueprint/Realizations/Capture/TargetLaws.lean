/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.RecipeLaws

/-! Exact acceptance and returned contract inventory for the production native target
selector. Selection is separate from completion and provider authenticity. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations

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
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some captureOwner || env.getModuleIdxFor? name == some lawsOwner ||
        env.getModuleIdxFor? name == some recipeOwner then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

namespace TargetSelection

/-- A selected declaration retains its exact native body-proof obligation. Other
required contracts remain part of the returned inventory as well. -/
def DeclarationValid (input : Input) (target : Name) (declaration : Realizations.Declaration) : Prop :=
  let proof : RequirementKey := ⟨.declaration ⟨target, `lean⟩ declaration.object, `proof⟩
  ∃ requirement,
    canonical ((input.requirements.filter (·.value.key == proof)).map (·.value)) = #[requirement] ∧
    requirement.expected = .check NativeLean.bodyValidator ∧
    requirement.coverage = .dependencyClosure ∧ proof ∈ declaration.required

/-- The per-target checks performed by the selector, without assuming that the
entire input has already been admitted or that any requirement is complete. -/
def Contract (input : Input) (context : Context) (target : Name) (model : Realization) : Prop :=
  (∃ node ∈ input.nodes, node.value.label = target) ∧
  canonical ((input.realizations.filter (·.value.key == ⟨target, `lean⟩)).map (·.value)) = #[model] ∧
  model.context = context ∧ model.declarations.isEmpty = false ∧
  ∀ declaration ∈ model.declarations, DeclarationValid input target declaration

private theorem declaration_guard_iff (input : Input) (target : Name) (declaration : Realizations.Declaration) :
    (let proof : RequirementKey := ⟨.declaration ⟨target, `lean⟩ declaration.object, `proof⟩
     let contracts := canonical ((input.requirements.filter (·.value.key == proof)).map (·.value))
     contracts.size == 1 && contracts[0]!.expected == .check NativeLean.bodyValidator &&
       contracts[0]!.coverage == .dependencyClosure && declaration.required.contains proof) = true ↔
    DeclarationValid input target declaration := by
  simp only [Bool.and_eq_true, beq_iff_eq, Array.contains_iff_mem, and_assoc]
  constructor
  · rintro ⟨size, expected, coverage, member⟩
    obtain ⟨requirement, singleton⟩ := Array.size_eq_one_iff.mp size
    refine ⟨requirement, singleton, ?_, ?_, member⟩
    · simpa [singleton] using expected
    · simpa [singleton] using coverage
  · rintro ⟨requirement, singleton, expected, coverage, member⟩
    simp [singleton, expected, coverage, member]

private theorem list_collect_iff (entries : List α) (valid : α → Bool)
    (fields : α → Array β) (failure : α → ε) (initial : Array β) (final : Option γ × Array β) :
    (forIn entries (none, initial) fun entry current =>
      if valid entry then (Except.ok (.yield (none, current.2 ++ fields entry)) : Except ε (ForInStep (Option γ × Array β)))
      else .error (failure entry)) = .ok final ↔
    (∀ entry ∈ entries, valid entry = true) ∧ final = (none, initial ++ entries.toArray.flatMap fields) := by
  induction entries generalizing initial with
  | nil => simp [pure, Except.pure]; exact eq_comm
  | cons entry entries ih =>
    by_cases accepted : valid entry = true
    · simp only [List.forIn_cons, accepted, ↓reduceIte, bind, Except.bind]
      rw [ih]
      simp [accepted, Array.append_assoc, ← List.append_toArray]
    · simp [List.forIn_cons, accepted, bind, Except.bind]

private theorem array_collect_iff (entries : Array α) (valid : α → Bool)
    (fields : α → Array β) (failure : α → ε) (initial : Array β) (final : Option γ × Array β) :
    (forIn entries (none, initial) fun entry current =>
      if valid entry then (Except.ok (.yield (none, current.2 ++ fields entry)) : Except ε (ForInStep (Option γ × Array β)))
      else .error (failure entry)) = .ok final ↔
    (∀ entry ∈ entries, valid entry = true) ∧ final = (none, initial ++ entries.flatMap fields) := by
  rw [← Array.forIn_toList, list_collect_iff]
  simp

private theorem selectTarget_checks_iff (input : Input) (context : Context) (target : Name) (keys : Array RequirementKey) :
    selectTarget input context target = .ok keys ↔
    let models := canonical ((input.realizations.filter (·.value.key == ⟨target, `lean⟩)).map (·.value))
    input.nodes.any (·.value.label == target) = true ∧ models.size = 1 ∧
    models[0]!.context = context ∧ models[0]!.declarations.isEmpty = false ∧
    (∀ declaration ∈ models[0]!.declarations, DeclarationValid input target declaration) ∧
    keys = canonical (models[0]!.declarations.flatMap (·.required)) := by
  unfold selectTarget
  dsimp only
  split
  · rename_i targetPresent
    split
    · rename_i singleton
      split
      · rename_i contextMatches
        split
        · rename_i hasDeclarations
          simp only [except_bind_ok_iff]
          simp only [pure, Except.pure, bind, Except.bind]
          simp only [array_collect_iff]
          simp only [declaration_guard_iff, and_assoc, exists_and_left, exists_eq_left,
            Array.empty_append, Except.ok.injEq]
          simp only [beq_iff_eq] at singleton contextMatches
          simp only [Bool.not_eq_true'] at hasDeclarations
          simp only [targetPresent, singleton, contextMatches, hasDeclarations, true_and]
          constructor <;> rintro ⟨valid, equal⟩ <;> exact ⟨valid, equal.symm⟩
        · rename_i noDeclarations
          constructor
          · intro impossible; cases impossible
          · rintro ⟨_, _, _, nonempty, _⟩
            exact False.elim (noDeclarations (by simp only [nonempty, Bool.not_false]))
      · rename_i contextMismatch
        simp only [beq_iff_eq] at contextMismatch
        simp [targetPresent, contextMismatch]
    · rename_i notSingleton
      simp only [beq_iff_eq] at notSingleton
      simp [targetPresent, notSingleton]
  · rename_i targetAbsent
    simp [targetAbsent]

end TargetSelection
/-- Exact acceptance and output of the production native target selector.
The selected model's complete declaration contracts are returned in canonical
order. This includes additional authored declaration requirements, not just native
body-proof keys. No completion or provider-authenticity premise is assumed. -/
theorem selectTarget_ok_iff (input : Input) (context : Context) (target : Name)
    (keys : Array RequirementKey) :
    selectTarget input context target = .ok keys ↔
      ∃ model, TargetSelection.Contract input context target model ∧
        keys = canonical (model.declarations.flatMap (·.required)) := by
  rw [TargetSelection.selectTarget_checks_iff]
  constructor
  · rintro ⟨present, size, contextEq, nonempty, valid, output⟩
    obtain ⟨model, singleton⟩ := Array.size_eq_one_iff.mp size
    have rest : model.context = context ∧ model.declarations.isEmpty = false ∧
        (∀ declaration ∈ model.declarations, TargetSelection.DeclarationValid input target declaration) ∧
        keys = canonical (model.declarations.flatMap (·.required)) := by
      simpa [singleton] using And.intro contextEq (And.intro nonempty (And.intro valid output))
    refine ⟨model, ⟨?_, singleton, rest.1, rest.2.1, rest.2.2.1⟩, rest.2.2.2⟩
    simpa only [Array.any_eq_true', beq_iff_eq] using present
  · rintro ⟨model, ⟨present, singleton, contextEq, nonempty, valid⟩, output⟩
    have presentBool : input.nodes.any (·.value.label == target) = true := by
      simpa only [Array.any_eq_true', beq_iff_eq] using present
    simpa [singleton] using And.intro presentBool
      (And.intro (by decide : (1 : Nat) = 1) (And.intro contextEq (And.intro nonempty (And.intro valid output))))

/-- Returned keys have exactly the membership of the selected declarations'
required lists; canonicalization cannot drop an additional obligation. -/
theorem selectTarget_membership (accepted : selectTarget input context target = .ok keys) :
    ∃ model, TargetSelection.Contract input context target model ∧
      ∀ key, key ∈ keys ↔ ∃ declaration ∈ model.declarations, key ∈ declaration.required := by
  obtain ⟨model, contract, rfl⟩ := (selectTarget_ok_iff _ _ _ _).mp accepted
  refine ⟨model, contract, ?_⟩
  intro key
  rw [mem_canonical]
  exact Array.mem_flatMap

/-- Matching original model payloads agree whenever target selection succeeds.
Repeated identical contributions are permitted; competing definitions are not. -/
theorem selectTarget_models_agree (accepted : selectTarget input context target = .ok keys)
    (aMember : a ∈ input.realizations) (bMember : b ∈ input.realizations)
    (aKey : a.value.key = ⟨target, `lean⟩) (bKey : b.value.key = ⟨target, `lean⟩) :
    a.value = b.value := by
  obtain ⟨model, contract, _⟩ := (selectTarget_ok_iff _ _ _ _).mp accepted
  have only (record : Contribution Realization) (member : record ∈ input.realizations)
      (keyEq : record.value.key = ⟨target, `lean⟩) : record.value = model := by
    apply Array.mem_singleton.mp
    rw [← contract.2.1, mem_canonical]
    refine Array.mem_map.mpr ⟨record, Array.mem_filter.mpr ⟨member, ?_⟩, rfl⟩
    simpa only [beq_iff_eq] using keyEq
  exact (only a aMember aKey).trans (only b bMember bKey).symm

/-- A selected native target always contributes an obligation. Empty contracts
cannot accidentally count as successful dependency selection. -/
theorem selectTarget_nonempty (accepted : selectTarget input context target = .ok keys) :
    keys.isEmpty = false := by
  obtain ⟨model, contract, membership⟩ := selectTarget_membership accepted
  obtain ⟨declaration, member⟩ := Array.isEmpty_eq_false_iff_exists_mem.mp contract.2.2.2.1
  obtain ⟨requirement, _, _, _, proofMember⟩ := contract.2.2.2.2 declaration member
  exact Array.isEmpty_eq_false_iff_exists_mem.mpr
    ⟨_, (membership _).mpr ⟨declaration, member, proofMember⟩⟩

/-- The model and each native proof requirement are original input records.
This links the selector's canonical views back to retained contribution payloads. -/
theorem selectTarget_native_requirements (accepted : selectTarget input context target = .ok keys) :
    ∃ model ∈ input.realizations,
      model.value.key = ⟨target, `lean⟩ ∧ model.value.context = context ∧
      model.value.declarations.isEmpty = false ∧
      ∀ declaration ∈ model.value.declarations,
        let proof : RequirementKey := ⟨.declaration ⟨target, `lean⟩ declaration.object, `proof⟩
        proof ∈ keys ∧ ∃ requirement ∈ input.requirements,
          requirement.value.key = proof ∧
          requirement.value.expected = .check NativeLean.bodyValidator ∧
          requirement.value.coverage = .dependencyClosure := by
  obtain ⟨model, contract, membership⟩ := selectTarget_membership accepted
  have modelMember : model ∈ canonical
      ((input.realizations.filter (·.value.key == ⟨target, `lean⟩)).map (·.value)) := by
    rw [contract.2.1]
    simp
  rw [mem_canonical] at modelMember
  simp only [Array.mem_map, Array.mem_filter, beq_iff_eq] at modelMember
  obtain ⟨original, ⟨originalMember, modelKey⟩, rfl⟩ := modelMember
  refine ⟨original, originalMember, modelKey, contract.2.2.1, contract.2.2.2.1, ?_⟩
  intro declaration member
  obtain ⟨requirement, singleton, expected, coverage, proofMember⟩ := contract.2.2.2.2 declaration member
  refine ⟨(membership _).mpr ⟨declaration, member, proofMember⟩, ?_⟩
  have requirementMember : requirement ∈ canonical
      ((input.requirements.filter (·.value.key == ⟨.declaration ⟨target, `lean⟩ declaration.object, `proof⟩)).map (·.value)) := by
    rw [singleton]
    simp
  rw [mem_canonical] at requirementMember
  simp only [Array.mem_map, Array.mem_filter, beq_iff_eq] at requirementMember
  obtain ⟨originalRequirement, ⟨originalMember, proofKey⟩, rfl⟩ := requirementMember
  exact ⟨originalRequirement, originalMember, proofKey, expected, coverage⟩

/-- Every successful emitted edge uses the exact native target selector in a
Lean context constructed from an original, scope-matching source model. No
global admission assumption is needed for the collection being selected. -/
theorem selectUses_success_source (member : edge ∈ selectUses collected)
    (selected : edge.selected = .ok keys) :
    ∃ context, ∃ source : Contribution Realization,
      edge.context = some context ∧ source ∈ (Collected.input collected).realizations ∧
      source.value.key.node = edge.source ∧
      (∀ name, edge.realization = some name → name = source.value.key.name) ∧
      context = { language := `lean, project := source.value.context.project } ∧
      selectTarget (Collected.input collected) context edge.reference.label = .ok keys := by
  let property (edges : Array SelectedUse) : Prop := ∀ edge ∈ edges, ∀ keys,
    edge.selected = .ok keys →
    ∃ context, ∃ source : Contribution Realization,
      edge.context = some context ∧ source ∈ (Collected.input collected).realizations ∧
      source.value.key.node = edge.source ∧
      (∀ name, edge.realization = some name → name = source.value.key.name) ∧
      context = { language := `lean, project := source.value.context.project } ∧
      selectTarget (Collected.input collected) context edge.reference.label = .ok keys
  suffices valid : property (selectUses collected) from valid edge member keys selected
  unfold selectUses
  simp only [Id.run, bind, pure]
  apply id_array_loop_invariant _ property _ (by simp [property])
  intro scope scopeMember current prior
  rcases scope with ⟨source, realization, facet⟩
  apply id_array_loop_invariant _ property _ prior
  intro reference referenceMember current prior
  apply Classical.byCases (p := _)
  · intro empty
    rw [ite_eq_left empty]
    intro edge member keys success
    simp only [Array.mem_push] at member
    rcases member with previous | rfl
    · exact prior edge previous keys success
    · cases success
  · intro nonempty
    rw [ite_eq_right nonempty]
    apply id_array_loop_invariant _ property _ prior
    intro context contextMember current prior
    intro edge member keys success
    simp only [Array.mem_push] at member
    rcases member with previous | rfl
    · exact prior edge previous keys success
    · rw [mem_canonical] at contextMember
      simp only [Array.mem_map, Array.mem_filter, Bool.and_eq_true, beq_iff_eq] at contextMember
      obtain ⟨model, ⟨original, nodeEq, scopeEq⟩, contextEq⟩ := contextMember
      refine ⟨context, model, rfl, original, nodeEq, ?_, contextEq.symm, success⟩
      simpa only [Option.all_eq_true, beq_iff_eq] using scopeEq

/-- Successful edge selection returns precisely its target's declaration
contracts in the constructed Lean context, including additional authored keys. -/
theorem selectUses_success_contract (member : edge ∈ selectUses collected)
    (selected : edge.selected = .ok keys) :
    ∃ context, edge.context = some context ∧ context.language = `lean ∧
      ∃ model, TargetSelection.Contract (Collected.input collected) context edge.reference.label model ∧
        keys = canonical (model.declarations.flatMap (·.required)) := by
  obtain ⟨context, source, contextEq, _, _, _, native, target⟩ :=
    selectUses_success_source member selected
  exact ⟨context, contextEq, by simp [native], (selectTarget_ok_iff _ _ _ _).mp target⟩

/-- An emitted successful edge cannot carry an empty selection. Missing source
contexts and invalid target contracts never supply vacuous success. -/
theorem selectUses_success_nonempty (member : edge ∈ selectUses collected)
    (selected : edge.selected = .ok keys) : keys.isEmpty = false := by
  obtain ⟨_, _, _, _, _, _, _, target⟩ := selectUses_success_source member selected
  exact selectTarget_nonempty target

/-- Every declaration in a successfully selected target has its original native
body-proof requirement among the edge's returned keys. These are contributions
in the collection before wiring; completion and final retention are separate. -/
theorem selectUses_success_native_requirements (member : edge ∈ selectUses collected)
    (selected : edge.selected = .ok keys) :
    ∃ context, edge.context = some context ∧ context.language = `lean ∧
      ∃ model ∈ (Collected.input collected).realizations,
        model.value.key = ⟨edge.reference.label, `lean⟩ ∧ model.value.context = context ∧
        model.value.declarations.isEmpty = false ∧
        ∀ declaration ∈ model.value.declarations,
          let proof : RequirementKey := ⟨.declaration ⟨edge.reference.label, `lean⟩ declaration.object, `proof⟩
          proof ∈ keys ∧ ∃ requirement ∈ (Collected.input collected).requirements,
            requirement.value.key = proof ∧
            requirement.value.expected = .check NativeLean.bodyValidator ∧
            requirement.value.coverage = .dependencyClosure := by
  obtain ⟨context, source, contextEq, _, _, _, native, target⟩ :=
    selectUses_success_source member selected
  exact ⟨context, contextEq, by simp [native], selectTarget_native_requirements target⟩

/-- Finalization retains the same selected edges: a successful public snapshot
edge has the exact target contract selected from the pre-wiring collection.
This does not yet assert preservation of those contracts in the final registry. -/
theorem finish_use_success_contract (accepted : finish collected = .ok snapshot)
    (member : edge ∈ snapshot.uses) (selected : edge.selected = .ok keys) :
    ∃ context, edge.context = some context ∧ context.language = `lean ∧
      ∃ model, TargetSelection.Contract (Collected.input collected) context edge.reference.label model ∧
        keys = canonical (model.declarations.flatMap (·.required)) := by
  rw [finish_uses accepted] at member
  exact selectUses_success_contract member selected

namespace TargetSelection

/-- The selected target contract is available through the final registry's real
lookups. Every returned key has a definition, including additional authored keys.
Native body contracts retain their validator and coverage; their prerequisites
may have grown during wiring. No completion status is required. -/
def Retained (registry : Registry) (context : Context) (target : Name)
    (keys : Array RequirementKey) : Prop :=
  ∃ model, registry.realization? ⟨target, `lean⟩ = some model ∧
    model.context = context ∧ model.declarations.isEmpty = false ∧
    keys = canonical (model.declarations.flatMap (·.required)) ∧
    (∀ key ∈ keys, ∃ requirement, registry.requirement? key = some requirement) ∧
    ∀ declaration ∈ model.declarations,
      let proof : RequirementKey := ⟨.declaration ⟨target, `lean⟩ declaration.object, `proof⟩
      proof ∈ keys ∧ ∃ requirement, registry.requirement? proof = some requirement ∧
        requirement.expected = .check NativeLean.bodyValidator ∧
        requirement.coverage = .dependencyClosure

end TargetSelection

/-- Successful finalization retains each selected target's exact declaration
inventory and native proof contracts in the admitted registry. Additional keys
also have actual definitions; this uses final admission, not an assumption that
the pre-wiring collection was globally admitted. -/
theorem finish_use_target_retained (accepted : finish collected = .ok snapshot)
    (member : edge ∈ snapshot.uses) (selected : edge.selected = .ok keys) :
    ∃ context, edge.context = some context ∧ context.language = `lean ∧
      TargetSelection.Retained snapshot.registry context edge.reference.label keys := by
  have emitted : edge ∈ selectUses collected := by rwa [← finish_uses accepted]
  obtain ⟨context, source, contextEq, _, _, _, native, target⟩ :=
    selectUses_success_source emitted selected
  obtain ⟨model, modelMember, modelKey, modelContext, nonempty, proofs⟩ :=
    selectTarget_native_requirements target
  obtain ⟨selectedModel, contract, inventory⟩ := (selectTarget_ok_iff _ _ _ _).mp target
  have same : model.value = selectedModel := by
    apply Array.mem_singleton.mp
    rw [← contract.2.1, mem_canonical]
    exact Array.mem_map.mpr ⟨model, Array.mem_filter.mpr ⟨modelMember, by simpa using modelKey⟩, rfl⟩
  rw [← same] at inventory
  have retained := finish_preserves_selection accepted
  have modelRetained : model ∈ snapshot.registry.contributions.realizations := by
    rwa [retained.2.1]
  have admitted : admit snapshot.registry.contributions = .ok snapshot.registry := by
    obtain ⟨input, admitted⟩ := finish_admitted accepted
    rw [(admit_sources admitted).contributions]
    exact admitted
  refine ⟨context, contextEq, by simp [native], model.value, ?_, modelContext, nonempty,
    inventory, ?_, ?_⟩
  · exact (admit_realization_lookup_iff admitted).mpr ⟨model, modelRetained, rfl, modelKey⟩
  · intro key keyMember
    have required : key ∈ model.value.requirements := by
      rw [inventory, mem_canonical] at keyMember
      simp only [Realization.requirements, List.mem_toArray, List.mem_eraseDups,
        Array.mem_toList_iff, Array.mem_append]
      exact Or.inr keyMember
    have present := (admit_realization_mem admitted _).mpr ⟨model, modelRetained, rfl⟩
    obtain ⟨record, recordMember, keyEq⟩ := admit_realization_requirement_exists admitted present required
    exact ⟨record.value, (admit_requirement_lookup_iff admitted).mpr ⟨record, recordMember, rfl, keyEq⟩⟩
  · intro declaration declarationMember
    obtain ⟨proofMember, requirement, requirementMember, keyEq, expected, coverage⟩ := proofs declaration declarationMember
    obtain ⟨final, finalMember, _, finalKey, finalExpected, finalCoverage, _⟩ := retained.2.2 requirement requirementMember
    exact ⟨proofMember, final.value,
      (admit_requirement_lookup_iff admitted).mpr ⟨final, finalMember, rfl, finalKey.trans keyEq⟩,
      finalExpected.trans expected, finalCoverage.trans coverage⟩

/-- The pure capture entry point exposes the same retained target contract for
each successful public dependency edge. This is a contract-retention guarantee,
not target completion or completeness of the authored edge inventory. -/
theorem evaluate_use_target_retained {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (member : edge ∈ snapshot.uses) (selected : edge.selected = .ok keys) :
    ∃ context, edge.context = some context ∧ context.language = `lean ∧
      TargetSelection.Retained snapshot.registry context edge.reference.label keys := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, collected, _, finished⟩ := accepted
  exact finish_use_target_retained finished member selected

/-- Completing a generated selection gate requires a nonempty scoped edge set
whose exact target contracts remain available in the same final registry.
The target requirements' own completion remains a separate obligation. -/
theorem evaluate_complete_dependency_targets {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (found : snapshot.registry.requirement? key = some requirement)
    (expected : requirement.expected = .check `blueprint.dependencySelection)
    (complete : (snapshot.registry.resultForRequirement key).complete = true) :
    ∃ realization context object name,
      context.language = `lean ∧ (name = `statement ∨ name = `proof) ∧
      key = ⟨.declaration realization object, name ++ `dependencySelection⟩ ∧
      (DependencySelection.edges snapshot.uses realization context name).isEmpty = false ∧
      ∀ edge ∈ DependencySelection.edges snapshot.uses realization context name,
        ∃ keys, edge.selected = .ok keys ∧
          TargetSelection.Retained snapshot.registry context edge.reference.label keys := by
  obtain ⟨realization, context, object, name, native, facet, keyEq, nonempty, passed⟩ :=
    evaluate_complete_dependency_selection evaluated found expected complete
  refine ⟨realization, context, object, name, native, facet, keyEq, nonempty, ?_⟩
  intro edge member
  obtain ⟨keys, selected⟩ := passed edge member
  have scopeFacts := (DependencySelection.mem_edges _ _ _ _ _).mp member
  obtain ⟨edgeContext, contextEq, _, retained⟩ := evaluate_use_target_retained evaluated scopeFacts.1 selected
  have same : edgeContext = context := Option.some.inj (contextEq.symm.trans scopeFacts.2.2.1)
  exact ⟨keys, selected, same ▸ retained⟩

end Informal.Realizations.Capture
