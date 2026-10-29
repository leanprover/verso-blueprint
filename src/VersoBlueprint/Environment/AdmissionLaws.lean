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

private theorem forIn_projection (entries : List α) (initial : β)
    (body : α → β → Id (ForInStep β)) (projection : β → γ) (step : γ → α → γ)
    (project : ∀ entry ∈ entries, ∀ state, ∃ next,
      body entry state = .yield next ∧ projection next = step (projection state) entry) :
    projection (forIn entries initial body) = entries.foldl step (projection initial) := by
  induction entries generalizing initial with
  | nil => rfl
  | cons entry entries ih =>
    obtain ⟨next, yielded, projected⟩ := project entry (by simp) initial
    simp only [List.forIn_cons, yielded, bind, List.foldl_cons]
    rw [ih next (fun other member => project other (by simp [member])), projected]

-- A law-only projection of one accepted import. It calls the production assembler;
-- the following bridge proves that the real import loop has exactly this behavior.
private def importedNode? (records : List Record) (label : Name) (pending : PendingNode) :
    Option RegisteredNode :=
  if pending.authoredOriginConflict then none else
    (NodeAssembly.assemble label pending.registrations records).toOption.map fun assembled => {
      toNode := assembled.node, origin := pending.authoredOrigin?.getD pending.origin,
      modules := pending.contributors }

private theorem reassembleImported_data (state : State) :
    (State.reassembleImported state).data =
      state.pendingNodes.toArray.foldl (fun (data : NameMap RegisteredNode) entry =>
        (importedNode? state.factRecords.reverse entry.1 entry.2).elim data (data.insert entry.1)) ({} : NameMap RegisteredNode) := by
  unfold State.reassembleImported
  simp only [Id.run, bind, pure]
  rw [← Array.forIn_toList, ← Array.foldl_toList]
  apply forIn_projection
  intro entry member accumulator
  simp only [importedNode?]
  split
  · exact ⟨_, rfl, rfl⟩
  · cases assembled : NodeAssembly.assemble entry.1 entry.2.registrations state.factRecords.reverse <;>
      exact ⟨_, rfl, by simp [Except.toOption] <;> rfl⟩

private theorem fold_optional_get (entries : List (Name × α)) (initial : NameMap β)
    (choose : Name → α → Option β) (key : Name) (selected : Option β)
    (matching : ∀ entry ∈ entries, entry.1 = key → choose entry.1 entry.2 = selected) :
    (entries.foldl (fun out entry => (choose entry.1 entry.2).elim out (out.insert entry.1)) initial).get? key =
      if key ∈ entries.map Prod.fst then selected.or (initial.get? key) else initial.get? key := by
  induction entries generalizing initial with
  | nil => simp
  | cons entry entries ih =>
    simp only [List.foldl_cons, ih _ (fun other member => matching other (by simp [member]))]
    by_cases same : entry.1 = key
    · have selectedHere := matching entry (by simp) same
      simp only [selectedHere, List.map_cons, List.mem_cons]
      cases selected <;> simp only [same, Option.elim, NameMapLaws.get?_insert, true_or, ite_true, Option.or] <;> split <;> rfl
    · cases picked : choose entry.1 entry.2 <;>
        simp only [Option.elim, List.map_cons, List.mem_cons, NameMapLaws.get?_insert, same, Ne.symm same, false_or, ite_false]

private theorem reassembleImported_lookup (state : State) (label : Name) :
    (State.reassembleImported state).data.get? label =
      (state.pendingNodes.get? label).bind (importedNode? state.factRecords.reverse label) := by
  rw [reassembleImported_data, ← Array.foldl_toList]
  have matching : ∀ entry ∈ state.pendingNodes.toArray.toList, entry.1 = label →
      importedNode? state.factRecords.reverse entry.1 entry.2 =
        (state.pendingNodes.get? label).bind (importedNode? state.factRecords.reverse label) := by
    intro entry member same
    have found := (NameMapLaws.mem_toArray state.pendingNodes entry.1 entry.2).mp (by simpa using member)
    rw [same] at found ⊢
    simp [found]
  refine (fold_optional_get _ ({} : NameMap RegisteredNode) _ _ _ matching).trans ?_
  cases found : state.pendingNodes.get? label with
  | none =>
    simp [NameMapLaws.get?_empty]
  | some pending =>
    have member := (NameMapLaws.mem_toArray state.pendingNodes label pending).mpr found
    have present : label ∈ state.pendingNodes.toArray.toList.map Prod.fst :=
      List.mem_map.mpr ⟨(label, pending), by simpa using member, rfl⟩
    simp [present, NameMapLaws.get?_empty]

/-- Imported node lookup is exactly successful assembly of a retained,
origin-valid pending entry against the complete evidence set. Both directions
include the stored provenance, not just the semantic node. -/
theorem State.reassembleImported_node_iff (state : State) (label : Name) (registered : RegisteredNode) :
    (State.reassembleImported state).data.get? label = some registered ↔
      ∃ pending, state.pendingNodes.get? label = some pending ∧
        pending.authoredOriginConflict = false ∧
        ∃ assembled, NodeAssembly.assemble label pending.registrations state.factRecords.reverse = .ok assembled ∧
          ({ toNode := assembled.node
             origin := pending.authoredOrigin?.getD pending.origin
             modules := pending.contributors } : RegisteredNode) = registered := by
  rw [reassembleImported_lookup state label]
  cases found : state.pendingNodes.get? label with
  | none => simp
  | some pending =>
    cases conflict : pending.authoredOriginConflict <;>
      cases assembled : NodeAssembly.assemble label pending.registrations state.factRecords.reverse <;>
      simp [importedNode?, conflict, assembled, Except.toOption]

/-- Rebuilding the imported state excludes an origin-conflicted label even when
an arbitrary preexisting node or index had made it visible. -/
theorem State.reassembleImported_conflicted_absent (state : State)
    (found : state.pendingNodes.get? label = some pending)
    (conflicted : pending.authoredOriginConflict = true) :
    (State.reassembleImported state).data.get? label = none := by
  rw [reassembleImported_lookup state label, found]
  simp [importedNode?, conflicted]

/-- Imported assembly never invents a label without retained registrations. -/
theorem State.reassembleImported_unknown_absent (state : State)
    (absent : state.pendingNodes.get? label = none) :
    (State.reassembleImported state).data.get? label = none := by
  rw [reassembleImported_lookup state label, absent]
  rfl

private theorem reassembleImported_index (state : State) :
    (State.reassembleImported state).leanNameLabels =
      state.pendingNodes.toArray.foldl (fun index entry =>
        (importedNode? state.factRecords.reverse entry.1 entry.2).elim index
          (fun node => addNodeLeanDeclLabels index entry.1 node.toNode)) {} := by
  unfold State.reassembleImported
  simp only [Id.run, bind, pure]
  rw [← Array.forIn_toList, ← Array.foldl_toList]
  apply forIn_projection (projection := fun (value : NameMap RegisteredNode × NameMap (Array Label) × Nat × Array ImportedConflict) => value.2.1)
  intro entry member accumulator
  simp only [importedNode?]
  split
  · exact ⟨_, rfl, rfl⟩
  · cases assembled : NodeAssembly.assemble entry.1 entry.2.registrations state.factRecords.reverse <;>
      exact ⟨_, rfl, by simp [Except.toOption] <;> rfl⟩

private theorem fold_imported_index_mem (entries : List (Name × PendingNode))
    (records : List Record) (initial : NameMap (Array Label)) (label : Label) (query : Name) :
    label ∈ (entries.foldl (fun index entry =>
      (importedNode? records entry.1 entry.2).elim index
        (fun node => addNodeLeanDeclLabels index entry.1 node.toNode)) initial).getD query #[] ↔
      label ∈ initial.getD query #[] ∨
      ∃ entry ∈ entries, entry.1 = label ∧ ∃ node, importedNode? records entry.1 entry.2 = some node ∧
        ∃ declaration ∈ node.leanDecls, declaration.eraseMacroScopes = query := by
  induction entries generalizing initial with
  | nil => simp
  | cons entry entries ih =>
    simp only [List.foldl_cons, ih]
    cases selected : importedNode? records entry.1 entry.2 with
    | none => simp [selected]
    | some node =>
      simp only [Option.elim]
      rw [addNodeLeanDeclLabels_mem initial node.toNode entry.1 label query]
      constructor
      · rintro ((old | ⟨same, declaration, member, canonical⟩) | tail)
        · exact Or.inl old
        · exact Or.inr ⟨entry, by simp, same.symm, node, selected, declaration, member, canonical⟩
        · obtain ⟨other, member, rest⟩ := tail
          exact Or.inr ⟨other, by simp [member], rest⟩
      · rintro (old | ⟨other, member, same, result, picked, declaration, declared, canonical⟩)
        · exact Or.inl (Or.inl old)
        · rcases List.mem_cons.mp member with rfl | tail
          · have equal := Option.some.inj (selected.symm.trans picked)
            subst result
            exact Or.inl (Or.inr ⟨same.symm, declaration, declared, canonical⟩)
          · exact Or.inr ⟨other, tail, same, result, picked, declaration, declared, canonical⟩

/-- Import reassembly constructs an exact declaration index from accepted nodes.
It discards stale preexisting entries; rejected imports contribute no entries.
The insertion function's macro-scope erasure is stated explicitly. -/
theorem State.reassembleImported_declaration_index (state : State) (label : Label) (query : Name) :
    label ∈ (State.reassembleImported state).leanNameLabels.getD query #[] ↔
      ∃ node, (State.reassembleImported state).data.get? label = some node ∧
        ∃ declaration ∈ node.leanDecls, declaration.eraseMacroScopes = query := by
  rw [reassembleImported_index, ← Array.foldl_toList, fold_imported_index_mem]
  have empty : ({} : NameMap (Array Label)).getD query #[] = #[] := rfl
  rw [empty]
  simp only [Array.not_mem_empty, false_or]
  constructor
  · rintro ⟨entry, member, same, node, accepted, declaration, declared, canonical⟩
    have found := (NameMapLaws.mem_toArray state.pendingNodes entry.1 entry.2).mp (by simpa using member)
    refine ⟨node, ?_, declaration, declared, canonical⟩
    rw [reassembleImported_lookup state label, ← same, found]
    exact accepted
  · rintro ⟨node, found, declaration, declared, canonical⟩
    rw [reassembleImported_lookup state label] at found
    cases pendingFound : state.pendingNodes.get? label with
    | none => simp [pendingFound] at found
    | some pending =>
      have member := (NameMapLaws.mem_toArray state.pendingNodes label pending).mpr pendingFound
      exact ⟨(label, pending), by simpa using member, rfl, node,
        by simpa [pendingFound] using found, declaration, declared, canonical⟩

/-- An origin-conflicted import cannot leak through declaration lookup either. -/
theorem State.reassembleImported_conflicted_unindexed (state : State) (label : Label)
    (found : state.pendingNodes.get? label = some pending)
    (conflicted : pending.authoredOriginConflict = true) (query : Name) :
    label ∉ (State.reassembleImported state).leanNameLabels.getD query #[] := by
  rw [State.reassembleImported_declaration_index]
  simp [State.reassembleImported_conflicted_absent state found conflicted]

/-- The import resolver rebuilds only accepted nodes, their index, numbering, and
diagnostics. Complete/local evidence, pending registrations, and authoring state
are preserved rather than overwritten with accepted projections. -/
theorem State.reassembleImported_frame (state : State) :
    { State.reassembleImported state with
      data := state.data
      leanNameLabels := state.leanNameLabels
      nextCount := state.nextCount
      importedConflicts := state.importedConflicts } = state := by
  simp only [State.reassembleImported, Id.run, bind, pure]

/-- Decoding one imported entry only collects evidence/metadata. It cannot
publish an accepted prefix of the nodes or declaration index. -/
theorem State.collectImportedEntry_unpublished (state : State) (entry : Entry) :
    (State.collectImportedEntry state entry).data = state.data ∧
      (State.collectImportedEntry state entry).leanNameLabels = state.leanNameLabels ∧
      (State.collectImportedEntry state entry).nextCount = state.nextCount ∧
      (State.collectImportedEntry state entry).localFactRecords = state.localFactRecords := by
  cases entry <;> simp only [State.collectImportedEntry]
  all_goals repeat (first | (solve | trivial) | split)

/-- Imports retain complete identified records without turning them into
current-module exports. Non-node entries add no selected-fact evidence. -/
theorem State.collectImportedEntry_records (state : State) (entry : Entry) (record : Record) :
    record ∈ (State.collectImportedEntry state entry).factRecords ↔
      record ∈ state.factRecords ∨ match entry with
        | .node _ _ _ _ facts _ => record ∈ facts
        | _ => False := by
  cases entry <;> simp only [State.collectImportedEntry]
  case node label origin contributor registrations facts authored =>
    exact mem_extend state.factRecords facts record
  all_goals repeat (first | (solve | simp) | split)

/-- Import decoding appends raw registrations but leaves the label's local
registration exports unchanged. It does not copy an assembled inherited node. -/
theorem State.collectImportedEntry_registrations (state : State)
    (registrations : Array SourceData.Registration) (facts : List Record) (authored : Bool) :
    let after := State.collectImportedEntry state (.node label origin contributor registrations facts authored)
    (after.pendingNodes.getD label {}).registrations =
      (state.pendingNodes.getD label {}).registrations ++ registrations ∧
    (after.pendingNodes.getD label {}).localRegistrations =
      (state.pendingNodes.getD label {}).localRegistrations := by
  simp only [State.collectImportedEntry, NameMapLaws.getD_insert_self, PendingNode.append, Bool.false_eq_true, ite_false]
  trivial

private theorem array_fold_preserves (entries : Array α) (initial : β) (step : β → α → β)
    (property : β → Prop) (start : property initial)
    (next : ∀ state entry, property state → property (step state entry)) :
    property (entries.foldl step initial) := by
  rw [← Array.foldl_toList]
  have loop (values : List α) (state : β) (valid : property state) :
      property (values.foldl step state) := by
    induction values generalizing state with
    | nil => exact valid
    | cons value values ih => exact ih _ (next state value valid)
  exact loop _ _ start

/-- The actual nested module/entry decoder leaves accepted nodes and their index
unpublished until the one full-evidence reassembly pass. Local selected records
also remain local throughout the complete import batch. -/
theorem State.collectImportedEntries_unpublished (state : State) (modules : Array (Array Entry)) :
    let collected := modules.foldl (fun state entries =>
      entries.foldl State.collectImportedEntry state) state
    collected.data = state.data ∧ collected.leanNameLabels = state.leanNameLabels ∧
      collected.nextCount = state.nextCount ∧ collected.localFactRecords = state.localFactRecords := by
  apply array_fold_preserves modules state _ (fun collected =>
    collected.data = state.data ∧ collected.leanNameLabels = state.leanNameLabels ∧
      collected.nextCount = state.nextCount ∧ collected.localFactRecords = state.localFactRecords)
  · exact ⟨rfl, rfl, rfl, rfl⟩
  · intro current entries valid
    apply array_fold_preserves entries current _ (fun collected =>
      collected.data = state.data ∧ collected.leanNameLabels = state.leanNameLabels ∧
        collected.nextCount = state.nextCount ∧ collected.localFactRecords = state.localFactRecords) valid
    intro intermediate entry prior
    obtain ⟨nodes, index, count, localRecords⟩ := State.collectImportedEntry_unpublished intermediate entry
    exact ⟨nodes.trans prior.1, index.trans prior.2.1, count.trans prior.2.2.1,
      localRecords.trans prior.2.2.2⟩

/-- Import rejection remains rejecting at the later local-admission boundary.
Reporting the diagnostic, or attempting a compatible new payload, does not make
its retained authored-origin conflict disappear. -/
theorem State.reassembleImported_no_resurrection (state : State)
    (conflicted : (state.pendingNodes.getD label {}).authoredOriginConflict = true) :
    ∃ reasons, State.addNode (State.reassembleImported state) label origin contributor incoming facts = .error reasons := by
  apply State.addNode_no_resurrection
  have preserved := congrArg State.pendingNodes (State.reassembleImported_frame state)
  change (State.reassembleImported state).pendingNodes = state.pendingNodes at preserved
  rw [preserved]
  exact conflicted

end Informal.Environment
