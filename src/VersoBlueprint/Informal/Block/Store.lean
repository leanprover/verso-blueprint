/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.TraversalIndex

namespace Informal

open Lean
open Verso
open Verso.Genre Manual

def numberingCounterState : Name := Lean.Name.mkSimple "Informal.Block.numberingCounter"

def nextGlobalBlockNumber (st : TraverseState) : Nat :=
  match st.get? numberingCounterState with
  | some (.ok (n : Nat)) => n
  | _ => 1

def reserveGlobalBlockNumber (st : TraverseState) : Nat × TraverseState :=
  let next := nextGlobalBlockNumber st
  (next, st.set numberingCounterState (next + 1))

/-- The first numbered part above the current block, used for chapter-style sub-numbering. -/
def numberedPartPrefix? (ctxt : TraverseContext) : Option String := Id.run do
  for header in ctxt.headers[1:] do
    if let some n := header.metadata.bind (·.assignedNumber) then
      return some (toString n)
  none

def resolveStoredBlockData? (st : TraverseState) (label : Data.Label) : Option BlockData :=
  Informal.TraversalIndex.Nodes.data? st label

private def mergeLabelArrays (xs ys : Array Data.Label) : Array Data.Label :=
  ys.foldl (init := xs) fun acc label =>
    if acc.contains label then acc else acc.push label

private def mergeStringArrays (xs ys : Array String) : Array String :=
  ys.foldl (init := xs) fun acc value =>
    if acc.contains value then acc else acc.push value

def mergeStoredBlockData (existing incoming : BlockData) : BlockData :=
  let kind :=
    match existing.kind, incoming.kind with
    | .statement _, _ => existing.kind
    | .proof, .statement _ => incoming.kind
    | .proof, .proof => existing.kind
  let codeData :=
    match existing.codeData, incoming.codeData with
    | some existingData, _ => some existingData
    | none, some incomingData => some incomingData
    | none, none => none
  { existing with
      kind
      codeData
      parent := existing.parent <|> incoming.parent
      partPrefix := existing.partPrefix <|> incoming.partPrefix
      globalCount := existing.globalCount <|> incoming.globalCount
      statementDeps := mergeLabelArrays existing.statementDeps incoming.statementDeps
      proofDeps := mergeLabelArrays existing.proofDeps incoming.proofDeps
      owner := existing.owner <|> incoming.owner
      ownerDisplayName := existing.ownerDisplayName <|> incoming.ownerDisplayName
      ownerUrl := existing.ownerUrl <|> incoming.ownerUrl
      ownerImageUrl := existing.ownerImageUrl <|> incoming.ownerImageUrl
      tags := mergeStringArrays existing.tags incoming.tags
      effort := existing.effort <|> incoming.effort
      priority := existing.priority <|> incoming.priority
      prUrl := existing.prUrl <|> incoming.prUrl
  }

private def sortStoredBlocks (entries : Array BlockData) : Array BlockData :=
  entries.qsort fun a b =>
    let aNum := a.globalCount.getD a.count
    let bNum := b.globalCount.getD b.count
    aNum < bNum ||
      (aNum == bNum && a.label.toString < b.label.toString)

def collectStoredBlocks (state : TraverseState) : Array BlockData :=
  match Informal.TraversalIndex.Nodes.domain? state with
  | none => #[]
  | some domain =>
    sortStoredBlocks <| domain.objects.foldl (init := #[]) fun acc _canonical obj =>
      match fromJson? (α := StoredBlockData) obj.data with
      | .ok block => acc.push block.toBlockData
      | .error _ =>
        match fromJson? (α := BlockData) obj.data with
        | .ok block => acc.push block
        | .error _ => acc

def BlockData.withResolvedNumbering
    (data : BlockData) (st : TraverseState) (fallbackPrefix? : Option String := none) : BlockData :=
  match resolveStoredBlockData? st data.label with
  | some stored =>
    { data with
        numberingMode := stored.numberingMode
        partPrefix := data.partPrefix <|> stored.partPrefix <|> fallbackPrefix?
        globalCount := data.globalCount <|> stored.globalCount
    }
  | none =>
    { data with partPrefix := data.partPrefix <|> fallbackPrefix? }

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

def blockDisplayTitle (data : BlockData) (numberText : String) : String :=
  match data.kind with
  | .proof => s!"Proof {numberText}"
  | .statement kind => s!"{kind} {numberText}"

def BlockData.displayTitle (data : BlockData)
    (st : TraverseState) (fallbackPrefix? : Option String := none) : String :=
  blockDisplayTitle data (data.displayNumber st fallbackPrefix?)

end Informal
