/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.Laws

/-! Native and authored provider provenance through the actual collection recipe and final
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

/-- The fields a proof obligation consumes; prerequisite wiring may extend the
prerequisite list without changing these fields or the contribution's origin. -/
private def PreservesContracts (before after : Input) : Prop :=
  (∀ record ∈ before.requirements, ∃ next ∈ after.requirements,
    next.origin = record.origin ∧ next.value.key = record.value.key ∧
    next.value.expected = record.value.expected ∧ next.value.coverage = record.value.coverage) ∧
  (∀ record ∈ before.bindingInputs, record ∈ after.bindingInputs)

private theorem preservesContracts_refl (input : Input) : PreservesContracts input input := by
  exact ⟨fun record member => ⟨record, member, rfl, rfl, rfl, rfl⟩, fun _ member => member⟩

private theorem preservesContracts_append (before after : Input)
    (requirements : ∀ record ∈ before.requirements, record ∈ after.requirements)
    (bindings : ∀ record ∈ before.bindingInputs, record ∈ after.bindingInputs) :
    PreservesContracts before after :=
  ⟨fun record member => ⟨record, requirements record member, rfl, rfl, rfl, rfl⟩, bindings⟩

/-- Joint projection from one authored expected-goal result. Origins share the
same authored site; wiring may extend prerequisites but preserves the obligation's
identity, expectation and coverage. Every reported semantic context is retained. -/
def AuthoredProofProjection (input : Input) (origin : Origin) (key : RequirementKey)
    (checked : NativeLean.Checked) (witness : ObjectKey) : Prop :=
  ∃ source index,
    origin = (authoredContribution source `expectedObservation index ()).origin ∧
    (∃ requirement ∈ input.requirements,
      requirement.origin = (authoredContribution source `expectedRequirement index ()).origin ∧
      requirement.value.key = key ∧ requirement.value.expected = .proof checked.goal witness ∧
      requirement.value.coverage = .dependencyClosure) ∧
    ∀ content, checked.semanticContext = some content →
      ∃ semantic ∈ input.bindingInputs,
        semantic = authoredContribution source `expectedContext index {
          subject := key.subject, name := NativeLean.expectedContextFor key, content }

private theorem proofProjection_mono {origin : Origin} (extension : PreservesContracts before after)
    (prior : AuthoredProofProjection before origin key checked witness) :
    AuthoredProofProjection after origin key checked witness := by
  obtain ⟨source, index, originEq, ⟨requirement, member, own, keyEq, expectedEq, coverage⟩, semantic⟩ := prior
  obtain ⟨next, nextMember, nextOrigin, nextKey, nextExpected, nextCoverage⟩ := extension.1 requirement member
  refine ⟨source, index, originEq, ⟨next, nextMember, nextOrigin.trans own,
    nextKey.trans keyEq, nextExpected.trans expectedEq, nextCoverage.trans coverage⟩, ?_⟩
  intro content someContent
  obtain ⟨record, member, same⟩ := semantic content someContent
  exact ⟨record, extension.2 record member, same⟩

namespace DependencySelection

/-- The edge scope used by the production selection gate. Proof gates include
both facets; statement gates include only statement edges. -/
def edges (uses : Array SelectedUse) (realization : RealizationKey) (context : Context)
    (name : Name) : Array SelectedUse :=
  (uses.filter fun use => use.source == realization.node &&
    use.context == some context && use.realization.all (· == realization.name)).filter
      fun use => name == `proof || use.facet == `statement

/-- Exact source/context/realization/facet membership in a selection gate. -/
theorem mem_edges (uses : Array SelectedUse) (realization : RealizationKey) (context : Context)
    (name : Name) (edge : SelectedUse) :
    edge ∈ edges uses realization context name ↔
      edge ∈ uses ∧ edge.source = realization.node ∧ edge.context = some context ∧
      (edge.realization = none ∨ edge.realization = some realization.name) ∧
      (name = `proof ∨ edge.facet = `statement) := by
  cases selected : edge.realization <;> simp [edges, selected, and_assoc, and_left_comm, and_comm]

/-- The complete ordered diagnostic inventory examined by the gate. -/
def failures (edges : Array SelectedUse) : Array Diagnostic :=
  edges.filterMap fun edge => match edge.selected with | .error issue => some issue | .ok _ => none

/-- Exact generation provenance, including identity, edge scope, result and
explanation. This is a specification over existing output, not another evaluator. -/
def Source (uses : Array SelectedUse) (origin : Origin) (key : RequirementKey)
    (observation : CheckObservation) : Prop :=
  ∃ realization context object name,
    context.language = `lean ∧ (name = `statement ∨ name = `proof) ∧
    key = ⟨.declaration realization object, name ++ `dependencySelection⟩ ∧
    origin = (contribution `observation (BindingEncoding.requirementKey key) ()).origin ∧
    (edges uses realization context name).isEmpty = false ∧
    observation = {
      validator := `blueprint.dependencySelection
      outcome := if (failures (edges uses realization context name)).isEmpty then .passed else .unavailable
      explanation := if (failures (edges uses realization context name)).isEmpty then
        "Every dependency selected its exact current native contract"
        else (toJson (failures (edges uses realization context name))).compress }

/-- Generated selection checks cannot impersonate a native proof checker. -/
theorem Source.validator {origin : Origin} (source : Source uses origin key observation) :
    observation.validator = `blueprint.dependencySelection := by
  obtain ⟨_, _, _, _, _, _, _, _, _, rfl⟩ := source
  rfl

/-- Success is exactly the absence of a failed selected edge; no requirement
completion or alternative realization is consulted by this mechanical gate. -/
theorem failures_empty_iff (selected : Array SelectedUse) :
    (failures selected).isEmpty = true ↔
      ∀ edge ∈ selected, ∃ keys, edge.selected = .ok keys := by
  simp only [failures, Array.isEmpty_iff, Array.filterMap_eq_empty_iff]
  constructor
  · intro noFailures edge member
    have noFailure := noFailures edge member
    cases result : edge.selected with
    | error diagnostic => simp [result] at noFailure
    | ok keys => exact ⟨keys, rfl⟩
  · intro success edge member
    obtain ⟨keys, result⟩ := success edge member
    simp [result]

/-- Every reported failure is exactly an original selected-edge diagnostic. -/
theorem mem_failures (selected : Array SelectedUse) (diagnostic : Diagnostic) :
    diagnostic ∈ failures selected ↔ ∃ edge ∈ selected, edge.selected = .error diagnostic := by
  simp only [failures, Array.mem_filterMap]
  constructor
  · rintro ⟨edge, member, found⟩
    cases result : edge.selected with
    | error issue => simp [result] at found; exact ⟨edge, member, found ▸ result⟩
    | ok keys => simp [result] at found
  · rintro ⟨edge, member, result⟩
    exact ⟨edge, member, by simp [result]⟩

/-- Exact outcome interpretation for the same scoped edges that generated the
observation. An unavailable check has a concrete failed edge; a passed check has
success for every edge. Neither conclusion asserts completion of target contracts. -/
theorem Source.outcomes {origin : Origin} (source : Source uses origin key observation) :
    ∃ realization context object name,
      context.language = `lean ∧ (name = `statement ∨ name = `proof) ∧
      key = ⟨.declaration realization object, name ++ `dependencySelection⟩ ∧
      (edges uses realization context name).isEmpty = false ∧
      (observation.outcome = .passed ↔
        ∀ edge ∈ edges uses realization context name, ∃ keys, edge.selected = .ok keys) ∧
      (observation.outcome = .unavailable ↔
        ∃ edge ∈ edges uses realization context name, ∃ diagnostic, edge.selected = .error diagnostic) := by
  obtain ⟨realization, context, object, name, native, facet, keyEq, _, nonempty, rfl⟩ := source
  refine ⟨realization, context, object, name, native, facet, keyEq, nonempty, ?_, ?_⟩
  · rw [← failures_empty_iff]
    change (if _ then Outcome.passed else Outcome.unavailable) = .passed ↔ _
    cases empty : (failures (edges uses realization context name)).isEmpty <;> simp
  · have nonemptyFailures : (failures (edges uses realization context name)).isEmpty = false ↔
        ∃ edge ∈ edges uses realization context name, ∃ diagnostic, edge.selected = .error diagnostic := by
      rw [Array.isEmpty_eq_false_iff_exists_mem]
      simp only [mem_failures]
      constructor
      · rintro ⟨diagnostic, edge, member, failure⟩; exact ⟨edge, member, diagnostic, failure⟩
      · rintro ⟨edge, member, diagnostic, failure⟩; exact ⟨diagnostic, edge, member, failure⟩
    rw [← nonemptyFailures]
    change (if _ then Outcome.passed else Outcome.unavailable) = .unavailable ↔ _
    cases empty : (failures (edges uses realization context name)).isEmpty <;> simp

end DependencySelection

/-- Recipe-generated checks and unavailable fallbacks remain distinct from provider
observations. Native checks and authored proofs retain their original full fields;
authored proofs also retain the selected specification call and document. -/
private def ObservationFrom (providers : Providers Id) (p : Plan)
    (policy : Origin → RequirementKey → CheckObservation → Prop) (input : Input)
    (origin : Origin) (key : RequirementKey) : Observation → Prop
  | .proof observation => ∃ handle witness documents checked,
      (Providers.expected providers handle witness documents).run = .ok (.ok checked) ∧
      observation = checked.observation ∧
      AuthoredProofProjection input origin key checked witness ∧
      ∃ document, (Providers.specification providers p.expected[handle]!.specification document).run = .ok (.ok ()) ∧
        document.key ∈ documents
  | .review _ => False
  | .check observation => (observation.outcome = .unavailable ∧
      (observation.validator = NativeLean.statementValidator ∨ observation.validator = NativeLean.bodyValidator)) ∨
      policy origin key observation ∨
      ∃ handle checked, (Providers.check providers handle).run = .ok (.ok checked) ∧
        (observation = checked.statement ∨ observation = checked.body)

private def CollectionFrom (providers : Providers Id) (p : Plan)
    (policy : Origin → RequirementKey → CheckObservation → Prop) (collected : Collected) : Prop :=
  ChecksFrom providers collected ∧
    (∀ entry ∈ Collected.observations collected, ObservationFrom providers p policy (Collected.input collected) entry.1 entry.2.1 entry.2.2) ∧
    (Collected.input collected).evidence = #[]

private theorem observationFrom_mono {origin : Origin} (extension : PreservesContracts before after)
    (prior : ObservationFrom providers p policy before origin key observation) :
    ObservationFrom providers p policy after origin key observation := by
  cases observation with
  | check observation => exact prior
  | review observation => exact prior
  | proof observation =>
    obtain ⟨handle, witness, documents, checked, supplied, observed, projection, specification⟩ := prior
    exact ⟨handle, witness, documents, checked, supplied, observed,
      proofProjection_mono extension projection, specification⟩

private theorem collectionFrom_mono (prior : CollectionFrom providers p policy before)
    (extension : PreservesContracts (Collected.input before) (Collected.input after))
    (checks : Collected.nativeChecks after = Collected.nativeChecks before)
    (observations : Collected.observations after = Collected.observations before)
    (evidence : (Collected.input after).evidence = #[]) : CollectionFrom providers p policy after := by
  refine ⟨?_, ?_, evidence⟩
  · simpa only [ChecksFrom, checks] using prior.1
  · intro entry member
    rw [observations] at member
    exact observationFrom_mono extension (prior.2.1 entry member)

private theorem recordObservation_from (prior : CollectionFrom providers p policy collected)
    (allowed : ObservationFrom providers p policy (Collected.input collected)
      (contribution `observation (BindingEncoding.requirementKey key) ()).origin key observation) :
    CollectionFrom providers p policy (recordObservation collected key observation) := by
  refine ⟨prior.1, ?_, prior.2.2⟩
  intro entry member
  simp only [recordObservation, Array.mem_push] at member
  rcases member with original | rfl
  · exact prior.2.1 entry original
  · exact allowed

private theorem collectOrdinary_from (providers : Providers Id) (p : Plan)
    (accepted : (collectOrdinary providers p).run = .ok collected) : CollectionFrom providers p policy collected := by
  simp only [collectOrdinary, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  apply array_loop_invariant p.ordinary (CollectionFrom providers p policy) _ (by simp [CollectionFrom, ChecksFrom]) ?_ loop
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
      have nextValid : CollectionFrom providers p policy next := by
        refine array_loop_invariant node.realizations (CollectionFrom providers p policy) _ ?_ ?_ realizations
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
              have sourceValid : CollectionFrom providers p policy sourced.1 := by
                refine array_loop_invariant realization.sources (fun pair => CollectionFrom providers p policy pair.1) _ ?_ ?_ sources
                · exact prior
                · intro source member pair result prior step
                  clear loop realizations sources declarations finished
                  repeat' first
                    | (cases step; exact prior)
                    | (simp only [exceptT_bind_ok_iff] at step; obtain ⟨value, returned, step⟩ := step)
                    | split at step
              have declarationValid : CollectionFrom providers p policy declared.1 := by
                refine array_loop_invariant realization.declarations (fun pair => CollectionFrom providers p policy pair.1) _ sourceValid ?_ declarations
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
                      · refine ⟨?_, ?_, prior.2.2⟩
                        intro item member
                        simp only [Array.mem_push] at member
                        rcases member with previous | rfl
                        · exact prior.1 item previous
                        · exact ⟨declaration.check, returned⟩
                        intro entry member
                        apply observationFrom_mono ?_ (prior.2.1 entry member)
                        apply preservesContracts_append <;> intro record member <;> simp [member]
                      · exact Or.inr (Or.inr ⟨declaration.check, checked, returned, Or.inl rfl⟩)
                    · exact Or.inr (Or.inr ⟨declaration.check, checked, returned, Or.inr rfl⟩)
                  | error diagnostic =>
                    simp only [exceptT_bind_ok_iff] at step
                    obtain ⟨next, unavailable, finished⟩ := step
                    have valid : CollectionFrom providers p policy next := by
                      refine array_loop_invariant _ (CollectionFrom providers p policy) _ ?_ ?_ unavailable
                      · refine collectionFrom_mono prior ?_ ?_ ?_ ?_
                        · apply preservesContracts_append <;> intro record member <;> simp [member]
                        · rfl
                        · rfl
                        · exact prior.2.2
                      · intro entry member current result prior step
                        cases step
                        apply recordObservation_from prior
                        refine Or.inl ⟨rfl, ?_⟩
                        simp at member
                        rcases member with rfl | rfl <;> simp
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
    (initialValid : CollectionFrom providers p policy initial)
    (accepted : (collectAuthored providers p initial).run = .ok collected) :
    CollectionFrom providers p policy collected := by
  simp only [collectAuthored, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  refine array_loop_invariant p.authored (CollectionFrom providers p policy)
    _ initialValid ?_ loop
  intro authored member current result prior step
  simp only [exceptT_bind_ok_iff] at step
  obtain ⟨goals, goalLoop, sourced, sourceLoop, finished⟩ := step
  have goalsValid : CollectionFrom providers p policy goals := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at goalLoop
    refine list_loop_invariant _ (CollectionFrom providers p policy)
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
        obtain ⟨specResult, specReturned, specUnit, specAccepted, expectedResult, expectedReturned, checked, checkedAccepted, finished⟩ := step
        cases finished
        refine ⟨prior.1, ?_, prior.2.2⟩
        intro entry member
        simp only [Array.mem_push] at member
        rcases member with original | rfl
        · apply observationFrom_mono ?_ (prior.2.1 entry original)
          apply preservesContracts_append <;> intro record member <;> simp [member]
        · cases expectedResult with
          | error diagnostic => cases checkedAccepted
          | ok value =>
            cases checkedAccepted
            cases specResult with
            | error diagnostics => cases specAccepted
            | ok value =>
              cases value
              refine ⟨_, _, _, _, expectedReturned, rfl, ?_, document.1, specReturned, ?_⟩
              · refine ⟨authored.record.origin, index, rfl, ?_, ?_⟩
                · exact ⟨_, Array.mem_push_self, rfl, rfl, rfl, rfl⟩
                · intro content someContent
                  refine ⟨_, ?_, rfl⟩
                  simp [someContent]
              · exact (mem_canonical _ _).mpr (by simp)
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
  have sourcesValid : CollectionFrom providers p policy sourced := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at sourceLoop
    refine list_loop_invariant _ (CollectionFrom providers p policy)
      _ goalsValid ?_ sourceLoop
    intro index member current result prior step
    simp only [exceptT_bind_ok_iff] at step
    obtain ⟨_, _, step⟩ := step
    cases step
    exact prior
  cases finished
  refine collectionFrom_mono sourcesValid ?_ ?_ ?_ ?_
  · apply preservesContracts_append <;> intro record member <;> simp [member]
  · rfl
  · rfl
  · exact sourcesValid.2.2

private theorem assemble_from (providers : Providers Id) (p : Plan)
    (accepted : (assemble providers p).run = .ok collected) : CollectionFrom providers p policy collected := by
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
      ∀ providers p policy,
        (∀ origin key observation, DependencySelection.Source uses origin key observation → policy origin key observation) →
        CollectionFrom providers p policy collected → CollectionFrom providers p policy (connectUses collected uses) := by
  let invariant (current : Collected) : Prop :=
    Collected.nativeChecks current = Collected.nativeChecks collected ∧
      ∀ providers p policy,
        (∀ origin key observation, DependencySelection.Source uses origin key observation → policy origin key observation) →
        CollectionFrom providers p policy collected → CollectionFrom providers p policy current
  unfold connectUses
  simp only [Id.run, bind, pure]
  apply id_array_loop_invariant _ invariant _ ⟨rfl, fun _ _ _ _ valid => valid⟩
  intro model member current prior
  by_cases foreign : (model.context.language != `lean) = true
  · rw [ite_eq_left foreign]
    exact prior
  · rw [ite_eq_right foreign]
    apply id_array_loop_invariant _ invariant _ prior
    intro declaration member current prior
    apply id_array_loop_invariant _ invariant _ prior
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
          refine ⟨prior.1, ?_⟩
          intro providers p policy allowed valid
          have original := prior.2 providers p policy allowed valid
          refine ⟨original.1, ?_, original.2.2⟩
          intro item member
          change item ∈ (Collected.observations current).push _ at member
          simp only [Array.mem_push] at member
          rcases member with previous | rfl
          · apply observationFrom_mono ?_ (original.2.1 item previous)
            refine ⟨?_, ?_⟩
            · intro record member
              refine ⟨_, Array.mem_map.mpr ⟨record, ?_, rfl⟩, ?_⟩
              · simp only [recordObservation, Array.mem_push]
                exact Or.inl member
              · split <;> exact ⟨rfl, rfl, rfl, rfl⟩
            · intro record member
              simp only [recordObservation, Array.mem_push]
              exact Or.inl member
          · apply Or.inr ∘ Or.inl
            apply allowed
            refine ⟨model.key, model.context, declaration.object, entry.1, ?_, ?_, rfl, rfl, ?_, rfl⟩
            · simpa using foreign
            · simp at entryMember
              rcases entryMember with rfl | rfl <;> simp
            · simpa [DependencySelection.edges] using edges
        · intro edges
          rw [ite_eq_right edges]
          refine ⟨prior.1, ?_⟩
          intro providers p policy allowed valid
          have original := prior.2 providers p policy allowed valid
          refine collectionFrom_mono original ?_ ?_ ?_ ?_
          · refine ⟨?_, fun _ member => member⟩
            intro record member
            refine ⟨_, Array.mem_map.mpr ⟨record, member, rfl⟩, ?_⟩
            split <;> exact ⟨rfl, rfl, rfl, rfl⟩
          · rfl
          · rfl
          · exact original.2.2
    · intro foreign; rw [ite_eq_right foreign]; exact prior


private theorem connectUses_nativeChecks (collected : Collected) (uses : Array SelectedUse) :
    Collected.nativeChecks (connectUses collected uses) = Collected.nativeChecks collected :=
  (connectUses_properties collected uses).1

private theorem connectUses_from (collected : Collected) (uses : Array SelectedUse)
    (initialValid : CollectionFrom providers p policy collected)
    (allowed : ∀ origin key observation, DependencySelection.Source uses origin key observation → policy origin key observation) :
    CollectionFrom providers p policy (connectUses collected uses) :=
  (connectUses_properties collected uses).2 providers p policy allowed initialValid

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

/-- The public snapshot retains exactly the edge inventory used by final wiring. -/
theorem finish_uses (accepted : finish collected = .ok snapshot) :
    snapshot.uses = selectUses collected := by
  simp only [finish] at accepted
  split at accepted
  · simp only [except_bind_ok_iff] at accepted
    obtain ⟨_, _, _, _, _, _, result⟩ := accepted
    cases result
    rfl
  · cases accepted

private theorem finish_observations_from
    (initialValid : CollectionFrom providers p (DependencySelection.Source snapshot.uses) collected)
    (accepted : finish collected = .ok snapshot)
    (member : record ∈ snapshot.registry.contributions.evidence) :
    ObservationFrom providers p (DependencySelection.Source snapshot.uses) snapshot.registry.contributions record.origin record.value.requirement record.value.observation := by
  have linked := connectUses_from collected (selectUses collected) initialValid (by
    intro origin key observation source
    rw [finish_uses accepted]
    exact source)
  rw [finish_sources accepted] at member
  simp only [Array.mem_append, Array.mem_map] at member
  rcases member with previous | ⟨entry, original, rfl⟩
  · rw [linked.2.2] at previous
    simp at previous
  · apply observationFrom_mono ?_ (linked.2.1 entry original)
    rw [finish_sources accepted]
    exact preservesContracts_refl _

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
  obtain ⟨handle, supplied⟩ := (assemble_from (policy := fun _ _ _ => False) _ _ assembled).1 checked member
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
  · have impossible := unavailable.1
    rw [passed] at impossible
    cases impossible
  · have policy := policy.validator
    rcases native with statement | body
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

/-- Every admitted dependency-selection observation is generated by the actual
wiring pass over the public snapshot's selected edges. Both passed and unavailable
outcomes retain their exact scoped edge inventory and diagnostic explanation;
supplied native observations cannot impersonate these generated checks. -/
theorem evaluate_dependency_selection_source {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (member : record ∈ snapshot.registry.contributions.evidence)
    (observed : record.value.observation = .check observation)
    (validator : observation.validator = `blueprint.dependencySelection) :
    DependencySelection.Source snapshot.uses record.origin record.value.requirement observation := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨documents, _, nativeTable, _, inline, _, documented, _, checks, _,
    specifications, _, expected, _, collected, assembled, finished⟩ := accepted
  have source := finish_observations_from (assemble_from _ _ assembled) finished member
  rw [observed] at source
  have notNative : ¬ (observation.validator = NativeLean.statementValidator ∨
      observation.validator = NativeLean.bodyValidator) := by
    rw [validator]
    decide
  rcases source with unavailable | policy | ⟨handle, checked, supplied, field⟩
  · exact False.elim (notNative unavailable.2)
  · exact policy
  · simp only [exceptT_bind_ok_iff] at supplied
    obtain ⟨result, _, matched⟩ := supplied
    cases result with
    | error diagnostic => cases matched
    | ok value =>
      simp only [exceptT_bind_ok_iff] at matched
      obtain ⟨_, checkedShape, output⟩ := matched
      cases output
      have shape := matching_success checkedShape
      simp only [Bool.and_eq_true, beq_iff_eq, and_assoc] at shape
      apply False.elim ∘ notNative
      rcases field with rfl | rfl
      · exact Or.inl shape.2.2.2.1
      · exact Or.inr shape.2.2.2.2

/-- A completed generated selection requirement has a nonempty, precisely scoped
edge inventory and every edge selected successfully. This connects the generated
check to actual public completion without assuming provider authenticity or target
completion. Target contracts remain independent prerequisite obligations. -/
theorem evaluate_complete_dependency_selection {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (found : snapshot.registry.requirement? key = some requirement)
    (expected : requirement.expected = .check `blueprint.dependencySelection)
    (complete : (snapshot.registry.resultForRequirement key).complete = true) :
    ∃ realization context object name,
      context.language = `lean ∧ (name = `statement ∨ name = `proof) ∧
      key = ⟨.declaration realization object, name ++ `dependencySelection⟩ ∧
      (DependencySelection.edges snapshot.uses realization context name).isEmpty = false ∧
      ∀ edge ∈ DependencySelection.edges snapshot.uses realization context name,
        ∃ keys, edge.selected = .ok keys := by
  obtain ⟨originalRequirement, _, evidence, member, lookup, originalKey, fits⟩ :=
    admit_complete_requirement_evidence (evaluate_admitted evaluated) complete
  have requirementEq := Option.some.inj (found.symm.trans lookup)
  rw [← requirementEq] at fits
  have suitable := fits.2.2.2
  cases observed : evidence.value.observation with
  | proof observation => simp [Observation.Satisfies, observed, expected] at suitable
  | review observation => simp [Observation.Satisfies, observed, expected] at suitable
  | check observation =>
    simp only [observed, Observation.Satisfies, expected] at suitable
    have source := evaluate_dependency_selection_source evaluated member observed suitable.1
    obtain ⟨realization, context, object, name, native, facet, keyEq, nonempty, passed, _⟩ := source.outcomes
    have evidenceKey : evidence.value.requirement = key :=
      fits.1.trans ((congrArg Requirement.key requirementEq).trans originalKey)
    exact ⟨realization, context, object, name, native, facet,
      evidenceKey.symm.trans keyEq, nonempty, passed.mp suitable.2.2.2⟩

/-- Every admitted independent-proof observation is unchanged from a successful
expected-goal batch result. Its selected witness and documents pass the actual
adapter checks, and its specification document belongs to that document inventory
and has an original successful specification result. This preserves the full
observation, including actual type, coverage, assumptions, and explanation.
The same result supplies the expected requirement and any semantic-context input,
with a common authored-site origin. Prerequisite wiring may extend the contract.
This does not authenticate the provider or assert that the observation passed. -/
theorem evaluate_proof_evidence_source {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (member : record ∈ snapshot.registry.contributions.evidence)
    (observed : record.value.observation = .proof observation) :
    ∃ entry ∈ observations.expected, ∃ checked,
      entry.result.result = .ok checked ∧ observation = checked.observation ∧
      entry.handle < p.expected.size ∧
      checked.observation.witness = entry.result.witness ∧
      checked.goal.documents = entry.result.documents ∧
      checked.goal.context = entry.result.witness.context ∧
      AuthoredProofProjection snapshot.registry.contributions record.origin record.value.requirement
        checked entry.result.witness ∧
      ∃ specification ∈ observations.specifications,
        specification.handle = p.expected[entry.handle]!.specification ∧
        specification.result.result = .ok () ∧
        specification.result.document.key ∈ entry.result.documents := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨documents, _, native, _, inline, _, documented, _, checks, _,
    specifications, specificationsIndexed, expected, expectedIndexed, collected, assembled, finished⟩ := accepted
  have source := finish_observations_from (assemble_from _ _ assembled) finished member
  rw [observed] at source
  obtain ⟨handle, witness, selectedDocuments, checked, supplied, observationEq, projection,
    document, specificationSupplied, documentMember⟩ := source
  simp only [exceptT_bind_ok_iff] at supplied
  obtain ⟨value, lookup, _, requestShape, returned⟩ := supplied
  have requestShape := matching_success requestShape
  have requestEq : value.witness = witness ∧ value.documents = selectedDocuments := by
    simpa only [Bool.and_eq_true, beq_iff_eq] using requestShape
  cases resultEq : value.result with
  | error diagnostic => rw [resultEq] at returned; cases returned
  | ok actual =>
    rw [resultEq] at returned
    simp only [exceptT_bind_ok_iff] at returned
    obtain ⟨_, checkedShape, output⟩ := returned
    cases output
    have checkedShape := matching_success checkedShape
    have checkedEq : checked.observation.witness = witness ∧
        checked.goal.documents = selectedDocuments ∧ checked.goal.context = witness.context := by
      simpa only [Bool.and_eq_true, beq_iff_eq, and_assoc] using checkedShape
    obtain ⟨entry, original, handleEq, entryEq⟩ :=
      (lookupResult_success_iff expectedIndexed handle value).mp lookup
    refine ⟨entry, original, checked, ?_, observationEq,
      (indexResults_valid expectedIndexed).1 entry original, ?_, ?_, ?_, ?_, ?_⟩
    · rw [entryEq]; exact resultEq
    · rw [entryEq, requestEq.1]; exact checkedEq.1
    · rw [entryEq, requestEq.2]; exact checkedEq.2.1
    · rw [entryEq, requestEq.1]; exact checkedEq.2.2
    · rw [entryEq, requestEq.1]; exact projection
    · simp only [exceptT_bind_ok_iff] at specificationSupplied
      obtain ⟨specValue, specLookup, _, specShape, specOutput⟩ := specificationSupplied
      have documentEq : specValue.document = document := by
        simpa only [beq_iff_eq] using matching_success specShape
      obtain ⟨specEntry, specOriginal, specHandle, specEq⟩ :=
        (lookupResult_success_iff specificationsIndexed _ specValue).mp specLookup
      refine ⟨specEntry, specOriginal, ?_, ?_, ?_⟩
      · rw [handleEq]; exact specHandle
      · rw [specEq]; exact Except.ok.inj specOutput
      · rw [specEq, documentEq, entryEq, requestEq.2]; exact documentMember

/-- End-to-end pure-capture soundness for an independent-proof requirement:
public completion has an original successful expected-goal result whose unchanged
observation satisfies the selected contract. This includes actual-type identity,
passed outcome, and dependency-closure coverage, as specified by `Satisfies`.
The exact expected goal and witness come from that same result, and any reported
semantic context is retained under this requirement's binding-input identity.
This justifies use of the supplier's report; its truth is a separate boundary. -/
theorem evaluate_complete_proof_provider {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (found : snapshot.registry.requirement? key = some requirement)
    (expected : requirement.expected = .proof goal witness)
    (complete : (snapshot.registry.resultForRequirement key).complete = true) :
    ∃ entry ∈ observations.expected, ∃ checked,
      entry.result.result = .ok checked ∧ checked.goal = goal ∧ entry.result.witness = witness ∧
      (Observation.proof checked.observation).Satisfies requirement ∧
      ∀ content, checked.semanticContext = some content →
        ∃ semantic ∈ snapshot.registry.contributions.bindingInputs,
          semantic.value = { subject := key.subject, name := NativeLean.expectedContextFor key, content } := by
  obtain ⟨originalRequirement, requirementMember, evidence, member, lookup, originalKey, fits⟩ :=
    admit_complete_requirement_evidence (evaluate_admitted evaluated) complete
  have requirementEq := Option.some.inj (found.symm.trans lookup)
  rw [← requirementEq] at fits
  have suitable := fits.2.2.2
  cases observed : evidence.value.observation with
  | check observation => simp [Observation.Satisfies, observed, expected] at suitable
  | review observation => simp [Observation.Satisfies, observed, expected] at suitable
  | proof observation =>
    obtain ⟨entry, original, checked, result, observationEq, _, _, _, _, projection, _⟩ :=
      evaluate_proof_evidence_source evaluated member observed
    obtain ⟨source, index, _, ⟨projected, projectedMember, _, projectedKey, projectedExpected, _⟩,
      projectedSemantic⟩ := projection
    have same := admit_requirements_agree (evaluate_admitted evaluated)
      projectedMember requirementMember (projectedKey.trans (fits.1.trans (congrArg Requirement.key requirementEq)))
    have expectedEq : Expectation.proof checked.goal entry.result.witness = .proof goal witness := by
      rw [← projectedExpected, same, ← requirementEq, expected]
    have parts := Expectation.proof.inj expectedEq
    refine ⟨entry, original, checked, result, parts.1, parts.2, ?_, ?_⟩
    · rwa [observed, observationEq] at suitable
    · intro content someContent
      obtain ⟨semantic, semanticMember, same⟩ := projectedSemantic content someContent
      refine ⟨semantic, semanticMember, ?_⟩
      have evidenceKey : evidence.value.requirement = key := fits.1.trans ((congrArg Requirement.key requirementEq).trans originalKey)
      rw [same, evidenceKey]
      rfl

end Informal.Realizations.Capture
