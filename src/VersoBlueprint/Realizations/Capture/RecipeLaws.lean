/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.Laws

/-! Native provider provenance through the actual collection recipe and final
admitted evidence. Provider authenticity and plan construction are separate. -/

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
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some captureOwner || env.getModuleIdxFor? name == some lawsOwner then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

private theorem exceptT_bind_ok_iff (action : ExceptT ε Id α) (next : α → ExceptT ε Id β) (result : β) :
    (action >>= next).run = .ok result ↔ ∃ value, action.run = .ok value ∧ (next value).run = .ok result := by
  cases action with
  | error error => simp [bind, ExceptT.bind, ExceptT.bindCont, ExceptT.run, ExceptT.mk, pure]
  | ok value =>
    change (next value).run = .ok result ↔ ∃ other, (Except.ok value : Except ε α) = .ok other ∧ (next other).run = .ok result
    simp only [Except.ok.injEq, exists_eq_left']

private theorem list_loop_invariant (entries : List α) (property : β → Prop)
    (body : α → β → ExceptT ε Id (ForInStep β))
    (initialValid : property initial)
    (step : ∀ entry ∈ entries, ∀ current result, property current → (body entry current).run = .ok result →
      match result with | .yield next => property next | .done next => property next)
    (accepted : (forIn entries initial body).run = .ok final) : property final := by
  induction entries generalizing initial with
  | nil => cases accepted; exact initialValid
  | cons entry entries ih =>
    simp only [List.forIn_cons, exceptT_bind_ok_iff] at accepted
    obtain ⟨result, first, rest⟩ := accepted
    have preserved := step entry (by simp) initial result initialValid first
    cases result with
    | done next => cases rest; exact preserved
    | yield next =>
      exact ih preserved (fun item member => step item (by simp [member])) rest

private theorem array_loop_invariant (entries : Array α) (property : β → Prop)
    (body : α → β → ExceptT ε Id (ForInStep β))
    (initialValid : property initial)
    (step : ∀ entry ∈ entries, ∀ current result, property current → (body entry current).run = .ok result →
      match result with | .yield next => property next | .done next => property next)
    (accepted : (forIn entries initial body).run = .ok final) : property final := by
  rw [← Array.forIn_toList] at accepted
  exact list_loop_invariant entries.toList property body initialValid
    (fun entry member => step entry (by simpa using member)) accepted

private def ChecksFrom (providers : Providers Id) (collected : Collected) : Prop :=
  ∀ checked ∈ Collected.nativeChecks collected,
    ∃ handle, (Providers.check providers handle).run = .ok (.ok checked)

/-- Recipe-generated non-native checks and unavailable fallbacks are distinct
from native provider observations. The successful-native case retains full fields. -/
private def ObservationFrom (providers : Providers Id) : Observation → Prop
  | .proof _ => True
  | .review _ => False
  | .check observation => observation.outcome = .unavailable ∨
      observation.validator = `blueprint.dependencySelection ∨
      ∃ handle checked, (Providers.check providers handle).run = .ok (.ok checked) ∧
        (observation = checked.statement ∨ observation = checked.body)

private def CollectionFrom (providers : Providers Id) (collected : Collected) : Prop :=
  ChecksFrom providers collected ∧
    (∀ entry ∈ Collected.observations collected, ObservationFrom providers entry.2.2) ∧
    (Collected.input collected).evidence = #[]

private theorem recordObservation_from (prior : CollectionFrom providers collected)
    (allowed : ObservationFrom providers observation) :
    CollectionFrom providers (recordObservation collected key observation) := by
  refine ⟨prior.1, ?_, prior.2.2⟩
  intro entry member
  simp only [recordObservation, Array.mem_push] at member
  rcases member with original | rfl
  · exact prior.2.1 entry original
  · exact allowed

private theorem collectOrdinary_from (providers : Providers Id) (p : Plan)
    (accepted : (collectOrdinary providers p).run = .ok collected) : CollectionFrom providers collected := by
  simp only [collectOrdinary, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  apply array_loop_invariant p.ordinary (CollectionFrom providers) _ (by simp [CollectionFrom, ChecksFrom]) ?_ loop
  intro node member current result prior step
  by_cases absent : (!p.raw.pending.contains node.label) = true
  · rw [ite_eq_left absent] at step
    simp only [exceptT_bind_ok_iff] at step
    obtain ⟨_, impossible, _⟩ := step
    cases impossible
  · rw [ite_eq_right absent] at step
    cases resolved : Contributions.resolve node.label p.raw.facts with
    | error diagnostics =>
      rw [resolved] at step
      simp only [exceptT_bind_ok_iff] at step
      obtain ⟨_, impossible, _⟩ := step
      cases impossible
    | ok view =>
      rw [resolved] at step
      simp only [exceptT_bind_ok_iff] at step
      obtain ⟨next, realizations, finished⟩ := step
      have nextValid : CollectionFrom providers next := by
        refine array_loop_invariant node.realizations (CollectionFrom providers) _ ?_ ?_ realizations
        · exact prior
        · intro realization member current result prior step
          -- Rewrite the outer guard without normalizing unrelated recipe branches.
          apply Classical.byCases (p := _)
          · intro contextValid
            rw [ite_eq_left contextValid] at step
            apply Classical.byCases (p := _)
            · intro sourcesValid
              rw [ite_eq_left sourcesValid] at step
              simp only [exceptT_bind_ok_iff] at step
              obtain ⟨sourced, sources, declared, declarations, finished⟩ := step
              have sourceValid : CollectionFrom providers sourced.1 := by
                refine array_loop_invariant realization.sources (fun pair => CollectionFrom providers pair.1) _ ?_ ?_ sources
                · exact prior
                · intro source member pair result prior step
                  clear loop realizations sources declarations finished
                  repeat' first
                    | (cases step; exact prior)
                    | (simp only [exceptT_bind_ok_iff] at step; obtain ⟨value, returned, step⟩ := step)
                    | split at step
              have declarationValid : CollectionFrom providers declared.1 := by
                refine array_loop_invariant realization.declarations (fun pair => CollectionFrom providers pair.1) _ sourceValid ?_ declarations
                intro declaration member pair result prior step
                clear loop realizations sources declarations finished
                simp only [exceptT_bind_ok_iff] at step
                obtain ⟨prepared, _, step⟩ := step
                cases prepared <;> simp only [exceptT_bind_ok_iff] at step
                all_goals
                  obtain ⟨observation, _, checkedResult, returned, step⟩ := step
                  cases checkedResult with
                  | ok checked =>
                    cases step
                    apply recordObservation_from
                    · apply recordObservation_from
                      · refine ⟨?_, prior.2.1, prior.2.2⟩
                        intro item member
                        simp only [Array.mem_push] at member
                        rcases member with previous | rfl
                        · exact prior.1 item previous
                        · exact ⟨declaration.check, returned⟩
                      · exact Or.inr (Or.inr ⟨declaration.check, checked, returned, Or.inl rfl⟩)
                    · exact Or.inr (Or.inr ⟨declaration.check, checked, returned, Or.inr rfl⟩)
                  | error diagnostic =>
                    simp only [exceptT_bind_ok_iff] at step
                    obtain ⟨next, unavailable, finished⟩ := step
                    have valid : CollectionFrom providers next := by
                      refine array_loop_invariant _ (CollectionFrom providers) _ ?_ ?_ unavailable
                      · exact prior
                      · intro entry member current result prior step
                        cases step
                        exact recordObservation_from prior (Or.inl rfl)
                    cases finished
                    exact valid
              cases finished
              exact declarationValid
            · intro sourcesInvalid
              rw [ite_eq_right sourcesInvalid] at step
              simp only [exceptT_bind_ok_iff] at step
              obtain ⟨_, impossible, _⟩ := step
              cases impossible
          · intro contextInvalid
            rw [ite_eq_right contextInvalid] at step
            simp only [exceptT_bind_ok_iff] at step
            obtain ⟨_, impossible, _⟩ := step
            cases impossible
      split at finished
      · cases finished; exact nextValid
      · simp only [exceptT_bind_ok_iff] at finished
        obtain ⟨_, impossible, _⟩ := finished
        cases impossible


private theorem collectAuthored_from (providers : Providers Id) (p : Plan)
    (initialValid : CollectionFrom providers initial)
    (accepted : (collectAuthored providers p initial).run = .ok collected) :
    CollectionFrom providers collected := by
  simp only [collectAuthored, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  refine array_loop_invariant p.authored (CollectionFrom providers)
    _ initialValid ?_ loop
  intro authored member current result prior step
  simp only [exceptT_bind_ok_iff] at step
  obtain ⟨goals, goalLoop, sourced, sourceLoop, finished⟩ := step
  have goalsValid : CollectionFrom providers goals := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at goalLoop
    refine list_loop_invariant _ (CollectionFrom providers)
      _ prior ?_ goalLoop
    intro index member current result prior step
    clear loop goalLoop sourceLoop finished
    apply Classical.byCases (p := _)
    · intro shapeValid
      rw [ite_eq_left shapeValid] at step
      simp only [exceptT_bind_ok_iff] at step
      obtain ⟨document, _, step⟩ := step
      apply Classical.byCases (p := _)
      · intro documentValid
        rw [ite_eq_left documentValid] at step
        simp only [exceptT_bind_ok_iff] at step
        obtain ⟨_, _, _, _, _, _, _, _, finished⟩ := step
        cases finished
        refine ⟨prior.1, ?_, prior.2.2⟩
        intro entry member
        simp only [Array.mem_push] at member
        rcases member with original | rfl
        · exact prior.2.1 entry original
        · trivial
      · intro documentInvalid
        rw [ite_eq_right documentInvalid] at step
        simp only [exceptT_bind_ok_iff] at step
        obtain ⟨_, impossible, _⟩ := step
        cases impossible
    · intro shapeInvalid
      rw [ite_eq_right shapeInvalid] at step
      simp only [exceptT_bind_ok_iff] at step
      obtain ⟨_, impossible, _⟩ := step
      cases impossible
  have sourcesValid : CollectionFrom providers sourced := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at sourceLoop
    refine list_loop_invariant _ (CollectionFrom providers)
      _ goalsValid ?_ sourceLoop
    intro index member current result prior step
    simp only [exceptT_bind_ok_iff] at step
    obtain ⟨_, _, step⟩ := step
    cases step
    exact prior
  cases finished
  exact sourcesValid

private theorem assemble_from (providers : Providers Id) (p : Plan)
    (accepted : (assemble providers p).run = .ok collected) : CollectionFrom providers collected := by
  simp only [assemble] at accepted
  split at accepted
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨ordinary, ordinaryOk, authoredOk⟩ := accepted
    exact collectAuthored_from providers p (collectOrdinary_from providers p ordinaryOk) authoredOk
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨_, impossible, _⟩ := accepted
    cases impossible

private theorem id_list_loop_invariant (entries : List α) (property : β → Prop)
    (body : α → β → Id (ForInStep β)) (initialValid : property initial)
    (step : ∀ entry ∈ entries, ∀ current, property current →
      match body entry current with | .yield next => property next | .done next => property next) :
    property (forIn entries initial body) := by
  induction entries generalizing initial with
  | nil => exact initialValid
  | cons entry entries ih =>
    have preserved := step entry (by simp) initial initialValid
    cases executed : body entry initial with
    | done next => simpa only [List.forIn_cons, executed, bind, pure] using preserved
    | yield next =>
      simp only [executed] at preserved
      simpa only [List.forIn_cons, executed, bind] using
        ih preserved (fun item member => step item (by simp [member]))

private theorem id_array_loop_invariant (entries : Array α) (property : β → Prop)
    (body : α → β → Id (ForInStep β)) (initialValid : property initial)
    (step : ∀ entry ∈ entries, ∀ current, property current →
      match body entry current with | .yield next => property next | .done next => property next) :
    property (forIn entries initial body) := by
  rw [← Array.forIn_toList]
  exact id_list_loop_invariant entries.toList property body initialValid
    (fun entry member => step entry (by simpa using member))

private theorem connectUses_properties (collected : Collected) (uses : Array SelectedUse) :
    Collected.nativeChecks (connectUses collected uses) = Collected.nativeChecks collected ∧
      ∀ providers, CollectionFrom providers collected → CollectionFrom providers (connectUses collected uses) := by
  let invariant (current : Collected) : Prop :=
    Collected.nativeChecks current = Collected.nativeChecks collected ∧
      ∀ providers, CollectionFrom providers collected → CollectionFrom providers current
  unfold connectUses
  simp only [Id.run, bind, pure]
  apply id_array_loop_invariant _ invariant _ ⟨rfl, fun _ valid => valid⟩
  intro model member current prior
  by_cases foreign : (model.context.language != `lean) = true
  · rw [ite_eq_left foreign]
    exact prior
  · rw [ite_eq_right foreign]
    apply id_array_loop_invariant _ invariant _ prior
    intro declaration member current prior
    apply id_array_loop_invariant _ invariant _ prior
    intro entry member current prior
    apply Classical.byCases (p := _)
    · intro owns
      rw [ite_eq_left owns]
      by_cases proof : (entry.1 == `proof) = true <;>
        (first | rw [ite_eq_left proof] | rw [ite_eq_right proof])
      all_goals
        apply Classical.byCases (p := _)
        · intro edges
          rw [ite_eq_left edges]
          refine ⟨prior.1, ?_⟩
          intro providers valid
          exact recordObservation_from (prior.2 providers valid) (Or.inr (Or.inl rfl))
        · intro edges; rw [ite_eq_right edges]; exact prior
    · intro foreign; rw [ite_eq_right foreign]; exact prior


private theorem connectUses_nativeChecks (collected : Collected) (uses : Array SelectedUse) :
    Collected.nativeChecks (connectUses collected uses) = Collected.nativeChecks collected :=
  (connectUses_properties collected uses).1

private theorem connectUses_from (collected : Collected) (uses : Array SelectedUse)
    (initialValid : CollectionFrom providers collected) :
    CollectionFrom providers (connectUses collected uses) :=
  (connectUses_properties collected uses).2 providers initialValid

/-- Final admission and dependency wiring preserve the complete native check
inventory, independently of completion status and evidence canonicalization. -/
theorem finish_nativeChecks (accepted : finish collected = .ok snapshot) :
    snapshot.nativeChecks = Collected.nativeChecks collected := by
  simp only [finish] at accepted
  split at accepted
  · simp only [except_bind_ok_iff] at accepted
    obtain ⟨_, _, _, _, _, _, result⟩ := accepted
    cases result
    exact connectUses_nativeChecks collected _
  · cases accepted

private theorem finish_observations_from (initialValid : CollectionFrom providers collected)
    (accepted : finish collected = .ok snapshot)
    (member : record ∈ snapshot.registry.contributions.evidence) :
    ObservationFrom providers record.value.observation := by
  have linked := connectUses_from collected (selectUses collected) initialValid
  rw [finish_sources accepted] at member
  simp only [Array.mem_append, Array.mem_map] at member
  rcases member with previous | ⟨entry, original, rfl⟩
  · rw [linked.2.2] at previous
    simp at previous
  · exact linked.2.1 entry original

private theorem matching_success
    (accepted : (matching family handle agrees).run = .ok result) : agrees = true := by
  cases agrees with
  | false => cases accepted
  | true => rfl

/-- Every native check retained by the public evaluator is an unchanged successful
result from the supplied batch, at a valid handle. The actual provider adapter
also checks ownership of both observations and their exact native validators.
This proves provenance and shape, not the truth of a supplied check. -/
theorem evaluate_nativeChecks_source {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot) (member : checked ∈ snapshot.nativeChecks) :
    ∃ entry ∈ observations.checks, entry.result = .ok checked ∧ entry.handle < p.checks.size ∧
      checked.declaration = p.checks[entry.handle]!.witness ∧
      checked.statement.declaration = some p.checks[entry.handle]!.witness ∧
      checked.body.declaration = some p.checks[entry.handle]!.witness ∧
      checked.statement.validator = NativeLean.statementValidator ∧
      checked.body.validator = NativeLean.bodyValidator := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨documents, _, native, _, inline, _, documented, _, checks, checksIndexed,
    specifications, _, expected, _, collected, assembled, finished⟩ := accepted
  rw [finish_nativeChecks finished] at member
  obtain ⟨handle, supplied⟩ := (assemble_from _ _ assembled).1 checked member
  simp only [exceptT_bind_ok_iff] at supplied
  obtain ⟨result, lookup, matched⟩ := supplied
  cases result with
  | error diagnostic => cases matched
  | ok value =>
    simp only [exceptT_bind_ok_iff] at matched
    obtain ⟨_, shape, output⟩ := matched
    cases output
    have shape := matching_success shape
    obtain ⟨entry, original, handleEq, resultEq⟩ :=
      (lookupResult_success_iff checksIndexed handle (.ok checked)).mp lookup
    refine ⟨entry, original, resultEq, (indexResults_valid checksIndexed).1 entry original, ?_⟩
    rw [← handleEq] at shape
    simpa only [Bool.and_eq_true, beq_iff_eq, and_assoc] using shape


/-- A passed native statement/body observation in final admitted evidence is an
unchanged field of an original successful native check result. Neither unavailable
fallbacks, authored proof observations, nor generated dependency-selection checks
can manufacture such evidence. This does not authenticate the supplied result. -/
theorem evaluate_native_evidence_source {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (member : record ∈ snapshot.registry.contributions.evidence)
    (observed : record.value.observation = .check observation)
    (passed : observation.outcome = .passed)
    (native : observation.validator = NativeLean.statementValidator ∨
      observation.validator = NativeLean.bodyValidator) :
    ∃ entry ∈ observations.checks, ∃ checked, entry.result = .ok checked ∧
      entry.handle < p.checks.size ∧
      (observation = checked.statement ∨ observation = checked.body) := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨documents, _, nativeTable, _, inline, _, documented, _, checks, checksIndexed,
    specifications, _, expected, _, collected, assembled, finished⟩ := accepted
  have source := finish_observations_from (assemble_from _ _ assembled) finished member
  rw [observed] at source
  rcases source with unavailable | policy | ⟨handle, checked, supplied, field⟩
  · rw [passed] at unavailable
    cases unavailable
  · rcases native with statement | body
    · rw [statement] at policy
      exact False.elim ((by decide : NativeLean.statementValidator ≠ `blueprint.dependencySelection) policy)
    · rw [body] at policy
      exact False.elim ((by decide : NativeLean.bodyValidator ≠ `blueprint.dependencySelection) policy)
  · simp only [exceptT_bind_ok_iff] at supplied
    obtain ⟨result, lookup, matched⟩ := supplied
    cases result with
    | error diagnostic => cases matched
    | ok value =>
      simp only [exceptT_bind_ok_iff] at matched
      obtain ⟨_, _, output⟩ := matched
      cases output
      obtain ⟨entry, original, _, resultEq⟩ :=
        (lookupResult_success_iff checksIndexed handle (.ok checked)).mp lookup
      exact ⟨entry, original, checked, resultEq,
        (indexResults_valid checksIndexed).1 entry original, field⟩

end Informal.Realizations.Capture
