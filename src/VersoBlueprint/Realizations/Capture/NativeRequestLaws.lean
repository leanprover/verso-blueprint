/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.AuthoredRequestLaws

/-! Ordered native source-request correspondence, including complete associations. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

run_cmd do
  let env ← getEnv
  let owners ← #[``finish_uses, ``plan_declaration_check, ``plan_authored_goal_handles].mapM fun name => do
    let some owner := env.getModuleIdxFor? name | throwError "Capture law helpers must be imported"
    pure owner
  for (name, _) in env.constants.toList do
    if (env.getModuleIdxFor? name).any owners.contains then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

/-- Handle positions correspond to full association records, retaining order and
multiplicity. This is a law about existing request arrays, not another inventory. -/
def NativeRequestSequence (requests : Array NativeRequest) (context : Context) (name : Name)
    (associations : Array NativeAssociation) (handles : Array Nat) : Prop :=
  associations.size = handles.size ∧ ∀ (index : Nat) association,
    associations[index]? = some association →
      ∃ handle, handles[index]? = some handle ∧
        requests[handle]? = some { context, name, association }

private theorem NativeRequestSequence.preserve
    (valid : NativeRequestSequence before context name associations handles)
    (growth : PreservesLookups before after) :
    NativeRequestSequence after context name associations handles :=
  ⟨valid.1, fun index association found => by
    obtain ⟨handle, selected, request⟩ := valid.2 index association found
    exact ⟨handle, selected, growth _ _ request⟩⟩

private theorem NativeRequestSequence.push
    (valid : NativeRequestSequence requests context name associations handles)
    (found : requests[handle]? = some { context, name, association }) :
    NativeRequestSequence requests context name (associations.push association) (handles.push handle) := by
  refine ⟨by simp [valid.1], ?_⟩
  intro index selected lookup
  by_cases bound : index < associations.size
  · have old : associations[index]? = some selected := by
      simpa [Array.getElem?_push, bound, Nat.ne_of_lt bound] using lookup
    obtain ⟨oldHandle, selectedHandle, request⟩ := valid.2 index selected old
    exact ⟨oldHandle, preservesLookups_push _ _ _ _ selectedHandle, request⟩
  · have atEnd : index = associations.size := by
      have bound := (Array.getElem?_eq_some_iff.mp lookup).1
      simp only [Array.size_push] at bound
      omega
    subst index
    have same : association = selected := by simpa using lookup
    subst selected
    exact ⟨handle, by simp [valid.1], found⟩

private def DeclarationNative (requests : Array NativeRequest) (context : Context)
    (associations : Array NativeAssociation) (declarations : Array DeclarationStep) : Prop :=
  ∀ declaration ∈ declarations, NativeRequestSequence requests context declaration.name
    (associations.filter (·.reference.canonical == declaration.name)) declaration.native

private theorem DeclarationNative.preserve (valid : DeclarationNative before context associations declarations)
    (growth : PreservesLookups before after) : DeclarationNative after context associations declarations :=
  fun declaration member => (valid declaration member).preserve growth

private def RealizationNative (requests : Array NativeRequest) (accepted : Environment.RegisteredNode)
    (steps : Array RealizationStep) : Prop :=
  ∀ step ∈ steps, DeclarationNative requests (sourceContext accepted step.key) step.associations step.declarations

private theorem RealizationNative.preserve (valid : RealizationNative before accepted steps)
    (growth : PreservesLookups before after) : RealizationNative after accepted steps :=
  fun step member => (valid step member).preserve growth

private def PlanNative (p : Plan) : Prop :=
  ∀ node ∈ p.ordinary, RealizationNative p.native node.accepted node.realizations

private theorem plan_native (raw : Raw) : PlanNative (plan raw) := by
  unfold plan
  simp only [Id.run, bind, pure]
  generalize ordinaryEq : forIn (m := Id) raw.nodes ({ raw } : Plan) _ = ordinary
  apply id_array_loop_invariant _ PlanNative _ ?_ ?_
  · rw [← ordinaryEq]
    apply id_array_loop_invariant raw.nodes PlanNative _ (by simp [PlanNative])
    intro entry member current prior
    rcases entry with ⟨label, accepted⟩
    clear ordinaryEq
    generalize realizationEq : forIn (m := Id) (α := RealizationKey)
      (β := Plan × Array RealizationStep) (_ : Array RealizationKey) (current, #[]) _ = expanded
    have realized : expanded.1.ordinary = current.ordinary ∧
        PreservesLookups current.native expanded.1.native ∧
        RealizationNative expanded.1.native accepted expanded.2 := by
      rw [← realizationEq]
      apply id_array_loop_invariant _
        (fun pair : Plan × Array RealizationStep => pair.1.ordinary = current.ordinary ∧
          PreservesLookups current.native pair.1.native ∧ RealizationNative pair.1.native accepted pair.2)
        _ ⟨rfl, preservesLookups_refl _, by simp [RealizationNative]⟩
      intro key member pair prior
      clear realizationEq
      generalize sourcesEq : forIn (m := Id) (α := FacetSource)
        (β := Plan × Array SourceStep) (_ : Array FacetSource) (pair.1, #[]) _ = sourced
      have sourcesUnchanged : (sourced.1.ordinary, sourced.1.native) = (pair.1.ordinary, pair.1.native) := by
        rw [← sourcesEq]
        apply id_array_loop_invariant _
          (fun pair : Plan × Array SourceStep => (pair.1.ordinary, pair.1.native) = _) _ rfl
        intro source member pair prior
        cases source.payload <;> simp only
        all_goals first
          | exact prior
          | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
      generalize declarationsEq : forIn (m := Id) (α := Name)
        (β := Plan × Array DeclarationStep) (_ : Array Name) (sourced.1, #[]) _ = declared
      have declaredNative : declared.1.ordinary = sourced.1.ordinary ∧
          PreservesLookups sourced.1.native declared.1.native ∧
          DeclarationNative declared.1.native (sourceContext accepted key)
            (accepted.nativeAssociations.filter (·.realization == key)) declared.2 := by
        rw [← declarationsEq]
        apply id_array_loop_invariant _
          (fun pair : Plan × Array DeclarationStep => pair.1.ordinary = sourced.1.ordinary ∧
            PreservesLookups sourced.1.native pair.1.native ∧
            DeclarationNative pair.1.native (sourceContext accepted key)
              (accepted.nativeAssociations.filter (·.realization == key)) pair.2)
          _ ⟨rfl, preservesLookups_refl _, by simp [DeclarationNative]⟩
        intro name member pair prior
        clear sourcesEq declarationsEq
        generalize nativeEq : forIn (m := Id) (α := NativeAssociation)
          (β := Plan × Array Nat) (_ : Array NativeAssociation) (pair.1, #[]) _ = native
        have nativeRequests : native.1.ordinary = pair.1.ordinary ∧
            PreservesLookups pair.1.native native.1.native ∧
            NativeRequestSequence native.1.native (sourceContext accepted key) name
              ((accepted.nativeAssociations.filter (·.realization == key)).filter (·.reference.canonical == name)) native.2 := by
          rw [← nativeEq]
          apply id_array_loop_history _
            (fun processed (pair' : Plan × Array Nat) => pair'.1.ordinary = pair.1.ordinary ∧
              PreservesLookups pair.1.native pair'.1.native ∧
              NativeRequestSequence pair'.1.native (sourceContext accepted key) name processed pair'.2)
            _ ?_ ⟨rfl, preservesLookups_refl _, by simp [NativeRequestSequence]⟩
          intro association member processed pair' prior
          refine ⟨_, rfl, prior.1, PreservesLookups.trans prior.2.1 (preservesLookups_push _ _), ?_⟩
          apply NativeRequestSequence.push
          · exact prior.2.2.preserve (preservesLookups_push _ _)
          · simp [sourceContext]
        generalize inlineEq : forIn (m := Id) (α := FacetSource)
          (β := Plan × Array Nat) (_ : Array FacetSource) (native.1, #[]) _ = inline
        have inlineUnchanged : (inline.1.ordinary, inline.1.native) = (native.1.ordinary, native.1.native) := by
          rw [← inlineEq]
          apply id_array_loop_invariant _
            (fun pair : Plan × Array Nat => (pair.1.ordinary, pair.1.native) = _) _ rfl
          intro source member pair prior
          cases source.payload <;> simp only
          all_goals first
            | exact prior
            | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
        have unchanged := Prod.mk.inj inlineUnchanged
        have growth : PreservesLookups pair.1.native inline.1.native := by
          rw [unchanged.2]
          exact nativeRequests.2.1
        refine ⟨unchanged.1.trans (nativeRequests.1.trans prior.1), PreservesLookups.trans prior.2.1 growth, ?_⟩
        intro declaration member
        simp only [Array.mem_push] at member
        rcases member with member | rfl
        · exact (prior.2.2 declaration member).preserve growth
        · simpa only [unchanged.2] using nativeRequests.2.2
      have unchanged := Prod.mk.inj sourcesUnchanged
      have growth : PreservesLookups pair.1.native declared.1.native := by
        rw [← unchanged.2]
        exact declaredNative.2.1
      refine ⟨declaredNative.1.trans (unchanged.1.trans prior.1), PreservesLookups.trans prior.2.1 growth, ?_⟩
      intro step member
      simp only [Array.mem_push] at member
      rcases member with member | rfl
      · exact (prior.2.2 step member).preserve growth
      · exact declaredNative.2.2
    intro node member
    simp only [Array.mem_push] at member
    rcases member with member | rfl
    · exact (prior node (by rwa [realized.1] at member)).preserve realized.2.1
    · exact realized.2.2
  · intro record member current prior
    clear ordinaryEq
    apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => PlanNative pair.1) _ ?_ ?_
    · apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => PlanNative pair.1) _ prior
      intro goal member pair prior
      exact prior
    · intro document member pair prior
      exact prior

/-- The original association position supplies both bounds and the exact job read
by the observer. Whole-record equality retains provenance, facets and snapshots. -/
theorem NativeRequestSequence.job {index : Nat}
    (sequence : NativeRequestSequence requests context name associations handles)
    (source : associations[index]? = some association) :
    index < handles.size ∧ handles[index]! < requests.size ∧
      requests[handles[index]!]! = { context, name, association } := by
  obtain ⟨handle, selected, request⟩ := sequence.2 index association source
  have indexBound := (Array.getElem?_eq_some_iff.mp selected).1
  have handleEq : handles[index]! = handle := by
    simpa only [getElem!_pos, indexBound] using (Array.getElem?_eq_some_iff.mp selected).2
  have handleBound := (Array.getElem?_eq_some_iff.mp request).1
  refine ⟨indexBound, ?_⟩
  rw [handleEq]
  exact ⟨handleBound, by simpa only [getElem!_pos, handleBound] using
    (Array.getElem?_eq_some_iff.mp request).2⟩

/-- Native handles preserve the exact filtered association sequence, including
order, duplicates and all fields. Context follows the actual planner policy;
no global admission or successful-evaluation premise is needed. -/
theorem plan_native_request_sequence (raw : Raw) (nodeMember : node ∈ (plan raw).ordinary)
    (stepMember : step ∈ node.realizations) (declarationMember : declaration ∈ step.declarations) :
    let context := (canonical ((node.accepted.sources.filter (·.destination.realization == step.key)).map (·.context) ++
      (node.accepted.nativeAssociations.filter (·.realization == step.key)).map (·.context)))[0]?.getD default
    NativeRequestSequence (plan raw).native context declaration.name
      (step.associations.filter (·.reference.canonical == declaration.name)) declaration.native :=
  plan_native raw node nodeMember step stepMember declaration declarationMember

/-- Agreed source context exposes the exact project alongside each full native
association. Inline overlap does not erase the native source-request sequence. -/
theorem plan_native_requests (raw : Raw) (nodeMember : node ∈ (plan raw).ordinary)
    (stepMember : step ∈ node.realizations) (declarationMember : declaration ∈ step.declarations)
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    NativeRequestSequence (plan raw).native context declaration.name
      (step.associations.filter (·.reference.canonical == declaration.name)) declaration.native := by
  have fields := plan_realization_fields raw nodeMember stepMember
  have mapped := congrArg (Array.map (·.context)) fields.2.1
  have agreed : canonical ((node.accepted.sources.filter (·.destination.realization == step.key)).map (·.context) ++
      (node.accepted.nativeAssociations.filter (·.realization == step.key)).map (·.context)) = #[context] := by
    simpa only [Array.map_map, Function.comp_def, fields.2.2.1, ← mapped] using contextAgrees
  have sequence := plan_native_request_sequence raw nodeMember stepMember declarationMember
  simpa only [agreed, Array.getElem?_singleton, ite_true, Option.getD_some] using sequence

/-- An accepted raw association supplies its actual realization, declaration and
bounded observer job, retaining the complete association. Neither declaration
membership nor a correctly resolved source handle is assumed by the caller. -/
theorem plan_raw_native_request (raw : Raw) (rawMember : (label, accepted) ∈ raw.nodes)
    (associationMember : association ∈ accepted.nativeAssociations)
    (contextAgrees : canonical ((accepted.sources.filter (·.destination.realization == association.realization)).map (·.context) ++
      (accepted.nativeAssociations.filter (·.realization == association.realization)).map (·.context)) = #[context]) :
    ∃ node ∈ (plan raw).ordinary, node.label = label ∧ node.accepted = accepted ∧
      ∃ step ∈ node.realizations, step.key = association.realization ∧
        ∃ declaration ∈ step.declarations, declaration.name = association.reference.canonical ∧
          ∃ index, index < declaration.native.size ∧
            declaration.native[index]! < (plan raw).native.size ∧
            (plan raw).native[declaration.native[index]!]! =
              { context, name := association.reference.canonical, association } := by
  have keyMember : association.realization ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization)) :=
    (mem_canonical _ _).mpr (Array.mem_append_right _ (Array.mem_map.mpr ⟨association, associationMember, rfl⟩))
  obtain ⟨node, nodeMember, nodeLabel, nodeAccepted, step, stepMember, stepKey, sources, associations⟩ :=
    plan_raw_realization raw rawMember keyMember
  have inStep : association ∈ step.associations := by
    rw [associations]
    exact Array.mem_filter.mpr ⟨associationMember, by simp⟩
  have nameMember : association.reference.canonical ∈ nativeNames step.associations (step.sources.map (·.source)) :=
    (nativeNames_mem_iff _ _ _).mpr (Array.mem_append_left _ (Array.mem_map.mpr ⟨association, inStep, rfl⟩))
  obtain ⟨declaration, declarationMember, declarationName⟩ :=
    (plan_declaration_mem_iff raw nodeMember stepMember _).mpr nameMember
  have mapped := congrArg (Array.map (·.context)) sources
  have agreed : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context] := by
    simpa only [Array.map_map, Function.comp_def, associations, ← mapped] using contextAgrees
  have selected : association ∈ step.associations.filter (·.reference.canonical == declaration.name) :=
    Array.mem_filter.mpr ⟨inStep, by simp [declarationName]⟩
  obtain ⟨index, bound, atIndex⟩ := Array.mem_iff_getElem.mp selected
  have found := (plan_native_requests raw nodeMember stepMember declarationMember agreed).job
    (Array.getElem?_eq_some_iff.mpr ⟨bound, atIndex⟩)
  exact ⟨node, nodeMember, nodeLabel, nodeAccepted, step, stepMember, stepKey,
    declaration, declarationMember, declarationName, index, by simpa only [declarationName] using found⟩

end Informal.Realizations.Capture
