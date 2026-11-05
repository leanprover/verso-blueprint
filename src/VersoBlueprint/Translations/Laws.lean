/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Translations
import VersoBlueprint.Validation.Laws
import VersoBlueprint.Realizations.Laws

namespace Informal.Translations
open Lean Realizations Validation

deriving instance ReflBEq, LawfulBEq for Status

/-- Public completion requires every selected contract, not a successful alternative. -/
private theorem Registry.complete_requires_canonical (registry : Registry) (subject : Subject)
    (h : (registry.resultFor subject).complete = true) :
    (canonical (registry.requiredFor subject)).isEmpty = false ∧
      ∀ key ∈ canonical (registry.requiredFor subject),
        (registry.resultForRequirement key).complete = true := by
  cases subject <;> simp [Registry.resultFor, Subject.translation?, Result.complete, Id.run, pure] at h
  all_goals repeat (first | split at h | simp_all [Result.complete, Array.mem_iff_getElem])
  all_goals try simp_all [Result.complete, Array.mem_iff_getElem]
  all_goals try (split at h <;> simp_all)
  all_goals
    intro key i hi he
    subst key
    simp_all

/-- Completed public subjects have at least one contract, and every required
contract is complete. Canonicalization cannot hide an unfinished requirement.
This is a query property; it does not assume or prove cache/index consistency. -/
theorem Registry.complete_requires_all (registry : Registry) (subject : Subject)
    (h : (registry.resultFor subject).complete = true) :
    (registry.requiredFor subject).isEmpty = false ∧
      ∀ key ∈ registry.requiredFor subject,
        (registry.resultForRequirement key).complete = true := by
  simpa only [Array.isEmpty_eq_false_iff_exists_mem, mem_canonical] using
    registry.complete_requires_canonical subject h

/-- No public subject can be certified by an empty requirement set. It may instead
be blocked by unavailable source or remain unassessed. -/
theorem Registry.empty_requirements_not_complete (registry : Registry) (subject : Subject)
    (empty : registry.requiredFor subject = #[]) :
    (registry.resultFor subject).complete = false := by
  cases h : (registry.resultFor subject).complete
  · rfl
  · have required := (registry.complete_requires_all subject h).1
    simp [empty] at required

/-- A complete alternative cannot hide an unfinished selected requirement. -/
theorem Registry.unfinished_requirement_not_complete (registry : Registry) (subject : Subject)
    (key : RequirementKey) (selected : key ∈ registry.requiredFor subject)
    (unfinished : (registry.resultForRequirement key).complete = false) :
    (registry.resultFor subject).complete = false := by
  cases h : (registry.resultFor subject).complete
  · rfl
  · have complete := (registry.complete_requires_all subject h).2 key selected
    simp [unfinished] at complete

/-- Completion implies a known subject; a missing subject never acquires a certificate. -/
theorem Registry.complete_hasSubject (registry : Registry) (subject : Subject)
    (h : (registry.resultFor subject).complete = true) :
    registry.hasSubject subject = true := by
  cases known : registry.hasSubject subject
  · simp [Registry.resultFor, known, Result.complete, Id.run, pure] at h
  · rfl

end Informal.Translations
