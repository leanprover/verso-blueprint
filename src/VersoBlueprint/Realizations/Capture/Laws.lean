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

/-- Main pure-capture completion guarantee. A completed rendering assessment
selects a nonempty contract. Every selected obligation has a well-founded
prerequisite justification, and the obligation itself and every transitive
prerequisite have original fitting evidence at their own current bindings.
This is soundness of reported completion, not completeness of the graph traversal
or authentication of the supplied observations. -/
theorem evaluate_assessment_justified {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (complete : (snapshot.assessmentFor label).requiredComplete = true) :
    (snapshot.registry.requiredFor (.realization ⟨label, `lean⟩)).isEmpty = false ∧
    ∀ key ∈ snapshot.registry.requiredFor (.realization ⟨label, `lean⟩),
      Acc snapshot.registry.Prerequisite key ∧
      ∀ dependency, dependency = key ∨ Relation.TransGen snapshot.registry.Prerequisite dependency key →
        ∃ requirement ∈ snapshot.registry.contributions.requirements,
          ∃ evidence ∈ snapshot.registry.contributions.evidence,
            snapshot.registry.requirement? dependency = some requirement.value ∧
            requirement.value.key = dependency ∧
            evidence.value.Fits requirement.value ((snapshot.registry.bindingFor dependency).getD "") := by
  have admitted := evaluate_admitted evaluated
  have selected := snapshot.registry.complete_requires_all _
    (snapshot.assessment_complete_result complete)
  refine ⟨selected.1, ?_⟩
  intro key member
  have completed := selected.2 key member
  refine ⟨admit_complete_accessible admitted completed, ?_⟩
  intro dependency reachable
  rcases reachable with rfl | path
  · exact admit_complete_requirement_evidence admitted completed
  · exact admit_complete_prerequisites_evidence admitted completed path

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

private theorem fresh_loop_membership (entries : List α) (key : α → Nat) (value : α → β)
    (body : α → Std.HashMap Nat β → Except ε (ForInStep (Std.HashMap Nat β)))
    (accepts : ∀ entry initial step, body entry initial = .ok step →
      initial.contains (key entry) = false ∧ step = .yield (initial.insert (key entry) (value entry)))
    (h : forIn entries initial body = .ok final) (query : Nat) (result : β) :
    final[query]? = some result ↔ initial[query]? = some result ∨
      ∃ entry ∈ entries, key entry = query ∧ value entry = result := by
  induction entries generalizing initial with
  | nil => cases h; simp
  | cons entry entries ih =>
    simp only [List.forIn_cons, except_bind_ok_iff] at h
    obtain ⟨step, accepted, rest⟩ := h
    obtain ⟨fresh, rfl⟩ := accepts entry initial step accepted
    rw [ih rest, Std.HashMap.getElem?_insert]
    have absent := Std.HashMap.getElem?_eq_none_of_contains_eq_false fresh
    by_cases same : key entry = query
    · rw [same] at absent
      simp [same, absent]
    · simp [same]

/-- The actual observation index preserves exactly the supplied handle/result
pairs. Even equal repeated entries must first pass its distinct-handle check;
no accepted result can be invented or overwritten by the table construction. -/
theorem indexResults_lookup_iff {p : Plan} {request : Type}
    {entries : Array (ResultEntry p request α)}
    (indexed : indexResults family size entries = .ok table) (handle : Nat) (result : α) :
    table[handle]? = some result ↔
      ∃ entry ∈ entries, entry.handle = handle ∧ entry.result = result := by
  simp only [indexResults, except_bind_ok_iff] at indexed
  obtain ⟨final, loop, same⟩ := indexed
  cases same
  rw [← Array.forIn_toList] at loop
  have exactResult := fresh_loop_membership entries.toList (·.handle) (·.result) _ ?_ loop handle result
  · simpa using exactResult
  · intro entry initial step accepted
    split at accepted
    · simp [bind, Except.bind, throw] at accepted
    · split at accepted
      · simp [bind, Except.bind, throw] at accepted
      · rename_i fresh
        cases accepted
        exact ⟨Bool.eq_false_iff.mpr fresh, rfl⟩

private theorem fresh_loop_exists (entries : List α) (key : α → Nat) (value : α → β)
    (body : α → Std.HashMap Nat β → Except ε (ForInStep (Std.HashMap Nat β)))
    (accepts : ∀ entry initial, key entry < size → initial.contains (key entry) = false →
      body entry initial = .ok (.yield (initial.insert (key entry) (value entry))))
    (bounded : ∀ entry ∈ entries, key entry < size)
    (distinct : (entries.map key).Nodup)
    (fresh : ∀ entry ∈ entries, initial.contains (key entry) = false) :
    ∃ final, forIn entries initial body = .ok final := by
  induction entries generalizing initial with
  | nil => exact ⟨initial, rfl⟩
  | cons entry entries ih =>
    have unique := List.nodup_cons.mp distinct
    have safe := accepts entry initial (bounded entry (by simp)) (fresh entry (by simp))
    obtain ⟨final, finished⟩ := ih (initial := initial.insert (key entry) (value entry))
      (fun other member => bounded other (by simp [member])) unique.2 (by
        intro other member
        have different : key entry ≠ key other := by
          intro same
          exact unique.1 (List.mem_map.mpr ⟨other, member, same.symm⟩)
        simp [Std.HashMap.contains_insert, different, fresh other (by simp [member])])
    refine ⟨final, ?_⟩
    simp only [List.forIn_cons, safe, bind, Except.bind]
    exact finished

/-- Table construction accepts exactly the bounded, unique-handle batches.
This is the real evaluator's indexing gate in both directions, not an assumption
about a prevalidated batch or the truth of a supplied observation. -/
theorem indexResults_success_iff {p : Plan} {request : Type}
    (entries : Array (ResultEntry p request α)) (family : String) (size : Nat) :
    (∃ table, indexResults family size entries = .ok table) ↔ ResultEntry.ValidHandles size entries := by
  constructor
  · rintro ⟨table, indexed⟩
    exact indexResults_valid indexed
  · rintro ⟨bounded, distinct⟩
    simp only [indexResults, ← Array.forIn_toList]
    have constructed := fresh_loop_exists (ε := Array Diagnostic) entries.toList (·.handle) (·.result)
      (fun entry table => do
        if entry.handle >= size then throw (batchIssue "extraneous-observation" family entry.handle)
        if table.contains entry.handle then throw (batchIssue "duplicate-observation" family entry.handle)
        pure (.yield (table.insert entry.handle entry.result)))
      (size := size) ?_ (fun entry member => bounded entry (by simpa using member)) distinct
      (initial := {}) (by simp)
    · obtain ⟨table, finished⟩ := constructed
      simp only [bind, Except.bind, pure, Except.pure] at finished
      exact ⟨table, by simp only [bind, Except.bind, pure, Except.pure, finished]⟩
    · intro entry initial bound fresh
      simp [fresh, Nat.not_le_of_gt bound, pure, Except.pure]

/-- The provider adapter returns exactly an original result for the requested
handle. A missing handle cannot silently acquire a default observation. -/
theorem lookupResult_success_iff {p : Plan} {request : Type}
    {entries : Array (ResultEntry p request α)}
    (indexed : indexResults family size entries = .ok table) (handle : Nat) (result : α) :
    (lookupResult family table handle).run = .ok result ↔
      ∃ entry ∈ entries, entry.handle = handle ∧ entry.result = result := by
  rw [← indexResults_lookup_iff indexed]
  unfold lookupResult full
  cases found : table[handle]? with
  | none => simp [found, pure]
  | some value =>
    simp only [Std.HashMap.get?_eq_getElem?, found, Option.some.injEq]
    change (Except.ok value : Except (Array Diagnostic) α) = .ok result ↔ value = result
    simp only [Except.ok.injEq]

/-- Observation order cannot change whether the actual indexing gate accepts.
In-range uniqueness is preserved by permutations, including repeated payloads. -/
theorem indexResults_success_permutation {p : Plan} {request : Type}
    (left right : Array (ResultEntry p request α)) (order : left.toList.Perm right.toList)
    (family : String) (size : Nat) :
    (∃ table, indexResults family size left = .ok table) ↔
      ∃ table, indexResults family size right = .ok table := by
  rw [indexResults_success_iff, indexResults_success_iff]
  unfold ResultEntry.ValidHandles
  have bounded : (∀ entry ∈ left, entry.handle < size) ↔ ∀ entry ∈ right, entry.handle < size := by
    constructor
    · intro valid entry member
      exact valid entry (by simpa using order.mem_iff.mpr (by simpa using member))
    · intro valid entry member
      exact valid entry (by simpa using order.mem_iff.mp (by simpa using member))
  exact and_congr bounded (order.map (·.handle)).nodup_iff

/-- Accepted permutations have identical observations at every handle. The law
compares lookup results, not an order-sensitive internal hash-table layout. -/
theorem indexResults_lookup_permutation {p : Plan} {request : Type}
    {left right : Array (ResultEntry p request α)} (order : left.toList.Perm right.toList)
    (acceptedLeft : indexResults family size left = .ok first)
    (acceptedRight : indexResults family size right = .ok second) (handle : Nat) :
    first[handle]? = second[handle]? := by
  have same (value : α) : first[handle]? = some value ↔ second[handle]? = some value := by
    rw [indexResults_lookup_iff acceptedLeft, indexResults_lookup_iff acceptedRight]
    constructor
    · rintro ⟨entry, member, rest⟩
      exact ⟨entry, by simpa using order.mem_iff.mp (by simpa using member), rest⟩
    · rintro ⟨entry, member, rest⟩
      exact ⟨entry, by simpa using order.mem_iff.mpr (by simpa using member), rest⟩
  cases firstFound : first[handle]? with
  | none =>
    cases secondFound : second[handle]? with
    | none => rfl
    | some value => have present := (same value).mpr secondFound; simp [firstFound] at present
  | some value => exact ((same value).mp firstFound).symm


/-- The record produced by binding one collected observation. This specification
retains the whole origin and observation; it does not assert provider authenticity. -/
def boundObservation (registry : Registry) (entry : Origin × RequirementKey × Observation) :
    Contribution Evidence := {
  origin := entry.1
  value := {
    id := entry.1.id, requirement := entry.2.1
    binding := (registry.bindingFor entry.2.1).getD "", observation := entry.2.2 } }

private theorem binding_loop (entries : List (Origin × RequirementKey × Observation))
    (candidate : Registry) (initial : Input)
    (body : (Origin × RequirementKey × Observation) → Input →
      Except (Array Diagnostic) (ForInStep Input))
    (step : ∀ entry input result, body entry input = .ok result →
      (candidate.bindingFor entry.2.1).isSome = true ∧
      result = .yield { input with evidence := input.evidence.push (boundObservation candidate entry) })
    (accepted : forIn entries initial body = .ok final) :
    final = { initial with evidence := initial.evidence ++ entries.toArray.map (boundObservation candidate) } ∧
      ∀ entry ∈ entries, (candidate.bindingFor entry.2.1).isSome = true := by
  induction entries generalizing initial with
  | nil => cases accepted; simp
  | cons entry entries ih =>
    simp only [List.forIn_cons, except_bind_ok_iff] at accepted
    obtain ⟨result, first, rest⟩ := accepted
    obtain ⟨bound, rfl⟩ := step entry initial result first
    obtain ⟨output, tail⟩ := ih _ rest
    refine ⟨?_, ?_⟩
    · rw [output]
      congr 1
      apply Array.toList_inj.mp
      simp
    · intro other member
      rcases List.mem_cons.mp member with rfl | member
      · exact bound
      · exact tail other member

private theorem finish_bound_input (accepted : finish collected = .ok snapshot) :
    let linked := connectUses collected (selectUses collected)
    ∃ candidate,
      admit (Collected.input linked) = .ok candidate ∧
      admit { (Collected.input linked) with
        evidence := (Collected.input linked).evidence ++ (Collected.observations linked).map (boundObservation candidate) } = .ok snapshot.registry ∧
      ∀ entry ∈ (Collected.observations linked), (candidate.bindingFor entry.2.1).isSome = true := by
  simp only [finish] at accepted
  split at accepted
  · simp only [except_bind_ok_iff] at accepted
    obtain ⟨candidate, admitted, input, loop, registry, finalAdmission, result⟩ := accepted
    cases result
    rw [← Array.forIn_toList] at loop
    have projected := binding_loop _ candidate _ _ ?_ loop
    · obtain ⟨output, bounded⟩ := projected
      refine ⟨candidate, admitted, ?_, ?_⟩
      · simpa only [output, Array.toArray_toList] using finalAdmission
      · intro entry member
        exact bounded entry (by simpa using member)
    · intro entry input result step
      rcases entry with ⟨origin, key, observation⟩
      split at step
      · rename_i binding found
        cases step
        exact ⟨by simp [found], by simp [boundObservation, found]⟩
      · cases step
  · simp [bind, Except.bind, throw] at accepted


/-- Finalization first admits the complete candidate. Adding freshly bound
observations cannot change that candidate's binding in the final admitted registry. -/
theorem finish_binding_basis (accepted : finish collected = .ok snapshot) :
    ∃ candidate, admit (Collected.input (connectUses collected (selectUses collected))) = .ok candidate ∧
      ∀ key, candidate.bindingFor key = snapshot.registry.bindingFor key := by
  obtain ⟨candidate, before, after, _⟩ := finish_bound_input accepted
  exact ⟨candidate, before, admit_bindings_evidence before after⟩

/-- The actual finalizer changes only evidence after prerequisite wiring. It
appends exactly the collected observations, preserving their order, multiplicity,
complete origins, and payloads, bound against the final admitted registry. -/
theorem finish_sources (accepted : finish collected = .ok snapshot) :
    let linked := connectUses collected (selectUses collected)
    snapshot.registry.contributions = { (Collected.input linked) with
      evidence := (Collected.input linked).evidence ++
        (Collected.observations linked).map (boundObservation snapshot.registry) } := by
  obtain ⟨candidate, before, after, _⟩ := finish_bound_input accepted
  have bindings := admit_bindings_evidence before after
  have same : boundObservation candidate = boundObservation snapshot.registry := by
    funext entry
    simp only [boundObservation, bindings]
  simpa only [same] using (admit_sources after).contributions

/-- Every final evidence record is either already part of the complete candidate
or comes from one exact collected observation. Finalization invents no payloads. -/
theorem finish_evidence_iff (accepted : finish collected = .ok snapshot) (record : Contribution Evidence) :
    let linked := connectUses collected (selectUses collected)
    record ∈ snapshot.registry.contributions.evidence ↔
      record ∈ (Collected.input linked).evidence ∨
      ∃ entry ∈ (Collected.observations linked), boundObservation snapshot.registry entry = record := by
  rw [finish_sources accepted]
  simp only [Array.mem_append, Array.mem_map]

/-- Every observation bound by the finalizer has a real, current binding. The
empty fallback in the specification is never used on an accepted observation. -/
theorem finish_observation_current (accepted : finish collected = .ok snapshot)
    (member : entry ∈ Collected.observations (connectUses collected (selectUses collected))) :
    snapshot.registry.bindingFor entry.2.1 =
      some (boundObservation snapshot.registry entry).value.binding ∧
    boundObservation snapshot.registry entry ∈ snapshot.registry.contributions.evidence := by
  obtain ⟨candidate, before, after, bounded⟩ := finish_bound_input accepted
  have current := bounded entry member
  rw [admit_bindings_evidence before after] at current
  refine ⟨?_, (finish_evidence_iff accepted _).mpr (Or.inr ⟨entry, member, rfl⟩)⟩
  cases found : snapshot.registry.bindingFor entry.2.1 with
  | none => simp [found] at current
  | some binding => simp [boundObservation, found]

end Informal.Realizations.Capture
