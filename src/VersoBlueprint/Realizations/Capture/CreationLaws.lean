/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.RecipeLaws

/-! Positive creation of dependency-selection gates by the production capture loops.
Eligibility is checked against original contracts; consistency follows from final admission. -/

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

private theorem id_list_loop_hits (entries : List α) (property : β → Prop)
    (hit : α → Prop) (body : α → β → Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ current, ∃ next,
      body entry current = .yield next ∧ (property current ∨ hit entry → property next))
    (seed : property initial ∨ ∃ entry ∈ entries, hit entry) :
    property (forIn entries initial body) := by
  induction entries generalizing initial with
  | nil => simpa [pure] using seed
  | cons entry entries ih =>
    obtain ⟨next, executed, advance⟩ := step entry (by simp) initial
    simp only [List.forIn_cons, executed, bind]
    apply ih (fun item member => step item (by simp [member]))
    rcases seed with prior | ⟨item, member, focus⟩
    · exact Or.inl (advance (Or.inl prior))
    · rcases List.mem_cons.mp member with rfl | member
      · exact Or.inl (advance (Or.inr focus))
      · exact Or.inr ⟨item, member, focus⟩

private theorem id_array_loop_hits (entries : Array α) (property : β → Prop)
    (hit : α → Prop) (body : α → β → Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ current, ∃ next,
      body entry current = .yield next ∧ (property current ∨ hit entry → property next))
    (seed : property initial ∨ ∃ entry ∈ entries, hit entry) :
    property (forIn entries initial body) := by
  rw [← Array.forIn_toList]
  exact id_list_loop_hits entries.toList property hit body
    (fun entry member => step entry (by simpa using member)) (by simpa using seed)

private theorem list_fold_hits (entries : List α) (property : β → Prop)
    (hit : α → Prop) (step : β → α → β)
    (advance : ∀ entry ∈ entries, ∀ current,
      property current ∨ hit entry → property (step current entry))
    (seed : property initial ∨ ∃ entry ∈ entries, hit entry) :
    property (entries.foldl step initial) := by
  induction entries generalizing initial with
  | nil => simpa [pure] using seed
  | cons entry entries ih =>
    apply ih (fun item member => advance item (by simp [member]))
    rcases seed with prior | ⟨item, member, focus⟩
    · exact Or.inl (advance entry (by simp) initial (Or.inl prior))
    · rcases List.mem_cons.mp member with rfl | member
      · exact Or.inl (advance item (by simp) initial (Or.inr focus))
      · exact Or.inr ⟨item, member, focus⟩

private theorem nativeContracts_contains (input : Input)
    (member : record ∈ input.requirements)
    (keyEq : record.value.key = key)
    (origin : record.origin =
      (contribution `requirement (BindingEncoding.requirementKey key) ()).origin)
    (expected : record.value.expected = .check validator)
    (coverage : record.value.coverage = .dependencyClosure)
    (native : validator = NativeLean.statementValidator ∨ validator = NativeLean.bodyValidator)
    (agree : ∀ other ∈ input.requirements, other.value.key = key →
      other.value.expected = .check validator) :
    (input.requirements.foldl (init := ({} : Std.HashMap RequirementKey Name))
      fun out record =>
        if record.value.coverage == .dependencyClosure &&
            record.origin == (contribution `requirement (BindingEncoding.requirementKey record.value.key) ()).origin then
          match record.value.expected with
          | .check validator =>
            if validator == NativeLean.statementValidator || validator == NativeLean.bodyValidator then
              out.insert record.value.key validator
            else out
          | _ => out
        else out)[key]? = some validator := by
  rw [← Array.foldl_toList]
  apply list_fold_hits (property := fun table : Std.HashMap RequirementKey Name => table[key]? = some validator)
    (hit := fun item => item = record)
  · intro item itemMember table prior
    have itemMember : item ∈ input.requirements := by simpa using itemMember
    rcases prior with prior | rfl
    · split
      · split
        · rename_i value expectedValue
          split
          · rw [Std.HashMap.getElem?_insert]
            split
            · rename_i same
              have same := beq_iff_eq.mp same
              have consistent := agree item itemMember same
              rw [expectedValue] at consistent
              cases consistent
              rfl
            · exact prior
          · exact prior
        · exact prior
      · exact prior
    · have isNative : (validator == NativeLean.statementValidator || validator == NativeLean.bodyValidator) = true := by
        simpa using native
      simp [keyEq, origin, expected, coverage, isNative]
  · exact Or.inr ⟨record, by simpa using member, rfl⟩

/-- Original same-key expectations agree whenever complete finalization succeeds.
The raw input itself need not be admissible before wiring. -/
theorem finish_original_expectations_agree (accepted : finish collected = .ok snapshot)
    (first : a ∈ (Collected.input collected).requirements)
    (second : b ∈ (Collected.input collected).requirements)
    (same : a.value.key = b.value.key) : a.value.expected = b.value.expected := by
  obtain ⟨input, admitted⟩ := finish_admitted accepted
  have admittedFinal : admit snapshot.registry.contributions = .ok snapshot.registry := by
    rw [(admit_sources admitted).contributions]
    exact admitted
  obtain ⟨left, leftMember, _, leftKey, leftExpected, _, _⟩ :=
    (finish_preserves_selection accepted).2.2 a first
  obtain ⟨right, rightMember, _, rightKey, rightExpected, _, _⟩ :=
    (finish_preserves_selection accepted).2.2 b second
  have equal := admit_requirements_agree admittedFinal leftMember rightMember
    (leftKey.trans (same.trans rightKey.symm))
  exact leftExpected.symm.trans ((congrArg Requirement.expected equal).trans rightExpected)


private def GateCreated (uses : Array SelectedUse) (model : Realization)
    (declaration : Realizations.Declaration) (name : Name) (collected : Collected) : Prop :=
  let gate : RequirementKey := ⟨.declaration model.key declaration.object, name ++ `dependencySelection⟩
  ∃ origin observation,
    (origin, gate, .check observation) ∈ Collected.observations collected ∧
    DependencySelection.GeneratedAt uses model.key model.context declaration.object name origin gate observation ∧
    ∃ requirement ∈ (Collected.input collected).requirements,
      requirement.value.key = gate ∧ requirement.value.expected = .check `blueprint.dependencySelection

private theorem gateCreated_mono (extension : PreservesContracts (Collected.input before) (Collected.input after))
    (observations : ∀ entry ∈ Collected.observations before, entry ∈ Collected.observations after)
    (prior : GateCreated uses model declaration name before) :
    GateCreated uses model declaration name after := by
  obtain ⟨origin, observation, member, generated, requirement, present, key, expected⟩ := prior
  obtain ⟨retained, retainedMember, _, retainedKey, retainedExpected, _, _⟩ := extension.1 requirement present
  exact ⟨origin, observation, observations _ member, generated, retained, retainedMember,
    retainedKey.trans key, retainedExpected.trans expected⟩

private theorem connectUses_creates (collected : Collected) (uses : Array SelectedUse)
    (target : Realization) (declaration : Realizations.Declaration) (name validator : Name)
    (modelMember : target ∈ (Collected.input collected).realizations.map (·.value))
    (native : target.context.language = `lean)
    (declarationMember : declaration ∈ target.declarations)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (nonempty : (DependencySelection.edges uses target.key target.context name).isEmpty = false)
    (owns : ((Collected.input collected).requirements.foldl (init := ({} : Std.HashMap RequirementKey Name))
      fun out record =>
        if record.value.coverage == .dependencyClosure &&
            record.origin == (contribution `requirement (BindingEncoding.requirementKey record.value.key) ()).origin then
          match record.value.expected with
          | .check validator =>
            if validator == NativeLean.statementValidator || validator == NativeLean.bodyValidator then
              out.insert record.value.key validator
            else out
          | _ => out
        else out)[(⟨.declaration target.key declaration.object, name⟩ : RequirementKey)]? = some validator) :
    GateCreated uses target declaration name (connectUses collected uses) := by
  let property := GateCreated uses target declaration name
  unfold connectUses
  simp only [Id.run, bind, pure]
  apply id_array_loop_hits _ property (fun model => model = target)
  · intro model modelMember current
    by_cases foreign : (model.context.language != `lean) = true
    · rw [ite_eq_left foreign]
      refine ⟨current, rfl, ?_⟩
      rintro (prior | rfl)
      · exact prior
      · simp [native] at foreign
    · rw [ite_eq_right foreign]
      refine ⟨_, rfl, ?_⟩
      intro prior
      apply id_array_loop_hits _ property (fun item => model = target ∧ item = declaration)
      · intro item itemMember current
        refine ⟨_, rfl, ?_⟩
        intro prior
        apply id_array_loop_hits _ property
          (fun entry => model = target ∧ item = declaration ∧ entry = (name, validator))
        · intro entry entryMember current
          apply Classical.byCases (p := _)
          · intro owned
            rw [ite_eq_left owned]
            by_cases proof : (entry.1 == `proof) = true <;>
              (first | rw [ite_eq_left proof] | rw [ite_eq_right proof])
            all_goals
              apply Classical.byCases (p := _)
              · intro edges
                rw [ite_eq_left edges]
                refine ⟨_, rfl, ?_⟩
                rintro (prior | ⟨rfl, rfl, rfl⟩)
                · apply gateCreated_mono ?_ ?_ prior
                  · constructor
                    · intro record member
                      refine ⟨_, Array.mem_map.mpr ⟨record, ?_, rfl⟩, ?_⟩
                      · exact Array.mem_push.mpr (Or.inl member)
                      · split
                        · exact ⟨rfl, rfl, rfl, rfl, fun _ member => member⟩
                        · exact ⟨rfl, rfl, rfl, rfl, fun key member =>
                            (mem_canonical _ key).mpr (Array.mem_append_left _ member)⟩
                    · intro record member
                      exact Array.mem_push.mpr (Or.inl member)
                  · intro observation member
                    exact Array.mem_push.mpr (Or.inl member)
                · refine ⟨_, _, Array.mem_push.mpr (Or.inr rfl), ?_, _,
                    Array.mem_map.mpr ⟨_, Array.mem_push.mpr (Or.inr rfl), rfl⟩, ?_⟩
                  · refine ⟨native, ?_, rfl, rfl, nonempty, rfl⟩
                    simp at facet
                    rcases facet with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> simp
                  · split <;> exact ⟨rfl, rfl⟩
              · intro empty
                rw [ite_eq_right empty]
                refine ⟨_, rfl, ?_⟩
                rintro (prior | ⟨rfl, rfl, rfl⟩)
                · apply gateCreated_mono ?_ ?_ prior
                  · constructor
                    · intro record member
                      refine ⟨_, Array.mem_map.mpr ⟨record, member, rfl⟩, ?_⟩
                      split
                      · exact ⟨rfl, rfl, rfl, rfl, fun _ member => member⟩
                      · exact ⟨rfl, rfl, rfl, rfl, fun key member =>
                          (mem_canonical _ key).mpr (Array.mem_append_left _ member)⟩
                    · exact fun _ member => member
                  · exact fun _ member => member
                · exact False.elim (empty (by simpa [DependencySelection.edges] using nonempty))
          · intro unowned
            rw [ite_eq_right unowned]
            refine ⟨current, rfl, ?_⟩
            rintro (prior | ⟨rfl, rfl, rfl⟩)
            · exact prior
            · exact False.elim (unowned (beq_iff_eq.mpr owns))
        · rcases prior with prior | ⟨sameModel, sameDeclaration⟩
          · exact Or.inl prior
          · exact Or.inr ⟨(name, validator), facet, sameModel, sameDeclaration, rfl⟩
      · rcases prior with prior | rfl
        · exact Or.inl prior
        · exact Or.inr ⟨declaration, declarationMember, rfl, rfl⟩
  · exact Or.inr ⟨target, modelMember, rfl⟩

/-- Exact ownership test used by the native wiring route. Sharing a validator or
facet name is insufficient; the complete collector origin must match. -/
def DependencySelection.CollectorOwned (origin : Origin) (key : RequirementKey) : Prop :=
  origin = (contribution `requirement (BindingEncoding.requirementKey key) ()).origin

/-- Successful finalization creates a current, retained selection gate for each
original collector-owned native contract with a nonempty exact edge scope. This
is a positive existence result, independent of whether edge selection succeeds. -/
theorem finish_native_dependency_gate_created (accepted : finish collected = .ok snapshot)
    (modelMember : model ∈ (Collected.input collected).realizations.map (·.value))
    (native : model.context.language = `lean)
    (declarationMember : declaration ∈ model.declarations)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (recordMember : record ∈ (Collected.input collected).requirements)
    (key : record.value.key = ⟨.declaration model.key declaration.object, name⟩)
    (origin : DependencySelection.CollectorOwned record.origin record.value.key)
    (expected : record.value.expected = .check validator)
    (coverage : record.value.coverage = .dependencyClosure)
    (nonempty : (DependencySelection.edges snapshot.uses model.key model.context name).isEmpty = false) :
    let gate : RequirementKey := ⟨.declaration model.key declaration.object, name ++ `dependencySelection⟩
    ∃ requirement, snapshot.registry.requirement? gate = some requirement ∧
      requirement.key = gate ∧ requirement.expected = .check `blueprint.dependencySelection ∧
      ∃ evidence ∈ snapshot.registry.contributions.evidence, ∃ observation,
        evidence.value.requirement = gate ∧ evidence.value.observation = .check observation ∧
        DependencySelection.GeneratedAt snapshot.uses model.key model.context declaration.object name
          evidence.origin gate observation ∧
        snapshot.registry.bindingFor gate = some evidence.value.binding := by
  have indexed := nativeContracts_contains (Collected.input collected) recordMember key
    (by simpa only [DependencySelection.CollectorOwned, key] using origin) expected coverage (by
      simp at facet
      rcases facet with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> simp) (by
      intro other member same
      exact (finish_original_expectations_agree accepted member recordMember (same.trans key.symm)).trans expected)
  have created := connectUses_creates collected (selectUses collected) model declaration name validator
    modelMember native declarationMember facet (by simpa only [finish_uses accepted] using nonempty) indexed
  obtain ⟨origin, observation, observed, generated, requirement, present, gateKey, gateExpected⟩ := created
  obtain ⟨current, retained⟩ := finish_observation_current accepted observed
  have requirementMember : requirement ∈ snapshot.registry.contributions.requirements := by
    rw [finish_sources accepted]
    exact present
  obtain ⟨input, admitted⟩ := finish_admitted accepted
  have admittedFinal : admit snapshot.registry.contributions = .ok snapshot.registry := by
    rw [(admit_sources admitted).contributions]
    exact admitted
  refine ⟨requirement.value, (admit_requirement_lookup_iff admittedFinal).mpr
    ⟨requirement, requirementMember, rfl, gateKey⟩, gateKey, gateExpected,
    _, retained, observation, rfl, rfl, ?_, current⟩
  simpa only [finish_uses accepted, boundObservation] using generated

private def ClosureSources (original current : Array (Contribution Requirement)) : Prop :=
  ∀ record ∈ current, record.value.coverage = .dependencyClosure →
    ∃ source ∈ original, source.origin = record.origin ∧ source.value.key = record.value.key ∧
      source.value.expected = record.value.expected ∧ source.value.coverage = .dependencyClosure

private theorem closureSources_map (prior : ClosureSources original current)
    (frame : ∀ record, (f record).origin = record.origin ∧
      (f record).value.key = record.value.key ∧ (f record).value.expected = record.value.expected ∧
      (f record).value.coverage = record.value.coverage) :
    ClosureSources original (current.map f) := by
  intro record member coverage
  obtain ⟨old, oldMember, rfl⟩ := Array.mem_map.mp member
  obtain ⟨origin, key, expected, sameCoverage⟩ := frame old
  obtain ⟨source, sourceMember, sourceOrigin, sourceKey, sourceExpected, sourceCoverage⟩ :=
    prior old oldMember (sameCoverage.symm.trans coverage)
  exact ⟨source, sourceMember, sourceOrigin.trans origin.symm, sourceKey.trans key.symm,
    sourceExpected.trans expected.symm, sourceCoverage⟩

private theorem closureSources_push_subject (prior : ClosureSources original current)
    (subject : record.value.coverage = .subject) : ClosureSources original (current.push record) := by
  intro item member coverage
  rcases Array.mem_push.mp member with old | rfl
  · exact prior item old coverage
  · rw [subject] at coverage
    cases coverage

/-- Wiring adds subject-local mechanical gates, never new dependency-closure
contracts. Thus every retained native closure contract has an original source. -/
private theorem connectUses_closure_source (collected : Collected) (uses : Array SelectedUse) :
    ClosureSources (Collected.input collected).requirements
      (Collected.input (connectUses collected uses)).requirements := by
  let property (current : Collected) : Prop :=
    ClosureSources (Collected.input collected).requirements (Collected.input current).requirements
  unfold connectUses
  simp only [Id.run, bind, pure]
  apply id_array_loop_invariant _ property _ (fun record member coverage =>
    ⟨record, member, rfl, rfl, rfl, coverage⟩)
  intro model modelMember current prior
  by_cases foreign : (model.context.language != `lean) = true
  · rw [ite_eq_left foreign]
    exact prior
  · rw [ite_eq_right foreign]
    apply id_array_loop_invariant _ property _ prior
    intro declaration declarationMember current prior
    apply id_array_loop_invariant _ property _ prior
    intro entry entryMember current prior
    apply Classical.byCases (p := _)
    · intro owns
      rw [ite_eq_left owns]
      by_cases proof : (entry.1 == `proof) = true <;>
        (first | rw [ite_eq_left proof] | rw [ite_eq_right proof])
      all_goals
        apply Classical.byCases (p := _)
        · intro edges
          rw [ite_eq_left edges]
          apply closureSources_map (closureSources_push_subject prior rfl)
          intro record
          split <;> exact ⟨rfl, rfl, rfl, rfl⟩
        · intro empty
          rw [ite_eq_right empty]
          apply closureSources_map prior
          intro record
          split <;> exact ⟨rfl, rfl, rfl, rfl⟩
    · intro unowned
      rw [ite_eq_right unowned]
      exact prior

/-- Closure contracts in the final registry come from before dependency wiring,
with their origin, identity and expectation intact. This converse is restricted
to closure contracts: subject-local selection gates are intentionally new. -/
theorem finish_closure_contract_source (accepted : finish collected = .ok snapshot)
    (member : record ∈ snapshot.registry.contributions.requirements)
    (coverage : record.value.coverage = .dependencyClosure) :
    ∃ original ∈ (Collected.input collected).requirements,
      original.origin = record.origin ∧ original.value.key = record.value.key ∧
      original.value.expected = record.value.expected ∧ original.value.coverage = .dependencyClosure := by
  rw [finish_sources accepted] at member
  exact connectUses_closure_source collected (selectUses collected) record member coverage

/-- Every accepted collector-owned native contract with a nonempty scoped edge
inventory has an actual selection gate and current evidence in the public
snapshot. No gate/evidence existence or validity of the raw input is assumed. -/
theorem evaluate_native_dependency_gate_created {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (native : model.context.language = `lean)
    (declarationMember : declaration ∈ model.declarations)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (recordMember : record ∈ snapshot.registry.contributions.requirements)
    (key : record.value.key = ⟨.declaration model.key declaration.object, name⟩)
    (origin : DependencySelection.CollectorOwned record.origin record.value.key)
    (expected : record.value.expected = .check validator)
    (coverage : record.value.coverage = .dependencyClosure)
    (nonempty : (DependencySelection.edges snapshot.uses model.key model.context name).isEmpty = false) :
    let gate : RequirementKey := ⟨.declaration model.key declaration.object, name ++ `dependencySelection⟩
    ∃ requirement, snapshot.registry.requirement? gate = some requirement ∧
      requirement.key = gate ∧ requirement.expected = .check `blueprint.dependencySelection ∧
      ∃ evidence ∈ snapshot.registry.contributions.evidence, ∃ observation,
        evidence.value.requirement = gate ∧ evidence.value.observation = .check observation ∧
        DependencySelection.GeneratedAt snapshot.uses model.key model.context declaration.object name
          evidence.origin gate observation ∧
        snapshot.registry.bindingFor gate = some evidence.value.binding := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨documents, _, nativeTable, _, inline, _, documented, _, checks, _,
    specifications, _, expectedTable, _, collected, _, finished⟩ := accepted
  obtain ⟨original, originalMember, originalOrigin, originalKey, originalExpected, originalCoverage⟩ :=
    finish_closure_contract_source finished recordMember coverage
  apply finish_native_dependency_gate_created finished
    (by simpa only [(finish_preserves_selection finished).2.1] using modelMember)
    native declarationMember facet originalMember (originalKey.trans key) ?_
    (originalExpected.trans expected) originalCoverage nonempty
  simpa only [DependencySelection.CollectorOwned, originalKey] using originalOrigin.trans origin

end Informal.Realizations.Capture
