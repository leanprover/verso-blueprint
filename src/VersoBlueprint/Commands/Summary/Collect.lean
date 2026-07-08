/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Commands.Summary.Data
import VersoBlueprint.Commands.Summary.Order
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.Graph
import VersoBlueprint.Informal.Block.Common

namespace Informal.Commands

/-!
Collects finished Blueprint traversal state into the serializable summary payload.
-/

open Lean
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

end Informal.Commands
