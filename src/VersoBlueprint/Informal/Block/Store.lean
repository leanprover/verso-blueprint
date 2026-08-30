/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprint.Informal.Block.Model
public import VersoBlueprint.TraversalIndex

public section

/-!
Traversal-time storage and numbering logic for informal blocks.

The renderer receives local block data from the directive syntax, but final HTML
needs document-order numbers, optional section prefixes, and metadata gathered
from all occurrences of a label. This module owns that stored view and exposes
small helpers for rendering code to ask for display numbers and titles.
-/

namespace Informal

open Lean
open Verso
open Verso.Genre Manual

/-- Traversal-state key for the next document-order informal block number. -/
abbrev numberingCounterState : Name := Lean.Name.mkSimple "Informal.Block.numberingCounter"

/-- Traversal-state key for the next informal block number under each rendered prefix. -/
abbrev prefixNumberingCounterState : Name :=
  Lean.Name.mkSimple "Informal.Block.prefixNumberingCounter"

/-- The next document-order informal block number, defaulting to `1`. -/
def nextGlobalBlockNumber (st : TraverseState) : Nat :=
  match st.get? numberingCounterState with
  | some (.ok (n : Nat)) => n
  | _ => 1

/-- Reserve one document-order informal block number and advance the global counter. -/
def reserveGlobalBlockNumber (st : TraverseState) : Nat × TraverseState :=
  let next := nextGlobalBlockNumber st
  (next, st.set numberingCounterState (next + 1))

/-- Prefix-local counters, stored as a small association list in traversal state. -/
private def prefixBlockCounters (st : TraverseState) : Array (String × Nat) :=
  match st.get? prefixNumberingCounterState with
  | some (.ok (counters : Array (String × Nat))) => counters
  | _ => #[]

private def nextPrefixBlockNumber (counters : Array (String × Nat)) (partPrefix : String) : Nat :=
  (counters.findSome? fun (candidate, next) =>
    if candidate == partPrefix then some next else none).getD 1

private def setPrefixBlockCounter
    (counters : Array (String × Nat)) (partPrefix : String) (next : Nat) :
    Array (String × Nat) :=
  let counters := counters.filter fun (candidate, _) => candidate != partPrefix
  counters.push (partPrefix, next)

/-- Reserve one informal block number under `partPrefix`. -/
def reservePrefixBlockNumber (st : TraverseState) (partPrefix : String) : Nat × TraverseState :=
  let counters := prefixBlockCounters st
  let next := nextPrefixBlockNumber counters partPrefix
  (next, st.set prefixNumberingCounterState (setPrefixBlockCounter counters partPrefix (next + 1)))

private def numberingPartString : Numbering → String
  | .nat n => toString n
  | .letter a => toString a

/-- First numbered ancestor above the block, for chapter-style prefixes. -/
private def firstNumberedPartPrefix? (ctxt : TraverseContext) : Option String := Id.run do
  for num? in ctxt.sectionNumber[1:] do
    if let some num := num? then
      return some (numberingPartString num)
  none

/-- Full numbered ancestor path above the block, for section-local prefixes. -/
private def fullNumberedPartPrefix? (ctxt : TraverseContext) : Option String := Id.run do
  let mut nums : Array String := #[]
  for num? in ctxt.sectionNumber[1:] do
    if let some num := num? then
      nums := nums.push (numberingPartString num)
  if nums.isEmpty then none else some (String.intercalate "." nums.toList)

/-- The rendered section prefix above the current block, according to the sub-numbering policy. -/
def numberedPartPrefix? (mode : SubNumberingPrefix) (ctxt : TraverseContext) : Option String :=
  match mode with
  | .full => fullNumberedPartPrefix? ctxt
  | .first => firstNumberedPartPrefix? ctxt

/--
Resolve the appended number for a sub-numbered block.

Only `SubNumberingCounter.prefix` reserves a new prefix-local number. In
document-order mode, the block keeps the elaboration-time `count`.
-/
def reserveSubBlockNumber (st : TraverseState) (data : StoredBlockData) : Nat × TraverseState :=
  match data.subNumberingCounter, data.partPrefix with
  | .prefix, some partPrefix => reservePrefixBlockNumber st partPrefix
  | _, _ => (data.count, st)

/-- Attach the current traversal prefix to a block before it is stored. -/
def BlockData.withTraversalNumberingContext (data : BlockData) (ctxt : TraverseContext) :
    BlockData :=
  { data with partPrefix := data.partPrefix <|> numberedPartPrefix? data.subNumberingPrefix ctxt }

/--
Reserve the traversal numbers for a newly seen block.

Every stored block gets a document-order `globalCount`. Sub-numbered blocks may
also replace `count` with a prefix-local count, depending on their policy.
-/
private def StoredBlockData.withReservedNumbering
    (data : StoredBlockData) (st : TraverseState) : StoredBlockData × TraverseState :=
  let (globalCount, st) :=
    match data.globalCount with
    | some globalCount => (globalCount, st)
    | none => reserveGlobalBlockNumber st
  let (count, st) :=
    match data.numberingMode with
    | .sub => reserveSubBlockNumber st data
    | _ => (data.count, st)
  ({ data with count, globalCount := some globalCount }, st)

/-- Look up the stored semantic payload for an informal block label. -/
def resolveStoredNodeData? (st : TraverseState) (label : Data.Label) : Option StoredBlockData :=
  Informal.TraversalIndex.Nodes.storedData? st label

/-- Look up stored informal block data in render-facing `BlockData` form. -/
def resolveStoredBlockData? (st : TraverseState) (label : Data.Label) : Option BlockData :=
  (resolveStoredNodeData? st label).map (·.toBlockData)

private def mergeStringArrays (xs ys : Array String) : Array String :=
  ys.foldl (init := xs) fun acc value =>
    if acc.contains value then acc else acc.push value

/--
Merge two stored entries for the same label.

Numbering stays with the first stored entry, while semantic metadata is filled
in from later entries. If either entry is a statement, the merged node is a
statement so summaries do not treat it as proof-only.
-/
def mergeStoredBlockData (existing incoming : StoredBlockData) : StoredBlockData :=
  let kind :=
    match existing.kind, incoming.kind with
    | .statement _, _ => existing.kind
    | .proof, .statement _ => incoming.kind
    | .proof, .proof => existing.kind
  { existing with
      kind := kind
      parent := existing.parent <|> incoming.parent
      partPrefix := existing.partPrefix <|> incoming.partPrefix
      globalCount := existing.globalCount <|> incoming.globalCount
      statementUses := Data.UseRef.mergeByLabel existing.statementUses incoming.statementUses
      proofUses := Data.UseRef.mergeByLabel existing.proofUses incoming.proofUses
      owner := existing.owner <|> incoming.owner
      ownerDisplayName := existing.ownerDisplayName <|> incoming.ownerDisplayName
      ownerUrl := existing.ownerUrl <|> incoming.ownerUrl
      ownerImageUrl := existing.ownerImageUrl <|> incoming.ownerImageUrl
      tags := mergeStringArrays existing.tags incoming.tags
      effort := existing.effort <|> incoming.effort
      priority := existing.priority <|> incoming.priority
      prUrl := existing.prUrl <|> incoming.prUrl
  }

/--
Stable document-order comparison for informal blocks.

`globalCount` is the traversal-order number assigned while walking the document.
Older or partially populated stored data may not have it, so the local block
counter remains the fallback. Labels break ties deterministically.
-/
def BlockData.traversalOrderLess (a b : BlockData) : Bool :=
  let aNum := a.globalCount.getD a.count
  let bNum := b.globalCount.getD b.count
  aNum < bNum ||
    (aNum == bNum && a.label.toString < b.label.toString)

/-- Sort stored blocks by traversal order, using the label as a stable tiebreaker. -/
private def sortStoredBlocks (entries : Array BlockData) : Array BlockData :=
  entries.qsort BlockData.traversalOrderLess

/-- Collect every informal block stored in the traversal index, in traversal order. -/
def collectStoredBlocks (state : TraverseState) : Array BlockData :=
  sortStoredBlocks <|
    Informal.TraversalIndex.Nodes.entries state |>.filterMap fun
      | .ok stored => some stored.data.toBlockData
      | .error _ => none

/-- Overlay stored numbering onto render-time block data. -/
private def BlockData.withStoredNumbering
    (data : BlockData) (stored : StoredBlockData) (fallbackPrefix? : Option String := none) :
    BlockData :=
  { data with
      count := stored.count
      numberingMode := stored.numberingMode
      subNumberingPrefix := stored.subNumberingPrefix
      subNumberingCounter := stored.subNumberingCounter
      partPrefix := data.partPrefix <|> stored.partPrefix <|> fallbackPrefix?
      globalCount := data.globalCount <|> stored.globalCount
  }

/-- Resolve stored numbering for a block, with an optional caller-provided prefix fallback. -/
def BlockData.withResolvedNumbering
    (data : BlockData) (st : TraverseState) (fallbackPrefix? : Option String := none) : BlockData :=
  match resolveStoredNodeData? st data.label with
  | some stored =>
    data.withStoredNumbering stored fallbackPrefix?
  | none =>
    { data with partPrefix := data.partPrefix <|> fallbackPrefix? }

/-- Resolve stored numbering for a block, computing the fallback prefix from traversal context. -/
def BlockData.withResolvedNumberingInContext
    (data : BlockData) (st : TraverseState) (ctxt : TraverseContext) : BlockData :=
  match resolveStoredNodeData? st data.label with
  | some stored =>
    data.withStoredNumbering stored (numberedPartPrefix? stored.subNumberingPrefix ctxt)
  | none =>
    data.withTraversalNumberingContext ctxt

/-- The user-facing number for a block, after applying stored numbering metadata. -/
def BlockData.displayNumber (data : BlockData)
    (st : TraverseState) (fallbackPrefix? : Option String := none) : String :=
  let data := data.withResolvedNumbering st fallbackPrefix?
  match data.numberingMode with
  | .local => s!"{data.count}"
  | .global => s!"{data.globalCount.getD data.count}"
  | .sub =>
      match data.partPrefix with
      | some numPrefix => s!"{numPrefix}.{data.count}"
      | none => s!"{data.count}"

/-- Add the block kind to a rendered number, for example `Definition 1.3.2`. -/
def blockDisplayTitle (data : BlockData) (numberText : String) : String :=
  match data.kind with
  | .proof => s!"Proof {numberText}"
  | .statement kind => s!"{kind} {numberText}"

def BlockData.statementKind? (data : BlockData) (st : TraverseState) : Option Data.NodeKind :=
  match data.kind with
  | .statement kind => some kind
  | .proof =>
      match resolveStoredNodeData? st data.label with
      | some stored =>
          match stored.kind with
          | .statement kind => some kind
          | .proof => none
      | none => none

def proofDisplayTitle (statementKind? : Option Data.NodeKind) (numberText : String) : String :=
  match statementKind? with
  | some kind => s!"Proof for {kind} {numberText}"
  | none => s!"Proof {numberText}"

def BlockData.displayProofTitle (data : BlockData)
    (st : TraverseState) (fallbackPrefix? : Option String := none) : String :=
  proofDisplayTitle (data.statementKind? st) (data.displayNumber st fallbackPrefix?)

/-- The user-facing title for a block, including kind and resolved number. -/
def BlockData.displayTitle (data : BlockData)
    (st : TraverseState) (fallbackPrefix? : Option String := none) : String :=
  let numberText := data.displayNumber st fallbackPrefix?
  match data.kind with
  | .proof => data.displayProofTitle st fallbackPrefix?
  | .statement _ => blockDisplayTitle data numberText

/--
Save one traversed informal block in the semantic node index.

New labels get ids, external tags, and reserved numbering. Repeated labels merge
their metadata without consuming another number.
-/
def saveTraversedBlockData
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (blockData : BlockData) :
    m Unit := do
  let label := blockData.label
  let storedBlockData := blockData.toStoredData
  match Informal.TraversalIndex.Nodes.storedData? (← get) label with
  | some existing =>
    let mergedData := mergeStoredBlockData existing storedBlockData
    modify λ s => Informal.TraversalIndex.Nodes.saveData s label (toJson mergedData)
  | none =>
    let path := (← read).path
    let _ ← Verso.Genre.Manual.externalTag id path s!"--informal-{label}"
    modify fun st =>
      let (storedBlockData, st) := storedBlockData.withReservedNumbering st
      st
        |> (fun st => Informal.TraversalIndex.Nodes.saveId st label id)
        |> (fun st => Informal.TraversalIndex.Nodes.saveData st label (toJson storedBlockData))

end Informal
