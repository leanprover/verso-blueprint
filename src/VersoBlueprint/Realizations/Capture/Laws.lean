/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture
import VersoBlueprint.Translations.AdmissionLaws

/-! Connect the pure capture entry point and consumer assessment to production
admission. Supplied observations remain distinct from authenticated providers. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations

-- Scope-local access for the pre-module-system implementation. This does not
-- change production visibility or export aliases for its private declarations.
run_cmd do
  let env ← getEnv
  let some owner := env.getModuleIdxFor? ``evaluate
    | throwError "Capture implementation must be imported before opening its proof scope"
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some owner then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

private theorem except_bind_ok_iff (action : Except ε α) (next : α → Except ε β) (result : β) :
    (action >>= next) = .ok result ↔ ∃ value, action = .ok value ∧ next value = .ok result := by
  cases action <;> simp [bind, Except.bind]

private theorem finish_admitted (h : finish collected = .ok snapshot) :
    ∃ input, admit input = .ok snapshot.registry := by
  simp only [finish] at h
  split at h
  · simp only [except_bind_ok_iff] at h
    rcases h with ⟨candidate, _, input, _, registry, admitted, h⟩
    cases h
    exact ⟨input, admitted⟩
  · simp [bind, Except.bind, throw] at h

/-- The real pure capture entry point returns a registry admitted from exactly
its retained contributions. This does not authenticate supplied observations. -/
theorem evaluate_admitted {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (h : evaluate p observations = .ok snapshot) :
    admit snapshot.registry.contributions = .ok snapshot.registry := by
  simp only [evaluate, except_bind_ok_iff] at h
  rcases h with ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, collected, _, finished⟩
  obtain ⟨input, admitted⟩ := finish_admitted finished
  rw [(admit_sources admitted).contributions]
  exact admitted

/-- The rendering assessment cannot upgrade the admitted contract result. -/
theorem Snapshot.assessment_complete_result (snapshot : Snapshot)
    (complete : (snapshot.assessmentFor label).requiredComplete = true) :
    (snapshot.registry.resultFor (.realization ⟨label, `lean⟩)).complete = true := by
  change (_ && _ : Bool) = true at complete
  simp only [Bool.and_eq_true] at complete
  exact complete.2

/-- A native completion assessment requires a nonempty native realization. -/
theorem Snapshot.assessment_complete_native (snapshot : Snapshot)
    (complete : (snapshot.assessmentFor label).requiredComplete = true) :
    ∃ realization, snapshot.registry.realization? ⟨label, `lean⟩ = some realization ∧
      realization.context.language = `lean ∧ realization.declarations.isEmpty = false := by
  change ((!((((snapshot.registry.realization? ⟨label, `lean⟩).filter
    (·.context.language == `lean)).map (·.declarations)).getD #[]).isEmpty) && _) = true at complete
  simp only [Bool.and_eq_true] at complete
  have nonempty := complete.1
  cases found : snapshot.registry.realization? ⟨label, `lean⟩ with
  | none => simp [found] at nonempty
  | some realization =>
    by_cases native : realization.context.language = `lean
    · exact ⟨realization, rfl, native, by simpa [found, Option.filter, native] using nonempty⟩
    · simp [found, Option.filter, native] at nonempty

/-- Completion shown by the real capture assessment has original fitting evidence
for each selected contract, at the binding of that same captured registry. -/
theorem evaluate_assessment_evidence {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (complete : (snapshot.assessmentFor label).requiredComplete = true)
    (selected : key ∈ snapshot.registry.requiredFor (.realization ⟨label, `lean⟩)) :
    ∃ requirement ∈ snapshot.registry.contributions.requirements,
      ∃ evidence ∈ snapshot.registry.contributions.evidence,
        snapshot.registry.requirement? key = some requirement.value ∧ requirement.value.key = key ∧
        evidence.value.Fits requirement.value ((snapshot.registry.bindingFor key).getD "") :=
  admit_complete_selected_evidence (evaluate_admitted evaluated)
    (snapshot.assessment_complete_result complete) selected

private theorem local_check_complete (snapshot : Snapshot)
    (selected : snapshot.registry.realization? ⟨label, `lean⟩ = some realization)
    (native : realization.context.language = `lean)
    (member : declaration ∈ realization.declarations)
    (complete : ((!((((snapshot.registry.realization? ⟨label, `lean⟩).filter
        (·.context.language == `lean)).map (·.declarations)).getD #[]).isEmpty) &&
      ((((snapshot.registry.realization? ⟨label, `lean⟩).filter
        (·.context.language == `lean)).map (·.declarations)).getD #[]).all fun declaration =>
          (snapshot.registry.requirement? ⟨.declaration ⟨label, `lean⟩ declaration.object, name⟩).any
            (fun value => value.expected == .check validator && value.coverage == .dependencyClosure) &&
          (snapshot.registry.localResult ⟨.declaration ⟨label, `lean⟩ declaration.object, name⟩).complete) = true) :
    ∃ requirement, snapshot.registry.requirement? ⟨.declaration ⟨label, `lean⟩ declaration.object, name⟩ = some requirement ∧
      requirement.expected = .check validator ∧ requirement.coverage = .dependencyClosure ∧
      (snapshot.registry.localResult ⟨.declaration ⟨label, `lean⟩ declaration.object, name⟩).complete = true := by
  simp only [selected, Option.filter, native, beq_self_eq_true, ↓reduceIte,
    Option.map_some, Option.getD_some, Bool.and_eq_true] at complete
  have own := Array.all_eq_true'.mp complete.2 declaration member
  cases found : snapshot.registry.requirement? ⟨.declaration ⟨label, `lean⟩ declaration.object, name⟩ with
  | none => simp [found] at own
  | some requirement =>
    simp only [found, Option.any_some, Bool.and_eq_true, beq_iff_eq] at own
    exact ⟨requirement, rfl, own.1.1, own.1.2, own.2⟩


/-- The native statement flag is supported by a fitting observation for every
selected native declaration, with the exact validator and closure coverage.
It does not assert independent-goal proof or prerequisite completion. -/
theorem evaluate_native_statement_evidence {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (selected : snapshot.registry.realization? ⟨label, `lean⟩ = some realization)
    (native : realization.context.language = `lean)
    (member : declaration ∈ realization.declarations)
    (complete : (snapshot.assessmentFor label).nativeStatementComplete = true) :
    ∃ requirement ∈ snapshot.registry.contributions.requirements,
      ∃ evidence ∈ snapshot.registry.contributions.evidence,
        requirement.value.key = ⟨.declaration ⟨label, `lean⟩ declaration.object, `statement⟩ ∧
        requirement.value.expected = .check NativeLean.statementValidator ∧
        requirement.value.coverage = .dependencyClosure ∧
        evidence.value.Fits requirement.value
          ((snapshot.registry.bindingFor requirement.value.key).getD "") := by
  obtain ⟨requirement, found, expected, coverage, own⟩ :=
    local_check_complete snapshot selected native member complete
  obtain ⟨record, hr, evidence, he, lookup, key, fits⟩ :=
    admit_local_complete_evidence (evaluate_admitted evaluated) own
  have same := Option.some.inj (found.symm.trans lookup)
  subst requirement
  exact ⟨record, hr, evidence, he, key, expected, coverage, by simpa [key] using fits⟩

/-- The native proof flag is supported by a fitting observation for every
selected native declaration, with the exact validator and closure coverage.
It does not assert independent-goal proof or prerequisite completion. -/
theorem evaluate_native_proof_evidence {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (selected : snapshot.registry.realization? ⟨label, `lean⟩ = some realization)
    (native : realization.context.language = `lean)
    (member : declaration ∈ realization.declarations)
    (complete : (snapshot.assessmentFor label).nativeProofComplete = true) :
    ∃ requirement ∈ snapshot.registry.contributions.requirements,
      ∃ evidence ∈ snapshot.registry.contributions.evidence,
        requirement.value.key = ⟨.declaration ⟨label, `lean⟩ declaration.object, `proof⟩ ∧
        requirement.value.expected = .check NativeLean.bodyValidator ∧
        requirement.value.coverage = .dependencyClosure ∧
        evidence.value.Fits requirement.value
          ((snapshot.registry.bindingFor requirement.value.key).getD "") := by
  obtain ⟨requirement, found, expected, coverage, own⟩ :=
    local_check_complete snapshot selected native member complete
  obtain ⟨record, hr, evidence, he, lookup, key, fits⟩ :=
    admit_local_complete_evidence (evaluate_admitted evaluated) own
  have same := Option.some.inj (found.symm.trans lookup)
  subst requirement
  exact ⟨record, hr, evidence, he, key, expected, coverage, by simpa [key] using fits⟩

private theorem fresh_loop_valid (entries : List α) (key : α → Nat) (value : α → β)
    (body : α → Std.HashMap Nat β → Except ε (ForInStep (Std.HashMap Nat β)))
    (accepts : ∀ entry initial step, body entry initial = .ok step →
      key entry < size ∧ initial.contains (key entry) = false ∧
        step = .yield (initial.insert (key entry) (value entry)))
    (h : forIn entries initial body = .ok final) :
    (∀ entry ∈ entries, key entry < size ∧ initial.contains (key entry) = false) ∧
      (entries.map key).Nodup := by
  induction entries generalizing initial with
  | nil => simp
  | cons entry entries ih =>
    simp only [List.forIn_cons, except_bind_ok_iff] at h
    obtain ⟨step, accepted, rest⟩ := h
    obtain ⟨bounded, fresh, rfl⟩ := accepts entry initial step accepted
    obtain ⟨tail, unique⟩ := ih rest
    constructor
    · intro other member
      rcases List.mem_cons.mp member with rfl | member
      · exact ⟨bounded, fresh⟩
      · have safe := tail other member
        simp only [Std.HashMap.contains_insert, Bool.or_eq_false_iff] at safe
        exact ⟨safe.1, safe.2.2⟩
    · simp only [List.map_cons, List.nodup_cons]
      refine ⟨?_, unique⟩
      intro member
      obtain ⟨other, member, same⟩ := List.mem_map.mp member
      have safe := (tail other member).2
      simp [Std.HashMap.contains_insert, same] at safe

private theorem indexResults_valid {p : Plan} {request : Type}
    {entries : Array (ResultEntry p request α)}
    (h : indexResults family size entries = .ok table) :
    (∀ entry ∈ entries, entry.handle < size) ∧ (entries.toList.map (·.handle)).Nodup := by
  simp only [indexResults, except_bind_ok_iff] at h
  obtain ⟨result, loop, _⟩ := h
  rw [← Array.forIn_toList] at loop
  have valid := fresh_loop_valid entries.toList (·.handle) (·.result) _ (size := size) ?_ loop
  · exact ⟨fun entry member => (valid.1 entry (by simpa using member)).1, valid.2⟩
  · intro entry initial step accepted
    split at accepted
    · simp [bind, Except.bind, throw] at accepted
    · rename_i bounded
      split at accepted
      · simp [bind, Except.bind, throw] at accepted
      · rename_i fresh
        cases accepted
        exact ⟨by omega, Bool.eq_false_iff.mpr fresh, rfl⟩

/-- One observation per handle, with every handle belonging to its plan family.
This says nothing about truth of an observation or whether every job was used. -/
def ResultEntry.ValidHandles {p : Plan} {request : Type} (size : Nat)
    (entries : Array (ResultEntry p request α)) : Prop :=
  (∀ entry ∈ entries, entry.handle < size) ∧ (entries.toList.map (·.handle)).Nodup

/-- The shape checks applied to all seven observation families by evaluation.
The plan index alone does not enforce these bounds or uniqueness. -/
structure Observations.ValidHandles {p : Plan} (observations : Observations p) : Prop where
  documents : ResultEntry.ValidHandles p.documents.size observations.documents
  native : ResultEntry.ValidHandles p.native.size observations.native
  inline : ResultEntry.ValidHandles p.inline.size observations.inline
  documented : ResultEntry.ValidHandles p.documented.size observations.documented
  checks : ResultEntry.ValidHandles p.checks.size observations.checks
  specifications : ResultEntry.ValidHandles p.specifications.size observations.specifications
  expected : ResultEntry.ValidHandles p.expected.size observations.expected

/-- Successful production evaluation rejects duplicate or out-of-range handles
in every observation family, even when duplicate entries carry equal payloads. -/
theorem evaluate_valid_handles {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (h : evaluate p observations = .ok snapshot) : observations.ValidHandles := by
  simp only [evaluate, except_bind_ok_iff] at h
  rcases h with ⟨_, documents, _, native, _, inline, _, documented, _, checks,
    _, specifications, _, expected, _⟩
  exact ⟨indexResults_valid documents, indexResults_valid native, indexResults_valid inline,
    indexResults_valid documented, indexResults_valid checks, indexResults_valid specifications,
    indexResults_valid expected⟩

end Informal.Realizations.Capture
