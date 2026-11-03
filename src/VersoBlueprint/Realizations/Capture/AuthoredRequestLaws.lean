/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.RequestLaws

/-! Authored goal/request/specification/document identity through actual planning. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

run_cmd do
  let env ← getEnv
  let owners ← #[``finish_uses, ``plan_declaration_check].mapM fun name => do
    let some owner := env.getModuleIdxFor? name | throwError "Capture law helpers must be imported"
    pure owner
  for (name, _) in env.constants.toList do
    if (env.getModuleIdxFor? name).any owners.contains then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

/-- The actual indexed requests retain a goal's project, provenance and specification
source. This law predicate does not certify provider execution or source inventories. -/
def AuthoredRequestChain (p : Plan) (record : Environment.AuthoringRecord)
    (goal : Name × Name) (handle : Nat) : Prop :=
  ∃ request specification, p.expected[handle]? = some request ∧
    request.node = goal.1 ∧ request.expected = goal.2 ∧
    request.project = record.project ∧ request.origin = record.origin ∧
    p.specifications[request.specification]? = some specification ∧
    specification.expected = goal.2 ∧ specification.origin = record.origin ∧
    p.documents[specification.document]? = some ⟨⟨`lean, record.project⟩, record.origin.source⟩

private def RequestGrowth (before after : Plan) : Prop :=
  PreservesLookups before.expected after.expected ∧
  PreservesLookups before.specifications after.specifications ∧
  PreservesLookups before.documents after.documents

private theorem requestGrowth_refl (p : Plan) : RequestGrowth p p :=
  ⟨preservesLookups_refl _, preservesLookups_refl _, preservesLookups_refl _⟩

private theorem RequestGrowth.trans (first : RequestGrowth a b) (second : RequestGrowth b c) :
    RequestGrowth a c :=
  ⟨PreservesLookups.trans first.1 second.1, PreservesLookups.trans first.2.1 second.2.1,
    PreservesLookups.trans first.2.2 second.2.2⟩

private theorem AuthoredRequestChain.preserve (chain : AuthoredRequestChain before record goal handle)
    (growth : RequestGrowth before after) : AuthoredRequestChain after record goal handle := by
  obtain ⟨request, specification, found, node, expected, project, origin, spec, specExpected, specOrigin, document⟩ := chain
  exact ⟨request, specification, growth.1 _ _ found, node, expected, project, origin,
    growth.2.1 _ _ spec, specExpected, specOrigin, growth.2.2 _ _ document⟩

private def GoalRequests (p : Plan) (record : Environment.AuthoringRecord)
    (goals : Array (Name × Name)) (handles : Array Nat) : Prop :=
  goals.size = handles.size ∧ ∀ (index : Nat) goal, goals[index]? = some goal →
    ∃ handle, handles[index]? = some handle ∧ AuthoredRequestChain p record goal handle

private theorem GoalRequests.preserve (valid : GoalRequests before record goals handles)
    (growth : RequestGrowth before after) : GoalRequests after record goals handles :=
  ⟨valid.1, fun index goal found => by
    obtain ⟨handle, selected, chain⟩ := valid.2 index goal found
    exact ⟨handle, selected, chain.preserve growth⟩⟩

private theorem GoalRequests.push (valid : GoalRequests p record goals handles)
    (chain : AuthoredRequestChain p record goal handle) :
    GoalRequests p record (goals.push goal) (handles.push handle) := by
  refine ⟨by simp [valid.1], ?_⟩
  intro index selected found
  by_cases bound : index < goals.size
  · have old : goals[index]? = some selected := by simpa [Array.getElem?_push, bound, Nat.ne_of_lt bound] using found
    obtain ⟨oldHandle, selectedHandle, chain⟩ := valid.2 index selected old
    exact ⟨oldHandle, preservesLookups_push _ _ _ _ selectedHandle, chain⟩
  · have atEnd : index = goals.size := by
      have bound := (Array.getElem?_eq_some_iff.mp found).1
      simp only [Array.size_push] at bound
      omega
    subst index
    have same : goal = selected := by simpa using found
    subst selected
    exact ⟨handle, by simp [valid.1], chain⟩

private def AuthoredRequests (p : Plan) : Prop :=
  ∀ step ∈ p.authored, GoalRequests p step.record step.record.nativeGoals step.goals

private theorem id_list_loop_history (entries : List α) (property : Array α → β → Prop)
    (body : α → β → Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ processed current, property processed current →
      ∃ next, body entry current = .yield next ∧ property (processed.push entry) next)
    (valid : property processed initial) :
    property (processed ++ entries.toArray) (forIn entries initial body) := by
  induction entries generalizing processed initial with
  | nil => simpa [pure] using valid
  | cons entry entries ih =>
    obtain ⟨next, executed, updated⟩ := step entry (by simp) processed initial valid
    simp only [List.forIn_cons, executed, bind]
    simpa using ih (fun item member => step item (by simp [member])) updated

private theorem id_array_loop_history (entries : Array α) (property : Array α → β → Prop)
    (body : α → β → Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ processed current, property processed current →
      ∃ next, body entry current = .yield next ∧ property (processed.push entry) next)
    (valid : property #[] initial) : property entries (forIn entries initial body) := by
  rw [← Array.forIn_toList]
  simpa using id_list_loop_history entries.toList property body
    (fun entry member => step entry (by simpa using member)) valid

private theorem plan_authoredRequests (raw : Raw) : AuthoredRequests (plan raw) := by
  unfold plan
  simp only [Id.run, bind, pure]
  generalize ordinaryEq : forIn (m := Id) raw.nodes ({ raw } : Plan) _ = ordinary
  have ordinaryEmpty : ordinary.authored = #[] := by
    rw [← ordinaryEq]
    apply id_array_loop_invariant raw.nodes (fun p : Plan => p.authored = #[]) _ rfl
    intro entry member current prior
    rcases entry with ⟨label, accepted⟩
    clear ordinaryEq
    apply id_array_loop_invariant _ (fun pair : Plan × Array RealizationStep => pair.1.authored = #[]) _ prior
    intro key member pair prior
    apply id_array_loop_invariant _ (fun pair : Plan × Array DeclarationStep => pair.1.authored = #[]) _ ?_ ?_
    · apply id_array_loop_invariant _ (fun pair : Plan × Array SourceStep => pair.1.authored = #[]) _ prior
      intro source member pair prior
      cases source.payload <;> simp only
      all_goals first
        | exact prior
        | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
    · intro name member pair prior
      apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => pair.1.authored = #[]) _ ?_ ?_
      · apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => pair.1.authored = #[]) _ prior
        intro association member pair prior
        exact prior
      · intro source member pair prior
        cases source.payload <;> simp only
        all_goals first
          | exact prior
          | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
  apply id_array_loop_invariant _ AuthoredRequests _ (by simp [AuthoredRequests, ordinaryEmpty])
  intro record member current prior
  clear ordinaryEq
  generalize goalsEq : forIn (m := Id) (α := Name × Name) (β := Plan × Array Nat)
    record.nativeGoals (current, #[]) _ = goals
  have goalChains : goals.1.authored = current.authored ∧ RequestGrowth current goals.1 ∧
      GoalRequests goals.1 record record.nativeGoals goals.2 := by
    rw [← goalsEq]
    apply id_array_loop_history record.nativeGoals
      (fun processed (pair : Plan × Array Nat) => pair.1.authored = current.authored ∧ RequestGrowth current pair.1 ∧
        GoalRequests pair.1 record processed pair.2) _ ?_ ⟨rfl, requestGrowth_refl _, by simp [GoalRequests]⟩
    intro goal member processed pair prior
    refine ⟨_, rfl, prior.1, ?_, ?_⟩
    · exact prior.2.1.trans ⟨preservesLookups_push _ _, preservesLookups_push _ _, preservesLookups_push _ _⟩
    · apply GoalRequests.push
      · exact prior.2.2.preserve ⟨preservesLookups_push _ _, preservesLookups_push _ _, preservesLookups_push _ _⟩
      · simp [AuthoredRequestChain]
  generalize documentsEq : forIn (m := Id) (α := DocumentKey) (β := Plan × Array Nat)
    record.authored.sources (goals.1, #[]) _ = documented
  have documentsPreserved : documented.1.authored = goals.1.authored ∧ RequestGrowth goals.1 documented.1 := by
    rw [← documentsEq]
    apply id_array_loop_invariant (initial := (goals.1, #[])) _ (fun pair : Plan × Array Nat =>
      pair.1.authored = goals.1.authored ∧ RequestGrowth goals.1 pair.1) _ ⟨rfl, requestGrowth_refl _⟩
    intro document member pair prior
    exact ⟨prior.1, prior.2.trans ⟨preservesLookups_refl _, preservesLookups_refl _, preservesLookups_push _ _⟩⟩
  intro step member
  simp only [Array.mem_push] at member
  rcases member with member | rfl
  · exact ((prior step (by rwa [documentsPreserved.1, goalChains.1] at member)).preserve
      (goalChains.2.1.trans documentsPreserved.2))
  · exact goalChains.2.2.preserve documentsPreserved.2

/-- Each authored goal has exactly one position in its step's handle array.
This is an array-length statement; duplicate goal values keep their own positions. -/
theorem plan_authored_goal_handles (raw : Raw) (member : step ∈ (plan raw).authored) :
    step.goals.size = step.record.nativeGoals.size :=
  (plan_authoredRequests raw step member).1.symm

/-- A goal's position selects the matching expected/specification/document chain.
No valid-handle or preexisting-request premise is supplied by the caller. -/
theorem plan_authored_goal_request (raw : Raw) {index : Nat} (member : step ∈ (plan raw).authored)
    (found : step.record.nativeGoals[index]? = some goal) :
    ∃ handle, step.goals[index]? = some handle ∧ AuthoredRequestChain (plan raw) step.record goal handle :=
  (plan_authoredRequests raw step member).2 index goal found

/-- Every lookup in the chain is in bounds. The exact bang lookups used by the
collector and observer preserve the goal, project, origin and source document;
none can take its default fallback. Provider execution is a separate boundary. -/
theorem AuthoredRequestChain.jobs (chain : AuthoredRequestChain p record goal handle) :
    handle < p.expected.size ∧
      let request := p.expected[handle]!
      request.node = goal.1 ∧ request.expected = goal.2 ∧
      request.project = record.project ∧ request.origin = record.origin ∧
      request.specification < p.specifications.size ∧
        let specification := p.specifications[request.specification]!
        specification.expected = goal.2 ∧ specification.origin = record.origin ∧
        specification.document < p.documents.size ∧
        p.documents[specification.document]! = ⟨⟨`lean, record.project⟩, record.origin.source⟩ := by
  obtain ⟨request, specification, found, node, expected, project, origin, spec, specExpected, specOrigin, document⟩ := chain
  have handleBound := (Array.getElem?_eq_some_iff.mp found).1
  have requestEq : p.expected[handle]! = request := by
    simpa only [getElem!_pos, handleBound] using (Array.getElem?_eq_some_iff.mp found).2
  have specBound := (Array.getElem?_eq_some_iff.mp spec).1
  have specEq : p.specifications[request.specification]! = specification := by
    simpa only [getElem!_pos, specBound] using (Array.getElem?_eq_some_iff.mp spec).2
  have documentBound := (Array.getElem?_eq_some_iff.mp document).1
  refine ⟨handleBound, ?_⟩
  dsimp only
  rw [requestEq]
  refine ⟨node, expected, project, origin, specBound, ?_⟩
  rw [specEq]
  refine ⟨specExpected, specOrigin, documentBound, ?_⟩
  simpa only [getElem!_pos, documentBound] using (Array.getElem?_eq_some_iff.mp document).2

/-- Raw authored records and indexed goals reach the actual collector's handle
lookup. Exact-record deduplication supplies the step; all handle bounds are derived. -/
theorem plan_raw_authored_goal_request (raw : Raw) {index : Nat} (recordMember : record ∈ raw.authored)
    (goalFound : record.nativeGoals[index]? = some goal) :
    ∃ step ∈ (plan raw).authored, step.record = record ∧
      index < step.goals.size ∧
      AuthoredRequestChain (plan raw) record goal step.goals[index]! := by
  have planned := (plan_authored_record_mem_iff raw record).mpr recordMember
  obtain ⟨step, member, same⟩ := Array.mem_map.mp planned
  obtain ⟨handle, selected, chain⟩ := plan_authored_goal_request raw member (by rwa [same])
  have bound := (Array.getElem?_eq_some_iff.mp selected).1
  have handleEq : step.goals[index]! = handle := by
    simpa only [getElem!_pos, bound] using (Array.getElem?_eq_some_iff.mp selected).2
  exact ⟨step, member, same, bound, by simpa only [handleEq, same] using chain⟩

end Informal.Realizations.Capture
