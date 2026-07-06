/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Elab.Command
import Verso
import VersoManual
import VersoBlueprint.Compat
import VersoBlueprint.Commands.Common
import VersoBlueprint.Commands.Summary.Data
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.Environment
import VersoBlueprint.Graph
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.MetadataView
import VersoBlueprint.Informal.LeanCodeLink
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.PreviewCache
import VersoBlueprint.Resolve
import VersoBlueprint.TeX
import VersoBlueprint.TraversalIndex

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment

register_option verso.blueprint.summary.debugDiagnostics : Bool := {
  defValue := false
  descr := "Show maintainer diagnostics such as external declaration render failures in blueprint summaries"
}

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

private def byNatAsc (left right : Nat) (tie : Bool) : Bool :=
  left < right || (left == right && tie)

private def byNatDesc (left right : Nat) (tie : Bool) : Bool :=
  left > right || (left == right && tie)

private def byStringAsc (left right : String) : Bool :=
  left < right

private def byNameStringAsc (left right : Name) : Bool :=
  left.toString < right.toString

private def sortPriorityItems (items : Array PriorityItem) : Array PriorityItem :=
  items.qsort fun a b =>
    byNatAsc (explicitPriorityRank a.priority) (explicitPriorityRank b.priority) <|
      byNatDesc a.downstreamUses b.downstreamUses <|
        byNatDesc a.directUses b.directUses <|
          byNatAsc (priorityStageRank a.stage) (priorityStageRank b.stage) <|
            byNameStringAsc a.label b.label

private def sortUsageItems (items : Array UsageItem) : Array UsageItem :=
  items.qsort fun a b =>
    byNatDesc a.directUses b.directUses <|
      byNatDesc a.downstreamUses b.downstreamUses <|
        byNameStringAsc a.label b.label

private def sortUsageItemsByAxis (items : Array UsageItem) (axisUses : UsageItem → Nat) : Array UsageItem :=
  items.qsort fun a b =>
    byNatDesc (axisUses a) (axisUses b) <|
      byNatDesc a.downstreamUses b.downstreamUses <|
        byNatDesc a.directUses b.directUses <|
          byNameStringAsc a.label b.label

private def sortDependencyLoadItems (items : Array DependencyLoadItem) : Array DependencyLoadItem :=
  items.qsort fun a b =>
    byNatDesc a.totalDeps b.totalDeps <|
      byNatDesc a.proofDeps b.proofDeps <|
        byNatDesc a.statementDeps b.statementDeps <|
          byNameStringAsc a.label b.label

private def sortDebtHotspotItems (items : Array DebtHotspotItem) : Array DebtHotspotItem :=
  items.qsort fun a b =>
    byNatDesc a.totalDebt b.totalDebt <|
      byNatDesc a.affectedEntries b.affectedEntries <|
        byStringAsc a.header b.header

private def sortGroupHealthItems (items : Array GroupHealthItem) : Array GroupHealthItem :=
  items.qsort fun a b =>
    byNatDesc a.readyEntries b.readyEntries <|
      byNatDesc a.unlockScore b.unlockScore <|
        byNatDesc a.totalEntries b.totalEntries <|
          byStringAsc a.header b.header

private def sortOwnerRollupItems (items : Array OwnerRollupItem) : Array OwnerRollupItem :=
  items.qsort fun a b =>
    byNatDesc a.actionableEntries b.actionableEntries <|
      byNatDesc a.quickWins b.quickWins <|
        byNatDesc a.totalEntries b.totalEntries <|
          byStringAsc a.displayName b.displayName

private def sortTagRollupItems (items : Array TagRollupItem) : Array TagRollupItem :=
  items.qsort fun a b =>
    byNatDesc a.actionableEntries b.actionableEntries <|
      byNatDesc a.quickWins b.quickWins <|
        byNatDesc a.totalEntries b.totalEntries <|
          byStringAsc a.tag b.tag

private def sortMetadataEntryItems (items : Array MetadataEntryItem) : Array MetadataEntryItem :=
  items.qsort fun a b =>
    byNameStringAsc a.label b.label

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
  let externalNames :=
    node.externalRefs.foldl (init := #[]) fun acc decl =>
      pushUniqueName acc decl.canonical
  let allNames :=
    node.literateCodes.foldl (init := externalNames) fun acc code =>
      code.definedDeclNames.foldl pushUniqueName acc
  allNames.toList

private def codeDeclCount (code : Data.Code) : Nat :=
  code.definedDefs.size + code.definedTheorems.size

private def codeSorryCount (code : Data.Code) : Nat :=
  countSorries code.definedDefs (fun (d : Data.LiterateDef) => d.provedStatus) +
  countSorries code.definedTheorems (fun (d : Data.LiterateThm) => d.provedStatus)

private def codeSorryDetails (label : Name) (kind : String) (code : Data.Code) : List SorryItem :=
  collectSorries label kind code.definedDefs
    (fun (d : Data.LiterateDef) => d.name)
    (fun (d : Data.LiterateDef) => d.provedStatus)
    (fun _ => false) ++
  collectSorries label kind code.definedTheorems
    (fun (d : Data.LiterateThm) => d.name)
    (fun (d : Data.LiterateThm) => d.provedStatus)
    (fun _ => true)

private structure NodeLeanSummary where
  leanDecls : Nat := 0
  sorries : Nat := 0
  leanObjects : List Name := []
  sorryDetails : List SorryItem := []
  missingLeanDecls : List MissingLeanDeclItem := []
  renderFailures : List RenderFailureItem := []
deriving Inhabited

private def nodeLeanSummary (label : Name) (node : Data.Node) : NodeLeanSummary :=
  if !node.hasAssociatedCode then
    {}
  else
    let kind := toString node.kind
    let externalDecls := node.externalRefs
    let missingLeanDecls :=
      externalDecls.foldl (init := []) fun acc decl =>
        if !decl.present then
          {
            label
            kind
            written := decl.written
            canonical := decl.canonical
          } :: acc
        else
          acc
    let incompleteExternalDecls :=
      externalDecls.foldl (init := #[]) fun acc decl =>
        if !decl.present then
          acc
        else
          let status := decl.provedStatus
          if status.isIncomplete then
            acc.push (decl.canonical, status)
          else
            acc
    let externalSorryDetails :=
      incompleteExternalDecls.toList.map fun (decl, status) =>
        {
          label
          kind
          decl
          isTheorem :=
            (externalDecls.find? (fun d => d.canonical == decl)).map (·.kind.isTheoremLike) |>.getD false
          status
        }
    let renderFailures :=
      (externalRenderFailures externalDecls).toList.map fun failure =>
        {
          label
          kind
          written := failure.decl.written
          canonical := failure.decl.canonical
          message := failure.message
        }
    let (inlineDecls, inlineSorries, inlineSorryDetails) :=
      node.literateCodes.foldl
        (init := (0, 0, ([] : List SorryItem)))
        fun (decls, sorryCount, details) code =>
          (
            decls + codeDeclCount code,
            sorryCount + codeSorryCount code,
            codeSorryDetails label kind code ++ details
          )
    {
      leanDecls := externalDecls.size + inlineDecls
      sorries := incompleteExternalDecls.size + inlineSorries
      leanObjects := nodeLeanObjects node
      sorryDetails := externalSorryDetails ++ inlineSorryDetails
      missingLeanDecls
      renderFailures
    }

private def nodeMissingLeanDeclCount (external : Informal.Graph.ExternalCodeStatus) (node : Data.Node) : Nat :=
  (Informal.Graph.nodeExternalDecls node).foldl (init := 0) fun acc decl =>
    acc + (if Informal.Graph.externalDeclMissing external decl then 1 else 0)

private def nodeIncompleteLeanDeclCount (external : Informal.Graph.ExternalCodeStatus) (node : Data.Node) : Nat :=
  let externalCount :=
    node.externalRefs.foldl (init := 0) fun acc decl =>
      if Informal.Graph.externalDeclMissing external decl then
        acc
      else
        acc + (if decl.provedStatus.isIncomplete then 1 else 0)
  externalCount + node.literateCodes.foldl (init := 0) fun acc code =>
    acc + codeSorryCount code

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

private def metadataIsQuickWin (priority effort : Option String) : Bool :=
  priority == some "high" && effort == some "small"

private def priorityItemIsQuickWin (item : PriorityItem) : Bool :=
  metadataIsQuickWin item.priority item.effort

private def nodeIsQuickWin (node : Data.Node) (actionable : Bool) : Bool :=
  actionable && metadataIsQuickWin node.priority node.effort

private def addParentTheoremLikeItem (groups : NameMap (List IndexItem)) (parent : Name) (item : IndexItem) :
    NameMap (List IndexItem) :=
  groups.insert parent (item :: groups.getD parent [])

private structure SummaryBuildContext where
  state : Environment.State
  entries : Array (Name × Data.Node)
  parentChildren : NameMap (Array Name)
  groupHeaders : NameMap String
  external : Informal.Graph.ExternalCodeStatus
  usageMap : NameMap UsageCounts
  reverseMap : NameMap (Array Name)

private def mkSummaryBuildContext (state : Environment.State) : SummaryBuildContext :=
  let entries := state.data.toArray
  let parentChildren := state.data.parentChildren
  let external : Informal.Graph.ExternalCodeStatus := {}
  let (usageMap, reverseMap) := buildUsageMaps entries
  {
    state
    entries
    parentChildren
    groupHeaders := state.groups
    external
    usageMap
    reverseMap
  }

private def SummaryBuildContext.downstreamUses (ctx : SummaryBuildContext) (label : Name) : Nat :=
  downstreamUseCount ctx.reverseMap (ctx.reverseMap.getD label #[]).toList

private def SummaryBuildContext.priorityEntry? (ctx : SummaryBuildContext)
    (label : Name) (node : Data.Node) : Option PriorityItem :=
  priorityItem? ctx.state ctx.external ctx.usageMap ctx.reverseMap label node

private def SummaryBuildContext.childEntries (ctx : SummaryBuildContext) (children : Array Name) :
    Array (Name × Data.Node) :=
  children.foldl (init := #[]) fun acc child =>
    match ctx.state.data.get? child with
    | some node => acc.push (child, node)
    | none => acc

private structure MetadataAudit where
  linkedPrs : Array MetadataEntryItem := #[]
  missingOwners : Array MetadataEntryItem := #[]
  missingEffort : Array MetadataEntryItem := #[]
  untaggedEntries : Array MetadataEntryItem := #[]

private def MetadataAudit.addEntry (audit : MetadataAudit)
    (state : Environment.State) (label : Name) (node : Data.Node) : MetadataAudit :=
  let item := metadataEntryItem state label node
  let audit :=
    if node.prUrl.isSome then
      { audit with linkedPrs := audit.linkedPrs.push item }
    else
      audit
  let audit :=
    if node.owner.isNone then
      { audit with missingOwners := audit.missingOwners.push item }
    else
      audit
  let audit :=
    if node.effort.isNone then
      { audit with missingEffort := audit.missingEffort.push item }
    else
      audit
  if node.tags.isEmpty then
    { audit with untaggedEntries := audit.untaggedEntries.push item }
  else
    audit

private def collectMetadataAudit (ctx : SummaryBuildContext) : MetadataAudit :=
  ctx.entries.foldl (init := ({} : MetadataAudit)) fun audit (label, node) =>
    audit.addEntry ctx.state label node

private def MetadataAudit.sortedLinkedPrs (audit : MetadataAudit) : List MetadataEntryItem :=
  (sortMetadataEntryItems audit.linkedPrs).toList

private def MetadataAudit.sortedMissingOwners (audit : MetadataAudit) : List MetadataEntryItem :=
  (sortMetadataEntryItems audit.missingOwners).toList

private def MetadataAudit.sortedMissingEffort (audit : MetadataAudit) : List MetadataEntryItem :=
  (sortMetadataEntryItems audit.missingEffort).toList

private def MetadataAudit.sortedUntaggedEntries (audit : MetadataAudit) : List MetadataEntryItem :=
  (sortMetadataEntryItems audit.untaggedEntries).toList

private def Summary.bumpNodeKindStatus (summary : Summary)
    (kind : Data.NodeKind) (flags : EntryStatusFlags) : Summary :=
  match kind with
  | Data.NodeKind.definition =>
    { summary with
      definitions := summary.definitions + 1
      definitionStatus := bumpEntryStatus summary.definitionStatus flags
    }
  | Data.NodeKind.proposition =>
    { summary with
      propositions := summary.propositions + 1
      propositionStatus := bumpEntryStatus summary.propositionStatus flags
    }
  | Data.NodeKind.lemma =>
    { summary with
      lemmas := summary.lemmas + 1
      lemmaStatus := bumpEntryStatus summary.lemmaStatus flags
    }
  | Data.NodeKind.theorem =>
    { summary with
      theorems := summary.theorems + 1
      theoremStatus := bumpEntryStatus summary.theoremStatus flags
    }
  | Data.NodeKind.corollary =>
    { summary with
      corollaries := summary.corollaries + 1
      corollaryStatus := bumpEntryStatus summary.corollaryStatus flags
    }

private def Summary.bumpAxiomStatus (summary : Summary) (flags : EntryStatusFlags) : Summary :=
  if flags.hasAxiomLike then
    { summary with
      axioms := summary.axioms + 1
      axiomStatus := bumpEntryStatus summary.axiomStatus flags
    }
  else
    summary

private def collectSummaryOverview (ctx : SummaryBuildContext) : Summary :=
  ctx.entries.foldl (init := ({} : Summary)) fun acc (label, node) =>
    let hasStatement := node.statement.isSome
    let hasProof := node.proof.isSome
    let hasCode := Informal.Graph.nodeHasAssociatedCode node
    let statusFlags := entryStatusFlags ctx.state ctx.external node
    let leanSummary := nodeLeanSummary label node
    let pendingInformalEntries : List PendingInformalItem :=
      if hasCode && ((node.kind.isTheoremLike && !hasProof) || !hasStatement) then
        mkIndexItem label node.kind leanSummary.leanObjects :: acc.pendingInformalEntries
      else
        acc.pendingInformalEntries
    let definitionIndex : List IndexItem :=
      if node.kind == Data.NodeKind.definition then
        mkIndexItem label node.kind leanSummary.leanObjects :: acc.definitionIndex
      else
        acc.definitionIndex
    let theoremLikeIndex : List IndexItem :=
      if node.kind.isTheoremLike then
        mkIndexItem label node.kind leanSummary.leanObjects :: acc.theoremLikeIndex
      else
        acc.theoremLikeIndex
    let axiomIndex : List IndexItem :=
      if statusFlags.hasAxiomLike then
        mkIndexItem label node.kind leanSummary.leanObjects :: acc.axiomIndex
      else
        acc.axiomIndex
    let acc := { acc with
      totalEntries := acc.totalEntries + 1
      leanOnlyEntries := acc.leanOnlyEntries + (if hasCode && !hasStatement then 1 else 0)
      informalOnlyEntries := acc.informalOnlyEntries + (if hasStatement && !hasCode then 1 else 0)
      totalStatus := bumpEntryStatus acc.totalStatus statusFlags
      pendingInformalEntries
      leanDecls := acc.leanDecls + leanSummary.leanDecls
      sorries := acc.sorries + leanSummary.sorries
      sorryDetails := leanSummary.sorryDetails ++ acc.sorryDetails
      missingLeanDecls := leanSummary.missingLeanDecls ++ acc.missingLeanDecls
      renderFailures := leanSummary.renderFailures ++ acc.renderFailures
      definitionIndex
      theoremLikeIndex
      axiomIndex
    }
    acc.bumpNodeKindStatus node.kind statusFlags
    |>.bumpAxiomStatus statusFlags

private def collectTheoremLikeByParent (ctx : SummaryBuildContext) : List ParentTheoremGroup :=
  let grouped := ctx.entries.foldl (init := ({} : NameMap (List IndexItem))) fun acc (label, node) =>
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
    if (ctx.parentChildren.getD parent #[]).size <= 1 then
      acc
    else
      let header := ctx.groupHeaders.getD parent parent.toString
      { parent, header, entries := items.reverse } :: acc

private def collectPriorityItems (ctx : SummaryBuildContext) : List PriorityItem :=
  let items := ctx.entries.foldl (init := #[]) fun acc (label, node) =>
    match ctx.priorityEntry? label node with
    | none => acc
    | some item => acc.push item
  (sortPriorityItems items).toList

private def usageItem? (ctx : SummaryBuildContext) (label : Name) (node : Data.Node) : Option UsageItem :=
  let usage := ctx.usageMap.getD label {}
  if usage.directUses == 0 then
    none
  else
    some {
      label
      kind := toString node.kind
      statementUses := usage.statementUses
      proofUses := usage.proofUses
      directUses := usage.directUses
      downstreamUses := ctx.downstreamUses label
      leanObjects := nodeLeanObjects node
    }

private def collectUsageItems (ctx : SummaryBuildContext) : List UsageItem :=
  let items := ctx.entries.foldl (init := #[]) fun acc (label, node) =>
    match usageItem? ctx label node with
    | none => acc
    | some item => acc.push item
  (sortUsageItems items).toList

private structure GroupHealthCounts where
  totalEntries : Nat := 0
  closedEntries : Nat := 0
  localOnlyEntries : Nat := 0
  readyEntries : Nat := 0
  blockedEntries : Nat := 0
  incompleteLeanEntries : Nat := 0
  unlockScore : Nat := 0

private def GroupHealthCounts.addEntry (counts : GroupHealthCounts)
    (ctx : SummaryBuildContext) (child : Name) (node : Data.Node) : GroupHealthCounts :=
  let statusFlags := entryStatusFlags ctx.state ctx.external node
  let statementStatus := Informal.Graph.statementStatus ctx.external ctx.state child node
  let proofStatus := Informal.Graph.proofStatus ctx.external ctx.state child node
  let readyNow :=
    !Informal.Graph.nodeLocalFormalized ctx.external node &&
      (actionableStage? node statementStatus proofStatus).isSome
  let blockedNow := !statusFlags.completed && !statusFlags.completedDepsNo && !readyNow
  let incompleteLeanNow :=
    Informal.Graph.nodeHasAssociatedCode node &&
      (Informal.Graph.nodeHasSorries ctx.external node ||
        Informal.Graph.nodeHasMissingExternalDecls ctx.external node)
  {
    totalEntries := counts.totalEntries + 1
    closedEntries := counts.closedEntries + (if statusFlags.completed then 1 else 0)
    localOnlyEntries := counts.localOnlyEntries + (if statusFlags.completedDepsNo then 1 else 0)
    readyEntries := counts.readyEntries + (if readyNow then 1 else 0)
    blockedEntries := counts.blockedEntries + (if blockedNow then 1 else 0)
    incompleteLeanEntries := counts.incompleteLeanEntries + (if incompleteLeanNow then 1 else 0)
    unlockScore := counts.unlockScore + ctx.downstreamUses child
  }

private def collectGroupHealth (ctx : SummaryBuildContext) : List GroupHealthItem :=
  let items := ctx.parentChildren.toArray.foldl (init := #[]) fun acc (parent, children) =>
    if children.size <= 1 then
      acc
    else
      let childEntries := ctx.childEntries children
      let counts := childEntries.foldl (init := ({} : GroupHealthCounts)) fun counts (child, node) =>
        counts.addEntry ctx child node
      let nextPriority? :=
        let candidates := childEntries.foldl (init := #[]) fun acc (child, node) =>
          match ctx.priorityEntry? child node with
          | none => acc
          | some item => acc.push item
        let sorted := sortPriorityItems candidates
        if h : 0 < sorted.size then
          some sorted[0]
        else
          none
      acc.push {
        parent
        header := ctx.groupHeaders.getD parent parent.toString
        totalEntries := counts.totalEntries
        closedEntries := counts.closedEntries
        localOnlyEntries := counts.localOnlyEntries
        readyEntries := counts.readyEntries
        blockedEntries := counts.blockedEntries
        incompleteLeanEntries := counts.incompleteLeanEntries
        unlockScore := counts.unlockScore
        nextPriority?
      }
  (sortGroupHealthItems items).toList

private def collectCoverageSplit (ctx : SummaryBuildContext) : CoverageSplit :=
  ctx.entries.foldl (init := ({} : CoverageSplit)) fun acc (label, node) =>
    let hasStatement := node.statement.isSome
    let hasCode := Informal.Graph.nodeHasAssociatedCode node
    let statusFlags := entryStatusFlags ctx.state ctx.external node
    let statementStatus := Informal.Graph.statementStatus ctx.external ctx.state label node
    let proofStatus := Informal.Graph.proofStatus ctx.external ctx.state label node
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

private def collectDependencyLoadItems (ctx : SummaryBuildContext) : List DependencyLoadItem :=
  let items := ctx.entries.foldl (init := #[]) fun acc (label, node) =>
    let statementDeps := Informal.Graph.eraseDups (Informal.Graph.statementDeps node)
    let proofDeps := Informal.Graph.eraseDups (Informal.Graph.proofDeps node)
    let totalDeps := (Informal.Graph.eraseDups (statementDeps ++ proofDeps)).size
    if totalDeps == 0 then
      acc
    else
      let usage := ctx.usageMap.getD label {}
      acc.push {
        label
        kind := toString node.kind
        statementDeps := statementDeps.size
        proofDeps := proofDeps.size
        totalDeps
        directUses := usage.directUses
        downstreamUses := ctx.downstreamUses label
        leanObjects := nodeLeanObjects node
      }
  (sortDependencyLoadItems items).toList

private def collectIndexItems (ctx : SummaryBuildContext) (keep : Name → Data.Node → Bool) :
    List IndexItem :=
  ctx.entries.foldl (init := []) fun acc (label, node) =>
    if keep label node then
      mkIndexItem label node.kind (nodeLeanObjects node) :: acc
    else
      acc
  |>.reverse

private structure ProofDebtCounts where
  affectedEntries : Nat := 0
  incompleteDecls : Nat := 0
  missingDecls : Nat := 0

private def ProofDebtCounts.addNode (counts : ProofDebtCounts)
    (external : Informal.Graph.ExternalCodeStatus) (node : Data.Node) : ProofDebtCounts :=
  let incompleteDeclCount := nodeIncompleteLeanDeclCount external node
  let missingDeclCount := nodeMissingLeanDeclCount external node
  let hasDebt := incompleteDeclCount > 0 || missingDeclCount > 0
  {
    affectedEntries := counts.affectedEntries + (if hasDebt then 1 else 0)
    incompleteDecls := counts.incompleteDecls + incompleteDeclCount
    missingDecls := counts.missingDecls + missingDeclCount
  }

private def ProofDebtCounts.totalDebt (counts : ProofDebtCounts) : Nat :=
  counts.incompleteDecls + counts.missingDecls

private def collectProofDebtHotspots (ctx : SummaryBuildContext) : List DebtHotspotItem :=
  let items := ctx.parentChildren.toArray.foldl (init := #[]) fun acc (parent, children) =>
    let counts :=
      children.foldl (init := ({} : ProofDebtCounts)) fun counts child =>
        match ctx.state.data.get? child with
        | none => counts
        | some node => counts.addNode ctx.external node
    let totalDebt := counts.totalDebt
    if totalDebt == 0 then
      acc
    else
      acc.push {
        parent
        header := ctx.groupHeaders.getD parent parent.toString
        affectedEntries := counts.affectedEntries
        incompleteDecls := counts.incompleteDecls
        missingDecls := counts.missingDecls
        totalDebt
      }
  (sortDebtHotspotItems items).toList

private def collectOwnerRollups (ctx : SummaryBuildContext) : List OwnerRollupItem :=
  let rollups := ctx.entries.foldl (init := ({} : NameMap OwnerRollupItem)) fun acc (label, node) =>
    match node.owner with
    | none => acc
    | some owner =>
      let actionable := (ctx.priorityEntry? label node).isSome
      let quickWin := nodeIsQuickWin node actionable
      let linkedPr := node.prUrl.isSome
      let displayName := (ownerDisplayName ctx.state node).getD owner.toString
      let cur := acc.getD owner { owner, displayName }
      acc.insert owner {
        cur with
          totalEntries := cur.totalEntries + 1
          actionableEntries := cur.actionableEntries + (if actionable then 1 else 0)
          quickWins := cur.quickWins + (if quickWin then 1 else 0)
          linkedPrs := cur.linkedPrs + (if linkedPr then 1 else 0)
      }
  (sortOwnerRollupItems (rollups.toArray.map fun pair => pair.2)).toList

private def collectTagRollups (ctx : SummaryBuildContext) : List TagRollupItem :=
  let rollups := ctx.entries.foldl (init := ({} : Std.HashMap String TagRollupItem)) fun acc (label, node) =>
    let actionable := (ctx.priorityEntry? label node).isSome
    let quickWin := nodeIsQuickWin node actionable
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

def buildSummary : CoreM Summary := do
  reportImportedConflicts
  let showDebugDiagnostics :=
    (← getOptions).get
      verso.blueprint.summary.debugDiagnostics.name
      verso.blueprint.summary.debugDiagnostics.defValue
  let env ← getEnv
  let state := informalExt.getState env
  let ctx := mkSummaryBuildContext state
  let summary := collectSummaryOverview ctx
  let topPriorities := collectPriorityItems ctx
  let metadataAudit := collectMetadataAudit ctx
  return {
    summary with
      showDebugDiagnostics := showDebugDiagnostics
      theoremLikeByParent := collectTheoremLikeByParent ctx
      topPriorities := topPriorities
      mostUsed := collectUsageItems ctx
      groupHealth := collectGroupHealth ctx
      coverageSplit := collectCoverageSplit ctx
      heaviestPrerequisites := collectDependencyLoadItems ctx
      noPrerequisites := collectIndexItems ctx fun _ node =>
        (Informal.Graph.eraseDups (Informal.Graph.allDeps node)).size == 0
      noDependents := collectIndexItems ctx fun label _ =>
        (ctx.usageMap.getD label {}).directUses == 0
      proofDebtHotspots := collectProofDebtHotspots ctx
      quickWins := topPriorities.filter priorityItemIsQuickWin
      ownerRollups := collectOwnerRollups ctx
      tagRollups := collectTagRollups ctx
      linkedPrs := metadataAudit.sortedLinkedPrs
      missingOwners := metadataAudit.sortedMissingOwners
      missingEffort := metadataAudit.sortedMissingEffort
      untaggedEntries := metadataAudit.sortedUntaggedEntries
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

def summaryAssetBundle : BlueprintAssetBundle :=
  previewPanelInlinePreviewAssetBundle (cssExtras := [summaryCss])

open Verso Doc Html Genre Manual
open Verso.Output.Html
open Verso.Multi (AllRemotes)

private abbrev SummaryHtmlM := HtmlT Manual (ReaderT AllRemotes (ReaderT ExtensionImpls IO))

private structure SummaryHtmlContext where
  entryHref? : Name → Option String
  declHref? : Name → Name → Option String
  previewLookupKey? : Name → Option String

private structure SummaryRows where
  pendingInformalRows : Array Output.Html := #[]
  sorryRows : Array Output.Html := #[]
  missingRows : Array Output.Html := #[]
  renderFailureRows : Array Output.Html := #[]
  topPriorityRows : Array Output.Html := #[]
  quickWinRows : Array Output.Html := #[]
  statementUsedItems : Array UsageItem := #[]
  proofUsedItems : Array UsageItem := #[]
  statementUsedRows : Array Output.Html := #[]
  proofUsedRows : Array Output.Html := #[]
  heaviestPrerequisiteRows : Array Output.Html := #[]
  noPrerequisiteRows : Array Output.Html := #[]
  noDependentRows : Array Output.Html := #[]
  proofDebtHotspotRows : Array Output.Html := #[]
  ownerRollupRows : Array Output.Html := #[]
  tagRollupRows : Array Output.Html := #[]
  linkedPrRows : Array Output.Html := #[]
  missingOwnerRows : Array Output.Html := #[]
  missingEffortRows : Array Output.Html := #[]
  untaggedRows : Array Output.Html := #[]
  groupHealthRows : Array Output.Html := #[]
  definitionRows : Array Output.Html := #[]
  theoremLikeRows : Array Output.Html := #[]
  axiomRows : Array Output.Html := #[]
  theoremLikeByParentRows : Array Output.Html := #[]
  blockerCount : Nat := 0
  blockerRows : Array Output.Html := #[]

private def summaryRenderLeanDeclLink (target : Name) (node : Output.Html)
    (href? : Option String) (linkTitle? : Option String := Option.none) : Output.Html :=
  match href? with
  | some href =>
    Informal.LeanCodeLink.renderResolved
      target node "" (some href) linkTitle?
      (previewTitle := Informal.LeanCodePreview.title target)
  | Option.none => node

private def SummaryHtmlContext.entryRef (ctx : SummaryHtmlContext) (label : Name) : Output.Html :=
  let previewLookupKey? := ctx.previewLookupKey? label
  let previewLabel? : Option Name := previewLookupKey?.map (fun _ => label)
  let labelNode : Output.Html :=
    match ctx.entryHref? label with
    | Option.some href => {{ <a href={{href}}> <code>s!"{label}"</code> </a> }}
    | Option.none => {{ <code>s!"{label}"</code> }}
  Informal.HoverRender.summaryPreviewWrap labelNode previewLabel? previewLookupKey?

private def SummaryHtmlContext.declItems (ctx : SummaryHtmlContext) (label : Name)
    (decls : List Name) : Array Output.Html :=
  decls.toArray.map fun decl =>
    let declNode := summaryRenderLeanDeclLink decl {{<code>s!"{decl}"</code>}} (ctx.declHref? label decl)
    {{ <li>{{declNode}}</li> }}

private def summaryBadgeClass : String := "bp_summary_badge"

private def summaryBadgeWarnClass : String :=
  s!"{summaryBadgeClass} bp_summary_badge_warn"

private def summaryBadgeErrorClass : String :=
  s!"{summaryBadgeClass} bp_summary_badge_error"

private def summaryBadge (text : String) (className : String := summaryBadgeClass) : Output.Html :=
  {{ <span class={{className}}>s!"{text}"</span> }}

private def summaryWarnBadge (text : String) : Output.Html :=
  summaryBadge text summaryBadgeWarnClass

private def summaryErrorBadge (text : String) : Output.Html :=
  summaryBadge text summaryBadgeErrorClass

private def summaryBadgeClassForStatus (status : Data.ProvedStatus) : String :=
  if status.isMissing then
    summaryBadgeErrorClass
  else if status.isIncomplete then
    summaryBadgeWarnClass
  else
    summaryBadgeClass

private def summaryBadgeRow (badges : Array Output.Html) : Output.Html :=
  if badges.isEmpty then
    .empty
  else
    {{ <div class="bp_summary_badge_row">{{badges}}</div> }}

private def summaryMetadataBadges (metadata : MetadataPresentation) : Array Output.Html :=
  metadata.summaryBadgeSpecs.map fun badge =>
    if badge.warning then
      summaryWarnBadge badge.text
    else
      summaryBadge badge.text

private def summaryMetadataActionLinks (metadata : MetadataPresentation) : Array Output.Html :=
  metadata.summaryActionLinks.map fun action =>
    {{ <a class="bp_code_link" href={{action.href}}>{{.text true action.label}}</a> }}

private def summaryActionLinksRow (actionLinks : Array Output.Html) : Output.Html :=
  if Array.isEmpty actionLinks then
    .empty
  else
    {{<div class="bp_summary_item_actions">"Links: " {{(actionLinks.toList.intersperse {{<span class="bp_summary_sep">" | "</span>}}).toArray}}</div>}}

private def summaryCardClass : String := "bp_summary_card"

private def summaryCardWarnClass : String :=
  s!"{summaryCardClass} bp_summary_card_warn"

private def summaryCard (label value : String) (status? : Option String := Option.none)
    (className : String := summaryCardClass) : Output.Html :=
  let statusNode : Output.Html :=
    match status? with
    | Option.some status => {{<span class="bp_summary_status">{{.text true status}}</span>}}
    | Option.none => .empty
  {{ <div class={{className}}>
      <span class="bp_summary_label">{{.text true label}}</span>
      <span class="bp_summary_value">{{.text true value}}</span>
      {{statusNode}}
    </div> }}

private def summaryOptionalCard (visible : Bool) (label value : String)
    (status? : Option String := Option.none) (className : String := summaryCardClass) :
    Output.Html :=
  if visible then
    summaryCard label value status? className
  else
    .empty

private def summaryWarnCard (label value : String) (status? : Option String := Option.none) :
    Output.Html :=
  summaryCard label value status? summaryCardWarnClass

private def summaryOptionalWarnCard (visible : Bool) (label value : String)
    (status? : Option String := Option.none) : Output.Html :=
  if visible then
    summaryWarnCard label value status?
  else
    .empty

private def summaryCapRows (rows : Array Output.Html) (noun : String) : Array Output.Html :=
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

private def summaryDetailsList (title : String) (rows : Array Output.Html)
    (className : String := "bp_summary_subsection") (open? : Bool := false) : Output.Html :=
  let attrs :=
    if open? then
      #[("class", className), ("open", "open")]
    else
      #[("class", className)]
  {{ <details {{attrs}}>
      <summary>{{.text true title}}</summary>
      <ul class="bp_summary_list">
        {{rows}}
      </ul>
    </details> }}

private def summarySection (title : String) (content : Output.Html)
    (open? : Bool := false) : Output.Html :=
  let attrs :=
    if open? then
      #[("class", "bp_summary_section"), ("open", "open")]
    else
      #[("class", "bp_summary_section")]
  {{ <details {{attrs}}>
      <summary>{{.text true title}}</summary>
      {{content}}
    </details> }}

private def summaryOptionalDetailsList (visible : Bool) (title : String) (rows : Array Output.Html)
    (className : String := "bp_summary_subsection") (open? : Bool := false) : Output.Html :=
  if visible then
    summaryDetailsList title rows className open?
  else
    .empty

private def summaryCappedDetailsList (title : String) (rows : Array Output.Html) (noun : String)
    (className : String := "bp_summary_subsection") (open? : Bool := false) : Output.Html :=
  summaryDetailsList title (summaryCapRows rows noun) className open?

private def summaryOptionalCappedDetailsList (visible : Bool) (title : String)
    (rows : Array Output.Html) (noun : String) (className : String := "bp_summary_subsection")
    (open? : Bool := false) : Output.Html :=
  if visible then
    summaryCappedDetailsList title rows noun className open?
  else
    .empty

private def summaryItemTop (head : Output.Html) (meta? : Option Output.Html) : Output.Html :=
  let metaNode :=
    match meta? with
    | Option.some metaHtml => {{<span class="bp_summary_item_meta">{{metaHtml}}</span>}}
    | Option.none => .empty
  {{ <div class="bp_summary_item_top">
      <span class="bp_summary_item_head">{{head}}</span>
      {{metaNode}}
    </div> }}

private def summaryItemBody (body : Output.Html) : Output.Html :=
  {{ <div class="bp_summary_item_body">{{body}}</div> }}

private def summaryItemTextBody (text : String) : Output.Html :=
  summaryItemBody (.text true text)

private def summaryItemActions (body : Output.Html) : Output.Html :=
  {{ <div class="bp_summary_item_actions">{{body}}</div> }}

private def summaryItemShell
    (head : Output.Html) (meta? : Option Output.Html)
    (body : Output.Html) (badges : Array Output.Html) (extra : Array Output.Html) : Output.Html :=
  {{ <li class="bp_summary_item">
      {{summaryItemTop head meta?}}
      {{body}}
      {{summaryBadgeRow badges}}
      {{extra}}
    </li> }}

private def SummaryHtmlContext.associatedDecls (ctx : SummaryHtmlContext) (label : Name)
    (leanObjects : List Name) : Output.Html :=
  if leanObjects.isEmpty then
    .empty
  else
    {{<details class="bp_summary_decls"><summary>s!"Associated lean decls ({leanObjects.length})"</summary><ul class="bp_summary_decl_list">{{ctx.declItems label leanObjects}}</ul></details>}}

private def SummaryHtmlContext.leanRow (ctx : SummaryHtmlContext) (label : Name) (kind : String)
    (leanObjects : List Name) : Output.Html :=
  let entryRef := ctx.entryRef label
  summaryItemShell entryRef (some (.text true s!"({kind})"))
    .empty #[] #[ctx.associatedDecls label leanObjects]

private def SummaryHtmlContext.leanRows (ctx : SummaryHtmlContext) (items : List IndexItem) :
    Array Output.Html :=
  items.toArray.map fun item => ctx.leanRow item.label item.kind item.leanObjects

private def SummaryHtmlContext.sorryRow (ctx : SummaryHtmlContext) (item : SorryItem) :
    SummaryHtmlM Output.Html := do
  let entryRef := ctx.entryRef item.label
  let declLink :=
    summaryRenderLeanDeclLink item.decl {{<code>s!"{item.decl}"</code>}} (ctx.declHref? item.label item.decl)
  let view := item.status.presentation
  let declPrefix ←
    match item.status with
    | .missing => pure "Missing declaration: "
    | .axiomLike => pure "Axiom-like declaration: "
    | .containsSorry _ => pure "Declaration with sorry: "
    | .proved =>
      Verso.reportError s!"Unexpected proved status in summary sorry details for {item.decl}"
      pure "Declaration: "
  let refsTxt :=
    match item.status with
    | .containsSorry _ =>
      let (typeSorryRefs, proofSorryRefs) := item.status.sorryRefCounts
      let sorryRefs := typeSorryRefs + proofSorryRefs
      if sorryRefs > 0 then toString sorryRefs else "unknown"
    | .proved => "0"
    | _ => "n/a"
  let statusLabel :=
    if item.status.isProved then
      item.status.statusLabel
    else
      view.externalHeaderText
  let whereTxt :=
    if item.status.isProved then
      item.status.statusLabel
    else
      item.status.sorryLocationText
  let badgeClass := summaryBadgeClassForStatus item.status
  let body := {{
    <div class="bp_summary_item_body">
      {{.text true declPrefix}} {{declLink}} " "
      <span class={{badgeClass}}>
        s!"[{if item.isTheorem then "theorem/lemma" else "definition"}; {statusLabel}; {whereTxt}; refs: {refsTxt}]"
      </span>
    </div>
  }}
  pure <| summaryItemShell entryRef (some (.text true s!"({item.kind})")) body #[] #[]

private def SummaryHtmlContext.externalDeclNode (ctx : SummaryHtmlContext) (label written canonical : Name) :
    Output.Html :=
  let canonicalNode : Output.Html :=
    summaryRenderLeanDeclLink
      canonical
      {{<code>s!"{canonical}"</code>}}
      (ctx.declHref? label canonical)
  if written == canonical then
    canonicalNode
  else
    {{ <span> <code>s!"{written}"</code> " (resolved as " {{canonicalNode}} ")" </span> }}

private def SummaryHtmlContext.externalDeclIssueRow (ctx : SummaryHtmlContext) (label : Name)
    (kind : String) (written canonical : Name) (bodyPrefix : String) (badge : Output.Html)
    (actions : Output.Html := .empty) : Output.Html :=
  let entryRef := ctx.entryRef label
  let declNode := ctx.externalDeclNode label written canonical
  let body := {{
    <div class="bp_summary_item_body">
        {{.text true bodyPrefix}} {{declNode}} " "
        {{badge}}
    </div>
  }}
  summaryItemShell entryRef (some (.text true s!"({kind})")) body #[] #[actions]

private def SummaryHtmlContext.missingRow (ctx : SummaryHtmlContext) (item : MissingLeanDeclItem) :
    Output.Html :=
  ctx.externalDeclIssueRow item.label item.kind item.written item.canonical
    "Missing external Lean declaration: " (summaryErrorBadge "[missing declaration]")

private def SummaryHtmlContext.renderFailureRow (ctx : SummaryHtmlContext) (item : RenderFailureItem) :
    Output.Html :=
  ctx.externalDeclIssueRow item.label item.kind item.written item.canonical
    "External render failed for " (summaryWarnBadge "[render failure]")
    (summaryItemActions {{<code>{{.text true item.message}}</code>}})

private def SummaryHtmlContext.priorityRow (ctx : SummaryHtmlContext) (item : PriorityItem) :
    Output.Html :=
  let entryRef := ctx.entryRef item.label
  let metadata := metadataPresentationOfPriorityItem item
  let metadataBadges := summaryMetadataBadges metadata
  let proofBadges : Array Output.Html :=
    if item.proofStatus.isEmpty then
      #[]
    else
      #[summaryBadge s!"proof: {item.proofStatus}"]
  let actionLinks := summaryMetadataActionLinks metadata
  let badges :=
    metadataBadges ++ #[
      summaryBadge s!"stage: {item.stage}",
      summaryBadge s!"statement: {item.statementStatus}",
      summaryBadge s!"direct uses: {item.directUses}",
      summaryBadge s!"downstream unlocks: {item.downstreamUses}"
    ] ++ proofBadges
  summaryItemShell entryRef (some (.text true s!"({item.kind})"))
    (summaryItemTextBody s!"Ready for {item.stage} work.")
    badges
    #[ctx.associatedDecls item.label item.leanObjects, summaryActionLinksRow actionLinks]

private def SummaryHtmlContext.usageRow (ctx : SummaryHtmlContext) (item : UsageItem)
    (bodyText primaryLabel secondaryLabel : String) (primaryCount secondaryCount : Nat) : Output.Html :=
  let entryRef := ctx.entryRef item.label
  let badges :=
    #[
      summaryWarnBadge s!"{primaryLabel}: {primaryCount}",
      summaryBadge s!"{secondaryLabel}: {secondaryCount}",
      summaryBadge s!"direct uses: {item.directUses}",
      summaryBadge s!"downstream unlocks: {item.downstreamUses}"
    ]
  summaryItemShell entryRef (some (.text true s!"({item.kind})"))
    (summaryItemTextBody bodyText)
    badges
    #[ctx.associatedDecls item.label item.leanObjects]

private def SummaryHtmlContext.dependencyLoadRow (ctx : SummaryHtmlContext)
    (item : DependencyLoadItem) : Output.Html :=
  let entryRef := ctx.entryRef item.label
  let badges :=
    #[
      summaryWarnBadge s!"total deps: {item.totalDeps}",
      summaryBadge s!"statement deps: {item.statementDeps}",
      summaryBadge s!"proof deps: {item.proofDeps}",
      summaryBadge s!"direct uses: {item.directUses}",
      summaryBadge s!"downstream unlocks: {item.downstreamUses}"
    ]
  summaryItemShell entryRef (some (.text true s!"({item.kind})"))
    (summaryItemTextBody "Prerequisite fan-in measured from the current statement/proof dependency graph.")
    badges
    #[ctx.associatedDecls item.label item.leanObjects]

private def summaryProofDebtHotspotRow (item : DebtHotspotItem) : Output.Html :=
  let badges :=
    #[
      summaryWarnBadge s!"affected entries: {item.affectedEntries}",
      summaryBadge s!"incomplete decls: {item.incompleteDecls}",
      summaryBadge s!"missing decls: {item.missingDecls}",
      summaryBadge s!"total debt: {item.totalDebt}"
    ]
  summaryItemShell
    (.text true item.header)
    (some {{<code>s!"{item.parent}"</code>}})
    (summaryItemTextBody "Grouped proof/code debt derived from the current incomplete-declaration snapshots.")
    badges
    #[]

private def summaryRollupBadges (totalEntries actionableEntries quickWins linkedPrs : Nat) :
    Array Output.Html :=
  #[
    summaryBadge s!"entries: {totalEntries}",
    summaryWarnBadge s!"actionable: {actionableEntries}",
    summaryBadge s!"quick wins: {quickWins}",
    summaryBadge s!"linked PRs: {linkedPrs}"
  ]

private def summaryOwnerRollupRow (item : OwnerRollupItem) : Output.Html :=
  let badges :=
    summaryRollupBadges item.totalEntries item.actionableEntries item.quickWins item.linkedPrs
  summaryItemShell
    (.text true item.displayName)
    (some {{<code>s!"{item.owner}"</code>}})
    .empty
    badges
    #[]

private def summaryTagRollupRow (item : TagRollupItem) : Output.Html :=
  let badges :=
    summaryRollupBadges item.totalEntries item.actionableEntries item.quickWins item.linkedPrs
  summaryItemShell
    (summaryWarnBadge s!"tag: {item.tag}")
    Option.none
    .empty
    badges
    #[]

private def SummaryHtmlContext.metadataEntryRow (ctx : SummaryHtmlContext) (item : MetadataEntryItem)
    (bodyText : String) : Output.Html :=
  let entryRef := ctx.entryRef item.label
  let metadata := metadataPresentationOfMetadataEntryItem item
  let badges := summaryMetadataBadges metadata
  let actionLinks := summaryMetadataActionLinks metadata
  summaryItemShell entryRef (some (.text true s!"({item.kind})"))
    (summaryItemTextBody bodyText)
    badges
    #[ctx.associatedDecls item.label item.leanObjects, summaryActionLinksRow actionLinks]

private def SummaryHtmlContext.metadataEntryRows (ctx : SummaryHtmlContext)
    (items : List MetadataEntryItem) (bodyText : String) : Array Output.Html :=
  items.toArray.map fun item => ctx.metadataEntryRow item bodyText

private def SummaryHtmlContext.groupHealthRow (ctx : SummaryHtmlContext) (item : GroupHealthItem) :
    Output.Html :=
  let badges :=
    #[
      summaryBadge s!"total: {item.totalEntries}",
      summaryBadge s!"closed: {item.closedEntries}",
      summaryBadge s!"local-only: {item.localOnlyEntries}",
      summaryWarnBadge s!"ready: {item.readyEntries}",
      summaryBadge s!"blocked: {item.blockedEntries}",
      summaryBadge s!"incomplete Lean: {item.incompleteLeanEntries}",
      summaryBadge s!"unlock score: {item.unlockScore}"
    ]
  match item.nextPriority? with
  | Option.none =>
    summaryItemShell
      (.text true item.header)
      (some {{<code>s!"{item.parent}"</code>}})
      (summaryItemTextBody "Grouped view over entries sharing the same parent.")
      badges
      #[summaryItemActions (.text true "Next: no ready child currently unlocks downstream work.")]
  | Option.some next =>
    let nextRef := ctx.entryRef next.label
    let priorityBadges : Array Output.Html :=
      match next.priority with
      | Option.some priority => #[summaryWarnBadge s!"priority: {priority}"]
      | Option.none => #[]
    summaryItemShell
      (.text true item.header)
      (some {{<code>s!"{item.parent}"</code>}})
      (summaryItemTextBody "Grouped view over entries sharing the same parent.")
      badges
      #[summaryItemActions {{
          "Next: " {{nextRef}} " "
          {{priorityBadges ++ #[
            summaryBadge s!"stage: {next.stage}",
            summaryBadge s!"downstream unlocks: {next.downstreamUses}"
          ]}}
        }}]

private def SummaryHtmlContext.theoremLikeParentGroup (ctx : SummaryHtmlContext)
    (group : ParentTheoremGroup) : Output.Html :=
  let rows := ctx.leanRows group.entries
  {{ <details class="bp_summary_subsection">
      <summary>s!"{group.header} ({group.entries.length})"</summary>
      <ul class="bp_summary_list">
        {{if rows.isEmpty then {{<li class="bp_summary_empty">"No theorem/proposition/lemma/corollary entries in this parent group."</li>}} else rows}}
      </ul>
    </details> }}

-- Keep the large summary renderer in small top-level pieces; compiling it as
-- one generated `block_extension` descriptor is disproportionately expensive.
private def SummaryRows.withOverviewRows
    (rows : SummaryRows) (ctx : SummaryHtmlContext) (data : Summary) : SummaryHtmlM SummaryRows := do
  let pendingInformalRows := ctx.leanRows data.pendingInformalEntries
  let sorryRows ← data.sorryDetails.toArray.mapM ctx.sorryRow
  let missingRows := data.missingLeanDecls.toArray.map ctx.missingRow
  let topPriorityRows := data.topPriorities.toArray.map ctx.priorityRow
  let quickWinRows := data.quickWins.toArray.map ctx.priorityRow
  let blockerCount := data.missingLeanDecls.length + data.sorryDetails.length
  let blockerRows := missingRows ++ sorryRows
  pure {
    rows with
    pendingInformalRows
    sorryRows
    missingRows
    topPriorityRows
    quickWinRows
    blockerCount
    blockerRows
  }

private def SummaryRows.withDependencyRows
    (rows : SummaryRows) (ctx : SummaryHtmlContext) (data : Summary) : SummaryRows :=
  let statementUsedItems :=
    sortUsageItemsByAxis
      (data.mostUsed.toArray.filter fun item => item.statementUses > 0)
      (fun item => item.statementUses)
  let proofUsedItems :=
    sortUsageItemsByAxis
      (data.mostUsed.toArray.filter fun item => item.proofUses > 0)
      (fun item => item.proofUses)
  let statementUsedRows :=
    statementUsedItems.map fun item =>
      ctx.usageRow item
        "Reverse dependencies recorded in statement dependencies."
        "statement uses"
        "proof uses"
        item.statementUses
        item.proofUses
  let proofUsedRows :=
    proofUsedItems.map fun item =>
      ctx.usageRow item
        "Reverse dependencies recorded in proof dependencies."
        "proof uses"
        "statement uses"
        item.proofUses
        item.statementUses
  let groupHealthRows := data.groupHealth.toArray.map ctx.groupHealthRow
  {
    rows with
    statementUsedItems
    proofUsedItems
    statementUsedRows
    proofUsedRows
    groupHealthRows
  }

private def SummaryRows.withStructureRows
    (rows : SummaryRows) (ctx : SummaryHtmlContext) (data : Summary) : SummaryRows :=
  let heaviestPrerequisiteRows := data.heaviestPrerequisites.toArray.map ctx.dependencyLoadRow
  let noPrerequisiteRows := ctx.leanRows data.noPrerequisites
  let noDependentRows := ctx.leanRows data.noDependents
  let proofDebtHotspotRows := data.proofDebtHotspots.toArray.map summaryProofDebtHotspotRow
  {
    rows with
    heaviestPrerequisiteRows
    noPrerequisiteRows
    noDependentRows
    proofDebtHotspotRows
  }

private def SummaryRows.withMetadataRows
    (rows : SummaryRows) (ctx : SummaryHtmlContext) (data : Summary) : SummaryRows :=
  let ownerRollupRows := data.ownerRollups.toArray.map summaryOwnerRollupRow
  let tagRollupRows := data.tagRollups.toArray.map summaryTagRollupRow
  let linkedPrRows := ctx.metadataEntryRows data.linkedPrs "Entry already linked to a review PR."
  let missingOwnerRows := ctx.metadataEntryRows data.missingOwners "Missing owner metadata."
  let missingEffortRows := ctx.metadataEntryRows data.missingEffort "Missing effort metadata."
  let untaggedRows := ctx.metadataEntryRows data.untaggedEntries "Missing tag metadata."
  {
    rows with
    ownerRollupRows
    tagRollupRows
    linkedPrRows
    missingOwnerRows
    missingEffortRows
    untaggedRows
  }

private def SummaryRows.withIndexRows
    (rows : SummaryRows) (ctx : SummaryHtmlContext) (data : Summary) : SummaryRows :=
  let definitionRows := ctx.leanRows data.definitionIndex
  let theoremLikeRows := ctx.leanRows data.theoremLikeIndex
  let axiomRows := ctx.leanRows data.axiomIndex
  let theoremLikeByParentRows := data.theoremLikeByParent.toArray.map ctx.theoremLikeParentGroup
  {
    rows with
    definitionRows
    theoremLikeRows
    axiomRows
    theoremLikeByParentRows
  }

private def SummaryRows.withDiagnosticsRows
    (rows : SummaryRows) (ctx : SummaryHtmlContext) (data : Summary) : SummaryRows :=
  let renderFailureRows := data.renderFailures.toArray.map ctx.renderFailureRow
  { rows with renderFailureRows }

private def SummaryRows.render (ctx : SummaryHtmlContext) (data : Summary) : SummaryHtmlM SummaryRows := do
  let rows ← ({} : SummaryRows).withOverviewRows ctx data
  let rows := rows.withDependencyRows ctx data
  let rows := rows.withMetadataRows ctx data
  let rows := rows.withDiagnosticsRows ctx data
  let rows := rows.withStructureRows ctx data
  let rows := rows.withIndexRows ctx data
  pure rows

private def summaryOverviewSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  let showBlockers := rows.blockerCount > 0
  let showPendingInformal := !rows.pendingInformalRows.isEmpty
  let showQuickWins := !rows.quickWinRows.isEmpty
  summarySection "Overview" {{
      <div class="bp_summary_grid">
        {{summaryCard "Total entries" (toString data.totalEntries) (Option.some (statusCountsText data.totalStatus))}}
        {{summaryCard
            "Ready now"
            (toString data.coverageSplit.readyToFormalize)
            (Option.some "Entries whose next formalization step is currently unblocked.")}}
        {{summaryCard
            "Fully closed"
            (toString data.coverageSplit.fullyClosed)
            (Option.some "Local code and prerequisite closure are both complete.")}}
        {{summaryCard
            "Actionable priorities"
            (toString data.topPriorities.length)
            (Option.some "Entries ready now and already unlocking downstream work.")}}
        {{summaryOptionalWarnCard
            showBlockers
            "Current blockers"
            (toString rows.blockerCount)
            (Option.some "Missing external or incomplete Lean declarations.")}}
        {{summaryOptionalCard
            showPendingInformal
            "Missing informal coverage"
            (toString data.pendingInformalEntries.length)
            (Option.some "Entries with Lean code but missing an informal statement or proof block.")}}
        {{summaryOptionalCard
            showQuickWins
            "Quick wins"
            (toString data.quickWins.length)
            (Option.some "Actionable entries with `high` priority and `small` effort.")}}
      </div>
      {{if data.totalEntries == 0 then
          {{<p class="bp_summary_empty">"No blueprint entries were registered in the current document."</p>}}
        else .empty}}
      {{summaryOptionalCappedDetailsList
          (!rows.topPriorityRows.isEmpty)
          s!"Ready next ({data.topPriorities.length})"
          rows.topPriorityRows
          "priorities"
          "bp_summary_subsection"
          true}}
      {{summaryOptionalDetailsList
          showBlockers
          s!"Current blockers ({rows.blockerCount})"
          rows.blockerRows
          "bp_summary_subsection bp_summary_subsection_warn"
          true}}
      {{summaryOptionalDetailsList
          showPendingInformal
          s!"Missing informal coverage ({data.pendingInformalEntries.length})"
          rows.pendingInformalRows}}
    }} true

private def summaryEntryIndexSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  let showDefinitionCard := data.definitions > 0
  let showPropositionCard := data.propositions > 0
  let showLemmaCard := data.lemmas > 0
  let showTheoremCard := data.theorems > 0
  let showCorollaryCard := data.corollaries > 0
  let showAxiomCard := data.axioms > 0
  let showLeanOnlyCard := data.leanOnlyEntries > 0
  let showInformalOnlyCard := data.informalOnlyEntries > 0
  let showDefinitionIndex := !rows.definitionRows.isEmpty
  let showTheoremLikeIndex := !rows.theoremLikeRows.isEmpty
  let showAxiomIndex := !rows.axiomRows.isEmpty
  let showTheoremLikeByParent := !rows.theoremLikeByParentRows.isEmpty
  if !(showDefinitionIndex || showTheoremLikeIndex || showAxiomIndex) then
    .empty
  else
    summarySection s!"Entry index ({data.totalEntries})" {{
        <div class="bp_summary_grid">
          {{summaryOptionalCard
              showDefinitionCard
              "Definitions"
              (toString data.definitions)
              (Option.some (statusCountsText data.definitionStatus))}}
          {{summaryOptionalCard
              showPropositionCard
              "Propositions"
              (toString data.propositions)
              (Option.some (statusCountsText data.propositionStatus))}}
          {{summaryOptionalCard showLemmaCard "Lemmas" (toString data.lemmas) (Option.some (statusCountsText data.lemmaStatus))}}
          {{summaryOptionalCard showTheoremCard "Theorems" (toString data.theorems) (Option.some (statusCountsText data.theoremStatus))}}
          {{summaryOptionalCard
              showCorollaryCard
              "Corollaries"
              (toString data.corollaries)
              (Option.some (statusCountsText data.corollaryStatus))}}
          {{summaryOptionalWarnCard
              showAxiomCard
              "Axiom-like entries"
              (toString data.axioms)
              (Option.some (statusCountsText data.axiomStatus))}}
          {{summaryOptionalCard showLeanOnlyCard "Lean-only entries" (toString data.leanOnlyEntries)}}
          {{summaryOptionalCard showInformalOnlyCard "Informal-only entries" (toString data.informalOnlyEntries)}}
        </div>
        {{summaryOptionalDetailsList showDefinitionIndex s!"Definition Index ({data.definitionIndex.length})" rows.definitionRows}}
        {{if showTheoremLikeIndex then
            {{<details class="bp_summary_subsection">
              <summary>s!"Theorem / Proposition / Lemma / Corollary Index ({data.theoremLikeIndex.length})"</summary>
              <ul class="bp_summary_list">
                {{rows.theoremLikeRows}}
              </ul>
              {{if showTheoremLikeByParent then
                  {{<details class="bp_summary_nested">
                    <summary>s!"By parent groups ({data.theoremLikeByParent.length})"</summary>
                    {{rows.theoremLikeByParentRows}}
                  </details>}}
                else .empty}}
            </details>}}
        else .empty}}
        {{summaryOptionalDetailsList
            showAxiomIndex
            s!"Axiom-like Index ({data.axiomIndex.length})"
            rows.axiomRows
            "bp_summary_subsection bp_summary_subsection_warn"}}
      }}

private def summaryDependencyInsightsSection (rows : SummaryRows) : Output.Html :=
  if rows.statementUsedRows.isEmpty && rows.proofUsedRows.isEmpty && rows.groupHealthRows.isEmpty then
    .empty
  else
    summarySection "Dependency insights" {{
        <div class="bp_summary_grid">
          {{summaryOptionalCard
              (!rows.statementUsedRows.isEmpty)
              "Statement-used entries"
              (toString rows.statementUsedItems.size)
              (Option.some "Entries reused in statement dependencies.")}}
          {{summaryOptionalCard
              (!rows.proofUsedRows.isEmpty)
              "Proof-used entries"
              (toString rows.proofUsedItems.size)
              (Option.some "Entries reused in proof-only dependencies.")}}
          {{summaryOptionalCard
              (!rows.groupHealthRows.isEmpty)
              "Tracked parent groups"
              (toString rows.groupHealthRows.size)
              (Option.some "Grouped health rollups for parents with more than one child entry.")}}
        </div>
        {{summaryOptionalCappedDetailsList
            (!rows.statementUsedRows.isEmpty)
            s!"Most used in statements ({rows.statementUsedItems.size})"
            rows.statementUsedRows
            "statement-used entries"}}
        {{summaryOptionalCappedDetailsList
            (!rows.proofUsedRows.isEmpty)
            s!"Most used in proofs ({rows.proofUsedItems.size})"
            rows.proofUsedRows
            "proof-used entries"}}
        {{summaryOptionalCappedDetailsList
            (!rows.groupHealthRows.isEmpty)
            s!"Group health ({rows.groupHealthRows.size})"
            rows.groupHealthRows
            "groups"}}
      }}

private def summaryMetadataSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  let showQuickWins := !rows.quickWinRows.isEmpty
  let showOwnerRollups := !rows.ownerRollupRows.isEmpty
  let showTagRollups := !rows.tagRollupRows.isEmpty
  let showLinkedPrs := !rows.linkedPrRows.isEmpty
  let showMetadataAudit :=
    !rows.missingOwnerRows.isEmpty || !rows.missingEffortRows.isEmpty || !rows.untaggedRows.isEmpty
  let showMetadataCards := showQuickWins || showOwnerRollups || showTagRollups || showLinkedPrs
  if !(showMetadataCards || showMetadataAudit) then
    .empty
  else
    summarySection "Metadata" {{
        {{if showMetadataCards then
            {{<div class="bp_summary_grid">
              {{summaryOptionalCard
                  showQuickWins
                  "Quick wins"
                  (toString data.quickWins.length)
                  (Option.some "Actionable entries with `high` priority and `small` effort.")}}
              {{summaryOptionalCard
                  showOwnerRollups
                  "Owners in use"
                  (toString data.ownerRollups.length)
                  (Option.some "Distinct owners referenced by the current blueprint entries.")}}
              {{summaryOptionalCard
                  showTagRollups
                  "Tags in use"
                  (toString data.tagRollups.length)
                  (Option.some "Distinct tags currently attached to blueprint entries.")}}
              {{summaryOptionalCard
                  showLinkedPrs
                  "Linked PRs"
                  (toString data.linkedPrs.length)
                  (Option.some "Entries already linked to a review URL.")}}
            </div>}}
          else .empty}}
        {{summaryOptionalCappedDetailsList
            showQuickWins
            s!"Quick wins ({data.quickWins.length})"
            rows.quickWinRows
            "quick wins"}}
        {{summaryOptionalCappedDetailsList
            showOwnerRollups
            s!"Owner rollups ({data.ownerRollups.length})"
            rows.ownerRollupRows
            "owners"}}
        {{summaryOptionalCappedDetailsList
            showTagRollups
            s!"Tag rollups ({data.tagRollups.length})"
            rows.tagRollupRows
            "tags"}}
        {{summaryOptionalCappedDetailsList
            showLinkedPrs
            s!"Linked PRs ({data.linkedPrs.length})"
            rows.linkedPrRows
            "linked PR entries"}}
        {{if showMetadataAudit then
            {{<details class="bp_summary_subsection bp_summary_subsection_warn">
              <summary>"Metadata audit"</summary>
              <div class="bp_summary_grid">
                {{summaryOptionalWarnCard
                    (!rows.missingOwnerRows.isEmpty)
                    "Missing owner"
                    (toString data.missingOwners.length)}}
                {{summaryOptionalWarnCard
                    (!rows.missingEffortRows.isEmpty)
                    "Missing effort"
                    (toString data.missingEffort.length)}}
                {{summaryOptionalWarnCard
                    (!rows.untaggedRows.isEmpty)
                    "Untagged"
                    (toString data.untaggedEntries.length)}}
              </div>
              {{summaryOptionalCappedDetailsList
                  (!rows.missingOwnerRows.isEmpty)
                  s!"Missing owner ({data.missingOwners.length})"
                  rows.missingOwnerRows
                  "entries missing owner"
                  "bp_summary_nested"}}
              {{summaryOptionalCappedDetailsList
                  (!rows.missingEffortRows.isEmpty)
                  s!"Missing effort ({data.missingEffort.length})"
                  rows.missingEffortRows
                  "entries missing effort"
                  "bp_summary_nested"}}
              {{summaryOptionalCappedDetailsList
                  (!rows.untaggedRows.isEmpty)
                  s!"Untagged ({data.untaggedEntries.length})"
                  rows.untaggedRows
                  "untagged entries"
                  "bp_summary_nested"}}
            </details>}}
          else .empty}}
      }}

private def summaryDiagnosticsSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  if !(data.showDebugDiagnostics && !rows.renderFailureRows.isEmpty) then
    .empty
  else
    summarySection "Maintainer diagnostics" {{
        <div class="bp_summary_grid">
          {{summaryWarnCard
              "Render failures"
              (toString data.renderFailures.length)
              (Option.some "External declarations that checked in Lean but failed HTML rendering.")}}
        </div>
        {{summaryCappedDetailsList
            s!"Render failures ({data.renderFailures.length})"
            rows.renderFailureRows
            "render-failure entries"
            "bp_summary_subsection bp_summary_subsection_warn"}}
      }}

private def summaryStructureSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  let showHeaviestPrerequisites := !rows.heaviestPrerequisiteRows.isEmpty
  let showNoPrerequisites := !rows.noPrerequisiteRows.isEmpty
  let showNoDependents := !rows.noDependentRows.isEmpty
  let showProofDebtHotspots := !rows.proofDebtHotspotRows.isEmpty
  let showStructureCards :=
    data.coverageSplit.informalOnly > 0 ||
    data.coverageSplit.readyToFormalize > 0 ||
    data.coverageSplit.formalizedWithoutAncestors > 0 ||
    data.coverageSplit.fullyClosed > 0 ||
    data.coverageSplit.blockedOrIncomplete > 0
  if !(showStructureCards || showHeaviestPrerequisites || showNoPrerequisites ||
      showNoDependents || showProofDebtHotspots) then
    .empty
  else
    summarySection "Structure and coverage" {{
        <div class="bp_summary_grid">
          {{summaryOptionalCard
              (data.coverageSplit.informalOnly > 0)
              "Informal-only"
              (toString data.coverageSplit.informalOnly)
              (Option.some "Statements with no associated Lean code yet.")}}
          {{summaryOptionalCard
              (data.coverageSplit.readyToFormalize > 0)
              "Ready to formalize"
              (toString data.coverageSplit.readyToFormalize)
              (Option.some "Entries whose next step is currently unblocked.")}}
          {{summaryOptionalCard
              (data.coverageSplit.formalizedWithoutAncestors > 0)
              "Formalized, ancestors open"
              (toString data.coverageSplit.formalizedWithoutAncestors)
              (Option.some "Local Lean work is done, but prerequisite closure is still open.")}}
          {{summaryOptionalCard
              (data.coverageSplit.fullyClosed > 0)
              "Fully closed"
              (toString data.coverageSplit.fullyClosed)
              (Option.some "Local code and ancestor closure are both complete.")}}
          {{summaryOptionalWarnCard
              (data.coverageSplit.blockedOrIncomplete > 0)
              "Blocked or incomplete"
              (toString data.coverageSplit.blockedOrIncomplete)
              (Option.some "Entries not covered by the highlighted readiness buckets above.")}}
        </div>
        {{summaryOptionalCappedDetailsList
            showHeaviestPrerequisites
            s!"Heaviest prerequisites ({data.heaviestPrerequisites.length})"
            rows.heaviestPrerequisiteRows
            "heaviest-prerequisite entries"}}
        {{summaryOptionalCappedDetailsList
            showNoPrerequisites
            s!"No prerequisites ({data.noPrerequisites.length})"
            rows.noPrerequisiteRows
            "entries without prerequisites"}}
        {{summaryOptionalCappedDetailsList
            showNoDependents
            s!"No dependents ({data.noDependents.length})"
            rows.noDependentRows
            "entries without dependents"}}
        {{summaryOptionalCappedDetailsList
            showProofDebtHotspots
            s!"Proof debt hotspots ({data.proofDebtHotspots.length})"
            rows.proofDebtHotspotRows
            "proof-debt hotspots"
            "bp_summary_subsection bp_summary_subsection_warn"}}
      }}

private def summaryBlockToHtml : BlockToHtml Manual (ReaderT AllRemotes (ReaderT ExtensionImpls IO)) :=
  fun _goI _goB _id json _blocks => do
    let some data ←
        Informal.ExtensionDecode.decode?
          (α := Summary)
          json
          (fun err => s!"Malformed data in Block.summary.toHtml ({err})")
      | pure .empty
    let s ← HtmlT.state
    let previewLookupKeys := (data.previewLabels).foldl (init := ({} : Lean.NameMap String)) fun keys label =>
      match Informal.PreviewSource.traversalSelection? s label with
      | some selection => keys.insert label selection.key
      | Option.none =>
        match Informal.PreviewSource.traversalExternalMarkupLookupKey? s label with
        | some key => keys.insert label key
        | Option.none => keys
    let ctx : SummaryHtmlContext := {
      entryHref? := fun label => Informal.TraversalIndex.Nodes.href? s label
      declHref? := fun label decl =>
        Resolve.resolveInformalDeclHref? s label decl
      previewLookupKey? := fun label => previewLookupKeys.get? label
    }
    let previewPanel := Informal.HoverRender.summaryPreviewPanel
    let summaryAttrs :=
      #[("class", "bp_summary")] ++
        Informal.HoverRender.templatePreviewDescriptorAttrs
          ".bp_summary_preview_panel"
          "template.bp_summary_preview_tpl[data-bp-preview-label]"
          ".bp_summary_preview_wrap_active[data-bp-preview-label]"
          ".bp_summary_preview_panel_title"
          ".bp_summary_preview_panel_body"
          ".bp_summary_preview_panel_close"
          (allowHtmlCache := true)
    let rows ← SummaryRows.render ctx data
    pure {{
      <div {{summaryAttrs}}>
        {{previewPanel}}
        {{summaryOverviewSection data rows}}
        {{summaryEntryIndexSection data rows}}
        {{summaryDependencyInsightsSection rows}}
        {{summaryMetadataSection data rows}}
        {{summaryDiagnosticsSection data rows}}
        {{summaryStructureSection data rows}}
      </div>
    }}

open Verso Doc Elab Genre Manual in
block_extension Block.summary (summary : Summary) where
  data := toJson summary
  usePackages := Informal.TeX.standardMathUsePackages
  traverse _id _data _contents := do
    return none
  toTeX :=
    open Verso.Output.TeX in
    some <| fun _goI _goB _id _data _blocks =>
      pure <| .text "The Blueprint summary is available in the HTML output."
  toHtml := some summaryBlockToHtml
  extraCss := summaryAssetBundle.css
  extraJs := summaryAssetBundle.js

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
