/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus

namespace Informal.Commands

open Lean

structure SorryItem where
  label : Name
  kind : String
  decl : Name
  isTheorem : Bool := false
  status : Data.ProvedStatus := .proved
deriving Inhabited, FromJson, ToJson

structure MissingLeanDeclItem where
  label : Name
  kind : String
  written : Name
  canonical : Name
deriving Inhabited, FromJson, ToJson

structure RenderFailureItem where
  label : Name
  kind : String
  written : Name
  canonical : Name
  message : String
deriving Inhabited, FromJson, ToJson

structure IndexItem where
  label : Name
  kind : String
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

abbrev PendingInformalItem := IndexItem

structure ParentTheoremGroup where
  parent : Name
  header : String := ""
  entries : List IndexItem := []
deriving Inhabited, FromJson, ToJson

structure EntryStatusCounts where
  completed : Nat := 0
  completedDepsNo : Nat := 0
  withSorries : Nat := 0
  noProof : Nat := 0
deriving Inhabited, FromJson, ToJson

structure PriorityItem where
  label : Name
  kind : String
  stage : String
  priority : Option String := none
  ownerDisplayName : Option String := none
  effort : Option String := none
  prUrl : Option String := none
  tags : List String := []
  statementStatus : String
  proofStatus : String := ""
  directUses : Nat := 0
  downstreamUses : Nat := 0
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

structure UsageItem where
  label : Name
  kind : String
  statementUses : Nat := 0
  proofUses : Nat := 0
  directUses : Nat := 0
  downstreamUses : Nat := 0
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

structure GroupHealthItem where
  parent : Name
  header : String := ""
  totalEntries : Nat := 0
  closedEntries : Nat := 0
  localOnlyEntries : Nat := 0
  readyEntries : Nat := 0
  blockedEntries : Nat := 0
  incompleteLeanEntries : Nat := 0
  unlockScore : Nat := 0
  nextPriority? : Option PriorityItem := none
deriving Inhabited, FromJson, ToJson

structure CoverageSplit where
  readyToFormalize : Nat := 0
  formalizedWithoutAncestors : Nat := 0
  fullyClosed : Nat := 0
  blockedOrIncomplete : Nat := 0
deriving Inhabited, FromJson, ToJson

structure DependencyLoadItem where
  label : Name
  kind : String
  statementDeps : Nat := 0
  proofDeps : Nat := 0
  totalDeps : Nat := 0
  directUses : Nat := 0
  downstreamUses : Nat := 0
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

structure DebtHotspotItem where
  parent : Name
  header : String := ""
  affectedEntries : Nat := 0
  incompleteDecls : Nat := 0
  missingDecls : Nat := 0
  totalDebt : Nat := 0
deriving Inhabited, FromJson, ToJson

structure OwnerRollupItem where
  owner : Name
  displayName : String := ""
  totalEntries : Nat := 0
  actionableEntries : Nat := 0
  quickWins : Nat := 0
  linkedPrs : Nat := 0
deriving Inhabited, FromJson, ToJson

structure TagRollupItem where
  tag : String
  totalEntries : Nat := 0
  actionableEntries : Nat := 0
  quickWins : Nat := 0
  linkedPrs : Nat := 0
deriving Inhabited, FromJson, ToJson

structure MetadataEntryItem where
  label : Name
  kind : String
  ownerDisplayName : Option String := none
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
  tags : List String := []
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

structure Summary where
  showDebugDiagnostics : Bool := false
  totalEntries : Nat := 0
  definitions : Nat := 0
  propositions : Nat := 0
  lemmas : Nat := 0
  theorems : Nat := 0
  corollaries : Nat := 0
  axioms : Nat := 0
  leanOnlyEntries : Nat := 0
  informalOnlyEntries : Nat := 0
  totalStatus : EntryStatusCounts := {}
  definitionStatus : EntryStatusCounts := {}
  propositionStatus : EntryStatusCounts := {}
  lemmaStatus : EntryStatusCounts := {}
  theoremStatus : EntryStatusCounts := {}
  corollaryStatus : EntryStatusCounts := {}
  axiomStatus : EntryStatusCounts := {}
  pendingInformalEntries : List PendingInformalItem := []
  leanDecls : Nat := 0
  sorries : Nat := 0
  sorryDetails : List SorryItem := []
  missingLeanDecls : List MissingLeanDeclItem := []
  renderFailures : List RenderFailureItem := []
  definitionIndex : List IndexItem := []
  theoremLikeIndex : List IndexItem := []
  axiomIndex : List IndexItem := []
  theoremLikeByParent : List ParentTheoremGroup := []
  actionablePriorities : List PriorityItem := []
  mostUsed : List UsageItem := []
  groupHealth : List GroupHealthItem := []
  coverageSplit : CoverageSplit := {}
  heaviestPrerequisites : List DependencyLoadItem := []
  noPrerequisites : List IndexItem := []
  noDependents : List IndexItem := []
  proofDebtHotspots : List DebtHotspotItem := []
  quickWins : List PriorityItem := []
  ownerRollups : List OwnerRollupItem := []
  tagRollups : List TagRollupItem := []
  linkedPrs : List MetadataEntryItem := []
  missingOwners : List MetadataEntryItem := []
  missingEffort : List MetadataEntryItem := []
  untaggedEntries : List MetadataEntryItem := []
deriving Inhabited, FromJson, ToJson

end Informal.Commands
