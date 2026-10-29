/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Environment
import VersoBlueprint.NodeAssembly.SourceLaws
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
  rw [← nodeEq, NodeAssembly.assemble_ok_nativeAssociations_membership assembly]
  simp only [List.mem_reverse]
  constructor
  · rintro ⟨record, member, rest⟩
    exact ⟨record, (State.addNode_records accepted record).1.mp member, rest⟩
  · rintro ⟨record, member, rest⟩
    exact ⟨record, (State.addNode_records accepted record).1.mpr member, rest⟩

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
  exact Array.foldl_induction (as := entries) (f := step) (fun _ current => property current)
    start (fun i current valid => next current entries[i] valid)

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

/-- Declaration lookup describes exactly the accepted node table, using the
actual insertion policy for canonical declaration names. This is a proposition
about existing stores, not another registry or an assumed runtime certificate. -/
def State.DeclarationIndexCoherent (state : State) : Prop :=
  ∀ label : Label, ∀ query : Name,
    label ∈ state.leanNameLabels.getD query #[] ↔
      ∃ node, state.data.get? label = some node ∧
        ∃ declaration ∈ node.leanDecls, declaration.eraseMacroScopes = query

/-- Full import reassembly establishes declaration-index coherence from any
input state, including one with stale previously accepted nodes or index entries. -/
theorem State.reassembleImported_index_coherent (state : State) :
    (State.reassembleImported state).DeclarationIndexCoherent :=
  State.reassembleImported_declaration_index state

private theorem addNode_returned_declarations
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node))
    (query : Name) :
    (∃ registered, after.data.get? label = some registered ∧
      ∃ declaration ∈ registered.leanDecls, declaration.eraseMacroScopes = query) ↔
    ∃ declaration ∈ node.leanDecls, declaration.eraseMacroScopes = query := by
  obtain ⟨assembled, assembly, nodeEq, stored⟩ := State.addNode_assembled accepted
  cases found : after.data.get? label with
  | none => simp [found] at stored
  | some registered =>
    have semantic : registered.toNode = node := by simpa [found] using stored
    simp only [Option.some.injEq, exists_eq_left']
    change (∃ declaration ∈ registered.toNode.leanDecls, declaration.eraseMacroScopes = query) ↔ _
    rw [semantic]

/-- Exact remaining local-update obligation: from a coherent prior index, a
successful registration preserves coherence iff every previously indexed name
for that label still belongs to the returned node. This theorem does not assume
or claim that arbitrary payload producers satisfy that monotonicity condition. -/
theorem State.addNode_index_coherent_iff
    (coherent : before.DeclarationIndexCoherent)
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node)) :
    after.DeclarationIndexCoherent ↔
      ∀ query, label ∈ before.leanNameLabels.getD query #[] →
        ∃ declaration ∈ node.leanDecls, declaration.eraseMacroScopes = query := by
  constructor
  · intro afterCoherent query previous
    have present := (State.addNode_declaration_index accepted query label).mpr (Or.inl previous)
    exact (addNode_returned_declarations accepted query).mp ((afterCoherent label query).mp present)
  · intro retained other query
    rw [State.addNode_declaration_index accepted query other]
    by_cases same : other = label
    · subst other
      rw [addNode_returned_declarations accepted query]
      constructor
      · rintro (previous | ⟨_, declaration, member, canonical⟩)
        · exact retained query previous
        · exact ⟨declaration, member, canonical⟩
      · intro present
        exact Or.inr ⟨rfl, present⟩
    · have unchanged := (State.addNode_other_labels accepted (Ne.symm same)).1
      rw [unchanged]
      simpa only [same, false_and, or_false] using coherent other query

/-- Each stored node is the actual assembly of its retained registrations and
complete selected evidence. Absence and authored-origin validity are additional
properties; this proposition records only the accepted projection agreement. -/
def State.NodesMatchAssembly (state : State) : Prop :=
  ∀ label : Label, ∀ registered, state.data.get? label = some registered →
    ∃ assembled, NodeAssembly.assemble label (state.pendingNodes.getD label {}).registrations
      state.factRecords.reverse = .ok assembled ∧ assembled.node = registered.toNode

/-- The full import pass establishes actual assembly agreement for every node it
publishes, while retaining the original pending registrations and evidence. -/
theorem State.reassembleImported_nodes_match (state : State) :
    (State.reassembleImported state).NodesMatchAssembly := by
  intro label registered found
  obtain ⟨pending, pendingFound, _, assembled, assembledOk, stored⟩ :=
    (State.reassembleImported_node_iff state label registered).mp found
  have pendingFrame := congrArg State.pendingNodes (State.reassembleImported_frame state)
  have recordsFrame := congrArg State.factRecords (State.reassembleImported_frame state)
  change (State.reassembleImported state).pendingNodes = state.pendingNodes at pendingFrame
  change (State.reassembleImported state).factRecords = state.factRecords at recordsFrame
  refine ⟨assembled, ?_, ?_⟩
  · rw [pendingFrame, recordsFrame, NameMapLaws.getD_of_get?_eq_some _ _ _ _ pendingFound]
    exact assembledOk
  · cases stored
    rfl

/-- The real successful update preserves every declaration of the prior assembly.
Source accumulation and identified-record growth discharge the monotonicity
obligation; no declaration-preservation assumption is supplied by the caller. -/
theorem State.addNode_declarations_preserved
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node))
    (previous : NodeAssembly.assemble label (before.pendingNodes.getD label {}).registrations
      before.factRecords.reverse = .ok prior)
    (member : name ∈ prior.node.leanDecls) : name ∈ node.leanDecls := by
  obtain ⟨assembled, assembledOk, nodeEq, _⟩ := State.addNode_assembled accepted
  rw [← nodeEq]
  apply NodeAssembly.assemble_leanDecls_monotone previous assembledOk ?_ ?_ member
  · intro registration registered
    rw [State.addNode_effects accepted]
    simp only [NameMapLaws.getD_insert_self, PendingNode.append, Array.mem_append]
    exact Or.inl registered
  · intro record recorded
    exact List.mem_reverse.mpr ((State.addNode_records accepted record).1.mpr
      (Or.inl (List.mem_reverse.mp recorded)))

/-- Successful local admission preserves a coherent declaration index whenever
the prior stored nodes match their actual retained-input assemblies. The proof
uses production source accumulation and record retention, not a producer axiom. -/
theorem State.addNode_index_coherent
    (coherent : before.DeclarationIndexCoherent) (assembled : before.NodesMatchAssembly)
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node)) :
    after.DeclarationIndexCoherent := by
  apply (State.addNode_index_coherent_iff coherent accepted).mpr
  intro query previous
  obtain ⟨registered, found, declaration, member, canonical⟩ := (coherent label query).mp previous
  obtain ⟨prior, priorOk, priorEq⟩ := assembled label registered found
  refine ⟨declaration, State.addNode_declarations_preserved accepted priorOk ?_, canonical⟩
  simpa only [priorEq] using member

/-- A successful local registration immediately after full import reconstruction
has an exact declaration index, with no additional caller-side invariant premise. -/
theorem State.addNode_after_import_index_coherent
    (accepted : State.addNode (State.reassembleImported state) label origin contributor incoming facts = .ok (after, node)) :
    after.DeclarationIndexCoherent :=
  State.addNode_index_coherent (State.reassembleImported_index_coherent state)
    (State.reassembleImported_nodes_match state) accepted

private theorem recordsFor_extend_other (before facts : List Record) (target other : Label)
    (labelLocal : ∀ record ∈ facts, record.label = target) (different : target ≠ other) :
    recordsFor other (collector.extend before facts).reverse = recordsFor other before.reverse := by
  unfold Collector.extend
  induction facts generalizing before with
  | nil => rfl
  | cons record facts ih =>
    simp only [List.foldl_cons]
    rw [ih _ (fun item member => labelLocal item (by simp [member]))]
    have foreign : record.label ≠ other := by rw [labelLocal record (by simp)]; exact different
    simp only [collector, Contributions.insert]
    split
    · rfl
    · simp [recordsFor, List.reverse_cons, foreign]

private theorem noCollision_extend_other (before facts : List Record) (target other : Label)
    (labelLocal : ∀ record ∈ facts, record.label = target) (different : target ≠ other)
    (oldValid : NoCollision before.reverse other)
    (newValid : NoCollision (collector.extend before facts).reverse target) :
    NoCollision (collector.extend before facts).reverse other := by
  intro identity collision
  obtain ⟨⟨first, firstMem, second, secondMem, firstId, secondId, distinct⟩,
    witness, witnessMem, witnessId, witnessLabel⟩ := collision
  have belongs (record : Record) (member : record ∈ (collector.extend before facts).reverse) :
      record ∈ before ∨ record ∈ facts :=
    (mem_extend before facts record).mp (List.mem_reverse.mp member)
  have originalWitness : witness ∈ before := by
    rcases belongs witness witnessMem with original | added
    · exact original
    · exact False.elim (different ((labelLocal witness added).symm.trans witnessLabel))
  by_cases firstOld : first ∈ before
  · by_cases secondOld : second ∈ before
    · exact oldValid identity ⟨⟨first, List.mem_reverse.mpr firstOld, second,
        List.mem_reverse.mpr secondOld, firstId, secondId, distinct⟩,
        witness, List.mem_reverse.mpr originalWitness, witnessId, witnessLabel⟩
    · have added := (belongs second secondMem).resolve_left secondOld
      exact newValid identity ⟨⟨first, firstMem, second, secondMem, firstId, secondId, distinct⟩,
        second, secondMem, secondId, labelLocal second added⟩
  · have added := (belongs first firstMem).resolve_left firstOld
    exact newValid identity ⟨⟨first, firstMem, second, secondMem, firstId, secondId, distinct⟩,
      first, firstMem, firstId, labelLocal first added⟩

private theorem assemble_same_label_records
    (accepted : NodeAssembly.assemble label registrations previous = .ok assembled)
    (same : recordsFor label records = recordsFor label previous)
    (collisionFree : NoCollision records label) :
    NodeAssembly.assemble label registrations records = .ok assembled := by
  have resolved := NodeAssembly.assemble_ok_resolve accepted
  have valid := (resolve_success label previous).mp ⟨assembled.view, resolved⟩
  have priorityEq : priorityDisagrees label records = priorityDisagrees label previous := by
    simp only [priorityDisagrees, priorityValues, same]
  have priorityValid : ¬ PriorityDisagreement records label := by
    intro disagreement
    have failed := (priorityDisagrees_eq _ _).mpr disagreement
    rw [priorityEq] at failed
    exact valid.2 ((priorityDisagrees_eq _ _).mp failed)
  have nextResolved := resolve_valid ⟨collisionFree, priorityValid⟩
  have viewEq : view label records = view label previous := by
    simp only [view, priorityValues, same]
  rw [viewEq, ← resolve_ok resolved] at nextResolved
  have resolveEq := nextResolved.trans resolved.symm
  have sourceEq : NodeAssembly.sourceDestinationIssues label registrations records =
      NodeAssembly.sourceDestinationIssues label registrations previous := by
    simp only [NodeAssembly.sourceDestinationIssues, same]
  have admissionEq : NodeAssembly.admissionErrors label registrations records =
      NodeAssembly.admissionErrors label registrations previous := by
    simp only [NodeAssembly.admissionErrors, sourceEq, NodeAssembly.referenceNameErrors, same]
  simpa only [NodeAssembly.assemble, resolveEq, admissionEq] using accepted

private theorem assemble_extend_other
    (accepted : NodeAssembly.assemble other registrations before.reverse = .ok assembled)
    (labelLocal : ∀ record ∈ facts, record.label = target) (different : target ≠ other)
    (newValid : NoCollision (collector.extend before facts).reverse target) :
    NodeAssembly.assemble other registrations (collector.extend before facts).reverse = .ok assembled := by
  have valid := (resolve_success other before.reverse).mp
    ⟨assembled.view, NodeAssembly.assemble_ok_resolve accepted⟩
  exact assemble_same_label_records accepted
    (recordsFor_extend_other before facts target other labelLocal different)
    (noCollision_extend_other before facts target other labelLocal different valid.1 newValid)

/-- A label-local accepted registration preserves every stored node's agreement
with its retained-input assembly. Any new cross-label identity collision would
also reject the registering label, so successful admission cannot hide one. -/
theorem State.addNode_nodes_match (consistent : before.NodesMatchAssembly)
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node))
    (labelLocal : ∀ record ∈ facts, record.label = label) : after.NodesMatchAssembly := by
  intro other registered found
  by_cases same : other = label
  · subst other
    obtain ⟨assembled, assembledOk, nodeEq, stored⟩ := State.addNode_assembled accepted
    have registeredEq : registered.toNode = node := by simpa [found] using stored
    exact ⟨assembled, assembledOk, nodeEq.trans registeredEq.symm⟩
  · have unchanged := (State.addNode_other_labels accepted (Ne.symm same)).1
    have priorFound : before.data.get? other = some registered := unchanged ▸ found
    obtain ⟨prior, priorOk, priorEq⟩ := consistent other registered priorFound
    refine ⟨prior, ?_, priorEq⟩
    obtain ⟨current, currentOk, _, _⟩ := State.addNode_assembled accepted
    have currentValid := ((NodeAssembly.assemble_success_iff _ _ _).mp ⟨current, currentOk⟩).2.1.1
    rw [State.addNode_effects accepted] at currentValid ⊢
    rw [NameMapLaws.getD_insert before.pendingNodes label other]
    have different : (label : Name) ≠ (other : Name) := Ne.symm same
    rw [ite_eq_right different]
    exact assemble_extend_other priorOk labelLocal (Ne.symm same) currentValid

/-- Both coherence properties are preserved by the real accepted label-local
transition. Together with the import theorems this supplies the induction step
for supported registration sequences, without a second evaluator or store. -/
theorem State.addNode_coherent
    (consistent : before.NodesMatchAssembly) (indexed : before.DeclarationIndexCoherent)
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node))
    (labelLocal : ∀ record ∈ facts, record.label = label) :
    after.NodesMatchAssembly ∧ after.DeclarationIndexCoherent :=
  ⟨State.addNode_nodes_match consistent accepted labelLocal,
    State.addNode_index_coherent indexed consistent accepted⟩


private theorem assemble_before_extend_other
    (accepted : NodeAssembly.assemble other registrations (collector.extend before facts).reverse = .ok assembled)
    (labelLocal : ∀ record ∈ facts, record.label = target) (different : target ≠ other) :
    NodeAssembly.assemble other registrations before.reverse = .ok assembled := by
  have resolved := NodeAssembly.assemble_ok_resolve accepted
  have valid := (resolve_success other (collector.extend before facts).reverse).mp ⟨assembled.view, resolved⟩
  have retained (record : Record) (member : record ∈ before.reverse) :
      record ∈ (collector.extend before facts).reverse :=
    List.mem_reverse.mpr ((mem_extend before facts record).mpr (Or.inl (List.mem_reverse.mp member)))
  have collisionFree : NoCollision before.reverse other := by
    intro identity collision
    obtain ⟨⟨first, firstMem, second, secondMem, firstId, secondId, distinct⟩,
      witness, witnessMem, witnessId, witnessLabel⟩ := collision
    exact valid.1 identity ⟨⟨first, retained first firstMem, second, retained second secondMem,
      firstId, secondId, distinct⟩, witness, retained witness witnessMem, witnessId, witnessLabel⟩
  exact assemble_same_label_records accepted
    (recordsFor_extend_other before facts target other labelLocal different).symm collisionFree

private theorem importedNode_extend_other (pending : PendingNode)
    (labelLocal : ∀ record ∈ facts, record.label = target) (different : target ≠ other)
    (valid : NoCollision (collector.extend before facts).reverse target) :
    importedNode? (collector.extend before facts).reverse other pending =
      importedNode? before.reverse other pending := by
  unfold importedNode?
  split
  · rfl
  · cases old : NodeAssembly.assemble other pending.registrations before.reverse with
    | ok assembled =>
      rw [assemble_extend_other old labelLocal different valid]
    | error reasons =>
      cases new : NodeAssembly.assemble other pending.registrations (collector.extend before facts).reverse with
      | error _ => rfl
      | ok assembled =>
        have original := assemble_before_extend_other new labelLocal different
        rw [old] at original
        cases original

/-- The published node table is exactly admission of retained pending entries.
This includes rejected/absent labels and stored provenance, not only agreement
for nodes that happen to be present. No extra runtime store is introduced. -/
def State.AdmissionCoherent (state : State) : Prop :=
  ∀ label : Name, state.data.get? label =
    (state.pendingNodes.get? label).bind (importedNode? state.factRecords.reverse label)

/-- Full import reconstruction establishes exact admission coherence even from
an arbitrary stale published node table. -/
theorem State.reassembleImported_admission_coherent (state : State) :
    (State.reassembleImported state).AdmissionCoherent := by
  intro label
  have pending := congrArg State.pendingNodes (State.reassembleImported_frame state)
  have facts := congrArg State.factRecords (State.reassembleImported_frame state)
  change (State.reassembleImported state).pendingNodes = state.pendingNodes at pending
  change (State.reassembleImported state).factRecords = state.factRecords at facts
  rw [pending, facts]
  exact reassembleImported_lookup state label

/-- The exact accepted/absent-node invariant is preserved by the actual local
transition. Label locality and successful admission rule out newly invalidating
an unrelated node through a cross-label identity collision. -/
theorem State.addNode_admission_coherent (coherent : before.AdmissionCoherent)
    (accepted : State.addNode before label origin contributor incoming facts = .ok (after, node))
    (labelLocal : ∀ record ∈ facts, record.label = label) : after.AdmissionCoherent := by
  obtain ⟨originValid, assembled, assembledOk⟩ :=
    (State.addNode_success_iff before incoming facts).mp ⟨after, node, accepted⟩
  have valid := ((NodeAssembly.assemble_success_iff _ _ _).mp ⟨assembled, assembledOk⟩).2.1.1
  have nodeEq : assembled.node = node := by
    obtain ⟨actual, actualOk, same, _⟩ := State.addNode_assembled accepted
    rw [State.addNode_effects accepted] at actualOk
    simp only [NameMapLaws.getD_insert_self] at actualOk
    rw [assembledOk] at actualOk
    cases actualOk
    exact same
  intro other
  rw [State.addNode_effects accepted]
  simp only [NameMapLaws.get?_insert]
  by_cases same : (label : Name) = other
  · subst other
    simp only [ite_true, Option.bind_some, importedNode?, originValid, Bool.false_eq_true,
      ite_false, assembledOk, Except.toOption, Option.map_some, nodeEq]
  · simp only [same, ite_false]
    rw [coherent other]
    cases found : before.pendingNodes.get? other with
    | none => rfl
    | some pending =>
      exact (importedNode_extend_other pending labelLocal same valid).symm


/-- Input-facing form of exact admission coherence, including the retained
origin and contributing-module provenance of the accepted node. -/
theorem State.AdmissionCoherent.node_iff {state : State} (coherent : state.AdmissionCoherent)
    (label : Name) (registered : RegisteredNode) :
    state.data.get? label = some registered ↔
      ∃ pending, state.pendingNodes.get? label = some pending ∧
        pending.authoredOriginConflict = false ∧
        ∃ assembled, NodeAssembly.assemble label pending.registrations state.factRecords.reverse = .ok assembled ∧
          ({ toNode := assembled.node
             origin := pending.authoredOrigin?.getD pending.origin
             modules := pending.contributors } : RegisteredNode) = registered := by
  rw [coherent label]
  cases found : state.pendingNodes.get? label with
  | none => simp
  | some pending =>
    cases conflict : pending.authoredOriginConflict <;>
      cases assembled : NodeAssembly.assemble label pending.registrations state.factRecords.reverse <;>
      simp [importedNode?, conflict, assembled, Except.toOption]

/-- Exact admission coherence implies the earlier, weaker accepted-node agreement. -/
theorem State.AdmissionCoherent.nodes_match {state : State} (coherent : state.AdmissionCoherent) :
    state.NodesMatchAssembly := by
  intro label registered found
  obtain ⟨pending, pendingFound, _, assembled, assembledOk, stored⟩ :=
    (coherent.node_iff label registered).mp found
  refine ⟨assembled, ?_, ?_⟩
  · rw [NameMapLaws.getD_of_get?_eq_some _ _ _ _ pendingFound]
    exact assembledOk
  · cases stored
    rfl

/-- Every origin-conflicted label stays absent in a coherent published state. -/
theorem State.AdmissionCoherent.conflicted_absent {state : State} (coherent : state.AdmissionCoherent)
    (found : state.pendingNodes.get? label = some pending)
    (conflicted : pending.authoredOriginConflict = true) : state.data.get? label = none := by
  rw [coherent label, found]
  simp [importedNode?, conflicted]

/-- The existence of an empty-input assembly cannot invent a node whose label
has no retained pending entry. -/
theorem State.AdmissionCoherent.unknown_absent {state : State} (coherent : state.AdmissionCoherent)
    (absent : state.pendingNodes.get? label = none) : state.data.get? label = none := by
  rw [coherent label, absent]
  rfl

/-- A successful, label-local invocation of the actual registration transition.
This relation describes existing code; it is not an alternative state machine. -/
def State.LocalAdmission (before after : State) : Prop :=
  ∃ label origin contributor incoming facts node,
    State.addNode before label origin contributor incoming facts = .ok (after, node) ∧
      ∀ record ∈ facts, record.label = label

/-- Import reconstruction followed by any finite sequence of supported local
registrations preserves exact admission and declaration-index coherence. -/
theorem State.admission_sequence_coherent {initial final : State}
    (steps : final = State.reassembleImported initial ∨
      Relation.TransGen State.LocalAdmission (State.reassembleImported initial) final) :
    final.AdmissionCoherent ∧ final.DeclarationIndexCoherent := by
  have start := And.intro (State.reassembleImported_admission_coherent initial)
    (State.reassembleImported_index_coherent initial)
  have advance {before after : State}
      (coherent : before.AdmissionCoherent ∧ before.DeclarationIndexCoherent)
      (next : before.LocalAdmission after) :
      after.AdmissionCoherent ∧ after.DeclarationIndexCoherent := by
    obtain ⟨label, origin, contributor, incoming, facts, node, accepted, labelLocal⟩ := next
    exact ⟨State.addNode_admission_coherent coherent.1 accepted labelLocal,
      State.addNode_index_coherent coherent.2 coherent.1.nodes_match accepted⟩
  rcases steps with rfl | steps
  · exact start
  · induction steps with
    | single next => exact advance start next
    | tail _ next ih => exact advance ih next

end Informal.Environment
