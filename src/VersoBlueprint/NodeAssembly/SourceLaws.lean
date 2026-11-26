/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.NodeAssembly.MembershipLaws

/-! Source inventory preservation in the actual registration reducer. -/
namespace Informal.NodeAssembly
open Lean Data Contributions

run_cmd do
  let env ← getEnv
  let some owner := env.getModuleIdxFor? ``Node.applyRegistrations
    | throwError "Registration implementation must be imported before opening its proof scope"
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some owner then
      if let some user := privateToUserName? name then
        if (`Informal.NodeAssembly).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.NodeAssembly .anonymous) name :: scope.openDecls }

private theorem state_bind_run (action : StateM σ α) (next : α → StateM σ β) (state : σ) :
    (StateT.bind action next) state = next (action state).1 (action state).2 := by
  unfold StateT.bind
  cases action state
  rfl

private theorem state_forIn_project (entries : List α) (initial : β)
    (body : α → β → StateM σ (ForInStep β)) (step : β → α → β)
    (project : ∀ entry current state, (body entry current state).1 = .yield (step current entry))
    (state : σ) :
    ((forIn entries initial body).run state).1 = entries.foldl step initial := by
  induction entries generalizing initial state with
  | nil => rfl
  | cons entry entries ih =>
    have projected := project entry initial state
    cases executed : body entry initial state with
    | mk result next =>
      rw [executed] at projected
      cases projected
      simp only [List.forIn_cons, StateT.run, bind, state_bind_run, executed, List.foldl_cons]
      exact ih _ _

private theorem state_forIn_append (entries : Array α) (initial : Array α)
    (check : α → Array α → StateM σ δ) (state : σ) :
    ((forIn entries initial (fun entry current => do
      let _ ← check entry current
      pure (.yield (current.push entry)))).run state).1 = initial ++ entries := by
  rw [← Array.forIn_toList]
  rw [state_forIn_project entries.toList initial _ Array.push
    (fun entry current state => by simp only [bind, state_bind_run, pure, StateT.pure])]
  simpa using (Array.foldl_push_eq_append (as := entries) (bs := initial) (f := id) rfl)

private theorem mergeContribution_sources (label : Label) (node : Node)
    (incoming : SourceData.Registration) (errors : Array String) :
    ((mergeContribution label node incoming).run errors).1.sources = node.sources ++ incoming.sources := by
  unfold mergeContribution
  cases kind : incoming.kind <;>
    simp only [StateT.run, bind, state_bind_run, pure]
  all_goals try split
  all_goals simp only [state_bind_run, StateT.pure]
  all_goals exact state_forIn_append incoming.sources node.sources _ errors

private theorem foldRegistrations_sources (label : Label) (registrations : List SourceData.Registration)
    (node : Node) (errors : Array String) :
    ((registrations.foldlM (mergeContribution label) node).run errors).1.sources =
      node.sources ++ (registrations.flatMap (·.sources.toList)).toArray := by
  induction registrations generalizing node errors with
  | nil => simp [List.foldlM, StateT.run, pure, StateT.pure]
  | cons registration registrations ih =>
    simp only [List.foldlM_cons, StateT.run, bind, state_bind_run]
    simp only [StateT.run] at ih
    rw [ih]
    have sourceEq := mergeContribution_sources label node registration errors
    simp only [StateT.run] at sourceEq
    rw [sourceEq]
    apply Array.toList_inj.mp
    simp

/-- Successful payload reduction preserves the exact ordered source inventory:
old sources followed by every newly supplied source, with provenance and payload
intact. Conflict checking may reject; it cannot silently replace accepted sources. -/
theorem applyRegistrations_sources
    (accepted : Node.applyRegistrations label initial registrations = .ok node) :
    node.sources = initial.sources ++ registrations.flatMap (·.sources) := by
  have conserved := foldRegistrations_sources label registrations.toList initial
    (registrations.flatMap (registrationIssues label))
  rw [Array.foldlM_toList] at conserved
  unfold Node.applyRegistrations applyPayloads at accepted
  cases executed : (registrations.foldlM (mergeContribution label) initial).run
      (registrations.flatMap (registrationIssues label)) with
  | mk result errors =>
    rw [executed] at conserved
    simp only [executed] at accepted
    split at accepted
    · cases accepted
      apply Array.toList_inj.mp
      simpa using congrArg Array.toList conserved
    · cases accepted

/-- Source membership after accepted payload reduction is exactly old membership
or an original registration's complete source record. -/
theorem applyRegistrations_source_mem
    (accepted : Node.applyRegistrations label initial registrations = .ok node)
    (source : SourceData.FacetSource) :
    source ∈ node.sources ↔ source ∈ initial.sources ∨
      ∃ registration ∈ registrations, source ∈ registration.sources := by
  rw [applyRegistrations_sources accepted]
  simp only [Array.mem_append, Array.mem_flatMap]

/-- Assembly preserves exactly the source records supplied by its payloads,
including order, duplicates, destinations, and original provenance. -/
theorem assemble_ok_source_inventory (accepted : assemble label registrations records = .ok assembled) :
    assembled.node.sources = registrations.flatMap (·.sources) := by
  obtain ⟨base, reduced⟩ := ((assemble_success_iff label registrations records).mp ⟨assembled, accepted⟩).1
  rw [assemble_ok_sources accepted reduced, applyRegistrations_sources reduced]
  simp

/-- Native declaration membership is connected all the way to original inputs:
present selected associations, or an inline source in an original registration.
No caller-supplied intermediate payload-node premise is needed. -/
theorem assemble_ok_leanDecls_input (accepted : assemble label registrations records = .ok assembled)
    (name : Name) :
    name ∈ assembled.node.leanDecls ↔ Association records label name ∨
      ∃ registration ∈ registrations, ∃ source ∈ registration.sources,
        ∃ code, source.payload = .leanInline code ∧
          ∃ declaration ∈ code.definedDeclNames, declaration.eraseMacroScopes = name := by
  obtain ⟨base, reduced⟩ := ((assemble_success_iff label registrations records).mp ⟨assembled, accepted⟩).1
  rw [assemble_ok_leanDecls_sources accepted reduced, applyRegistrations_sources reduced]
  simp only [Array.empty_append, Array.mem_flatMap]
  grind only

/-- Accepted growth of the complete registration/evidence sets cannot remove a
native declaration. This concerns membership, not order or completion status. -/
theorem assemble_leanDecls_monotone
    (before : assemble label previous priorRecords = .ok first)
    (after : assemble label registrations records = .ok second)
    (payloadsGrow : ∀ registration ∈ previous, registration ∈ registrations)
    (recordsGrow : ∀ record ∈ priorRecords, record ∈ records)
    (member : name ∈ first.node.leanDecls) : name ∈ second.node.leanDecls := by
  rw [assemble_ok_leanDecls_input before] at member
  rw [assemble_ok_leanDecls_input after]
  rcases member with association | ⟨registration, registered, rest⟩
  · rcases association with ⟨record, recorded, rest⟩
    exact Or.inl ⟨record, recordsGrow record recorded, rest⟩
  · exact Or.inr ⟨registration, payloadsGrow registration registered, rest⟩

end Informal.NodeAssembly
