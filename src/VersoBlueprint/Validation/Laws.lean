/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Validation

/-! Exact suitability of supplied evidence. These laws do not authenticate an
observation, execute its provider, or assume injectivity of content bindings. -/

namespace Informal.Validation
open Lean Realizations

-- Prove the executable identity comparisons lawful in the law layer.
deriving instance ReflBEq, LawfulBEq for Context, ObjectKey, RealizationKey, TranslationKey,
  ClaimKey, Subject, RequirementKey, Coverage, Outcome

/-- The supplied observation meets the requirement's semantic contract, apart
from subject identity and freshness. This specification contains no diagnostics. -/
def Observation.Satisfies (observation : Observation) (requirement : Requirement) : Prop :=
  match requirement.expected, observation with
  | .proof goal witness, .proof observed =>
    observed.witness = witness ∧
    (∃ actual, observed.actualType = some actual ∧
      actual.context = goal.context ∧ actual.fingerprint = goal.fingerprint) ∧
    observed.coverage = .dependencyClosure ∧ observed.outcome = .passed
  | .review criterion, .review observed =>
    observed.criterion = criterion ∧ observed.reviewer.isAnonymous = false ∧
    (observed.coverage = .dependencyClosure ∨ observed.coverage = requirement.coverage) ∧
    observed.outcome = .passed
  | .check validator, .check observed =>
    observed.validator = validator ∧
    (requirement.expected.isNativeDeclarationCheck = true →
      ∃ realization object, requirement.key.subject = .declaration realization object ∧
        observed.declaration = some object) ∧
    (observed.coverage = .dependencyClosure ∨ observed.coverage = requirement.coverage) ∧
    observed.outcome = .passed
  | _, _ => False

/-- Identity, current nonblank binding, and observation suitability are separate
obligations. Equality of binding strings does not prove collision resistance. -/
def Evidence.Fits (evidence : Evidence) (requirement : Requirement)
    (currentBinding : ContentBinding) : Prop :=
  evidence.requirement = requirement.key ∧
  blank evidence.binding = false ∧ evidence.binding = currentBinding ∧
  evidence.observation.Satisfies requirement

private theorem if_some_eq_none (p : Prop) [Decidable p] (message : String)
    (rest : Option String) :
    (if p then some message else rest) = none ↔ ¬p ∧ rest = none := by
  split <;> simp_all

private theorem if_else_some_eq_none (p : Prop) [Decidable p] (rest : Option String)
    (message : String) :
    (if p then rest else some message) = none ↔ p ∧ rest = none := by
  split <;> simp_all

/-- Neither false acceptance nor unconditional rejection implements this contract. -/
theorem Evidence.mismatch?_eq_none_iff (evidence : Evidence) (requirement : Requirement)
    (currentBinding : ContentBinding) :
    evidence.mismatch? requirement currentBinding = none ↔
      evidence.Fits requirement currentBinding := by
  cases evidence with
  | mk id key binding observation =>
    cases requirement with
    | mk rkey expected coverage prerequisites =>
      cases expected <;> cases observation <;>
        simp [Evidence.mismatch?, Evidence.Fits, Observation.Satisfies,
          Goal.sameProposition, Coverage.covers, if_some_eq_none, if_else_some_eq_none]
      · rename_i goal witness observed
        cases observed.outcome <;> cases observed.actualType <;>
          simp [and_assoc]
      · rename_i criterion observed
        cases observed.outcome <;> cases observed.coverage <;>
          simp [and_assoc]
      · rename_i validator observed
        cases rkey with
        | mk subject name =>
          cases subject <;> cases observed.outcome <;> cases observed.coverage <;>
            simp [if_some_eq_none, if_else_some_eq_none, and_assoc] <;>
            split <;> simp_all [if_else_some_eq_none]


/-- Accepted evidence identifies this exact requirement, not a sibling contract. -/
theorem Evidence.accepted_requirement {evidence : Evidence} {requirement : Requirement}
    {binding : ContentBinding} (h : evidence.mismatch? requirement binding = none) :
    evidence.requirement = requirement.key :=
  ((evidence.mismatch?_eq_none_iff requirement binding).mp h).1

/-- Accepted evidence has a current, nonblank binding. This proves string equality,
not authenticity or collision resistance of the provider's fingerprint. -/
theorem Evidence.accepted_binding {evidence : Evidence} {requirement : Requirement}
    {binding : ContentBinding} (h : evidence.mismatch? requirement binding = none) :
    blank evidence.binding = false ∧ evidence.binding = binding := by
  have fits := (evidence.mismatch?_eq_none_iff requirement binding).mp h
  exact ⟨fits.2.1, fits.2.2.1⟩

/-- Changing the current binding invalidates previously accepted evidence. -/
theorem Evidence.rejects_changed_binding {evidence : Evidence} {requirement : Requirement}
    {before after : ContentBinding} (h : evidence.mismatch? requirement before = none)
    (changed : before ≠ after) : evidence.mismatch? requirement after ≠ none := by
  intro accepted
  exact changed ((Evidence.accepted_binding h).2.symm.trans
    (Evidence.accepted_binding accepted).2)

/-- Independent proof evidence must identify the witness and actual goal and report
successful dependency-closure checking, even for a subject-only requirement. -/
theorem Evidence.accepted_proof {evidence : Evidence} {requirement : Requirement}
    {binding : ContentBinding} {goal : Goal} {witness : ObjectKey}
    (expected : requirement.expected = .proof goal witness)
    (h : evidence.mismatch? requirement binding = none) :
    ∃ observed : ProofObservation, evidence.observation = .proof observed ∧
      observed.witness = witness ∧
      (∃ actual, observed.actualType = some actual ∧
        actual.context = goal.context ∧ actual.fingerprint = goal.fingerprint) ∧
      observed.coverage = .dependencyClosure ∧ observed.outcome = .passed := by
  have fits := ((evidence.mismatch?_eq_none_iff requirement binding).mp h).2.2.2
  cases ho : evidence.observation <;> simp [Observation.Satisfies, expected, ho] at fits ⊢
  exact fits

/-- Human review requires the named criterion, an identified reviewer, sufficient
coverage and acceptance; none of these observations substitutes for proof evidence. -/
theorem Evidence.accepted_review {evidence : Evidence} {requirement : Requirement}
    {binding : ContentBinding} {criterion : Name}
    (expected : requirement.expected = .review criterion)
    (h : evidence.mismatch? requirement binding = none) :
    ∃ observed : ReviewObservation, evidence.observation = .review observed ∧
      observed.criterion = criterion ∧ observed.reviewer.isAnonymous = false ∧
      (observed.coverage = .dependencyClosure ∨ observed.coverage = requirement.coverage) ∧
      observed.outcome = .passed := by
  have fits := ((evidence.mismatch?_eq_none_iff requirement binding).mp h).2.2.2
  cases ho : evidence.observation <;> simp [Observation.Satisfies, expected, ho] at fits ⊢
  exact fits

/-- A native check can only discharge its exact declaration subject. A passed
check on another declaration, a non-declaration subject, or another observation
kind cannot be used in its place. -/
theorem Evidence.accepted_native_check {evidence : Evidence} {requirement : Requirement}
    {binding : ContentBinding}
    (native : requirement.expected.isNativeDeclarationCheck = true)
    (h : evidence.mismatch? requirement binding = none) :
    ∃ realization object observed, requirement.key.subject = .declaration realization object ∧
      evidence.observation = .check observed ∧ observed.declaration = some object ∧
      observed.outcome = .passed := by
  have fits := ((evidence.mismatch?_eq_none_iff requirement binding).mp h).2.2.2
  cases he : requirement.expected <;>
    simp [Expectation.isNativeDeclarationCheck, he] at native
  cases ho : evidence.observation <;> simp [Observation.Satisfies, he, ho] at fits
  rename_i validator observed
  obtain ⟨realization, object, subject, declaration⟩ := fits.2.1 (by
    simpa [he, Expectation.isNativeDeclarationCheck] using native)
  exact ⟨realization, object, observed, subject, rfl, declaration, fits.2.2.2⟩

/-- Suitability is local: prerequisite closure is enforced separately by Registry.
Changing prerequisite lists alone does not turn a supplied observation into proof
of that closure. -/
theorem Evidence.mismatch?_prerequisites (evidence : Evidence) (requirement : Requirement)
    (binding : ContentBinding) (prerequisites : Array RequirementKey) :
    evidence.mismatch? { requirement with prerequisites } binding =
      evidence.mismatch? requirement binding := rfl

end Informal.Validation
