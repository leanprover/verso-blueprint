/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment
import VersoBlueprint.NodeAssembly.Laws
import VersoBlueprint.Util.NameMapLaws

/-! The actual pure environment admission transition. Monadic environment commits,
error logging, and persistence replay remain separate obligations. -/
namespace Informal.Environment
open Lean Data Contributions
variable {label origin contributor : Name}

run_cmd do
  let env ← getEnv
  let some owner := env.getModuleIdxFor? ``contribute
    | throwError "Environment implementation must be imported before opening its proof scope"
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some owner then
      if let some user := privateToUserName? name then
        if (`Informal.Environment).isPrefixOf user then
          Elab.Command.modifyScope fun scope => { scope with
            openDecls := .explicit (user.replacePrefix `Informal.Environment .anonymous) name :: scope.openDecls }

/-- An imported authored-origin conflict remains rejecting under every subsequent
registration; compatible payloads cannot resurrect the rejected label. -/
theorem State.addNode_no_resurrection (state : State)
    (conflicted : (state.pendingNodes.getD label {}).authoredOriginConflict = true) :
    ∃ reasons, State.addNode state label origin contributor incoming facts = .error reasons := by
  refine ⟨#[s!"Label {label} was independently introduced by authored contributions"], ?_⟩
  simp only [State.addNode, PendingNode.append, conflicted, Bool.true_or, ↓reduceIte]
  rfl

/-- Successful admission stores the very node returned by assembly against the
retained pending registrations and complete selected-fact evidence. -/
theorem State.addNode_assembled
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node)) :
    ∃ assembled, NodeAssembly.assemble label (after.pendingNodes.getD label {}).registrations
        after.factRecords.reverse = .ok assembled ∧
      assembled.node = node ∧ (after.data.get? label).map RegisteredNode.toNode = some node := by
  simp only [State.addNode, bind, Except.bind, pure] at accepted
  split at accepted
  · contradiction
  · split at accepted
    · contradiction
    · rename_i assembled assembledOk
      cases accepted
      refine ⟨assembled, ?_, rfl, ?_⟩
      · simpa only [NameMapLaws.getD_insert_self] using assembledOk
      · simp only [NameMapLaws.get?_insert, ↓reduceIte, Option.map_some]

private theorem State.addNode_effects
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node)) :
    let pending := PendingNode.append (before.pendingNodes.getD label {}) origin contributor incoming true
      (incoming.any (·.claimsAuthoredNode))
    after = { before with
      data := before.data.insert label {
        toNode := node, origin := pending.authoredOrigin?.getD pending.origin,
        modules := pending.contributors }
      nextCount := max before.nextCount (node.count + 1)
      leanNameLabels := addNodeLeanDeclLabels before.leanNameLabels label node
      pendingNodes := before.pendingNodes.insert label pending
      factRecords := collector.extend before.factRecords facts
      localFactRecords := collector.extend before.localFactRecords facts } := by
  simp only [State.addNode, bind, Except.bind, pure] at accepted
  split at accepted
  · contradiction
  · split at accepted
    · contradiction
    · cases accepted
      rfl

/-- Both complete and module-local evidence retain exact full-record membership.
Local exports do not copy inherited records merely because a node was updated. -/
theorem State.addNode_records
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node))
    (record : Record) :
    (record ∈ after.factRecords ↔ record ∈ before.factRecords ∨ record ∈ facts) ∧
    (record ∈ after.localFactRecords ↔ record ∈ before.localFactRecords ∨ record ∈ facts) := by
  rw [State.addNode_effects accepted]
  exact ⟨mem_extend _ _ _, mem_extend _ _ _⟩

/-- Registering one label changes neither another accepted node nor another
label's retained registrations/provenance. Names are compared structurally. -/
theorem State.addNode_other_labels
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node))
    (different : label ≠ other) :
    after.data.get? other = before.data.get? other ∧
      after.pendingNodes.get? other = before.pendingNodes.get? other := by
  rw [State.addNode_effects accepted]
  simp only [NameMapLaws.get?_insert, different, ↓reduceIte, and_self]

/-- The six admission stores account for the entire update. Configuration,
authoring, diagnostics, directive scope, and module catalogs are preserved. -/
theorem State.addNode_frame
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node)) :
    { after with
      data := before.data
      nextCount := before.nextCount
      leanNameLabels := before.leanNameLabels
      pendingNodes := before.pendingNodes
      factRecords := before.factRecords
      localFactRecords := before.localFactRecords } = before := by
  rw [State.addNode_effects accepted]

/-- Successful admission reserves the returned node's count without decreasing
an existing reservation. Duplicate occurrences need not advance it again. -/
theorem State.addNode_count
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node)) :
    after.nextCount = max before.nextCount (node.count + 1) := by
  rw [State.addNode_effects accepted]

/-- Every raw native association in the returned/stored node comes from the
complete accepted input evidence, preserving named facets and provenance. -/
theorem State.addNode_nativeAssociations
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node))
    (association : SourceData.NativeAssociation) :
    association ∈ node.nativeAssociations ↔
      ∃ record, (record ∈ before.factRecords ∨ record ∈ facts) ∧ record.label = label ∧
        association ∈ record.nativeAssociations := by
  obtain ⟨assembled, assembly, nodeEq, _⟩ := State.addNode_assembled accepted
  rw [← nodeEq, NodeAssembly.assemble_ok_nativeAssociations assembly]
  simp only [Array.mem_flatMap, List.mem_toArray]
  constructor
  · rintro ⟨record, member, associationMem⟩
    obtain ⟨evidence, labelEq⟩ := (NodeAssembly.assemble_ok_supports assembly record).mp member
    exact ⟨record, (State.addNode_records accepted record).1.mp (List.mem_reverse.mp evidence),
      labelEq, associationMem⟩
  · rintro ⟨record, member, labelEq, associationMem⟩
    refine ⟨record, (NodeAssembly.assemble_ok_supports assembly record).mpr ⟨?_, labelEq⟩, associationMem⟩
    exact List.mem_reverse.mpr ((State.addNode_records accepted record).1.mpr member)

/-- Local admission accepts exactly the origin-valid cases accepted by the
production assembler. Together with `NodeAssembly.assemble_success_iff`, this
adds authored-origin validity to the proved payload/selected-evidence contract. -/
theorem State.addNode_success_iff (before : State) (incoming : Array SourceData.Registration)
    (facts : List Record) :
    let pending := PendingNode.append (before.pendingNodes.getD label {}) origin contributor incoming true
      (incoming.any (·.claimsAuthoredNode))
    (∃ after node, State.addNode before label origin contributor incoming facts = .ok (after, node)) ↔
      pending.authoredOriginConflict = false ∧
      ∃ assembled, NodeAssembly.assemble label pending.registrations
        (collector.extend before.factRecords facts).reverse = .ok assembled := by
  dsimp only
  constructor
  · rintro ⟨after, node, accepted⟩
    simp only [State.addNode, bind, Except.bind, pure] at accepted
    split at accepted
    · contradiction
    · rename_i valid
      refine ⟨Bool.eq_false_iff.mpr valid, ?_⟩
      split at accepted
      · contradiction
      · rename_i assembled assembledOk
        exact ⟨assembled, assembledOk⟩
  · rintro ⟨valid, assembled, assembledOk⟩
    simp only [Collector.extend] at assembledOk
    simp only [State.addNode, valid, Bool.false_eq_true, ↓reduceIte,
      bind, Except.bind, assembledOk, pure]
    exact ⟨_, _, rfl⟩

private theorem mem_pushUnique (labels : Array Label) (label query : Label) :
    query ∈ Label.pushUnique labels label ↔ query ∈ labels ∨ query = label := by
  unfold Label.pushUnique
  split <;> simp_all

private theorem addLeanDeclLabel_mem (index : NameMap (Array Label))
    (declaration query : Name) (label found : Label) :
    found ∈ (addLeanDeclLabel index declaration label).getD query #[] ↔
      found ∈ index.getD query #[] ∨ declaration.eraseMacroScopes = query ∧ found = label := by
  simp only [addLeanDeclLabel, NameMapLaws.getD_insert]
  split <;> simp_all [mem_pushUnique]

private theorem addNodeLeanDeclLabels_mem (index : NameMap (Array Label)) (node : Node)
    (label found : Label) (query : Name) :
    found ∈ (addNodeLeanDeclLabels index label node).getD query #[] ↔
      found ∈ index.getD query #[] ∨
        found = label ∧ ∃ declaration ∈ node.leanDecls, declaration.eraseMacroScopes = query := by
  unfold addNodeLeanDeclLabels
  rw [← Array.foldl_toList]
  have loop (declarations : List Name) (initial : NameMap (Array Label)) :
      found ∈ (declarations.foldl (fun acc declaration => addLeanDeclLabel acc declaration label) initial).getD query #[] ↔
      found ∈ initial.getD query #[] ∨
        found = label ∧ ∃ declaration ∈ declarations, declaration.eraseMacroScopes = query := by
    induction declarations generalizing initial with
    | nil => simp
    | cons declaration declarations ih =>
      simp only [List.foldl_cons, ih, addLeanDeclLabel_mem, List.mem_cons]
      grind
  simpa using loop node.leanDecls.toList index

/-- Exact incremental declaration-index membership. Existing entries remain;
new entries are precisely the returned node's declarations under the insertion
function's macro-scope erasure. No idempotence of erasure is assumed. -/
theorem State.addNode_declaration_index
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node))
    (query : Name) (found : Label) :
    found ∈ after.leanNameLabels.getD query #[] ↔
      found ∈ before.leanNameLabels.getD query #[] ∨
        found = label ∧ ∃ declaration ∈ node.leanDecls, declaration.eraseMacroScopes = query := by
  rw [State.addNode_effects accepted]
  exact addNodeLeanDeclLabels_mem _ _ _ _ _

end Informal.Environment
