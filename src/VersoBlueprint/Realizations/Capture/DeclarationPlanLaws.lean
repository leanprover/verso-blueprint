/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.ModelLaws

/-! Exact source/declaration correspondence through the actual planner.
Request handles, provider authenticity and required-key coverage remain separate. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

-- Only shared proof helpers need private access; production visibility is unchanged.
run_cmd do
  let env ← getEnv
  let owners ← #[``finish_uses, ``plan_raw].mapM fun name => do
    let some owner := env.getModuleIdxFor? name | throwError "Capture helpers must be imported"
    pure owner
  for (name, _) in env.constants.toList do
    if (env.getModuleIdxFor? name).any owners.contains then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

/-- One joint projection, retaining the source payloads next to the names that
their realization plans to check. It deliberately omits request handles. -/
def RealizationStep.sourceInventory (step : RealizationStep) :
    RealizationKey × Array FacetSource × Array NativeAssociation × Array Name :=
  (step.key, step.sources.map (·.source), step.associations, step.declarations.map (·.name))

private def sourceInventoryAt (accepted : Environment.RegisteredNode) (key : RealizationKey) :
    RealizationKey × Array FacetSource × Array NativeAssociation × Array Name :=
  let sources := accepted.sources.filter (·.destination.realization == key)
  let associations := accepted.nativeAssociations.filter (·.realization == key)
  (key, sources, associations, nativeNames associations sources)

/-- Source-side specification of the ordered realization inventory. This is a
law-layer projection, not another planner. -/
def sourceInventoryFor (accepted : Environment.RegisteredNode) :
    Array (RealizationKey × Array FacetSource × Array NativeAssociation × Array Name) :=
  (canonical (accepted.sources.map (·.destination.realization) ++ accepted.nativeAssociations.map (·.realization))).map
    (sourceInventoryAt accepted)

private def SourcesMatch (p : Plan) : Prop :=
  ∀ node ∈ p.ordinary, node.realizations.map (·.sourceInventory) = sourceInventoryFor node.accepted

private theorem plan_sourcesMatch (raw : Raw) : SourcesMatch (plan raw) := by
  unfold plan
  simp only [Id.run, bind, pure]
  generalize ordinaryEq : forIn (m := Id) raw.nodes ({ raw } : Plan) _ = ordinary
  apply id_array_loop_invariant _ SourcesMatch _ ?_ ?_
  · rw [← ordinaryEq]
    apply id_array_loop_invariant raw.nodes SourcesMatch _ (by simp [SourcesMatch])
    intro entry member current prior
    rcases entry with ⟨label, accepted⟩
    clear ordinaryEq
    generalize realizationEq : forIn (m := Id) (α := RealizationKey)
      (β := Plan × Array RealizationStep) (_ : Array RealizationKey) (current, #[]) _ = expanded
    have realized : (expanded.1.ordinary, expanded.2.map (·.sourceInventory)) =
        (current.ordinary, sourceInventoryFor accepted) := by
      rw [← realizationEq]
      refine (id_array_loop_projects _
        (fun pair : Plan × Array RealizationStep => (pair.1.ordinary, pair.2.map (·.sourceInventory)))
        (sourceInventoryAt accepted) _ ?_).trans ?_
      · intro key member pair
        clear realizationEq
        generalize sourcesEq : forIn (m := Id) (α := FacetSource)
          (β := Plan × Array SourceStep) (_ : Array FacetSource) (pair.1, #[]) _ = sourced
        have sourceInventory : (sourced.1.ordinary, sourced.2.map (·.source)) =
            (pair.1.ordinary, accepted.sources.filter (·.destination.realization == key)) := by
          rw [← sourcesEq]
          refine (id_array_loop_projects _
            (fun pair : Plan × Array SourceStep => (pair.1.ordinary, pair.2.map (·.source))) id _ ?_).trans ?_
          · intro source member pair
            cases source.payload <;> simp only
            all_goals (repeat' split) <;> exact ⟨_, rfl, by simp [Array.map_push]⟩
          · simp
        generalize declarationsEq : forIn (m := Id) (α := Name)
          (β := Plan × Array DeclarationStep) (_ : Array Name) (sourced.1, #[]) _ = declared
        have declarationInventory : (declared.1.ordinary, declared.2.map (·.name)) =
            (sourced.1.ordinary, nativeNames (accepted.nativeAssociations.filter (·.realization == key))
              (accepted.sources.filter (·.destination.realization == key))) := by
          rw [← declarationsEq]
          refine (id_array_loop_projects _
            (fun pair : Plan × Array DeclarationStep => (pair.1.ordinary, pair.2.map (·.name))) id _ ?_).trans ?_
          · intro name member pair
            clear sourcesEq declarationsEq
            refine ⟨_, rfl, ?_⟩
            generalize nativeEq : forIn (m := Id) (α := NativeAssociation)
              (β := Plan × Array Nat) (_ : Array NativeAssociation) (pair.1, #[]) _ = native
            have nativeUnchanged : native.1.ordinary = pair.1.ordinary := by
              rw [← nativeEq]
              apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => pair.1.ordinary = _) _ rfl
              intro association member pair prior
              exact prior
            generalize inlineEq : forIn (m := Id) (α := FacetSource)
              (β := Plan × Array Nat) (_ : Array FacetSource) (native.1, #[]) _ = inline
            have inlineUnchanged : inline.1.ordinary = native.1.ordinary := by
              rw [← inlineEq]
              apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => pair.1.ordinary = _) _ rfl
              intro source member pair prior
              cases source.payload <;> simp only
              all_goals first
                | exact prior
                | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
            simpa only [Array.map_push, id_eq] using congrArg
              (fun ordinary => (ordinary, (pair.2.map (·.name)).push name))
              (inlineUnchanged.trans nativeUnchanged)
          · simp
        refine ⟨_, rfl, ?_⟩
        simp only [Prod.mk.injEq] at sourceInventory declarationInventory
        simp only [Array.map_push, RealizationStep.sourceInventory, sourceInventoryAt]
        rw [declarationInventory.1, sourceInventory.1, sourceInventory.2, declarationInventory.2]
      · simp [sourceInventoryFor]
    simp only [Prod.mk.injEq] at realized
    intro node member
    simp only [Array.mem_push] at member
    rcases member with member | rfl
    · exact prior node (by rwa [realized.1] at member)
    · exact realized.2
  · intro record member current prior
    clear ordinaryEq
    apply id_array_loop_invariant _
      (fun pair : Plan × Array Nat => SourcesMatch pair.1) _ ?_ ?_
    · apply id_array_loop_invariant _
        (fun pair : Plan × Array Nat => SourcesMatch pair.1) _ prior
      intro goal member pair prior
      exact prior
    · intro document member pair prior
      exact prior

/-- Every generated node has exactly its source-side realization inventory:
keys, filtered payloads and declaration-name unions remain paired and ordered.
No acceptance, validity or uniqueness premise is needed. -/
theorem plan_realization_sources (raw : Raw) (nodeMember : node ∈ (plan raw).ordinary) :
    node.realizations.map (·.sourceInventory) = sourceInventoryFor node.accepted :=
  plan_sourcesMatch raw node nodeMember

/-- A generated realization retains precisely the payloads for its source key,
and its declaration steps enumerate exactly their native declaration union. -/
theorem plan_realization_fields (raw : Raw) (nodeMember : node ∈ (plan raw).ordinary)
    (stepMember : step ∈ node.realizations) :
    step.key ∈ canonical (node.accepted.sources.map (·.destination.realization) ++
      node.accepted.nativeAssociations.map (·.realization)) ∧
    step.sources.map (·.source) = node.accepted.sources.filter (·.destination.realization == step.key) ∧
    step.associations = node.accepted.nativeAssociations.filter (·.realization == step.key) ∧
    step.declarations.map (·.name) = nativeNames step.associations (step.sources.map (·.source)) := by
  have member : step.sourceInventory ∈ sourceInventoryFor node.accepted := by
    rw [← plan_realization_sources raw nodeMember]
    exact Array.mem_map.mpr ⟨step, stepMember, rfl⟩
  obtain ⟨key, member, fields⟩ := Array.mem_map.mp member
  simp only [sourceInventoryAt, RealizationStep.sourceInventory, Prod.mk.injEq] at fields
  rcases fields with ⟨rfl, sources, associations, declarations⟩
  exact ⟨member, sources.symm, associations.symm, by rw [← sources, ← associations]; exact declarations.symm⟩

/-- Exact name-array correspondence, not just successful-example membership. -/
theorem plan_declaration_names (raw : Raw) (nodeMember : node ∈ (plan raw).ordinary)
    (stepMember : step ∈ node.realizations) :
    step.declarations.map (·.name) = nativeNames step.associations (step.sources.map (·.source)) :=
  (plan_realization_fields raw nodeMember stepMember).2.2.2

/-- Every source declaration gets a declaration step, and no additional name is
invented. Request-handle correctness is not part of this membership law. -/
theorem plan_declaration_mem_iff (raw : Raw) (nodeMember : node ∈ (plan raw).ordinary)
    (stepMember : step ∈ node.realizations) (name : Name) :
    (∃ declaration ∈ step.declarations, declaration.name = name) ↔
      name ∈ nativeNames step.associations (step.sources.map (·.source)) := by
  rw [← plan_declaration_names raw nodeMember stepMember, Array.mem_map]

/-- Every raw node/realization pair supplies the actual generated steps with
matching accepted record, key, source payloads and associations. -/
theorem plan_raw_realization (raw : Raw) (rawMember : (label, accepted) ∈ raw.nodes)
    (keyMember : key ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization))) :
    ∃ node ∈ (plan raw).ordinary, node.label = label ∧ node.accepted = accepted ∧
      ∃ step ∈ node.realizations, step.key = key ∧
        step.sources.map (·.source) = accepted.sources.filter (·.destination.realization == key) ∧
        step.associations = accepted.nativeAssociations.filter (·.realization == key) := by
  rw [← plan_ordinary_nodes raw, Array.mem_map] at rawMember
  obtain ⟨node, nodeMember, nodeFields⟩ := rawMember
  have labelEq : node.label = label := congrArg Prod.fst nodeFields
  have acceptedEq : node.accepted = accepted := congrArg Prod.snd nodeFields
  have inventoryMember : sourceInventoryAt accepted key ∈ sourceInventoryFor node.accepted := by
    rw [acceptedEq]
    exact Array.mem_map.mpr ⟨key, keyMember, rfl⟩
  rw [← plan_realization_sources raw nodeMember, Array.mem_map] at inventoryMember
  obtain ⟨step, stepMember, fields⟩ := inventoryMember
  simp only [RealizationStep.sourceInventory, sourceInventoryAt, Prod.mk.injEq] at fields
  exact ⟨node, nodeMember, labelEq, acceptedEq, step, stepMember, fields.1, fields.2.1, fields.2.2.1⟩

/-- Completion for an actual raw source declaration justifies its source uses.
The production planner supplies all intermediate node/realization/declaration
steps; evaluation supplies final models, parent requirements and selected edges.
Source context/scope and completion remain explicit, as does provider authenticity
outside this pure theorem. -/
theorem evaluate_raw_source_use_justified
    {raw : Raw} {observations : Observations (plan raw)} {snapshot : Snapshot}
    (evaluated : evaluate (plan raw) observations = .ok snapshot)
    (useMember : use ∈ raw.nodes.flatMap (·.2.uses))
    (rawMember : (label, accepted) ∈ raw.nodes)
    (keyMember : key ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization)))
    (sourceDeclaration : declarationName ∈ nativeNames
      (accepted.nativeAssociations.filter (·.realization == key))
      (accepted.sources.filter (·.destination.realization == key)))
    (contextAgrees : canonical ((accepted.sources.filter (·.destination.realization == key)).map (·.context) ++
      (accepted.nativeAssociations.filter (·.realization == key)).map (·.context)) = #[context])
    (native : context.language = `lean)
    (facet : (name, validator) ∈ #[(`statement, NativeLean.statementValidator), (`proof, NativeLean.bodyValidator)])
    (source : use.node = key.node)
    (restriction : ∀ realization, use.realization = some realization → realization = key.name)
    (useFacet : name = `proof ∨ use.facet = `statement)
    (complete : (snapshot.registry.resultForRequirement
      ⟨.declaration key ⟨context, declarationName.toString⟩, name⟩).complete = true) :
    ∃ parent ∈ snapshot.registry.contributions.requirements,
      parent.value.key = ⟨.declaration key ⟨context, declarationName.toString⟩, name⟩ ∧
      DependencySelection.CollectorOwned parent.origin parent.value.key ∧
      parent.value.expected = .check validator ∧ parent.value.coverage = .dependencyClosure ∧
      ∃ edge ∈ snapshot.uses, UseSelection.Matches use edge ∧ edge.context = some context ∧
        ∃ keys, edge.selected = .ok keys ∧
          TargetSelection.Retained snapshot.registry context use.reference.label keys ∧
          ∀ selected ∈ keys, selected ∈ parent.value.prerequisites ∧
            ∃ requirement ∈ snapshot.registry.contributions.requirements,
              ∃ evidence ∈ snapshot.registry.contributions.evidence,
                snapshot.registry.requirement? selected = some requirement.value ∧
                requirement.value.key = selected ∧
                evidence.value.Fits requirement.value ((snapshot.registry.bindingFor selected).getD "") := by
  obtain ⟨node, nodeMember, _, _, step, stepMember, stepKey, sources, associations⟩ :=
    plan_raw_realization raw rawMember keyMember
  have sourceMember : declarationName ∈ nativeNames step.associations (step.sources.map (·.source)) := by
    rwa [sources, associations]
  obtain ⟨planned, plannedMember, plannedName⟩ :=
    (plan_declaration_mem_iff raw nodeMember stepMember declarationName).mpr sourceMember
  have sameContext : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context] := by
    have mapped := congrArg (Array.map (·.context)) sources
    simpa only [Array.map_map, Function.comp_def, associations, ← mapped] using contextAgrees
  have result := evaluate_declared_use_justified evaluated (by rwa [plan_ordinary_uses]) nodeMember
    stepMember plannedMember (by rwa [plannedName]) sameContext native facet
    (by rwa [stepKey]) (by rwa [stepKey]) useFacet (by rwa [stepKey, plannedName])
  simpa only [stepKey, plannedName] using result

end Informal.Realizations.Capture
