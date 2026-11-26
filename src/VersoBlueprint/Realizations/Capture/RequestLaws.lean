/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture.ExpectedLaws

/-! Check-request identity and bounds through the actual production planner. -/

namespace Informal.Realizations.Capture
open Lean Validation Translations SourceData

run_cmd do
  let env ← getEnv
  let some owner := env.getModuleIdxFor? ``finish_uses
    | throwError "Capture loop helpers must be imported"
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some owner then
      if let some user := privateToUserName? name then
        if (`Informal.Realizations.Capture).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Realizations.Capture .anonymous) name :: scope.openDecls }

/-- Appending work preserves each existing successful indexed lookup. -/
private def PreservesLookups (before after : Array α) : Prop :=
  ∀ (index : Nat) value, before[index]? = some value → after[index]? = some value

private theorem preservesLookups_refl (entries : Array α) : PreservesLookups entries entries :=
  fun _ _ found => found

private theorem PreservesLookups.trans (first : PreservesLookups a b)
    (second : PreservesLookups b c) : PreservesLookups a c :=
  fun index value found => second index value (first index value found)

private theorem preservesLookups_push (entries : Array α) (extra : α) :
    PreservesLookups entries (entries.push extra) := by
  intro index value found
  have bound : index < entries.size := (Array.getElem?_eq_some_iff.mp found).1
  simpa [Array.getElem?_push, bound, Nat.ne_of_lt bound] using found

private def sourceContext (accepted : Environment.RegisteredNode) (key : RealizationKey) : Context :=
  (canonical ((accepted.sources.filter (·.destination.realization == key)).map (·.context) ++
    (accepted.nativeAssociations.filter (·.realization == key)).map (·.context)))[0]?.getD default

private def DeclarationChecks (checks : Array CheckRequest) (context : Context)
    (declarations : Array DeclarationStep) : Prop :=
  ∀ declaration ∈ declarations, checks[declaration.check]? =
    some { project := context.project, witness := ⟨context, declaration.name.toString⟩ }

private theorem DeclarationChecks.preserve (valid : DeclarationChecks before context declarations)
    (growth : PreservesLookups before after) : DeclarationChecks after context declarations :=
  fun declaration member => growth _ _ (valid declaration member)

private def RealizationChecks (checks : Array CheckRequest) (accepted : Environment.RegisteredNode)
    (steps : Array RealizationStep) : Prop :=
  ∀ step ∈ steps, DeclarationChecks checks (sourceContext accepted step.key) step.declarations

private theorem RealizationChecks.preserve (valid : RealizationChecks before accepted steps)
    (growth : PreservesLookups before after) : RealizationChecks after accepted steps :=
  fun step member => (valid step member).preserve growth

private def PlanChecks (p : Plan) : Prop :=
  ∀ node ∈ p.ordinary, RealizationChecks p.checks node.accepted node.realizations

private theorem plan_checks (raw : Raw) : PlanChecks (plan raw) := by
  unfold plan
  simp only [Id.run, bind, pure]
  generalize ordinaryEq : forIn (m := Id) raw.nodes ({ raw } : Plan) _ = ordinary
  apply id_array_loop_invariant _ PlanChecks _ ?_ ?_
  · rw [← ordinaryEq]
    apply id_array_loop_invariant raw.nodes PlanChecks _ (by simp [PlanChecks])
    intro entry member current prior
    rcases entry with ⟨label, accepted⟩
    clear ordinaryEq
    generalize realizationEq : forIn (m := Id) (α := RealizationKey)
      (β := Plan × Array RealizationStep) (_ : Array RealizationKey) (current, #[]) _ = expanded
    have realized : expanded.1.ordinary = current.ordinary ∧
        PreservesLookups current.checks expanded.1.checks ∧
        RealizationChecks expanded.1.checks accepted expanded.2 := by
      rw [← realizationEq]
      apply id_array_loop_invariant _
        (fun pair : Plan × Array RealizationStep => pair.1.ordinary = current.ordinary ∧
          PreservesLookups current.checks pair.1.checks ∧ RealizationChecks pair.1.checks accepted pair.2)
        _ ⟨rfl, preservesLookups_refl _, by simp [RealizationChecks]⟩
      intro key member pair prior
      clear realizationEq
      generalize sourcesEq : forIn (m := Id) (α := FacetSource)
        (β := Plan × Array SourceStep) (_ : Array FacetSource) (pair.1, #[]) _ = sourced
      have sourcesUnchanged : (sourced.1.ordinary, sourced.1.checks) = (pair.1.ordinary, pair.1.checks) := by
        rw [← sourcesEq]
        apply id_array_loop_invariant _
          (fun pair : Plan × Array SourceStep => (pair.1.ordinary, pair.1.checks) = _) _ rfl
        intro source member pair prior
        cases source.payload <;> simp only
        all_goals first
          | exact prior
          | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
      generalize declarationsEq : forIn (m := Id) (α := Name)
        (β := Plan × Array DeclarationStep) (_ : Array Name) (sourced.1, #[]) _ = declared
      have declaredChecks : declared.1.ordinary = sourced.1.ordinary ∧
          PreservesLookups sourced.1.checks declared.1.checks ∧
          DeclarationChecks declared.1.checks (sourceContext accepted key) declared.2 := by
        rw [← declarationsEq]
        apply id_array_loop_invariant _
          (fun pair : Plan × Array DeclarationStep => pair.1.ordinary = sourced.1.ordinary ∧
            PreservesLookups sourced.1.checks pair.1.checks ∧
            DeclarationChecks pair.1.checks (sourceContext accepted key) pair.2)
          _ ⟨rfl, preservesLookups_refl _, by simp [DeclarationChecks]⟩
        intro name member pair prior
        clear sourcesEq declarationsEq
        generalize nativeEq : forIn (m := Id) (α := NativeAssociation)
          (β := Plan × Array Nat) (_ : Array NativeAssociation) (pair.1, #[]) _ = native
        have nativeUnchanged : (native.1.ordinary, native.1.checks) = (pair.1.ordinary, pair.1.checks) := by
          rw [← nativeEq]
          apply id_array_loop_invariant _
            (fun pair : Plan × Array Nat => (pair.1.ordinary, pair.1.checks) = _) _ rfl
          intro association member pair prior
          exact prior
        generalize inlineEq : forIn (m := Id) (α := FacetSource)
          (β := Plan × Array Nat) (_ : Array FacetSource) (native.1, #[]) _ = inline
        have inlineUnchanged : (inline.1.ordinary, inline.1.checks) = (native.1.ordinary, native.1.checks) := by
          rw [← inlineEq]
          apply id_array_loop_invariant _
            (fun pair : Plan × Array Nat => (pair.1.ordinary, pair.1.checks) = _) _ rfl
          intro source member pair prior
          cases source.payload <;> simp only
          all_goals first
            | exact prior
            | (split <;> (rename_i outcome; (repeat' split at outcome) <;> cases outcome <;> exact prior))
        have unchanged := Prod.mk.inj (inlineUnchanged.trans nativeUnchanged)
        refine ⟨unchanged.1.trans prior.1, ?_, ?_⟩
        · apply prior.2.1.trans
          rw [← unchanged.2]
          exact preservesLookups_push _ _
        · intro declaration member
          simp only [Array.mem_push] at member
          rcases member with member | rfl
          · apply preservesLookups_push
            rw [unchanged.2]
            exact prior.2.2 declaration member
          · simp [sourceContext]
      have unchanged := Prod.mk.inj sourcesUnchanged
      have growth : PreservesLookups pair.1.checks declared.1.checks := by
        rw [← unchanged.2]
        exact declaredChecks.2.1
      refine ⟨declaredChecks.1.trans (unchanged.1.trans prior.1), prior.2.1.trans growth, ?_⟩
      intro step member
      simp only [Array.mem_push] at member
      rcases member with member | rfl
      · exact (prior.2.2 step member).preserve growth
      · exact declaredChecks.2.2
    intro node member
    simp only [Array.mem_push] at member
    rcases member with member | rfl
    · exact (prior node (by rwa [realized.1] at member)).preserve realized.2.1
    · exact realized.2.2
  · intro record member current prior
    clear ordinaryEq
    apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => PlanChecks pair.1) _ ?_ ?_
    · apply id_array_loop_invariant _ (fun pair : Plan × Array Nat => PlanChecks pair.1) _ prior
      intro goal member pair prior
      exact prior
    · intro document member pair prior
      exact prior

/-- Every generated declaration check handle has the exact request constructed
from its source realization. This holds even for plans later rejected by evaluation;
context selection here is the planner's actual first-or-default policy. -/
theorem plan_declaration_check_request (raw : Raw) (nodeMember : node ∈ (plan raw).ordinary)
    (stepMember : step ∈ node.realizations) (declarationMember : declaration ∈ step.declarations) :
    let context := (canonical ((node.accepted.sources.filter (·.destination.realization == step.key)).map (·.context) ++
      (node.accepted.nativeAssociations.filter (·.realization == step.key)).map (·.context)))[0]?.getD default
    (plan raw).checks[declaration.check]? =
      some { project := context.project, witness := ⟨context, declaration.name.toString⟩ } :=
  plan_checks raw node nodeMember step stepMember declaration declarationMember

/-- With agreed source context, the generated handle is in bounds and resolves
to the corresponding declaration in that project. Later planning cannot retarget it. -/
theorem plan_declaration_check (raw : Raw) (nodeMember : node ∈ (plan raw).ordinary)
    (stepMember : step ∈ node.realizations) (declarationMember : declaration ∈ step.declarations)
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    declaration.check < (plan raw).checks.size ∧
      (plan raw).checks[declaration.check]? =
        some { project := context.project, witness := ⟨context, declaration.name.toString⟩ } := by
  have fields := plan_realization_fields raw nodeMember stepMember
  have mapped := congrArg (Array.map (·.context)) fields.2.1
  have agreed : canonical ((node.accepted.sources.filter (·.destination.realization == step.key)).map (·.context) ++
      (node.accepted.nativeAssociations.filter (·.realization == step.key)).map (·.context)) = #[context] := by
    simpa only [Array.map_map, Function.comp_def, fields.2.2.1, ← mapped] using contextAgrees
  have lookup := plan_declaration_check_request raw nodeMember stepMember declarationMember
  simp only [agreed, Array.getElem?_singleton] at lookup
  exact ⟨(Array.getElem?_eq_some_iff.mp lookup).1, lookup⟩

/-- The exact lookup used by the real observer returns the intended job; its
fallback is unreachable for declaration steps produced by this planner. This
identifies the arguments, not the correctness of the native checker execution. -/
theorem plan_declaration_check_job (raw : Raw) (nodeMember : node ∈ (plan raw).ordinary)
    (stepMember : step ∈ node.realizations) (declarationMember : declaration ∈ step.declarations)
    (contextAgrees : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context]) :
    (plan raw).checks[declaration.check]! =
      { project := context.project, witness := ⟨context, declaration.name.toString⟩ } := by
  obtain ⟨bound, found⟩ := plan_declaration_check raw nodeMember stepMember declarationMember contextAgrees
  simpa only [getElem!_pos, bound] using (Array.getElem?_eq_some_iff.mp found).2

/-- Raw accepted sources supply the actual declaration step, its in-bounds check
handle, and its exact request. Callers need no prevalidated plan or request lookup. -/
theorem plan_raw_declaration_check (raw : Raw) (rawMember : (label, accepted) ∈ raw.nodes)
    (keyMember : key ∈ canonical (accepted.sources.map (·.destination.realization) ++
      accepted.nativeAssociations.map (·.realization)))
    (sourceDeclaration : name ∈ nativeNames
      (accepted.nativeAssociations.filter (·.realization == key))
      (accepted.sources.filter (·.destination.realization == key)))
    (contextAgrees : canonical ((accepted.sources.filter (·.destination.realization == key)).map (·.context) ++
      (accepted.nativeAssociations.filter (·.realization == key)).map (·.context)) = #[context]) :
    ∃ node ∈ (plan raw).ordinary, node.label = label ∧ node.accepted = accepted ∧
      ∃ step ∈ node.realizations, step.key = key ∧
        ∃ declaration ∈ step.declarations, declaration.name = name ∧
          declaration.check < (plan raw).checks.size ∧
          (plan raw).checks[declaration.check]? =
            some { project := context.project, witness := ⟨context, name.toString⟩ } := by
  obtain ⟨node, nodeMember, nodeLabel, nodeAccepted, step, stepMember, stepKey, sources, associations⟩ :=
    plan_raw_realization raw rawMember keyMember
  have sourceMember : name ∈ nativeNames step.associations (step.sources.map (·.source)) := by
    rwa [sources, associations]
  obtain ⟨declaration, declarationMember, declarationName⟩ :=
    (plan_declaration_mem_iff raw nodeMember stepMember name).mpr sourceMember
  have mapped := congrArg (Array.map (·.context)) sources
  have agreed : canonical (step.sources.map (·.source.context) ++ step.associations.map (·.context)) = #[context] := by
    simpa only [Array.map_map, Function.comp_def, associations, ← mapped] using contextAgrees
  obtain ⟨bound, found⟩ := plan_declaration_check raw nodeMember stepMember declarationMember agreed
  exact ⟨node, nodeMember, nodeLabel, nodeAccepted, step, stepMember, stepKey,
    declaration, declarationMember, declarationName, bound, by simpa only [declarationName] using found⟩

end Informal.Realizations.Capture
