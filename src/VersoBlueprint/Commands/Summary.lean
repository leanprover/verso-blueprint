/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Elab.Command
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.Environment
import VersoBlueprint.Graph
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.MetadataView
import VersoBlueprint.Informal.LeanCodeLink
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.PreviewCache
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment

register_option verso.blueprint.summary.debugDiagnostics : Bool := {
  defValue := false
  descr := "Show maintainer diagnostics such as external declaration render failures in blueprint summaries"
}

structure SorryItem where
  label : Name
  kind : String
  decl : Name
  isTheorem : Bool := false
  status : Data.ProvedStatus := .proved
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote SorryItem where
  quote s := mkCApp ``SorryItem.mk #[quote s.label, quote s.kind, quote s.decl, quote s.isTheorem, quote s.status]

structure MissingLeanDeclItem where
  label : Name
  kind : String
  written : Name
  canonical : Name
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote MissingLeanDeclItem where
  quote s := mkCApp ``MissingLeanDeclItem.mk #[quote s.label, quote s.kind, quote s.written, quote s.canonical]

structure RenderFailureItem where
  label : Name
  kind : String
  written : Name
  canonical : Name
  message : String
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote RenderFailureItem where
  quote s := mkCApp ``RenderFailureItem.mk #[quote s.label, quote s.kind, quote s.written, quote s.canonical, quote s.message]

structure IndexItem where
  label : Name
  kind : String
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote IndexItem where
  quote s := mkCApp ``IndexItem.mk #[quote s.label, quote s.kind, quote s.leanObjects]

abbrev PendingInformalItem := IndexItem

structure ParentTheoremGroup where
  parent : Name
  header : String := ""
  entries : List IndexItem := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote ParentTheoremGroup where
  quote s := mkCApp ``ParentTheoremGroup.mk #[quote s.parent, quote s.header, quote s.entries]

structure EntryStatusCounts where
  completed : Nat := 0
  completedDepsNo : Nat := 0
  withSorries : Nat := 0
  noProof : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote EntryStatusCounts where
  quote s := mkCApp ``EntryStatusCounts.mk
    #[
      quote s.completed,
      quote s.completedDepsNo,
      quote s.withSorries,
      quote s.noProof
    ]

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

open Syntax in
instance : Quote PriorityItem where
  quote s := mkCApp ``PriorityItem.mk
    #[
      quote s.label,
      quote s.kind,
      quote s.stage,
      quote s.priority,
      quote s.ownerDisplayName,
      quote s.effort,
      quote s.prUrl,
      quote s.tags,
      quote s.statementStatus,
      quote s.proofStatus,
      quote s.directUses,
      quote s.downstreamUses,
      quote s.leanObjects
    ]

structure UsageItem where
  label : Name
  kind : String
  statementUses : Nat := 0
  proofUses : Nat := 0
  directUses : Nat := 0
  downstreamUses : Nat := 0
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote UsageItem where
  quote s := mkCApp ``UsageItem.mk
    #[
      quote s.label,
      quote s.kind,
      quote s.statementUses,
      quote s.proofUses,
      quote s.directUses,
      quote s.downstreamUses,
      quote s.leanObjects
    ]

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

open Syntax in
instance : Quote GroupHealthItem where
  quote s := mkCApp ``GroupHealthItem.mk
    #[
      quote s.parent,
      quote s.header,
      quote s.totalEntries,
      quote s.closedEntries,
      quote s.localOnlyEntries,
      quote s.readyEntries,
      quote s.blockedEntries,
      quote s.incompleteLeanEntries,
      quote s.unlockScore,
      quote s.nextPriority?
    ]

structure CoverageSplit where
  informalOnly : Nat := 0
  readyToFormalize : Nat := 0
  formalizedWithoutAncestors : Nat := 0
  fullyClosed : Nat := 0
  blockedOrIncomplete : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote CoverageSplit where
  quote s := mkCApp ``CoverageSplit.mk
    #[
      quote s.informalOnly,
      quote s.readyToFormalize,
      quote s.formalizedWithoutAncestors,
      quote s.fullyClosed,
      quote s.blockedOrIncomplete
    ]

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

open Syntax in
instance : Quote DependencyLoadItem where
  quote s := mkCApp ``DependencyLoadItem.mk
    #[
      quote s.label,
      quote s.kind,
      quote s.statementDeps,
      quote s.proofDeps,
      quote s.totalDeps,
      quote s.directUses,
      quote s.downstreamUses,
      quote s.leanObjects
    ]

structure DebtHotspotItem where
  parent : Name
  header : String := ""
  affectedEntries : Nat := 0
  incompleteDecls : Nat := 0
  missingDecls : Nat := 0
  totalDebt : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote DebtHotspotItem where
  quote s := mkCApp ``DebtHotspotItem.mk
    #[
      quote s.parent,
      quote s.header,
      quote s.affectedEntries,
      quote s.incompleteDecls,
      quote s.missingDecls,
      quote s.totalDebt
    ]

structure OwnerRollupItem where
  owner : Name
  displayName : String := ""
  totalEntries : Nat := 0
  actionableEntries : Nat := 0
  quickWins : Nat := 0
  linkedPrs : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote OwnerRollupItem where
  quote s := mkCApp ``OwnerRollupItem.mk
    #[
      quote s.owner,
      quote s.displayName,
      quote s.totalEntries,
      quote s.actionableEntries,
      quote s.quickWins,
      quote s.linkedPrs
    ]

structure TagRollupItem where
  tag : String
  totalEntries : Nat := 0
  actionableEntries : Nat := 0
  quickWins : Nat := 0
  linkedPrs : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote TagRollupItem where
  quote s := mkCApp ``TagRollupItem.mk
    #[
      quote s.tag,
      quote s.totalEntries,
      quote s.actionableEntries,
      quote s.quickWins,
      quote s.linkedPrs
    ]

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

open Syntax in
instance : Quote MetadataEntryItem where
  quote s := mkCApp ``MetadataEntryItem.mk
    #[
      quote s.label,
      quote s.kind,
      quote s.ownerDisplayName,
      quote s.effort,
      quote s.priority,
      quote s.prUrl,
      quote s.tags,
      quote s.leanObjects
    ]

structure Summary where
  showDebugDiagnostics : Bool := false
  totalEntries : Nat := 0
  definitions : Nat := 0
  lemmas : Nat := 0
  theorems : Nat := 0
  corollaries : Nat := 0
  axioms : Nat := 0
  leanOnlyEntries : Nat := 0
  informalOnlyEntries : Nat := 0
  totalStatus : EntryStatusCounts := {}
  definitionStatus : EntryStatusCounts := {}
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
  topPriorities : List PriorityItem := []
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

open Syntax in
instance : Quote Summary where
  quote s := mkCApp ``Summary.mk
    #[
      quote s.showDebugDiagnostics,
      quote s.totalEntries,
      quote s.definitions,
      quote s.lemmas,
      quote s.theorems,
      quote s.corollaries,
      quote s.axioms,
      quote s.leanOnlyEntries,
      quote s.informalOnlyEntries,
      quote s.totalStatus,
      quote s.definitionStatus,
      quote s.lemmaStatus,
      quote s.theoremStatus,
      quote s.corollaryStatus,
      quote s.axiomStatus,
      quote s.pendingInformalEntries,
      quote s.leanDecls,
      quote s.sorries,
      quote s.sorryDetails,
      quote s.missingLeanDecls,
      quote s.renderFailures,
      quote s.definitionIndex,
      quote s.theoremLikeIndex,
      quote s.axiomIndex,
      quote s.theoremLikeByParent,
      quote s.topPriorities,
      quote s.mostUsed,
      quote s.groupHealth,
      quote s.coverageSplit,
      quote s.heaviestPrerequisites,
      quote s.noPrerequisites,
      quote s.noDependents,
      quote s.proofDebtHotspots,
      quote s.quickWins,
      quote s.ownerRollups,
      quote s.tagRollups,
      quote s.linkedPrs,
      quote s.missingOwners,
      quote s.missingEffort,
      quote s.untaggedEntries
    ]

structure EntryStatusFlags where
  completed : Bool := false
  completedDepsNo : Bool := false
  withSorries : Bool := false
  noProof : Bool := false
  hasAxiomLike : Bool := false
deriving Inhabited

private structure UsageCounts where
  statementUses : Nat := 0
  proofUses : Nat := 0
deriving Inhabited

private def UsageCounts.directUses (counts : UsageCounts) : Nat :=
  counts.statementUses + counts.proofUses

private def bumpUsageCounts (acc : UsageCounts) (inStatement inProof : Bool) : UsageCounts :=
  {
    statementUses := acc.statementUses + (if inStatement then 1 else 0)
    proofUses := acc.proofUses + (if inProof then 1 else 0)
  }

private def pushUniqueName (xs : Array Name) (x : Name) : Array Name :=
  if xs.contains x then xs else xs.push x

private def buildUsageMaps (entries : Array (Name × Data.Node)) : NameMap UsageCounts × NameMap (Array Name) :=
  entries.foldl (init := (({} : NameMap UsageCounts), ({} : NameMap (Array Name)))) fun (usageMap, reverseMap) (sourceLabel, node) =>
    let statementDeps := Informal.Graph.eraseDups (Informal.Graph.statementDeps node)
    let proofDeps := Informal.Graph.eraseDups (Informal.Graph.proofDeps node)
    let usageMap :=
      statementDeps.foldl (init := usageMap) fun acc dep =>
        acc.insert dep (bumpUsageCounts (acc.getD dep {}) true false)
    let usageMap :=
      proofDeps.foldl (init := usageMap) fun acc dep =>
        acc.insert dep (bumpUsageCounts (acc.getD dep {}) false true)
    let reverseDeps := Informal.Graph.eraseDups (statementDeps ++ proofDeps)
    let reverseMap :=
      reverseDeps.foldl (init := reverseMap) fun acc dep =>
        acc.insert dep (pushUniqueName (acc.getD dep #[]) sourceLabel)
    (usageMap, reverseMap)

partial def downstreamUseCount (reverseMap : NameMap (Array Name))
    (pending : List Name) (visited : NameSet := {}) (count : Nat := 0) : Nat :=
  match pending with
  | [] => count
  | label :: rest =>
    if visited.contains label then
      downstreamUseCount reverseMap rest visited count
    else
      let next := (reverseMap.getD label #[]).toList
      downstreamUseCount reverseMap (next ++ rest) (visited.insert label) (count + 1)

private def actionableStage? (node : Data.Node)
    (statementStatus : Informal.Graph.StatementStatus) (proofStatus : Informal.Graph.ProofStatus) : Option String :=
  if node.kind.isTheoremLike then
    if proofStatus == .ready || proofStatus == .incomplete then
      some "proof"
    else if statementStatus == .ready then
      some "statement"
    else
      none
  else if statementStatus == .ready then
    some "statement"
  else
    none

private def priorityStageRank (stage : String) : Nat :=
  if stage == "proof" then 0 else if stage == "statement" then 1 else 2

private def explicitPriorityRank (priority? : Option String) : Nat :=
  match priority? with
  | some "high" => 0
  | some "medium" => 1
  | some "low" => 2
  | _ => 3

private def sortPriorityItems (items : Array PriorityItem) : Array PriorityItem :=
  items.qsort fun a b =>
    explicitPriorityRank a.priority < explicitPriorityRank b.priority ||
      (explicitPriorityRank a.priority == explicitPriorityRank b.priority &&
        (a.downstreamUses > b.downstreamUses ||
      (a.downstreamUses == b.downstreamUses &&
        (a.directUses > b.directUses ||
          (a.directUses == b.directUses &&
            (priorityStageRank a.stage < priorityStageRank b.stage ||
              (priorityStageRank a.stage == priorityStageRank b.stage &&
                a.label.toString < b.label.toString)))))))

private def sortUsageItems (items : Array UsageItem) : Array UsageItem :=
  items.qsort fun a b =>
    a.directUses > b.directUses ||
      (a.directUses == b.directUses &&
        (a.downstreamUses > b.downstreamUses ||
          (a.downstreamUses == b.downstreamUses &&
            a.label.toString < b.label.toString)))

private def sortUsageItemsByAxis (items : Array UsageItem) (axisUses : UsageItem → Nat) : Array UsageItem :=
  items.qsort fun a b =>
    axisUses a > axisUses b ||
      (axisUses a == axisUses b &&
        (a.downstreamUses > b.downstreamUses ||
          (a.downstreamUses == b.downstreamUses &&
            (a.directUses > b.directUses ||
              (a.directUses == b.directUses &&
                a.label.toString < b.label.toString)))))

private def sortDependencyLoadItems (items : Array DependencyLoadItem) : Array DependencyLoadItem :=
  items.qsort fun a b =>
    a.totalDeps > b.totalDeps ||
      (a.totalDeps == b.totalDeps &&
        (a.proofDeps > b.proofDeps ||
          (a.proofDeps == b.proofDeps &&
            (a.statementDeps > b.statementDeps ||
              (a.statementDeps == b.statementDeps &&
                a.label.toString < b.label.toString)))))

private def sortDebtHotspotItems (items : Array DebtHotspotItem) : Array DebtHotspotItem :=
  items.qsort fun a b =>
    a.totalDebt > b.totalDebt ||
      (a.totalDebt == b.totalDebt &&
        (a.affectedEntries > b.affectedEntries ||
          (a.affectedEntries == b.affectedEntries &&
            a.header < b.header)))

private def sortGroupHealthItems (items : Array GroupHealthItem) : Array GroupHealthItem :=
  items.qsort fun a b =>
    a.readyEntries > b.readyEntries ||
      (a.readyEntries == b.readyEntries &&
        (a.unlockScore > b.unlockScore ||
          (a.unlockScore == b.unlockScore &&
            (a.totalEntries > b.totalEntries ||
              (a.totalEntries == b.totalEntries &&
                a.header < b.header)))))

private def sortOwnerRollupItems (items : Array OwnerRollupItem) : Array OwnerRollupItem :=
  items.qsort fun a b =>
    a.actionableEntries > b.actionableEntries ||
      (a.actionableEntries == b.actionableEntries &&
        (a.quickWins > b.quickWins ||
          (a.quickWins == b.quickWins &&
            (a.totalEntries > b.totalEntries ||
              (a.totalEntries == b.totalEntries &&
                a.displayName < b.displayName)))))

private def sortTagRollupItems (items : Array TagRollupItem) : Array TagRollupItem :=
  items.qsort fun a b =>
    a.actionableEntries > b.actionableEntries ||
      (a.actionableEntries == b.actionableEntries &&
        (a.quickWins > b.quickWins ||
          (a.quickWins == b.quickWins &&
            (a.totalEntries > b.totalEntries ||
              (a.totalEntries == b.totalEntries &&
                a.tag < b.tag)))))

private def sortMetadataEntryItems (items : Array MetadataEntryItem) : Array MetadataEntryItem :=
  items.qsort fun a b =>
    a.label.toString < b.label.toString

private def triageVisibleLimit : Nat := 10

private def bumpEntryStatus (acc : EntryStatusCounts) (flags : EntryStatusFlags) : EntryStatusCounts :=
  {
    completed := acc.completed + (if flags.completed then 1 else 0)
    completedDepsNo := acc.completedDepsNo + (if flags.completedDepsNo then 1 else 0)
    withSorries := acc.withSorries + (if flags.withSorries then 1 else 0)
    noProof := acc.noProof + (if flags.noProof then 1 else 0)
  }

private def entryStatusFlags (state : Environment.State)
    (external : Informal.Graph.ExternalCodeStatus) (node : Data.Node) : EntryStatusFlags :=
  let health := Informal.Graph.nodeCodeHealth external node
  let localFormalized := health.localFormalized node.kind
  let ancestorsFormalized := Informal.Graph.nodeAncestorsFormalized external state node
  let withSorries := health.hasAssociatedCode && health.hasAnyGaps
  let noProof := node.kind.isTheoremLike && !health.hasAssociatedCode
  {
    completed := localFormalized && ancestorsFormalized
    completedDepsNo := localFormalized && !ancestorsFormalized
    withSorries
    noProof
    hasAxiomLike := health.hasAxiomLike
  }

private def statusCountsText (counts : EntryStatusCounts) : String :=
  s!"completed: {counts.completed}; deps incomplete: {counts.completedDepsNo}; sorries: {counts.withSorries}; no proof: {counts.noProof}"

private def countSorries (decls : Array α) (statusOf : α → Data.ProvedStatus) : Nat :=
  decls.foldl (init := 0) fun acc decl =>
    let status := statusOf decl
    acc + (if status.isIncomplete then 1 else 0)

private def collectSorries (label : Name) (kind : String) (decls : Array α)
    (nameOf : α → Name) (statusOf : α → Data.ProvedStatus) (isTheorem : α → Bool) :
    List SorryItem :=
  decls.foldl (init := []) fun acc decl =>
    let status := statusOf decl
    if status.isIncomplete then
      {
        label
        kind
        decl := nameOf decl
        isTheorem := isTheorem decl
        status
      } :: acc
    else
      acc

private def mkIndexItem (label : Name) (kind : Data.NodeKind) (leanObjects : List Name := []) : IndexItem :=
  { label, kind := toString kind, leanObjects }

private def nodeLeanObjects (node : Data.Node) : List Name :=
  match node.code with
  | some (.external decls) => (decls.map (·.canonical)).toList
  | some (.literate code) => (code.definedDefs.map (·.name) ++ code.definedTheorems.map (·.name)).toList
  | _ => []

private def nodeMissingLeanDeclCount (external : Informal.Graph.ExternalCodeStatus) (node : Data.Node) : Nat :=
  (Informal.Graph.nodeExternalDecls node).foldl (init := 0) fun acc decl =>
    acc + (if Informal.Graph.externalDeclMissing external decl then 1 else 0)

private def nodeIncompleteLeanDeclCount (external : Informal.Graph.ExternalCodeStatus) (node : Data.Node) : Nat :=
  match node.code with
  | some (.external decls) =>
    decls.foldl (init := 0) fun acc decl =>
      if Informal.Graph.externalDeclMissing external decl then
        acc
      else
        acc + (if decl.provedStatus.isIncomplete then 1 else 0)
  | some (.literate code) =>
      countSorries code.definedDefs (fun (d : Data.LiterateDef) => d.provedStatus) +
      countSorries code.definedTheorems (fun (d : Data.LiterateThm) => d.provedStatus)
  | _ => 0

private def ownerDisplayName (state : Environment.State) (node : Data.Node) : Option String :=
  match node.owner with
  | some owner =>
    match state.authors.get? owner with
    | some info => some info.displayName
    | none => some owner.toString
  | none => none

private def metadataEntryItem (state : Environment.State) (label : Name) (node : Data.Node) : MetadataEntryItem :=
  {
    label
    kind := toString node.kind
    ownerDisplayName := ownerDisplayName state node
    effort := node.effort
    priority := node.priority
    prUrl := node.prUrl
    tags := node.tags.toList
    leanObjects := nodeLeanObjects node
  }

private def priorityItem? (state : Environment.State) (external : Informal.Graph.ExternalCodeStatus)
    (usageMap : NameMap UsageCounts) (reverseMap : NameMap (Array Name))
    (label : Name) (node : Data.Node) : Option PriorityItem :=
  let statementStatus := Informal.Graph.statementStatus external state label node
  let proofStatus := Informal.Graph.proofStatus external state label node
  let localFormalized := Informal.Graph.nodeLocalFormalized external node
  match actionableStage? node statementStatus proofStatus with
  | Option.none => Option.none
  | Option.some stage =>
    if localFormalized then
      Option.none
    else
      let usage := usageMap.getD label {}
      let downstreamUses := downstreamUseCount reverseMap (reverseMap.getD label #[]).toList
      if downstreamUses == 0 then
        Option.none
      else
        Option.some {
          label
          kind := toString node.kind
          stage
          priority := node.priority
          ownerDisplayName := ownerDisplayName state node
          effort := node.effort
          prUrl := node.prUrl
          tags := node.tags.toList
          statementStatus := Informal.Graph.StatementStatus.toText statementStatus
          proofStatus := if node.kind.isTheoremLike then Informal.Graph.ProofStatus.toText proofStatus else ""
          directUses := usage.directUses
          downstreamUses
          leanObjects := nodeLeanObjects node
        }

private def metadataPresentationOfPriorityItem (item : PriorityItem) : MetadataPresentation := {
  ownerText := item.ownerDisplayName
  effort := item.effort
  priority := item.priority
  prUrl := item.prUrl
  tags := item.tags.toArray
}

private def metadataPresentationOfMetadataEntryItem (item : MetadataEntryItem) : MetadataPresentation := {
  ownerText := item.ownerDisplayName
  effort := item.effort
  priority := item.priority
  prUrl := item.prUrl
  tags := item.tags.toArray
}

private def addParentTheoremLikeItem (groups : NameMap (List IndexItem)) (parent : Name) (item : IndexItem) :
    NameMap (List IndexItem) :=
  groups.insert parent (item :: groups.getD parent [])

def buildSummary : CoreM Summary := do
  reportImportedConflicts
  let showDebugDiagnostics :=
    (← getOptions).get
      verso.blueprint.summary.debugDiagnostics.name
      verso.blueprint.summary.debugDiagnostics.defValue
  let env ← getEnv
  let state := informalExt.getState env
  let entries := state.data.toArray
  let parentChildren := state.data.parentChildren
  let groupHeaders := state.groups
  let external : Informal.Graph.ExternalCodeStatus := {}
  let (usageMap, reverseMap) := buildUsageMaps entries
  let summary := entries.foldl (init := ({} : Summary)) fun acc (label, node) =>
      let hasStatement := node.statement.isSome
      let hasProof := node.proof.isSome
      let hasCode := node.code.isSome
      let statusFlags := entryStatusFlags state external node
      let (leanDecls, sorries, leanObjects, sorryDetails, missingLeanDecls, renderFailures) :=
        match node.code with
        | none => (0, 0, ([] : List Name), ([] : List SorryItem), ([] : List MissingLeanDeclItem), ([] : List RenderFailureItem))
        | some (.external decls) =>
          let leanObjects := nodeLeanObjects node
          let missingDecls :=
            decls.foldl (init := []) fun acc decl =>
              if !decl.present then
                {
                  label
                  kind := toString node.kind
                  written := decl.written
                  canonical := decl.canonical
                } :: acc
              else
                acc
          let incompleteDecls :=
            decls.foldl (init := #[]) fun acc decl =>
              if !decl.present then
                acc
              else
                let status := decl.provedStatus
                if status.isIncomplete then
                  acc.push (decl.canonical, status)
                else
                  acc
          let sorryDetails :=
            incompleteDecls.toList.map fun (decl, status) =>
              {
                label
                kind := toString node.kind
                decl
                isTheorem :=
                  (decls.find? (fun d => d.canonical == decl)).map (·.kind.isTheoremLike) |>.getD false
                status
              }
          let renderFailures :=
            (externalRenderFailures decls).toList.map fun failure =>
              {
                label
                kind := toString node.kind
                written := failure.decl.written
                canonical := failure.decl.canonical
                message := failure.message
              }
          (decls.size, incompleteDecls.size, leanObjects, sorryDetails, missingDecls, renderFailures)
        | some (.literate code) =>
          let kind := toString node.kind
          let leanObjects := nodeLeanObjects node
          let leanDecls := code.definedDefs.size + code.definedTheorems.size
          let sorries :=
            countSorries code.definedDefs (fun (d : Data.LiterateDef) => d.provedStatus) +
            countSorries code.definedTheorems (fun (d : Data.LiterateThm) => d.provedStatus)
          let sorryDetails :=
            collectSorries label kind code.definedDefs
              (fun (d : Data.LiterateDef) => d.name)
              (fun (d : Data.LiterateDef) => d.provedStatus)
              (fun _ => false) ++
            collectSorries label kind code.definedTheorems
              (fun (d : Data.LiterateThm) => d.name)
              (fun (d : Data.LiterateThm) => d.provedStatus)
              (fun _ => true)
          (leanDecls, sorries, leanObjects, sorryDetails, ([] : List MissingLeanDeclItem), ([] : List RenderFailureItem))
      let pendingInformalEntries : List PendingInformalItem :=
        if hasCode && ((node.kind.isTheoremLike && !hasProof) || !hasStatement) then
          mkIndexItem label node.kind leanObjects :: acc.pendingInformalEntries
        else
          acc.pendingInformalEntries
      let definitionIndex : List IndexItem :=
        if node.kind == Data.NodeKind.definition then
          mkIndexItem label node.kind leanObjects :: acc.definitionIndex
        else
          acc.definitionIndex
      let theoremLikeIndex : List IndexItem :=
        if node.kind.isTheoremLike then
          mkIndexItem label node.kind leanObjects :: acc.theoremLikeIndex
        else
          acc.theoremLikeIndex
      let axiomIndex : List IndexItem :=
        if statusFlags.hasAxiomLike then
          mkIndexItem label node.kind leanObjects :: acc.axiomIndex
        else
          acc.axiomIndex
      let acc := { acc with
        totalEntries := acc.totalEntries + 1
        leanOnlyEntries := acc.leanOnlyEntries + (if hasCode && !hasStatement then 1 else 0)
        informalOnlyEntries := acc.informalOnlyEntries + (if hasStatement && !hasCode then 1 else 0)
        totalStatus := bumpEntryStatus acc.totalStatus statusFlags
        pendingInformalEntries
        leanDecls := acc.leanDecls + leanDecls
        sorries := acc.sorries + sorries
        sorryDetails := sorryDetails ++ acc.sorryDetails
        missingLeanDecls := missingLeanDecls ++ acc.missingLeanDecls
        renderFailures := renderFailures ++ acc.renderFailures
        definitionIndex
        theoremLikeIndex
        axiomIndex
      }
      let acc :=
        match node.kind with
        | Data.NodeKind.definition =>
          { acc with
            definitions := acc.definitions + 1
            definitionStatus := bumpEntryStatus acc.definitionStatus statusFlags
          }
        | Data.NodeKind.lemma =>
          { acc with
            lemmas := acc.lemmas + 1
            lemmaStatus := bumpEntryStatus acc.lemmaStatus statusFlags
          }
        | Data.NodeKind.theorem =>
          { acc with
            theorems := acc.theorems + 1
            theoremStatus := bumpEntryStatus acc.theoremStatus statusFlags
          }
        | Data.NodeKind.corollary =>
          { acc with
            corollaries := acc.corollaries + 1
            corollaryStatus := bumpEntryStatus acc.corollaryStatus statusFlags
          }
      if statusFlags.hasAxiomLike then
        { acc with
          axioms := acc.axioms + 1
          axiomStatus := bumpEntryStatus acc.axiomStatus statusFlags
        }
      else
        acc
  let theoremLikeByParent : List ParentTheoremGroup :=
    let grouped := entries.foldl (init := ({} : NameMap (List IndexItem))) fun acc (label, node) =>
      if node.kind.isTheoremLike then
        let leanObjects := nodeLeanObjects node
        match node.parent with
        | some parent =>
          let item : IndexItem := mkIndexItem label node.kind leanObjects
          addParentTheoremLikeItem acc parent item
        | none => acc
      else
        acc
    grouped.toArray.toList.foldr (init := []) fun (parent, items) acc =>
      if (parentChildren.getD parent #[]).size <= 1 then
        acc
      else
        let header := groupHeaders.getD parent parent.toString
        { parent, header, entries := items.reverse } :: acc
  let topPriorities : List PriorityItem :=
    let items := entries.foldl (init := #[]) fun acc (label, node) =>
      match priorityItem? state external usageMap reverseMap label node with
      | none => acc
      | some item => acc.push item
    (sortPriorityItems items).toList
  let mostUsed : List UsageItem :=
    let items := entries.foldl (init := #[]) fun acc (label, node) =>
      let usage := usageMap.getD label {}
      if usage.directUses == 0 then
        acc
      else
        let downstreamUses := downstreamUseCount reverseMap (reverseMap.getD label #[]).toList
        acc.push {
          label
          kind := toString node.kind
          statementUses := usage.statementUses
          proofUses := usage.proofUses
          directUses := usage.directUses
          downstreamUses
          leanObjects := nodeLeanObjects node
        }
    (sortUsageItems items).toList
  let groupHealth : List GroupHealthItem :=
    let items := parentChildren.toArray.foldl (init := #[]) fun acc (parent, children) =>
      if children.size <= 1 then
        acc
      else
        let childEntries := children.foldl (init := #[]) fun acc child =>
          match state.data.get? child with
          | some node => acc.push (child, node)
          | none => acc
        let (totalEntries, closedEntries, localOnlyEntries, readyEntries, blockedEntries, incompleteLeanEntries, unlockScore) :=
          childEntries.foldl (init := (0, 0, 0, 0, 0, 0, 0)) fun (totalEntries, closedEntries, localOnlyEntries, readyEntries, blockedEntries, incompleteLeanEntries, unlockScore) (child, node) =>
            let statusFlags := entryStatusFlags state external node
            let statementStatus := Informal.Graph.statementStatus external state child node
            let proofStatus := Informal.Graph.proofStatus external state child node
            let readyNow :=
              !Informal.Graph.nodeLocalFormalized external node &&
                (actionableStage? node statementStatus proofStatus).isSome
            let blockedNow := !statusFlags.completed && !statusFlags.completedDepsNo && !readyNow
            let incompleteLeanNow :=
              Informal.Graph.nodeHasAssociatedCode node &&
                (Informal.Graph.nodeHasSorries external node || Informal.Graph.nodeHasMissingExternalDecls external node)
            let unlockScore := unlockScore + downstreamUseCount reverseMap (reverseMap.getD child #[]).toList
            (
              totalEntries + 1,
              closedEntries + (if statusFlags.completed then 1 else 0),
              localOnlyEntries + (if statusFlags.completedDepsNo then 1 else 0),
              readyEntries + (if readyNow then 1 else 0),
              blockedEntries + (if blockedNow then 1 else 0),
              incompleteLeanEntries + (if incompleteLeanNow then 1 else 0),
              unlockScore
            )
        let nextPriority? :=
          let candidates := childEntries.foldl (init := #[]) fun acc (child, node) =>
            match priorityItem? state external usageMap reverseMap child node with
            | none => acc
            | some item => acc.push item
          let sorted := sortPriorityItems candidates
          if h : 0 < sorted.size then
            some sorted[0]
          else
            none
        acc.push {
          parent
          header := groupHeaders.getD parent parent.toString
          totalEntries
          closedEntries
          localOnlyEntries
          readyEntries
          blockedEntries
          incompleteLeanEntries
          unlockScore
          nextPriority?
        }
    (sortGroupHealthItems items).toList
  let coverageSplit :=
    entries.foldl (init := ({} : CoverageSplit)) fun acc (label, node) =>
      let hasStatement := node.statement.isSome
      let hasCode := node.code.isSome
      let statusFlags := entryStatusFlags state external node
      let statementStatus := Informal.Graph.statementStatus external state label node
      let proofStatus := Informal.Graph.proofStatus external state label node
      if hasStatement && !hasCode then
        { acc with informalOnly := acc.informalOnly + 1 }
      else if statusFlags.completed then
        { acc with fullyClosed := acc.fullyClosed + 1 }
      else if statusFlags.completedDepsNo then
        { acc with formalizedWithoutAncestors := acc.formalizedWithoutAncestors + 1 }
      else if (actionableStage? node statementStatus proofStatus).isSome then
        { acc with readyToFormalize := acc.readyToFormalize + 1 }
      else
        { acc with blockedOrIncomplete := acc.blockedOrIncomplete + 1 }
  let heaviestPrerequisites : List DependencyLoadItem :=
    let items := entries.foldl (init := #[]) fun acc (label, node) =>
      let statementDeps := Informal.Graph.eraseDups (Informal.Graph.statementDeps node)
      let proofDeps := Informal.Graph.eraseDups (Informal.Graph.proofDeps node)
      let totalDeps := (Informal.Graph.eraseDups (statementDeps ++ proofDeps)).size
      if totalDeps == 0 then
        acc
      else
        let usage := usageMap.getD label {}
        let downstreamUses := downstreamUseCount reverseMap (reverseMap.getD label #[]).toList
        acc.push {
          label
          kind := toString node.kind
          statementDeps := statementDeps.size
          proofDeps := proofDeps.size
          totalDeps
          directUses := usage.directUses
          downstreamUses
          leanObjects := nodeLeanObjects node
        }
    (sortDependencyLoadItems items).toList
  let noPrerequisites : List IndexItem :=
    entries.foldl (init := []) fun acc (label, node) =>
      let totalDeps := (Informal.Graph.eraseDups (Informal.Graph.allDeps node)).size
      if totalDeps == 0 then
        mkIndexItem label node.kind (nodeLeanObjects node) :: acc
      else
        acc
    |>.reverse
  let noDependents : List IndexItem :=
    entries.foldl (init := []) fun acc (label, node) =>
      let usage := usageMap.getD label {}
      if usage.directUses == 0 then
        mkIndexItem label node.kind (nodeLeanObjects node) :: acc
      else
        acc
    |>.reverse
  let proofDebtHotspots : List DebtHotspotItem :=
    let items := parentChildren.toArray.foldl (init := #[]) fun acc (parent, children) =>
      let (affectedEntries, incompleteDecls, missingDecls) :=
        children.foldl (init := (0, 0, 0)) fun (affectedEntries, incompleteDecls, missingDecls) child =>
          match state.data.get? child with
          | none => (affectedEntries, incompleteDecls, missingDecls)
          | some node =>
            let incompleteDeclCount := nodeIncompleteLeanDeclCount external node
            let missingDeclCount := nodeMissingLeanDeclCount external node
            let hasDebt := incompleteDeclCount > 0 || missingDeclCount > 0
            (
              affectedEntries + (if hasDebt then 1 else 0),
              incompleteDecls + incompleteDeclCount,
              missingDecls + missingDeclCount
            )
      let totalDebt := incompleteDecls + missingDecls
      if totalDebt == 0 then
        acc
      else
        acc.push {
          parent
          header := groupHeaders.getD parent parent.toString
          affectedEntries
          incompleteDecls
          missingDecls
          totalDebt
        }
    (sortDebtHotspotItems items).toList
  let quickWins : List PriorityItem :=
    topPriorities.filter fun item => item.priority == some "high" && item.effort == some "small"
  let ownerRollups : List OwnerRollupItem :=
    let rollups := entries.foldl (init := ({} : NameMap OwnerRollupItem)) fun acc (label, node) =>
      match node.owner with
      | none => acc
      | some owner =>
        let actionable := (priorityItem? state external usageMap reverseMap label node).isSome
        let quickWin := actionable && node.priority == some "high" && node.effort == some "small"
        let linkedPr := node.prUrl.isSome
        let displayName := (ownerDisplayName state node).getD owner.toString
        let cur := acc.getD owner { owner, displayName }
        acc.insert owner {
          cur with
            totalEntries := cur.totalEntries + 1
            actionableEntries := cur.actionableEntries + (if actionable then 1 else 0)
            quickWins := cur.quickWins + (if quickWin then 1 else 0)
            linkedPrs := cur.linkedPrs + (if linkedPr then 1 else 0)
        }
    (sortOwnerRollupItems (rollups.toArray.map fun pair => pair.2)).toList
  let tagRollups : List TagRollupItem :=
    let rollups := entries.foldl (init := ({} : Std.HashMap String TagRollupItem)) fun acc (label, node) =>
      let actionable := (priorityItem? state external usageMap reverseMap label node).isSome
      let quickWin := actionable && node.priority == some "high" && node.effort == some "small"
      let linkedPr := node.prUrl.isSome
      node.tags.foldl (init := acc) fun acc tag =>
        let cur := acc.getD tag { tag }
        acc.insert tag {
          cur with
            totalEntries := cur.totalEntries + 1
            actionableEntries := cur.actionableEntries + (if actionable then 1 else 0)
            quickWins := cur.quickWins + (if quickWin then 1 else 0)
            linkedPrs := cur.linkedPrs + (if linkedPr then 1 else 0)
        }
    (sortTagRollupItems (rollups.toArray.map fun pair => pair.2)).toList
  let linkedPrs : List MetadataEntryItem :=
    let items := entries.foldl (init := #[]) fun acc (label, node) =>
      if node.prUrl.isSome then
        acc.push (metadataEntryItem state label node)
      else
        acc
    (sortMetadataEntryItems items).toList
  let missingOwners : List MetadataEntryItem :=
    let items := entries.foldl (init := #[]) fun acc (label, node) =>
      if node.owner.isNone then
        acc.push (metadataEntryItem state label node)
      else
        acc
    (sortMetadataEntryItems items).toList
  let missingEffort : List MetadataEntryItem :=
    let items := entries.foldl (init := #[]) fun acc (label, node) =>
      if node.effort.isNone then
        acc.push (metadataEntryItem state label node)
      else
        acc
    (sortMetadataEntryItems items).toList
  let untaggedEntries : List MetadataEntryItem :=
    let items := entries.foldl (init := #[]) fun acc (label, node) =>
      if node.tags.isEmpty then
        acc.push (metadataEntryItem state label node)
      else
        acc
    (sortMetadataEntryItems items).toList
  return {
    summary with
      showDebugDiagnostics,
      theoremLikeByParent,
      topPriorities,
      mostUsed,
      groupHealth,
      coverageSplit,
      heaviestPrerequisites,
      noPrerequisites,
      noDependents,
      proofDebtHotspots,
      quickWins,
      ownerRollups,
      tagRollups,
      linkedPrs,
      missingOwners,
      missingEffort,
      untaggedEntries
  }

private def Summary.previewLabels (data : Summary) : Array Name :=
  let allLabels : List Name :=
    data.pendingInformalEntries.map (·.label) ++
    data.sorryDetails.map (·.label) ++
    data.missingLeanDecls.map (·.label) ++
    data.renderFailures.map (·.label) ++
    data.definitionIndex.map (·.label) ++
    data.theoremLikeIndex.map (·.label) ++
    data.topPriorities.map (·.label) ++
    data.quickWins.map (·.label) ++
    data.mostUsed.map (·.label) ++
    data.heaviestPrerequisites.map (·.label) ++
    data.noPrerequisites.map (·.label) ++
    data.noDependents.map (·.label) ++
    data.linkedPrs.map (·.label) ++
    data.missingOwners.map (·.label) ++
    data.missingEffort.map (·.label) ++
    data.untaggedEntries.map (·.label) ++
    data.theoremLikeByParent.foldr (init := []) fun group acc =>
      group.entries.map (·.label) ++ acc
  let (_, labels) := allLabels.foldl (init := (({} : NameSet), (#[] : Array Name))) fun (seen, labels) label =>
    if seen.contains label then
      (seen, labels)
    else
      (seen.insert label, labels.push label)
  labels

-- Keep this binding in Lean so summary CSS edits ride along with command module rebuilds.
def summaryCss := include_str "summary.css"

def summaryPreviewJs : String := r##"(function () {
  function bindSummaryPreview(root) {
    if (!(root instanceof Element)) return;
    if (root.getAttribute("data-bp-summary-preview-bound") === "1") return;
    root.setAttribute("data-bp-summary-preview-bound", "1");

    const previewUtils = window.bpPreviewUtils;
    const panel = root.querySelector(".bp_summary_preview_panel");
    if (!panel || !previewUtils || typeof previewUtils.bindTemplatePreview !== "function") return;
    previewUtils.bindTemplatePreview({
      root: root,
      previewRoot: root,
      triggerRoot: root,
      panel: panel,
      allowSharedManifest: true,
      templateSelector: "template.bp_summary_preview_tpl[data-bp-preview-label]",
      triggerSelector: ".bp_summary_preview_wrap_active[data-bp-preview-label]",
      titleSelector: ".bp_summary_preview_panel_title",
      bodySelector: ".bp_summary_preview_panel_body",
      closeSelector: ".bp_summary_preview_panel_close",
      defaults: { mode: "hover", placement: "anchored" },
      readTitle: function (_wrap, label) { return label; }
    });
  }

  function init() {
    document.querySelectorAll(".bp_summary").forEach(bindSummaryPreview);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();"##

open Verso Doc Elab Genre Manual in
block_extension Block.summary (summary : Summary) where
  data := toJson summary
  traverse _id _data _contents := do
    return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB _id data _blocks => do
      let .ok data := fromJson? (α := Summary) data
        | HtmlT.logError "Malformed data in Block.summary.toHtml"
          pure .empty
      let s ← HtmlT.state
      let getEntryHref (label : Name) : Option String :=
        Informal.TraversalIndex.Nodes.href? s label
      let getDeclHref (label : Name) (decl : Name) : Option String :=
        match Resolve.resolveRenderedExternalDeclHref? s label decl with
        | Option.some href => Option.some href
        | Option.none => Resolve.resolveInlineLeanDeclHref? s decl
      let renderLeanDeclLink (target : Name) (node : Output.Html)
          (href? : Option String) (linkTitle? : Option String := Option.none) : Output.Html :=
        match href? with
        | some href =>
          Informal.LeanCodeLink.renderResolved
            target node "" (some href) linkTitle?
            (previewTitle := Informal.LeanCodePreview.title target)
        | Option.none => node
      let previewLookupKeys := (data.previewLabels).foldl (init := ({} : Lean.NameMap String)) fun keys label =>
        match Informal.PreviewSource.traversalLookupKey? s label with
        | some key => keys.insert label key
        | Option.none => keys
      let previewUi := Informal.HoverRender.summaryPreviewUi
      let mkEntryRef (label : Name) := do
        let previewLookupKey? := previewLookupKeys.get? label
        let previewLabel? : Option Name := previewLookupKey?.map (fun _ => label)
        let labelNode : Output.Html :=
          match getEntryHref label with
          | Option.some href => {{ <a href={{href}}> <code>s!"{label}"</code> </a> }}
          | Option.none => {{ <code>s!"{label}"</code> }}
        pure (Informal.HoverRender.summaryPreviewWrap labelNode previewLabel? previewLookupKey?)
      let mkDeclItems (label : Name) (decls : List Name) :=
        decls.toArray.map fun decl =>
          let declNode := renderLeanDeclLink decl {{<code>s!"{decl}"</code>}} (getDeclHref label decl)
          {{ <li>{{declNode}}</li> }}
      let mkBadge (text : String) (className : String := "bp_summary_badge") : Output.Html :=
        {{ <span class={{className}}>s!"{text}"</span> }}
      let mkBadgeRow (badges : Array Output.Html) : Output.Html :=
        if badges.isEmpty then
          .empty
        else
          {{ <div class="bp_summary_badge_row">{{badges}}</div> }}
      let mkMetadataBadges (metadata : MetadataPresentation) : Array Output.Html :=
        metadata.summaryBadgeSpecs.map fun badge =>
          mkBadge badge.text <|
            if badge.warning then
              "bp_summary_badge bp_summary_badge_warn"
            else
              "bp_summary_badge"
      let mkMetadataActionLinks (metadata : MetadataPresentation) : Array Output.Html :=
        metadata.summaryActionLinks.map fun action =>
          {{ <a class="bp_code_link" href={{action.href}}>{{.text true action.label}}</a> }}
      let capRows (rows : Array Output.Html) (noun : String) : Array Output.Html :=
        let visible := (rows.toList.take triageVisibleLimit).toArray
        let hidden := (rows.toList.drop triageVisibleLimit).toArray
        if hidden.isEmpty then
          visible
        else
          visible.push {{
            <li class="bp_summary_item bp_summary_item_nested">
              <details class="bp_summary_nested">
                <summary>s!"Show all {hidden.size} more {noun}"</summary>
                <ul class="bp_summary_list">
                  {{hidden}}
                </ul>
              </details>
            </li>
          }}
      let mkLeanRow (label : Name) (kind : String) (leanObjects : List Name) := do
        let entryRef ← mkEntryRef label
        let associatedDecls := !leanObjects.isEmpty
        pure {{ <li class="bp_summary_item">
                  <div class="bp_summary_item_top">
                    <span class="bp_summary_item_head">{{entryRef}}</span>
                    <span class="bp_summary_item_meta">s!"({kind})"</span>
                  </div>
                  {{if associatedDecls then
                     {{<details class="bp_summary_decls"><summary>s!"Associated lean decls ({leanObjects.length})"</summary><ul class="bp_summary_decl_list">{{mkDeclItems label leanObjects}}</ul></details>}}
                    else
                     .empty}}
                </li> }}
      let pendingInformalRows ←
        data.pendingInformalEntries.toArray.mapM fun item =>
          mkLeanRow item.label item.kind item.leanObjects
      let sorryRows ←
        data.sorryDetails.toArray.mapM fun item => do
          let entryRef ← mkEntryRef item.label
          let declLink :=
            renderLeanDeclLink item.decl {{<code>s!"{item.decl}"</code>}} (getDeclHref item.label item.decl)
          let statusInfo ←
            match item.status with
            | .missing =>
              pure ("missing", "Missing declaration: ", "bp_summary_badge bp_summary_badge_error",
                item.status.sorryLocationText, "n/a")
            | .axiomLike =>
              pure ("axiom-like", "Axiom-like declaration: ", "bp_summary_badge bp_summary_badge_warn",
                item.status.sorryLocationText, "n/a")
            | .containsSorry _ =>
              let (typeSorryRefs, proofSorryRefs) := item.status.sorryRefCounts
              let sorryRefs := typeSorryRefs + proofSorryRefs
              let refsTxt := if sorryRefs > 0 then toString sorryRefs else "unknown"
              pure ("contains sorry", "Declaration with sorry: ", "bp_summary_badge bp_summary_badge_warn",
                item.status.sorryLocationText, refsTxt)
            | .proved =>
              HtmlT.logError s!"Unexpected proved status in summary sorry details for {item.decl}"
              pure ("proved", "Declaration: ", "bp_summary_badge", "proved", "0")
          let (statusLabel, declPrefix, badgeClass, whereTxt, refsTxt) := statusInfo
          pure {{ <li class="bp_summary_item">
                    <div class="bp_summary_item_top">
                      <span class="bp_summary_item_head">{{entryRef}}</span>
                      <span class="bp_summary_item_meta">s!"({item.kind})"</span>
                    </div>
                    <div class="bp_summary_item_body">
                      {{.text true declPrefix}} {{declLink}} " "
                      <span class={{badgeClass}}>
                        s!"[{if item.isTheorem then "theorem/lemma" else "definition"}; {statusLabel}; {whereTxt}; refs: {refsTxt}]"
                      </span>
                    </div>
                  </li> }}
      let missingRows ←
        data.missingLeanDecls.toArray.mapM fun item => do
          let entryRef ← mkEntryRef item.label
          let canonicalNode : Output.Html :=
            renderLeanDeclLink
              item.canonical
              {{<code>s!"{item.canonical}"</code>}}
              (getDeclHref item.label item.canonical)
          let declNode : Output.Html :=
            if item.written == item.canonical then
              canonicalNode
            else
              {{ <span> <code>s!"{item.written}"</code> " (resolved as " {{canonicalNode}} ")" </span> }}
          pure {{ <li class="bp_summary_item">
                    <div class="bp_summary_item_top">
                      <span class="bp_summary_item_head">{{entryRef}}</span>
                      <span class="bp_summary_item_meta">s!"({item.kind})"</span>
                    </div>
                    <div class="bp_summary_item_body">
                      "Missing external Lean declaration: " {{declNode}} " "
                      <span class="bp_summary_badge bp_summary_badge_error">"[missing declaration]"</span>
                    </div>
                  </li> }}
      let renderFailureRows ←
        data.renderFailures.toArray.mapM fun item => do
          let entryRef ← mkEntryRef item.label
          let canonicalNode : Output.Html :=
            renderLeanDeclLink
              item.canonical
              {{<code>s!"{item.canonical}"</code>}}
              (getDeclHref item.label item.canonical)
          let declNode : Output.Html :=
            if item.written == item.canonical then
              canonicalNode
            else
              {{ <span> <code>s!"{item.written}"</code> " (resolved as " {{canonicalNode}} ")" </span> }}
          pure {{ <li class="bp_summary_item">
                    <div class="bp_summary_item_top">
                      <span class="bp_summary_item_head">{{entryRef}}</span>
                      <span class="bp_summary_item_meta">s!"({item.kind})"</span>
                    </div>
                    <div class="bp_summary_item_body">
                      "External render failed for " {{declNode}} " "
                      <span class="bp_summary_badge bp_summary_badge_warn">"[render failure]"</span>
                    </div>
                    <div class="bp_summary_item_actions"><code>{{.text true item.message}}</code></div>
                  </li> }}
      let mkPriorityRow (item : PriorityItem) := do
        let entryRef ← mkEntryRef item.label
        let associatedDecls := !item.leanObjects.isEmpty
        let metadata := metadataPresentationOfPriorityItem item
        let metadataBadges := mkMetadataBadges metadata
        let proofBadges : Array Output.Html :=
          if item.proofStatus.isEmpty then
            #[]
          else
            #[mkBadge s!"proof: {item.proofStatus}"]
        let actionLinks := mkMetadataActionLinks metadata
        let badges :=
          metadataBadges ++ #[
            mkBadge s!"stage: {item.stage}",
            mkBadge s!"statement: {item.statementStatus}",
            mkBadge s!"direct uses: {item.directUses}",
            mkBadge s!"downstream unlocks: {item.downstreamUses}"
          ] ++ proofBadges
        pure {{
          <li class="bp_summary_item">
            <div class="bp_summary_item_top">
              <span class="bp_summary_item_head">{{entryRef}}</span>
              <span class="bp_summary_item_meta">s!"({item.kind})"</span>
            </div>
            <div class="bp_summary_item_body">s!"Ready for {item.stage} work."</div>
            {{mkBadgeRow badges}}
            {{if associatedDecls then
               {{<details class="bp_summary_decls"><summary>s!"Associated lean decls ({item.leanObjects.length})"</summary><ul class="bp_summary_decl_list">{{mkDeclItems item.label item.leanObjects}}</ul></details>}}
              else
               .empty}}
            {{if Array.isEmpty actionLinks then
               .empty
              else
               {{<div class="bp_summary_item_actions">"Links: " {{(actionLinks.toList.intersperse {{<span class="bp_summary_sep">" | "</span>}}).toArray}}</div>}}}}
          </li>
        }}
      let topPriorityRows ←
        data.topPriorities.toArray.mapM mkPriorityRow
      let quickWinRows ←
        data.quickWins.toArray.mapM mkPriorityRow
      let statementUsedItems :=
        sortUsageItemsByAxis
          (data.mostUsed.toArray.filter fun item => item.statementUses > 0)
          (fun item => item.statementUses)
      let proofUsedItems :=
        sortUsageItemsByAxis
          (data.mostUsed.toArray.filter fun item => item.proofUses > 0)
          (fun item => item.proofUses)
      let mkUsageRow (item : UsageItem) (bodyText primaryLabel secondaryLabel : String)
          (primaryCount secondaryCount : Nat) := do
          let entryRef ← mkEntryRef item.label
          let associatedDecls := !item.leanObjects.isEmpty
          let badges :=
            #[
              mkBadge s!"{primaryLabel}: {primaryCount}" "bp_summary_badge bp_summary_badge_warn",
              mkBadge s!"{secondaryLabel}: {secondaryCount}",
              mkBadge s!"direct uses: {item.directUses}",
              mkBadge s!"downstream unlocks: {item.downstreamUses}"
            ]
          pure {{
            <li class="bp_summary_item">
              <div class="bp_summary_item_top">
                <span class="bp_summary_item_head">{{entryRef}}</span>
                <span class="bp_summary_item_meta">s!"({item.kind})"</span>
              </div>
              <div class="bp_summary_item_body">{{.text true bodyText}}</div>
              {{mkBadgeRow badges}}
              {{if associatedDecls then
                 {{<details class="bp_summary_decls"><summary>s!"Associated lean decls ({item.leanObjects.length})"</summary><ul class="bp_summary_decl_list">{{mkDeclItems item.label item.leanObjects}}</ul></details>}}
                else
                 .empty}}
            </li>
          }}
      let statementUsedRows ←
        statementUsedItems.mapM fun item =>
          mkUsageRow item
            "Reverse dependencies recorded in statement dependencies."
            "statement uses"
            "proof uses"
            item.statementUses
            item.proofUses
      let proofUsedRows ←
        proofUsedItems.mapM fun item =>
          mkUsageRow item
            "Reverse dependencies recorded in proof dependencies."
            "proof uses"
            "statement uses"
            item.proofUses
            item.statementUses
      let heaviestPrerequisiteRows ←
        data.heaviestPrerequisites.toArray.mapM fun item => do
          let entryRef ← mkEntryRef item.label
          let associatedDecls := !item.leanObjects.isEmpty
          let badges :=
            #[
              mkBadge s!"total deps: {item.totalDeps}" "bp_summary_badge bp_summary_badge_warn",
              mkBadge s!"statement deps: {item.statementDeps}",
              mkBadge s!"proof deps: {item.proofDeps}",
              mkBadge s!"direct uses: {item.directUses}",
              mkBadge s!"downstream unlocks: {item.downstreamUses}"
            ]
          pure {{
            <li class="bp_summary_item">
              <div class="bp_summary_item_top">
                <span class="bp_summary_item_head">{{entryRef}}</span>
                <span class="bp_summary_item_meta">s!"({item.kind})"</span>
              </div>
              <div class="bp_summary_item_body">"Prerequisite fan-in measured from the current statement/proof dependency graph."</div>
              {{mkBadgeRow badges}}
              {{if associatedDecls then
                 {{<details class="bp_summary_decls"><summary>s!"Associated lean decls ({item.leanObjects.length})"</summary><ul class="bp_summary_decl_list">{{mkDeclItems item.label item.leanObjects}}</ul></details>}}
                else
                 .empty}}
            </li>
          }}
      let noPrerequisiteRows ←
        data.noPrerequisites.toArray.mapM fun item =>
          mkLeanRow item.label item.kind item.leanObjects
      let noDependentRows ←
        data.noDependents.toArray.mapM fun item =>
          mkLeanRow item.label item.kind item.leanObjects
      let proofDebtHotspotRows :=
        data.proofDebtHotspots.toArray.map fun item =>
          let badges :=
            #[
              mkBadge s!"affected entries: {item.affectedEntries}" "bp_summary_badge bp_summary_badge_warn",
              mkBadge s!"incomplete decls: {item.incompleteDecls}",
              mkBadge s!"missing decls: {item.missingDecls}",
              mkBadge s!"total debt: {item.totalDebt}"
            ]
          {{
            <li class="bp_summary_item">
              <div class="bp_summary_item_top">
                <span class="bp_summary_item_head">{{.text true item.header}}</span>
                <span class="bp_summary_item_meta"><code>s!"{item.parent}"</code></span>
              </div>
              <div class="bp_summary_item_body">"Grouped proof/code debt derived from the current incomplete-declaration snapshots."</div>
              {{mkBadgeRow badges}}
            </li>
          }}
      let ownerRollupRows :=
        data.ownerRollups.toArray.map fun item =>
          let badges :=
            #[
              mkBadge s!"entries: {item.totalEntries}",
              mkBadge s!"actionable: {item.actionableEntries}" "bp_summary_badge bp_summary_badge_warn",
              mkBadge s!"quick wins: {item.quickWins}",
              mkBadge s!"linked PRs: {item.linkedPrs}"
            ]
          {{
            <li class="bp_summary_item">
              <div class="bp_summary_item_top">
                <span class="bp_summary_item_head">{{.text true item.displayName}}</span>
                <span class="bp_summary_item_meta"><code>s!"{item.owner}"</code></span>
              </div>
              {{mkBadgeRow badges}}
            </li>
          }}
      let tagRollupRows :=
        data.tagRollups.toArray.map fun item =>
          let badges :=
            #[
              mkBadge s!"entries: {item.totalEntries}",
              mkBadge s!"actionable: {item.actionableEntries}" "bp_summary_badge bp_summary_badge_warn",
              mkBadge s!"quick wins: {item.quickWins}",
              mkBadge s!"linked PRs: {item.linkedPrs}"
            ]
          {{
            <li class="bp_summary_item">
              <div class="bp_summary_item_top">
                <span class="bp_summary_item_head">{{mkBadge s!"tag: {item.tag}" "bp_summary_badge bp_summary_badge_warn"}}</span>
              </div>
              {{mkBadgeRow badges}}
            </li>
          }}
      let mkMetadataEntryRow (item : MetadataEntryItem) (bodyText : String) := do
        let entryRef ← mkEntryRef item.label
        let associatedDecls := !item.leanObjects.isEmpty
        let metadata := metadataPresentationOfMetadataEntryItem item
        let badges := mkMetadataBadges metadata
        let actionLinks := mkMetadataActionLinks metadata
        pure {{
          <li class="bp_summary_item">
            <div class="bp_summary_item_top">
              <span class="bp_summary_item_head">{{entryRef}}</span>
              <span class="bp_summary_item_meta">s!"({item.kind})"</span>
            </div>
            <div class="bp_summary_item_body">{{.text true bodyText}}</div>
            {{mkBadgeRow badges}}
            {{if associatedDecls then
               {{<details class="bp_summary_decls"><summary>s!"Associated lean decls ({item.leanObjects.length})"</summary><ul class="bp_summary_decl_list">{{mkDeclItems item.label item.leanObjects}}</ul></details>}}
              else
               .empty}}
            {{if Array.isEmpty actionLinks then
               .empty
              else
               {{<div class="bp_summary_item_actions">"Links: " {{(actionLinks.toList.intersperse {{<span class="bp_summary_sep">" | "</span>}}).toArray}}</div>}}}}
          </li>
        }}
      let linkedPrRows ←
        data.linkedPrs.toArray.mapM fun item =>
          mkMetadataEntryRow item "Entry already linked to a review PR."
      let missingOwnerRows ←
        data.missingOwners.toArray.mapM fun item =>
          mkMetadataEntryRow item "Missing owner metadata."
      let missingEffortRows ←
        data.missingEffort.toArray.mapM fun item =>
          mkMetadataEntryRow item "Missing effort metadata."
      let untaggedRows ←
        data.untaggedEntries.toArray.mapM fun item =>
          mkMetadataEntryRow item "Missing tag metadata."
      let groupHealthRows ←
        data.groupHealth.toArray.mapM fun item => do
          let badges :=
            #[
              mkBadge s!"total: {item.totalEntries}",
              mkBadge s!"closed: {item.closedEntries}",
              mkBadge s!"local-only: {item.localOnlyEntries}",
              mkBadge s!"ready: {item.readyEntries}" "bp_summary_badge bp_summary_badge_warn",
              mkBadge s!"blocked: {item.blockedEntries}",
              mkBadge s!"incomplete Lean: {item.incompleteLeanEntries}",
              mkBadge s!"unlock score: {item.unlockScore}"
            ]
          match item.nextPriority? with
          | Option.none =>
            pure {{
              <li class="bp_summary_item">
                <div class="bp_summary_item_top">
                  <span class="bp_summary_item_head">{{.text true item.header}}</span>
                  <span class="bp_summary_item_meta"><code>s!"{item.parent}"</code></span>
                </div>
                <div class="bp_summary_item_body">"Grouped view over entries sharing the same parent."</div>
                {{mkBadgeRow badges}}
                <div class="bp_summary_item_actions">"Next: no ready child currently unlocks downstream work."</div>
              </li>
            }}
          | Option.some next =>
            let nextRef ← mkEntryRef next.label
            let priorityBadges : Array Output.Html :=
              match next.priority with
              | Option.some priority => #[mkBadge s!"priority: {priority}" "bp_summary_badge bp_summary_badge_warn"]
              | Option.none => #[]
            pure {{
              <li class="bp_summary_item">
                <div class="bp_summary_item_top">
                  <span class="bp_summary_item_head">{{.text true item.header}}</span>
                  <span class="bp_summary_item_meta"><code>s!"{item.parent}"</code></span>
                </div>
                <div class="bp_summary_item_body">"Grouped view over entries sharing the same parent."</div>
                {{mkBadgeRow badges}}
                <div class="bp_summary_item_actions">
                  "Next: " {{nextRef}} " "
                  {{priorityBadges ++ #[
                    mkBadge s!"stage: {next.stage}",
                    mkBadge s!"downstream unlocks: {next.downstreamUses}"
                  ]}}
                </div>
              </li>
            }}
      let definitionRows ←
        data.definitionIndex.toArray.mapM fun item =>
          mkLeanRow item.label item.kind item.leanObjects
      let theoremLikeRows ←
        data.theoremLikeIndex.toArray.mapM fun item =>
          mkLeanRow item.label item.kind item.leanObjects
      let axiomRows ←
        data.axiomIndex.toArray.mapM fun item =>
          mkLeanRow item.label item.kind item.leanObjects
      let theoremLikeByParentRows ←
        data.theoremLikeByParent.toArray.mapM fun group => do
          let rows ← group.entries.toArray.mapM fun item =>
            mkLeanRow item.label item.kind item.leanObjects
          pure {{
            <details class="bp_summary_subsection">
              <summary>s!"{group.header} ({group.entries.length})"</summary>
              <ul class="bp_summary_list">
                {{if rows.isEmpty then {{<li class="bp_summary_empty">"No theorem/lemma/corollary entries in this parent group."</li>}} else rows}}
              </ul>
            </details>
          }}
      let blockerCount := data.missingLeanDecls.length + data.sorryDetails.length
      let blockerRows := missingRows ++ sorryRows
      let showDefinitionCard := data.definitions > 0
      let showLemmaCard := data.lemmas > 0
      let showTheoremCard := data.theorems > 0
      let showCorollaryCard := data.corollaries > 0
      let showAxiomCard := data.axioms > 0
      let showLeanOnlyCard := data.leanOnlyEntries > 0
      let showInformalOnlyCard := data.informalOnlyEntries > 0
      let showDefinitionIndex := !definitionRows.isEmpty
      let showTheoremLikeIndex := !theoremLikeRows.isEmpty
      let showAxiomIndex := !axiomRows.isEmpty
      let showTheoremLikeByParent := !theoremLikeByParentRows.isEmpty
      let showPendingInformal := !pendingInformalRows.isEmpty
      let showBlockers := blockerCount > 0
      let showQuickWins := !quickWinRows.isEmpty
      let showOwnerRollups := !ownerRollupRows.isEmpty
      let showTagRollups := !tagRollupRows.isEmpty
      let showLinkedPrs := !linkedPrRows.isEmpty
      let showMetadataAudit :=
        !missingOwnerRows.isEmpty || !missingEffortRows.isEmpty || !untaggedRows.isEmpty
      let showMetadataCards := showQuickWins || showOwnerRollups || showTagRollups || showLinkedPrs
      let showMetadataSection := showMetadataCards || showMetadataAudit
      let showDiagnosticsSection := data.showDebugDiagnostics && !renderFailureRows.isEmpty
      let showEntryIndexSection := showDefinitionIndex || showTheoremLikeIndex || showAxiomIndex
      let showDependencyInsightsSection :=
        !statementUsedRows.isEmpty || !proofUsedRows.isEmpty || !groupHealthRows.isEmpty
      let showHeaviestPrerequisites := !heaviestPrerequisiteRows.isEmpty
      let showNoPrerequisites := !noPrerequisiteRows.isEmpty
      let showNoDependents := !noDependentRows.isEmpty
      let showProofDebtHotspots := !proofDebtHotspotRows.isEmpty
      let showStructureCards :=
        data.coverageSplit.informalOnly > 0 ||
        data.coverageSplit.readyToFormalize > 0 ||
        data.coverageSplit.formalizedWithoutAncestors > 0 ||
        data.coverageSplit.fullyClosed > 0 ||
        data.coverageSplit.blockedOrIncomplete > 0
      let showStructureSection :=
        showStructureCards || showHeaviestPrerequisites || showNoPrerequisites ||
        showNoDependents || showProofDebtHotspots
      return {{
        <div class="bp_summary">
          {{previewUi.store}}
          {{previewUi.panel}}
          <details class="bp_summary_section" open>
            <summary>"Overview"</summary>
            <div class="bp_summary_grid">
              <div class="bp_summary_card"><span class="bp_summary_label">"Total entries"</span><span class="bp_summary_value">s!"{data.totalEntries}"</span><span class="bp_summary_status">{{.text true (statusCountsText data.totalStatus)}}</span></div>
              <div class="bp_summary_card"><span class="bp_summary_label">"Ready now"</span><span class="bp_summary_value">s!"{data.coverageSplit.readyToFormalize}"</span><span class="bp_summary_status">"Entries whose next formalization step is currently unblocked."</span></div>
              <div class="bp_summary_card"><span class="bp_summary_label">"Fully closed"</span><span class="bp_summary_value">s!"{data.coverageSplit.fullyClosed}"</span><span class="bp_summary_status">"Local code and prerequisite closure are both complete."</span></div>
              <div class="bp_summary_card"><span class="bp_summary_label">"Actionable priorities"</span><span class="bp_summary_value">s!"{data.topPriorities.length}"</span><span class="bp_summary_status">"Entries ready now and already unlocking downstream work."</span></div>
              {{if showBlockers then
                  {{<div class="bp_summary_card bp_summary_card_warn"><span class="bp_summary_label">"Current blockers"</span><span class="bp_summary_value">s!"{blockerCount}"</span><span class="bp_summary_status">"Missing external or incomplete Lean declarations."</span></div>}}
                else .empty}}
              {{if showPendingInformal then
                  {{<div class="bp_summary_card"><span class="bp_summary_label">"Missing informal coverage"</span><span class="bp_summary_value">s!"{data.pendingInformalEntries.length}"</span><span class="bp_summary_status">"Entries with Lean code but missing an informal statement or proof block."</span></div>}}
                else .empty}}
              {{if showQuickWins then
                  {{<div class="bp_summary_card"><span class="bp_summary_label">"Quick wins"</span><span class="bp_summary_value">s!"{data.quickWins.length}"</span><span class="bp_summary_status">"Actionable entries with `high` priority and `small` effort."</span></div>}}
                else .empty}}
            </div>
            {{if data.totalEntries == 0 then
                {{<p class="bp_summary_empty">"No blueprint entries were registered in the current document."</p>}}
              else .empty}}
            {{if !topPriorityRows.isEmpty then
                {{<details class="bp_summary_subsection" open>
                  <summary>s!"Ready next ({data.topPriorities.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows topPriorityRows "priorities"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if showBlockers then
                {{<details class="bp_summary_subsection bp_summary_subsection_warn" open>
                  <summary>s!"Current blockers ({blockerCount})"</summary>
                  <ul class="bp_summary_list">
                    {{blockerRows}}
                  </ul>
                </details>}}
              else .empty}}
            {{if showPendingInformal then
                {{<details class="bp_summary_subsection">
                  <summary>s!"Missing informal coverage ({data.pendingInformalEntries.length})"</summary>
                  <ul class="bp_summary_list">
                    {{pendingInformalRows}}
                  </ul>
                </details>}}
              else .empty}}
          </details>
          {{if showEntryIndexSection then
              {{<details class="bp_summary_section">
                <summary>s!"Entry index ({data.totalEntries})"</summary>
                <div class="bp_summary_grid">
                  {{if showDefinitionCard then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Definitions"</span><span class="bp_summary_value">s!"{data.definitions}"</span><span class="bp_summary_status">{{.text true (statusCountsText data.definitionStatus)}}</span></div>}}
                    else .empty}}
                  {{if showLemmaCard then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Lemmas"</span><span class="bp_summary_value">s!"{data.lemmas}"</span><span class="bp_summary_status">{{.text true (statusCountsText data.lemmaStatus)}}</span></div>}}
                    else .empty}}
                  {{if showTheoremCard then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Theorems"</span><span class="bp_summary_value">s!"{data.theorems}"</span><span class="bp_summary_status">{{.text true (statusCountsText data.theoremStatus)}}</span></div>}}
                    else .empty}}
                  {{if showCorollaryCard then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Corollaries"</span><span class="bp_summary_value">s!"{data.corollaries}"</span><span class="bp_summary_status">{{.text true (statusCountsText data.corollaryStatus)}}</span></div>}}
                    else .empty}}
                  {{if showAxiomCard then
                      {{<div class="bp_summary_card bp_summary_card_warn"><span class="bp_summary_label">"Axiom-like entries"</span><span class="bp_summary_value">s!"{data.axioms}"</span><span class="bp_summary_status">{{.text true (statusCountsText data.axiomStatus)}}</span></div>}}
                    else .empty}}
                  {{if showLeanOnlyCard then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Lean-only entries"</span><span class="bp_summary_value">s!"{data.leanOnlyEntries}"</span></div>}}
                    else .empty}}
                  {{if showInformalOnlyCard then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Informal-only entries"</span><span class="bp_summary_value">s!"{data.informalOnlyEntries}"</span></div>}}
                    else .empty}}
                </div>
                {{if showDefinitionIndex then
                    {{<details class="bp_summary_subsection">
                      <summary>s!"Definition Index ({data.definitionIndex.length})"</summary>
                      <ul class="bp_summary_list">
                        {{definitionRows}}
                      </ul>
                    </details>}}
                  else .empty}}
                {{if showTheoremLikeIndex then
                    {{<details class="bp_summary_subsection">
                      <summary>s!"Theorem / Lemma / Corollary Index ({data.theoremLikeIndex.length})"</summary>
                      <ul class="bp_summary_list">
                        {{theoremLikeRows}}
                      </ul>
                      {{if showTheoremLikeByParent then
                          {{<details class="bp_summary_nested"><summary>s!"By parent groups ({data.theoremLikeByParent.length})"</summary>{{theoremLikeByParentRows}}</details>}}
                        else .empty}}
                    </details>}}
                else .empty}}
                {{if showAxiomIndex then
                    {{<details class="bp_summary_subsection bp_summary_subsection_warn">
                      <summary>s!"Axiom-like Index ({data.axiomIndex.length})"</summary>
                      <ul class="bp_summary_list">
                        {{axiomRows}}
                      </ul>
                    </details>}}
                  else .empty}}
              </details>}}
            else .empty}}
          {{if showDependencyInsightsSection then
              {{<details class="bp_summary_section">
            <summary>"Dependency insights"</summary>
            <div class="bp_summary_grid">
              {{if !statementUsedRows.isEmpty then
                  {{<div class="bp_summary_card"><span class="bp_summary_label">"Statement-used entries"</span><span class="bp_summary_value">s!"{statementUsedItems.size}"</span><span class="bp_summary_status">"Entries reused in statement dependencies."</span></div>}}
                else .empty}}
              {{if !proofUsedRows.isEmpty then
                  {{<div class="bp_summary_card"><span class="bp_summary_label">"Proof-used entries"</span><span class="bp_summary_value">s!"{proofUsedItems.size}"</span><span class="bp_summary_status">"Entries reused in proof-only dependencies."</span></div>}}
                else .empty}}
              {{if !groupHealthRows.isEmpty then
                  {{<div class="bp_summary_card"><span class="bp_summary_label">"Tracked parent groups"</span><span class="bp_summary_value">s!"{data.groupHealth.length}"</span><span class="bp_summary_status">"Grouped health rollups for parents with more than one child entry."</span></div>}}
                else .empty}}
            </div>
            {{if !statementUsedRows.isEmpty then
                {{<details class="bp_summary_subsection">
                  <summary>s!"Most used in statements ({statementUsedItems.size})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows statementUsedRows "statement-used entries"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if !proofUsedRows.isEmpty then
                {{<details class="bp_summary_subsection">
                  <summary>s!"Most used in proofs ({proofUsedItems.size})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows proofUsedRows "proof-used entries"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if !groupHealthRows.isEmpty then
                {{<details class="bp_summary_subsection">
                  <summary>s!"Group health ({data.groupHealth.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows groupHealthRows "groups"}}
                  </ul>
                </details>}}
              else .empty}}
          </details>}}
            else .empty}}
          {{if showMetadataSection then
              {{<details class="bp_summary_section">
            <summary>"Metadata"</summary>
            {{if showMetadataCards then
                {{<div class="bp_summary_grid">
                  {{if showQuickWins then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Quick wins"</span><span class="bp_summary_value">s!"{data.quickWins.length}"</span><span class="bp_summary_status">"Actionable entries with `high` priority and `small` effort."</span></div>}}
                    else .empty}}
                  {{if showOwnerRollups then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Owners in use"</span><span class="bp_summary_value">s!"{data.ownerRollups.length}"</span><span class="bp_summary_status">"Distinct owners referenced by the current blueprint entries."</span></div>}}
                    else .empty}}
                  {{if showTagRollups then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Tags in use"</span><span class="bp_summary_value">s!"{data.tagRollups.length}"</span><span class="bp_summary_status">"Distinct tags currently attached to blueprint entries."</span></div>}}
                    else .empty}}
                  {{if showLinkedPrs then
                      {{<div class="bp_summary_card"><span class="bp_summary_label">"Linked PRs"</span><span class="bp_summary_value">s!"{data.linkedPrs.length}"</span><span class="bp_summary_status">"Entries already linked to a review URL."</span></div>}}
                    else .empty}}
                </div>}}
              else .empty}}
            {{if showQuickWins then
                {{<details class="bp_summary_subsection">
                  <summary>s!"Quick wins ({data.quickWins.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows quickWinRows "quick wins"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if showOwnerRollups then
                {{<details class="bp_summary_subsection">
                  <summary>s!"Owner rollups ({data.ownerRollups.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows ownerRollupRows "owners"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if showTagRollups then
                {{<details class="bp_summary_subsection">
                  <summary>s!"Tag rollups ({data.tagRollups.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows tagRollupRows "tags"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if showLinkedPrs then
                {{<details class="bp_summary_subsection">
                  <summary>s!"Linked PRs ({data.linkedPrs.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows linkedPrRows "linked PR entries"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if showMetadataAudit then
                {{<details class="bp_summary_subsection bp_summary_subsection_warn">
                  <summary>"Metadata audit"</summary>
                  <div class="bp_summary_grid">
                    {{if !missingOwnerRows.isEmpty then {{<div class="bp_summary_card bp_summary_card_warn"><span class="bp_summary_label">"Missing owner"</span><span class="bp_summary_value">s!"{data.missingOwners.length}"</span></div>}} else .empty}}
                    {{if !missingEffortRows.isEmpty then {{<div class="bp_summary_card bp_summary_card_warn"><span class="bp_summary_label">"Missing effort"</span><span class="bp_summary_value">s!"{data.missingEffort.length}"</span></div>}} else .empty}}
                    {{if !untaggedRows.isEmpty then {{<div class="bp_summary_card bp_summary_card_warn"><span class="bp_summary_label">"Untagged"</span><span class="bp_summary_value">s!"{data.untaggedEntries.length}"</span></div>}} else .empty}}
                  </div>
                  {{if !missingOwnerRows.isEmpty then {{<details class="bp_summary_nested"><summary>s!"Missing owner ({data.missingOwners.length})"</summary><ul class="bp_summary_list">{{capRows missingOwnerRows "entries missing owner"}}</ul></details>}} else .empty}}
                  {{if !missingEffortRows.isEmpty then {{<details class="bp_summary_nested"><summary>s!"Missing effort ({data.missingEffort.length})"</summary><ul class="bp_summary_list">{{capRows missingEffortRows "entries missing effort"}}</ul></details>}} else .empty}}
                  {{if !untaggedRows.isEmpty then {{<details class="bp_summary_nested"><summary>s!"Untagged ({data.untaggedEntries.length})"</summary><ul class="bp_summary_list">{{capRows untaggedRows "untagged entries"}}</ul></details>}} else .empty}}
                </details>}}
              else .empty}}
          </details>}}
            else .empty}}
          {{if showDiagnosticsSection then
              {{<details class="bp_summary_section">
            <summary>"Maintainer diagnostics"</summary>
            <div class="bp_summary_grid">
              <div class="bp_summary_card bp_summary_card_warn"><span class="bp_summary_label">"Render failures"</span><span class="bp_summary_value">s!"{data.renderFailures.length}"</span><span class="bp_summary_status">"External declarations that checked in Lean but failed HTML rendering."</span></div>
            </div>
            <details class="bp_summary_subsection bp_summary_subsection_warn">
              <summary>s!"Render failures ({data.renderFailures.length})"</summary>
              <ul class="bp_summary_list">
                {{capRows renderFailureRows "render-failure entries"}}
              </ul>
            </details>
          </details>}}
            else .empty}}
          {{if showStructureSection then
              {{<details class="bp_summary_section">
            <summary>"Structure and coverage"</summary>
            <div class="bp_summary_grid">
              {{if data.coverageSplit.informalOnly > 0 then
                  {{<div class="bp_summary_card"><span class="bp_summary_label">"Informal-only"</span><span class="bp_summary_value">s!"{data.coverageSplit.informalOnly}"</span><span class="bp_summary_status">"Statements with no associated Lean code yet."</span></div>}}
                else .empty}}
              {{if data.coverageSplit.readyToFormalize > 0 then
                  {{<div class="bp_summary_card"><span class="bp_summary_label">"Ready to formalize"</span><span class="bp_summary_value">s!"{data.coverageSplit.readyToFormalize}"</span><span class="bp_summary_status">"Entries whose next step is currently unblocked."</span></div>}}
                else .empty}}
              {{if data.coverageSplit.formalizedWithoutAncestors > 0 then
                  {{<div class="bp_summary_card"><span class="bp_summary_label">"Formalized, ancestors open"</span><span class="bp_summary_value">s!"{data.coverageSplit.formalizedWithoutAncestors}"</span><span class="bp_summary_status">"Local Lean work is done, but prerequisite closure is still open."</span></div>}}
                else .empty}}
              {{if data.coverageSplit.fullyClosed > 0 then
                  {{<div class="bp_summary_card"><span class="bp_summary_label">"Fully closed"</span><span class="bp_summary_value">s!"{data.coverageSplit.fullyClosed}"</span><span class="bp_summary_status">"Local code and ancestor closure are both complete."</span></div>}}
                else .empty}}
              {{if data.coverageSplit.blockedOrIncomplete > 0 then
                  {{<div class="bp_summary_card bp_summary_card_warn"><span class="bp_summary_label">"Blocked or incomplete"</span><span class="bp_summary_value">s!"{data.coverageSplit.blockedOrIncomplete}"</span><span class="bp_summary_status">"Entries not covered by the highlighted readiness buckets above."</span></div>}}
                else .empty}}
            </div>
            {{if showHeaviestPrerequisites then
                {{<details class="bp_summary_subsection">
                  <summary>s!"Heaviest prerequisites ({data.heaviestPrerequisites.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows heaviestPrerequisiteRows "heaviest-prerequisite entries"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if showNoPrerequisites then
                {{<details class="bp_summary_subsection">
                  <summary>s!"No prerequisites ({data.noPrerequisites.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows noPrerequisiteRows "entries without prerequisites"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if showNoDependents then
                {{<details class="bp_summary_subsection">
                  <summary>s!"No dependents ({data.noDependents.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows noDependentRows "entries without dependents"}}
                  </ul>
                </details>}}
              else .empty}}
            {{if showProofDebtHotspots then
                {{<details class="bp_summary_subsection bp_summary_subsection_warn">
                  <summary>s!"Proof debt hotspots ({data.proofDebtHotspots.length})"</summary>
                  <ul class="bp_summary_list">
                    {{capRows proofDebtHotspotRows "proof-debt hotspots"}}
                  </ul>
                </details>}}
              else .empty}}
          </details>}}
            else .empty}}
        </div>
      }}
  extraCss := withPreviewPanelInlinePreviewCssAssets [summaryCss]
  extraJs := withInlinePreviewJsAssets [openTargetDetailsJs] [summaryPreviewJs]

open Verso Doc Elab Syntax in
def mkSummaryPart (stx : Syntax) (endPos : String.Pos.Raw) : PartElabM FinishedPart := do
  let titlePreview := "Blueprint Summary"
  let titleInlines ← `(inline | "Blueprint Summary")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let summary ← buildSummary
  if verso.blueprint.debug.commands.get (← Lean.getOptions) then
    logInfo m!"Blueprint summary for {summary.totalEntries} entries"
  let block ← ``(Verso.Doc.Block.other (Informal.Commands.Block.summary $(quote summary)) #[])
  let subParts := #[]
  pure <| FinishedPart.mk stx expandedTitle titlePreview metadata #[block] subParts endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def blueprintSummaryCmd : PartCommand
  | stx@`(block|command{blueprint_summary}) => do
    let endPos := stx.getTailPos?.get!
    closePartsUntil 1 endPos
    addPart (← mkSummaryPart stx endPos)
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
