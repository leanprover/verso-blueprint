/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Translations.AdmissionLaws

/-! Prerequisites select a contract by identity and context. Completion of an
alternative cannot determine the selected contract. -/
namespace Informal.Translations
open Lean Realizations Validation

/-- The identity constraints of an authored prerequisite, independently of
requirement status or evidence. Optional names restrict rather than rank matches. -/
def Selection.Matches (selection : Selection) (registry : Registry)
    (requirement : Requirement) : Prop :=
  ∃ key, requirement.key.subject.realization? = some key ∧
    key.node = selection.node ∧
    (∀ name, selection.realization = some name → name = key.name) ∧
    (∃ realization, registry.realization? key = some realization ∧
      realization.context = selection.context) ∧
    requirement.key.name = selection.requirement ∧
    (∀ name, selection.facet = some name → requirement.key.subject = .facet key name)

private theorem matches_filter (selection : Selection) (registry : Registry)
    (requirement : Requirement) :
    (match requirement.key.subject.realization? with
      | none => false
      | some key => key.node == selection.node &&
          selection.realization.all (· == key.name) &&
          (registry.realization? key).any (·.context == selection.context) &&
          requirement.key.name == selection.requirement &&
          (match selection.facet, requirement.key.subject with
           | none, _ => true
           | some name, .facet _ actual => name == actual
           | _, _ => false)) = true ↔ selection.Matches registry requirement := by
  cases subject : requirement.key.subject <;>
    cases realization : selection.realization <;> cases facet : selection.facet <;>
    simp [Selection.Matches, Subject.realization?, subject, realization, facet, Option.any_eq_true, and_assoc] <;> grind

/-- Selection returns the unique matching collected requirement, without using
its completion status to choose between alternatives. -/
theorem Registry.selectRequirement_matches (registry : Registry)
    (selected : registry.selectRequirement selection = .ok key) :
    ∃ requirement ∈ registry.requirements, selection.Matches registry requirement ∧
      requirement.key = key ∧
      ∀ other ∈ registry.requirements, selection.Matches registry other → other = requirement := by
  simp only [Registry.selectRequirement] at selected
  split at selected
  · rename_i requirement found
    cases selected
    have membership (other : Requirement) :
        (other ∈ registry.requirements ∧ selection.Matches registry other) ↔ other = requirement := by
      have equality := congrArg (fun xs : List Requirement => other ∈ xs) found
      rw [← matches_filter selection registry other]
      cases subject : other.key.subject <;> cases facet : selection.facet <;>
        simpa [subject, Subject.realization?, facet] using Iff.of_eq equality
    obtain ⟨member, matching⟩ := (membership requirement).mpr rfl
    exact ⟨requirement, member, matching, rfl, fun other member matching =>
      (membership other).mp ⟨member, matching⟩⟩
  · contradiction
  · contradiction

/-- Every successful selection identifies original input evidence, and every
other original matching record agrees. Repeated identical contributions are
allowed; distinct matching alternatives are not resolved by their status. -/
theorem admit_selection_matches (admitted : admit input = .ok registry)
    (selected : registry.selectRequirement selection = .ok key) :
    ∃ record ∈ input.requirements, selection.Matches registry record.value ∧
      record.value.key = key ∧
      ∀ other ∈ input.requirements, selection.Matches registry other.value → other.value = record.value := by
  obtain ⟨requirement, member, matching, identity, unique⟩ := registry.selectRequirement_matches selected
  obtain ⟨record, original, rfl⟩ := (admit_requirement_mem admitted requirement).mp member
  exact ⟨record, original, matching, identity, fun other member matching =>
    unique other.value ((admit_requirement_mem admitted _).mpr ⟨other, member, rfl⟩) matching⟩

/-- Selection reads only requirements and realization identities/contexts.
Completion caches, evidence, and the ranking of successful alternatives are
not inputs to this policy. -/
theorem Registry.selectRequirement_congr (left right : Registry) (selection : Selection)
    (requirements : left.requirements = right.requirements)
    (realizations : ∀ key, left.realization? key = right.realization? key) :
    left.selectRequirement selection = right.selectRequirement selection := by
  simp only [Registry.selectRequirement, requirements, realizations]

/-- Changing evidence or any other input family cannot change prerequisite
selection when requirement and realization contributions are preserved and both
complete inputs are admitted. This covers selection failures as well as success. -/
theorem admit_selection_sources (admittedLeft : admit before = .ok left)
    (admittedRight : admit after = .ok right)
    (requirements : before.requirements = after.requirements)
    (realizations : before.realizations = after.realizations) (selection : Selection) :
    left.selectRequirement selection = right.selectRequirement selection := by
  apply Registry.selectRequirement_congr
  · rw [(admit_sources admittedLeft).requirements, (admit_sources admittedRight).requirements, requirements]
  · intro key
    cases found : left.realization? key with
    | none =>
      cases other : right.realization? key with
      | none => rfl
      | some realization =>
        have source := (admit_realization_lookup_iff admittedRight).mp other
        rw [← realizations] at source
        have same := (admit_realization_lookup_iff admittedLeft).mpr source
        simp [found] at same
    | some realization =>
      have source := (admit_realization_lookup_iff admittedLeft).mp found
      rw [realizations] at source
      exact ((admit_realization_lookup_iff admittedRight).mpr source).symm

end Informal.Translations
