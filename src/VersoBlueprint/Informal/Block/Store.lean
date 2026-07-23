/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.TraversalIndex

/-!
Traversal-time storage and numbering logic for informal blocks.

The renderer resolves checked node semantics through the captured registry.
This module supplies document-order numbers and section prefixes, reusing one
number for repeated occurrences of a label.
-/

namespace Informal

open Lean
open Verso
open Verso.Genre Manual

/-- Traversal-state key for the next document-order informal block number. -/
def numberingCounterState : Name := Lean.Name.mkSimple "Informal.Block.numberingCounter"

/-- Traversal-state key for the next informal block number under each rendered prefix. -/
def prefixNumberingCounterState : Name :=
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

/--
Traversal-state key for the next source-local number available during traversal.
-/
private def sourceNumberingCounterState : Name :=
  Lean.Name.mkSimple "Informal.Block.sourceNumberingCounter"

private def nextSourceBlockNumber (st : TraverseState) : Nat :=
  match st.get? sourceNumberingCounterState with
  | some (.ok (n : Nat)) => n
  | _ => 1

/--
Resolve a source-local block number monotonically in traversal order.

Zero is the unassigned sentinel. A nonzero elaboration-time count is also
reassigned when an earlier generated placement has already advanced beyond it.
-/
private def resolveSourceBlockNumber (st : TraverseState) (count : Nat) :
    Nat × TraverseState :=
  let next := nextSourceBlockNumber st
  if count == 0 || count < next then
    (next, st.set sourceNumberingCounterState (next + 1))
  else
    (count, st.set sourceNumberingCounterState (count + 1))

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
document-order mode, the block keeps the source-local `count` already resolved
during traversal.
-/
def reserveSubBlockNumber (st : TraverseState) (data : BlockData) : Nat × TraverseState :=
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
private def BlockData.withReservedNumbering
    (data : BlockData) (st : TraverseState) : BlockData × TraverseState :=
  let (globalCount, st) :=
    match data.globalCount with
    | some globalCount => (globalCount, st)
    | none => reserveGlobalBlockNumber st
  let (sourceCount, st) := resolveSourceBlockNumber st data.count
  let (count, st) :=
    match data.numberingMode with
    | .sub => reserveSubBlockNumber st { data with count := sourceCount }
    | _ => (sourceCount, st)
  ({ data with count, globalCount := some globalCount }, st)

/-- Merge occurrence facts after resolving both occurrences through the shared node registry. -/
def mergeBlockOccurrences (existing incoming : BlockData) : BlockData :=
  { existing with
      isProof := existing.isProof && incoming.isProof
      partPrefix := existing.partPrefix <|> incoming.partPrefix
      globalCount := existing.globalCount <|> incoming.globalCount
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
      | .ok stored => some stored.data
      | .error _ => none

/-- Overlay stored numbering onto render-time block data. -/
private def BlockData.withStoredNumbering
    (data : BlockData) (stored : BlockPresentation) (fallbackPrefix? : Option String := none) :
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
  match Informal.TraversalIndex.Nodes.occurrence? st data.label with
  | some stored =>
    data.withStoredNumbering stored.toBlockPresentation fallbackPrefix?
  | none =>
    { data with partPrefix := data.partPrefix <|> fallbackPrefix? }

/-- Resolve stored numbering for a block, computing the fallback prefix from traversal context. -/
def BlockData.withResolvedNumberingInContext
    (data : BlockData) (st : TraverseState) (ctxt : TraverseContext) : BlockData :=
  match Informal.TraversalIndex.Nodes.occurrence? st data.label with
  | some stored =>
    data.withStoredNumbering stored.toBlockPresentation (numberedPartPrefix? stored.subNumberingPrefix ctxt)
  | none =>
    data.withTraversalNumberingContext ctxt

/-- Format numbering from an actual document occurrence. -/
private def occurrenceNumber (data : BlockData) : String :=
  match data.numberingMode with
  | .local => s!"{data.count}"
  | .global => s!"{data.globalCount.getD data.count}"
  | .sub =>
      match data.partPrefix with
      | some numberPrefix => s!"{numberPrefix}.{data.count}"
      | none => s!"{data.count}"

/-- One presentation boundary for captured identity and optional document numbering. -/
def BlockData.display (data : BlockData) (st : TraverseState)
    (fallbackPrefix? : Option String := none) : NodeDisplay := {
  label := data.label
  kind := data.kind
  number? := (Informal.TraversalIndex.Nodes.occurrence? st data.label).map fun stored =>
    occurrenceNumber (data.withStoredNumbering stored.toBlockPresentation fallbackPrefix?)
}

/-- Resolve node presentation without turning an elaboration count into a document number. -/
def Informal.TraversalIndex.Nodes.display? (st : TraverseState) (label : Data.Label) : Option NodeDisplay := do
  let node ← Informal.TraversalIndex.Nodes.node? st label
  return node.toBlockData.display st

def BlockData.displayTitle (data : BlockData) (st : TraverseState)
    (fallbackPrefix? : Option String := none) : String :=
  let display := data.display st fallbackPrefix?
  if data.isProof then display.proofTitle else display.title

def BlockData.displayProofTitle (data : BlockData) (st : TraverseState)
    (fallbackPrefix? : Option String := none) : String :=
  (data.display st fallbackPrefix?).proofTitle

/--
Save one traversed informal block in the semantic node index.

New labels get ids, external tags, and reserved numbering. Repeated labels reuse their checked
semantic metadata and merge occurrence facts without consuming another number.
-/
def saveTraversedBlockData
    {m}
    [Monad m]
    [MonadBuildLog m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (blockData : BlockData) :
    m Unit := do
  let label := blockData.label
  let state ← get
  let existing := Informal.TraversalIndex.Nodes.renderedData? state label
  match existing with
  | some existing =>
    let mergedData := mergeBlockOccurrences existing blockData
    modify λ s => Informal.TraversalIndex.Nodes.saveOccurrence s mergedData.toOccurrence
  | none =>
    let path := (← read).path
    let _ ← Verso.Genre.Manual.externalTag id path s!"--informal-{label}"
    modify fun st =>
      let (storedBlockData, st) := blockData.withReservedNumbering st
      st
        |> (fun st => Informal.TraversalIndex.Nodes.saveId st label id)
        |> (fun st => Informal.TraversalIndex.Nodes.saveOccurrence st storedBlockData.toOccurrence)

end Informal
