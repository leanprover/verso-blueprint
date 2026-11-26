/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.UseLaws

/-! Exact ordinary source-use collection through the production recipe.
Plan construction and provider authenticity remain separate boundaries. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

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
  let some creationOwner := env.getModuleIdxFor? ``finish_native_dependency_gate_created
    | throwError "Capture creation helpers must be imported"
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some captureOwner || env.getModuleIdxFor? name == some lawsOwner ||
        env.getModuleIdxFor? name == some recipeOwner || env.getModuleIdxFor? name == some creationOwner then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

private theorem list_loop_appends (entries : List α) (project : β → Array γ)
    (payload : α → Array γ) (body : α → β → ExceptT ε Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ current result, (body entry current).run = .ok result →
      ∃ next, result = .yield next ∧ project next = project current ++ payload entry)
    (accepted : (forIn entries initial body).run = .ok final) :
    project final = project initial ++ (entries.flatMap fun entry => (payload entry).toList).toArray := by
  induction entries generalizing initial with
  | nil => cases accepted; simp
  | cons entry entries ih =>
    simp only [List.forIn_cons, exceptT_bind_ok_iff] at accepted
    obtain ⟨result, first, rest⟩ := accepted
    obtain ⟨next, rfl, projected⟩ := step entry (by simp) initial result first
    have later := ih (fun item member => step item (by simp [member])) rest
    apply Array.toList_inj.mp
    simpa [projected, List.append_assoc] using congrArg Array.toList later

private theorem array_loop_appends (entries : Array α) (project : β → Array γ)
    (payload : α → Array γ) (body : α → β → ExceptT ε Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ current result, (body entry current).run = .ok result →
      ∃ next, result = .yield next ∧ project next = project current ++ payload entry)
    (accepted : (forIn entries initial body).run = .ok final) :
    project final = project initial ++ entries.flatMap payload := by
  rw [← Array.forIn_toList] at accepted
  apply Array.toList_inj.mp
  simpa using congrArg Array.toList (list_loop_appends entries.toList project payload body
    (fun entry member => step entry (by simpa using member)) accepted)

/-- Ordinary collection appends exactly the accepted source uses, in plan order.
Provider branches may fail, but no successful branch drops or invents a use. -/
theorem collectOrdinary_uses (providers : Providers Id) (p : Plan)
    (accepted : (collectOrdinary providers p).run = .ok collected) :
    Collected.uses collected = p.ordinary.flatMap (·.accepted.uses) := by
  simp only [collectOrdinary, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  have projected := array_loop_appends p.ordinary Collected.uses (·.accepted.uses) _ ?_ loop
  · simpa using projected
  intro node member current result step
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
      have nextUses : Collected.uses next = Collected.uses current ++ node.accepted.uses := by
        refine array_loop_invariant node.realizations
          (fun next => Collected.uses next = Collected.uses current ++ node.accepted.uses) _ rfl ?_ realizations
        intro realization member current result prior step
        apply Classical.byCases (p := _)
        · intro contextValid
          rw [ite_eq_left contextValid] at step
          apply Classical.byCases (p := _)
          · intro sourcesValid
            rw [ite_eq_left sourcesValid] at step
            simp only [exceptT_bind_ok_iff] at step
            obtain ⟨sourced, sources, declared, declarations, finished⟩ := step
            have sourceUses : Collected.uses sourced.1 = Collected.uses current := by
              refine array_loop_invariant realization.sources
                (fun pair => Collected.uses pair.1 = Collected.uses current) _ rfl ?_ sources
              intro source member pair result prior step
              clear loop realizations sources declarations finished
              repeat' first
                | (cases step; exact prior)
                | (simp only [exceptT_bind_ok_iff] at step; obtain ⟨value, returned, step⟩ := step)
                | split at step
            have declarationUses : Collected.uses declared.1 = Collected.uses sourced.1 := by
              refine array_loop_invariant realization.declarations
                (fun pair => Collected.uses pair.1 = Collected.uses sourced.1) _ rfl ?_ declarations
              intro declaration member pair result prior step
              clear loop realizations sources declarations finished
              simp only [exceptT_bind_ok_iff] at step
              obtain ⟨prepared, _, step⟩ := step
              cases prepared <;> simp only [exceptT_bind_ok_iff] at step
              all_goals
                obtain ⟨observation, _, checkedResult, returned, step⟩ := step
                cases checkedResult with
                | ok checked => cases step; exact prior
                | error diagnostic =>
                  simp only [exceptT_bind_ok_iff] at step
                  obtain ⟨next, unavailable, finished⟩ := step
                  have nextUses : Collected.uses next = Collected.uses pair.1 := by
                    refine array_loop_invariant _
                      (fun next => Collected.uses next = Collected.uses pair.1) _ ?_ ?_ unavailable
                    · rfl
                    · intro entry member current result prior step
                      cases step
                      exact prior
                  cases finished
                  exact nextUses.trans prior
            cases finished
            exact declarationUses.trans (sourceUses.trans prior)
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
      · cases finished; exact ⟨next, rfl, nextUses⟩
      · simp only [exceptT_bind_ok_iff] at finished
        obtain ⟨_, impossible, _⟩ := finished
        cases impossible

/-- Authored collection can enrich models and contracts, but preserves the exact
ordinary use array, including its original order and duplicate metadata. -/
theorem collectAuthored_uses (providers : Providers Id) (p : Plan)
    (accepted : (collectAuthored providers p initial).run = .ok collected) :
    Collected.uses collected = Collected.uses initial := by
  simp only [collectAuthored, exceptT_bind_ok_iff] at accepted
  obtain ⟨result, loop, finished⟩ := accepted
  cases finished
  refine array_loop_invariant p.authored
    (fun current => Collected.uses current = Collected.uses initial) _ rfl ?_ loop
  intro authored member current result prior step
  simp only [exceptT_bind_ok_iff] at step
  obtain ⟨goals, goalLoop, sourced, sourceLoop, finished⟩ := step
  have goalUses : Collected.uses goals = Collected.uses current := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at goalLoop
    refine list_loop_invariant _ (fun next => Collected.uses next = Collected.uses current)
      _ rfl ?_ goalLoop
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
        exact prior
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
  have sourceUses : Collected.uses sourced = Collected.uses goals := by
    rw [Std.Legacy.Range.forIn_eq_forIn_range'] at sourceLoop
    refine list_loop_invariant _ (fun next => Collected.uses next = Collected.uses goals)
      _ rfl ?_ sourceLoop
    intro index member current result prior step
    simp only [exceptT_bind_ok_iff] at step
    obtain ⟨_, _, step⟩ := step
    cases step
    exact prior
  cases finished
  exact sourceUses.trans (goalUses.trans prior)

/-- The actual complete recipe carries precisely the ordinary plan entries' uses
into finalization. This is array equality, not only inclusion. -/
theorem assemble_uses (providers : Providers Id) (p : Plan)
    (accepted : (assemble providers p).run = .ok collected) :
    Collected.uses collected = p.ordinary.flatMap (·.accepted.uses) := by
  simp only [assemble] at accepted
  split at accepted
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨ordinary, ordinaryOk, authoredOk⟩ := accepted
    exact (collectAuthored_uses providers p authoredOk).trans
      (collectOrdinary_uses providers p ordinaryOk)
  · simp only [exceptT_bind_ok_iff] at accepted
    obtain ⟨_, impossible, _⟩ := accepted
    cases impossible

/-- Successful evaluation supplies its real pre-finalization collection, with
exact ordinary-use coverage. No collection witness is assumed by callers. -/
theorem evaluate_use_collection {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot) :
    ∃ collected, finish collected = .ok snapshot ∧
      Collected.uses collected = p.ordinary.flatMap (·.accepted.uses) := by
  simp only [evaluate, except_bind_ok_iff] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, collected, assembled, finished⟩ := accepted
  exact ⟨collected, finished, assemble_uses _ _ assembled⟩

/-- Every use from an accepted ordinary plan entry reaches each matching final
project context. Duplicate payloads may merge, but source/facet/target remain. -/
theorem evaluate_use_in_context {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (member : use ∈ p.ordinary.flatMap (·.accepted.uses))
    (available : UseSelection.ContextFor snapshot.registry.contributions use context) :
    ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = some context := by
  obtain ⟨collected, finished, uses⟩ := evaluate_use_collection accepted
  rw [← uses] at member
  obtain ⟨edge, edgeMember, aligned, context, _⟩ := finish_use_in_context finished member available
  exact ⟨edge, edgeMember, aligned, context⟩

/-- A use without a matching source context remains an explicit diagnostic,
including when the complete evaluator succeeds. -/
theorem evaluate_use_without_context {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (accepted : evaluate p observations = .ok snapshot)
    (member : use ∈ p.ordinary.flatMap (·.accepted.uses))
    (missing : ∀ context, ¬ UseSelection.ContextFor snapshot.registry.contributions use context) :
    ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = none ∧
      edge.selected = .error {
        code := "missing-source-context", subject := use.node.toString
        message := "Dependency has no stored source project context" } := by
  obtain ⟨collected, finished, uses⟩ := evaluate_use_collection accepted
  rw [← uses] at member
  exact finish_use_without_context finished member missing

/-- Every ordinary plan use of a completed native parent has a retained target
contract and fitting original evidence for every returned obligation. The actual
evaluator supplies collection, selection, gate creation and wiring; none is an
extra caller premise. Plan construction and provider authenticity are separate. -/
theorem evaluate_ordinary_use_justified
    {p : Plan} {observations : Observations p} {snapshot : Snapshot}
    (evaluated : evaluate p observations = .ok snapshot)
    (useMember : use ∈ p.ordinary.flatMap (·.accepted.uses))
    (modelMember : model ∈ snapshot.registry.contributions.realizations.map (·.value))
    (native : model.context.language = `lean)
    (declarationMember : declaration ∈ model.declarations)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (parentMember : parent ∈ snapshot.registry.contributions.requirements)
    (parentKey : parent.value.key = ⟨.declaration model.key declaration.object, name⟩)
    (origin : DependencySelection.CollectorOwned parent.origin parent.value.key)
    (expected : parent.value.expected = .check validator)
    (coverage : parent.value.coverage = .dependencyClosure)
    (source : use.node = model.key.node)
    (restriction : ∀ realization, use.realization = some realization → realization = model.key.name)
    (useFacet : name = `proof ∨ use.facet = `statement)
    (complete : (snapshot.registry.resultForRequirement parent.value.key).complete = true) :
    ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = some model.context ∧
      ∃ keys, edge.selected = .ok keys ∧
        TargetSelection.Retained snapshot.registry model.context use.reference.label keys ∧
        ∀ selected ∈ keys, selected ∈ parent.value.prerequisites ∧
          ∃ requirement ∈ snapshot.registry.contributions.requirements,
            ∃ evidence ∈ snapshot.registry.contributions.evidence,
              snapshot.registry.requirement? selected = some requirement.value ∧
              requirement.value.key = selected ∧
              evidence.value.Fits requirement.value ((snapshot.registry.bindingFor selected).getD "") := by
  obtain ⟨collected, finished, uses⟩ := evaluate_use_collection evaluated
  rw [← uses] at useMember
  exact finish_collected_use_justified evaluated finished useMember modelMember native
    declarationMember facet parentMember parentKey origin expected coverage source
    restriction useFacet complete

end Informal.Realizations.Capture
