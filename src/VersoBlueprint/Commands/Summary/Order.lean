/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Commands.Summary.Data

/-!
Shared ordering helpers for Blueprint summary collection and rendering.
-/

namespace Informal.Commands

open Lean

private def priorityStageRank (stage : String) : Nat :=
  if stage == "proof" then 0 else if stage == "statement" then 1 else 2

private def explicitPriorityRank (priority? : Option String) : Nat :=
  match priority? with
  | some "high" => 0
  | some "medium" => 1
  | some "low" => 2
  | _ => 3

private def byNatAsc (left right : Nat) (tie : Bool) : Bool :=
  left < right || (left == right && tie)

private def byNatDesc (left right : Nat) (tie : Bool) : Bool :=
  left > right || (left == right && tie)

private def byStringAsc (left right : String) : Bool :=
  left < right

private def byNameStringAsc (left right : Name) : Bool :=
  left.toString < right.toString

def sortPriorityItems (items : Array PriorityItem) : Array PriorityItem :=
  items.qsort fun a b =>
    byNatAsc (explicitPriorityRank a.priority) (explicitPriorityRank b.priority) <|
      byNatDesc a.downstreamUses b.downstreamUses <|
        byNatDesc a.directUses b.directUses <|
          byNatAsc (priorityStageRank a.stage) (priorityStageRank b.stage) <|
            byNameStringAsc a.label b.label

def sortUsageItems (items : Array UsageItem) : Array UsageItem :=
  items.qsort fun a b =>
    byNatDesc a.directUses b.directUses <|
      byNatDesc a.downstreamUses b.downstreamUses <|
        byNameStringAsc a.label b.label

def sortDependencyLoadItems (items : Array DependencyLoadItem) : Array DependencyLoadItem :=
  items.qsort fun a b =>
    byNatDesc a.totalDeps b.totalDeps <|
      byNatDesc a.proofDeps b.proofDeps <|
        byNatDesc a.statementDeps b.statementDeps <|
          byNameStringAsc a.label b.label

def sortDebtHotspotItems (items : Array DebtHotspotItem) : Array DebtHotspotItem :=
  items.qsort fun a b =>
    byNatDesc a.totalDebt b.totalDebt <|
      byNatDesc a.affectedEntries b.affectedEntries <|
        byStringAsc a.header b.header

def sortGroupHealthItems (items : Array GroupHealthItem) : Array GroupHealthItem :=
  items.qsort fun a b =>
    byNatDesc a.readyEntries b.readyEntries <|
      byNatDesc a.unlockScore b.unlockScore <|
        byNatDesc a.totalEntries b.totalEntries <|
          byStringAsc a.header b.header

def sortOwnerRollupItems (items : Array OwnerRollupItem) : Array OwnerRollupItem :=
  items.qsort fun a b =>
    byNatDesc a.actionableEntries b.actionableEntries <|
      byNatDesc a.quickWins b.quickWins <|
        byNatDesc a.totalEntries b.totalEntries <|
          byStringAsc a.displayName b.displayName

def sortTagRollupItems (items : Array TagRollupItem) : Array TagRollupItem :=
  items.qsort fun a b =>
    byNatDesc a.actionableEntries b.actionableEntries <|
      byNatDesc a.quickWins b.quickWins <|
        byNatDesc a.totalEntries b.totalEntries <|
          byStringAsc a.tag b.tag

def sortMetadataEntryItems (items : Array MetadataEntryItem) : Array MetadataEntryItem :=
  items.qsort fun a b =>
    byNameStringAsc a.label b.label

def sortUsageItemsByAxis (items : Array UsageItem) (axisUses : UsageItem → Nat) : Array UsageItem :=
  items.qsort fun a b =>
    byNatDesc (axisUses a) (axisUses b) <|
      byNatDesc a.downstreamUses b.downstreamUses <|
        byNatDesc a.directUses b.directUses <|
          byNameStringAsc a.label b.label

end Informal.Commands
