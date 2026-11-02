/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.CollectionLaws
import VersoBlueprint.Util.NameMapLaws

/-! The actual planner preserves raw accepted nodes and their source-use inventory.
Request correctness, provider authenticity and native-contract coverage are separate. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

-- Only shared proof helpers need private access; production visibility is unchanged.
run_cmd do
  let env ← getEnv
  let some owner := env.getModuleIdxFor? ``finish_uses
    | throwError "Capture recipe helpers must be imported"
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some owner then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

private theorem id_list_loop_projects (entries : List α) (project : β → δ × Array γ)
    (payload : α → γ) (body : α → β → Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ current, ∃ next, body entry current = .yield next ∧
      project next = ((project current).1, (project current).2.push (payload entry))) :
    project (forIn entries initial body) =
      ((project initial).1, (project initial).2 ++ (entries.map payload).toArray) := by
  induction entries generalizing initial with
  | nil => simp [pure]
  | cons entry entries ih =>
    obtain ⟨next, executed, projected⟩ := step entry (by simp) initial
    simp only [List.forIn_cons, executed, bind]
    rw [ih (fun item member => step item (by simp [member])), projected]
    simp

private theorem id_array_loop_projects (entries : Array α) (project : β → δ × Array γ)
    (payload : α → γ) (body : α → β → Id (ForInStep β))
    (step : ∀ entry ∈ entries, ∀ current, ∃ next, body entry current = .yield next ∧
      project next = ((project current).1, (project current).2.push (payload entry))) :
    project (forIn entries initial body) =
      ((project initial).1, (project initial).2 ++ entries.map payload) := by
  rw [← Array.forIn_toList]
  simpa only [← List.map_toArray, Array.toArray_toList] using id_list_loop_projects (initial := initial) entries.toList project payload body
    (fun entry member => step entry (by simpa using member))

private def inventory (p : Plan) : Raw × Array (Name × Environment.RegisteredNode) :=
  (p.raw, p.ordinary.map fun step => (step.label, step.accepted))

private theorem plan_inventory (raw : Raw) : inventory (plan raw) = (raw, raw.nodes) := by
  unfold plan
  simp only [Id.run, bind, pure]
  generalize ordinaryEq : forIn (m := Id) raw.nodes ({ raw } : Plan) _ = ordinary
  apply id_array_loop_invariant _ (fun p => inventory p = (raw, raw.nodes)) _ ?_ ?_
  · rw [← ordinaryEq]
    refine (id_array_loop_projects raw.nodes inventory id _ ?_).trans ?_
    · intro entry member current
      rcases entry with ⟨label, accepted⟩
      clear ordinaryEq
      refine ⟨_, rfl, ?_⟩
      generalize realizationEq : forIn (m := Id) (α := RealizationKey)
        (β := Plan × Array RealizationStep) (_ : Array RealizationKey) (current, #[]) _ = expanded
      have unchanged : inventory expanded.1 = inventory current := by
        rw [← realizationEq]
        apply id_array_loop_invariant _ (fun pair : Plan × Array RealizationStep => inventory pair.1 = inventory current) _ rfl
        intro key member pair prior
        clear realizationEq
        apply id_array_loop_invariant _
          (fun pair : Plan × Array DeclarationStep => inventory pair.1 = inventory current) _ ?_ ?_
        · apply id_array_loop_invariant _
            (fun pair : Plan × Array SourceStep => inventory pair.1 = inventory current) _ prior
          intro source member pair prior
          cases source.payload <;> simp only
          all_goals first
            | exact prior
            | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
        · intro name member pair prior
          apply id_array_loop_invariant _
            (fun pair : Plan × Array Nat => inventory pair.1 = inventory current) _ ?_ ?_
          · apply id_array_loop_invariant _
              (fun pair : Plan × Array Nat => inventory pair.1 = inventory current) _ prior
            intro association member pair prior
            exact prior
          · intro source member pair prior
            cases source.payload <;> simp only
            all_goals first
              | exact prior
              | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
      simpa only [inventory, Array.map_push, id_eq] using congrArg
        (fun value : Raw × Array (Name × Environment.RegisteredNode) =>
          (value.1, value.2.push (label, accepted))) unchanged
    · simp [inventory]
  · intro record member current prior
    clear ordinaryEq
    apply id_array_loop_invariant _
      (fun pair : Plan × Array Nat => inventory pair.1 = (raw, raw.nodes)) _ ?_ ?_
    · apply id_array_loop_invariant _
        (fun pair : Plan × Array Nat => inventory pair.1 = (raw, raw.nodes)) _ prior
      intro goal member pair prior
      exact prior
    · intro document member pair prior
      exact prior

/-- Planning retains the complete raw input, including pending registrations,
fact records, authored entries and initial issues. -/
theorem plan_raw (raw : Raw) : (plan raw).raw = raw :=
  congrArg Prod.fst (plan_inventory raw)

/-- Every raw node is copied exactly once in input order, with its original label
and entire accepted record kept together. No validity or uniqueness is assumed. -/
theorem plan_ordinary_nodes (raw : Raw) :
    (plan raw).ordinary.map (fun step => (step.label, step.accepted)) = raw.nodes :=
  congrArg Prod.snd (plan_inventory raw)

/-- The planner preserves all source uses, before collection or scope merging. -/
theorem plan_ordinary_uses (raw : Raw) :
    (plan raw).ordinary.flatMap (·.accepted.uses) = raw.nodes.flatMap (·.2.uses) := by
  simpa only [Array.flatMap_map, Function.comp_def] using congrArg
    (fun nodes : Array (Name × Environment.RegisteredNode) => nodes.flatMap (·.2.uses))
    (plan_ordinary_nodes raw)

/-- Raw capture exposes uses of exactly the records returned by the actual
accepted-node lookup. Pending entries absent from that lookup contribute no uses. -/
theorem Raw.ofState_use_iff (state : Environment.State) (use : UseDeclaration) :
    use ∈ (Raw.ofState state).nodes.flatMap (·.2.uses) ↔
      ∃ label node, state.data.get? label = some node ∧ use ∈ node.uses := by
  simp only [Raw.ofState, Array.mem_flatMap, Prod.exists, NameMapLaws.mem_toArray]

/-- Raw accepted-node uses reach every matching project context through the
actual planner and evaluator, without an assumed plan inventory. -/
theorem evaluate_raw_use_in_context {raw : Raw} {observations : Observations (plan raw)}
    {snapshot : Snapshot} (accepted : evaluate (plan raw) observations = .ok snapshot)
    (member : use ∈ raw.nodes.flatMap (·.2.uses))
    (available : UseSelection.ContextFor snapshot.registry.contributions use context) :
    ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = some context := by
  exact evaluate_use_in_context accepted (by rwa [plan_ordinary_uses]) available

/-- Missing source contexts remain explicit diagnostics for raw accepted uses. -/
theorem evaluate_raw_use_without_context {raw : Raw} {observations : Observations (plan raw)}
    {snapshot : Snapshot} (accepted : evaluate (plan raw) observations = .ok snapshot)
    (member : use ∈ raw.nodes.flatMap (·.2.uses))
    (missing : ∀ context, ¬ UseSelection.ContextFor snapshot.registry.contributions use context) :
    ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = none ∧
      edge.selected = .error {
        code := "missing-source-context", subject := use.node.toString
        message := "Dependency has no stored source project context" } := by
  exact evaluate_use_without_context accepted (by rwa [plan_ordinary_uses]) missing

/-- Completed eligible native parents justify their raw accepted source uses.
The actual planner, collection recipe, selector and wiring pass connect each use
to retained obligations with fitting original evidence. Provider authenticity
and positive native-contract coverage remain separate. -/
theorem evaluate_raw_use_justified
    {raw : Raw} {observations : Observations (plan raw)} {snapshot : Snapshot}
    (evaluated : evaluate (plan raw) observations = .ok snapshot)
    (useMember : use ∈ raw.nodes.flatMap (·.2.uses))
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
  exact evaluate_ordinary_use_justified evaluated (by rwa [plan_ordinary_uses])
    modelMember native declarationMember facet parentMember parentKey origin expected
    coverage source restriction useFacet complete

end Informal.Realizations.Capture
