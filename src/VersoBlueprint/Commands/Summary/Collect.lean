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
Collects the assembled Blueprint environment into the serializable summary payload.
-/

open Lean
open Informal Data Environment
open Realizations Validation

register_option verso.blueprint.summary.debugDiagnostics : Bool := {
  defValue := false
  descr := "Show maintainer diagnostics such as external declaration render failures in blueprint summaries"
}

structure EntryStatusFlags where
  completed : Bool := false
  completedDepsNo : Bool := false
  withIncompleteCode : Bool := false
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

private def buildUsageMaps (snapshot : Realizations.Capture.Snapshot)
    (entries : Array (Name × Realizations.Node)) : NameMap UsageCounts × NameMap (Array Name) :=
  entries.foldl (init := (({} : NameMap UsageCounts), ({} : NameMap (Array Name)))) fun (usageMap, reverseMap) (sourceLabel, _) =>
    let statementDeps := Informal.Graph.capturedUses snapshot sourceLabel `statement |>.map (·.label)
    let proofDeps := Informal.Graph.capturedUses snapshot sourceLabel `proof |>.map (·.label)
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

private def bumpEntryStatus (acc : EntryStatusCounts) (flags : EntryStatusFlags) : EntryStatusCounts :=
  {
    completed := acc.completed + (if flags.completed then 1 else 0)
    completedDepsNo := acc.completedDepsNo + (if flags.completedDepsNo then 1 else 0)
    withIncompleteCode := acc.withIncompleteCode + (if flags.withIncompleteCode then 1 else 0)
    noProof := acc.noProof + (if flags.noProof then 1 else 0)
  }

private def entryStatusFlags (assessment : Realizations.NodeAssessment)
    (node : Realizations.Node) : EntryStatusFlags :=
  let localFormalized := assessment.hasNativeDeclarations &&
    assessment.nativeStatementComplete && assessment.nativeProofComplete
  let withIncompleteCode := assessment.hasNativeDeclarations && !assessment.nativeStatementComplete
  let noProof := node.kind.isTheoremLike && assessment.hasNativeDeclarations && !assessment.nativeProofComplete
  {
    completed := assessment.requiredComplete
    completedDepsNo := localFormalized && !assessment.requiredComplete
    withIncompleteCode
    noProof
    hasAxiomLike := assessment.hasAxiomLike
  }

private def mkIndexItem (label : Name) (kind : Data.NodeKind) (leanObjects : List Name := []) : IndexItem :=
  { label, kind := toString kind, leanObjects }

private def defaultLeanRealizations (snapshot : Realizations.Capture.Snapshot) (label : Name) :
    Array Realizations.Realization :=
  snapshot.registry.realizations.filter fun realization =>
    realization.key.node == label && realization.key.name == `lean && realization.context.language == `lean

private def facetHasAvailableSource (snapshot : Realizations.Capture.Snapshot)
    (facet : Realizations.Facet) : Bool :=
  facet.documents.any fun key =>
    snapshot.registry.documents.any fun document =>
      document.key == key && !document.text.trimAscii.toString.isEmpty

private def nodeLeanObjects (snapshot : Realizations.Capture.Snapshot) (label : Name) : List Name :=
  let names := (defaultLeanRealizations snapshot label).flatMap fun realization =>
    realization.declarations.map fun declaration => declaration.object.native.toName
  names.foldl pushUniqueName #[] |>.toList

/- Summary detail rows preserve fresh native provider inventory for inspection.
They are not closure/completion authority; semantic completion is projected from
the admitted Registry into NodeAssessment above. -/
private structure NodeLeanSummary where
  leanDecls : Nat := 0
  incompleteDecls : Nat := 0
  leanObjects : List Name := []
  incompleteDetails : List IncompleteItem := []
  missingLeanDecls : List MissingLeanDeclItem := []
deriving Inhabited

private def nodeLeanSummary (snapshot : Realizations.Capture.Snapshot) (label : Name)
    (node : Realizations.Node) : NodeLeanSummary := Id.run do
  let realizations := defaultLeanRealizations snapshot label
  let declarations := (realizations.flatMap (·.declarations)).foldl
    (init := #[]) fun acc declaration =>
      if acc.any (·.object == declaration.object) then acc else acc.push declaration
  let requiredNativeChecks := snapshot.registry.requirements.filter fun requirement =>
    match requirement.key.subject with
    | .declaration key _ => key == ⟨label, `lean⟩ &&
      (match requirement.expected with
      | .check validator => validator == NativeLean.statementValidator || validator == NativeLean.bodyValidator
      | _ => false)
    | _ => false
  let incompleteDecls := declarations.filter fun declaration =>
    requiredNativeChecks.any fun requirement =>
      requirement.key.subject == .declaration ⟨label, `lean⟩ declaration.object &&
        !(snapshot.registry.localResult requirement.key).complete
  let incompleteDetails := snapshot.nativeChecks.foldl (init := #[]) fun items checked =>
    if !declarations.any (·.object == checked.declaration) || !checked.status.isIncomplete ||
        items.any (·.decl == checked.declaration.native.toName) then
      items
    else
      items.push {
        label
        kind := toString node.kind
        decl := checked.declaration.native.toName
        isTheorem := checked.kind.any (·.isTheoremLike)
        status := checked.status
      }
  let missingLeanDecls : List MissingLeanDeclItem := (declarations.filterMap fun declaration =>
    match snapshot.registry.objects.find? (·.key == declaration.object) with
    | some object =>
      if object.resolution == .missing then
        some ({
          label
          kind := toString node.kind
          written := declaration.object.native.toName
          canonical := declaration.object.native.toName
        } : MissingLeanDeclItem)
      else none
    | none => none).toList
  return {
    leanDecls := declarations.size
    incompleteDecls := incompleteDecls.size
    leanObjects := nodeLeanObjects snapshot label
    incompleteDetails := incompleteDetails.toList
    missingLeanDecls
  }

/- Render failures are retained registration-time presentation facts, not fresh
proof evidence. Restrict them to associations selected by this exact current
default Lean realization and its captured context. -/
private def nodeRenderFailures (state : Environment.State) (snapshot : Realizations.Capture.Snapshot)
    (label : Name) (node : Realizations.Node) : List RenderFailureItem := Id.run do
  let realizations := defaultLeanRealizations snapshot label
  let mut failures : Array RenderFailureItem := #[]
  for record in state.factRecords do
    if record.label != label then continue
    for association in record.nativeAssociations do
      let selected := realizations.any fun realization =>
        association.realization == realization.key && association.context == realization.context &&
          realization.facets.any (fun facet => association.facets.contains facet.name)
      if !selected then continue
      if let some failure := Informal.externalRenderFailure? association.reference then
        if !failures.any (·.canonical == failure.decl.canonical) then
          failures := failures.push {
            label
            kind := toString node.kind
            written := failure.decl.written
            canonical := failure.decl.canonical
            message := failure.message
          }
  return failures.toList

private def nodeMissingLeanDeclCount (snapshot : Realizations.Capture.Snapshot) (label : Name) : Nat :=
  match snapshot.registry.nodes.find? (·.label == label) with
  | some node => (nodeLeanSummary snapshot label node).missingLeanDecls.length
  | none => 0

private def nodeIncompleteLeanDeclCount (snapshot : Realizations.Capture.Snapshot) (label : Name) : Nat :=
  match snapshot.registry.nodes.find? (·.label == label) with
  | some node => (nodeLeanSummary snapshot label node).incompleteDecls
  | none => 0

private def ownerDisplayName (state : Environment.State) (node : Realizations.Node) : Option String :=
  match node.owner with
  | some owner =>
    match state.authors.get? owner with
    | some info => some info.displayName
    | none => some owner.toString
  | none => none

private def metadataEntryItem (state : Environment.State) (snapshot : Realizations.Capture.Snapshot)
    (label : Name) (node : Realizations.Node) : MetadataEntryItem :=
  {
    label
    kind := toString node.kind
    ownerDisplayName := ownerDisplayName state node
    effort := node.effort
    priority := node.priority
    prUrl := node.prUrl
    issueUrl := node.issueUrl
    tags := node.tags.toList
    leanObjects := nodeLeanObjects snapshot label
  }

private def mkActionableItem? (state : Environment.State) (snapshot : Realizations.Capture.Snapshot)
    (assessment : Realizations.NodeAssessment)
    (usageMap : NameMap UsageCounts) (reverseMap : NameMap (Array Name))
    (label : Name) (node : Realizations.Node) : Option PriorityItem :=
  let (statementStatus, proofStatus) := Informal.Graph.statusesForAssessment node.kind assessment
  match Informal.Graph.actionableStageForAssessment? assessment with
  | Option.none => Option.none
  | Option.some stage =>
    let usage := usageMap.getD label {}
    let downstreamUses := downstreamUseCount reverseMap (reverseMap.getD label #[]).toList
    Option.some {
      label
      kind := toString node.kind
      stage
      priority := node.priority
      ownerDisplayName := ownerDisplayName state node
      effort := node.effort
      prUrl := node.prUrl
      issueUrl := node.issueUrl
      tags := node.tags.toList
      statementStatus := Informal.Graph.StatementStatus.toText statementStatus
      proofStatus := if node.kind.isTheoremLike then Informal.Graph.ProofStatus.toText proofStatus else ""
      directUses := usage.directUses
      downstreamUses
      leanObjects := nodeLeanObjects snapshot label
    }

private def metadataIsQuickWin (priority effort : Option String) : Bool :=
  priority == some "high" && effort == some "small"

private def priorityItemIsQuickWin (item : PriorityItem) : Bool :=
  metadataIsQuickWin item.priority item.effort

private def addParentTheoremLikeItem (groups : NameMap (List IndexItem)) (parent : Name) (item : IndexItem) :
    NameMap (List IndexItem) :=
  groups.insert parent (item :: groups.getD parent [])

private structure SummaryBuildContext where
  state : Environment.State
  snapshot : Realizations.Capture.Snapshot
  entries : Array (Name × Realizations.Node)
  parentChildren : NameMap (Array Name)
  groupHeaders : NameMap String
  usageMap : NameMap UsageCounts
  reverseMap : NameMap (Array Name)

private def mkSummaryBuildContext (state : Environment.State) (snapshot : Realizations.Capture.Snapshot) : SummaryBuildContext :=
  let entries := snapshot.registry.nodes.map fun node => (node.label, node)
  let parentChildren := entries.foldl (init := ({} : NameMap (Array Name))) fun acc (child, node) =>
    match node.parent with
    | none => acc
    | some parent => acc.insert parent ((acc.getD parent #[]).push child)
  let (usageMap, reverseMap) := buildUsageMaps snapshot entries
  {
    state
    snapshot
    entries
    parentChildren
    groupHeaders := state.groups
    usageMap
    reverseMap
  }

private def SummaryBuildContext.downstreamUses (ctx : SummaryBuildContext) (label : Name) : Nat :=
  downstreamUseCount ctx.reverseMap (ctx.reverseMap.getD label #[]).toList

private def SummaryBuildContext.actionableItem? (ctx : SummaryBuildContext)
    (label : Name) (node : Realizations.Node) : Option PriorityItem :=
  mkActionableItem? ctx.state ctx.snapshot (ctx.snapshot.assessmentFor label)
    ctx.usageMap ctx.reverseMap label node

private def SummaryBuildContext.childEntries (ctx : SummaryBuildContext) (children : Array Name) :
    Array (Name × Realizations.Node) :=
  children.foldl (init := #[]) fun acc child =>
    match ctx.entries.find? (·.1 == child) with
    | some entry => acc.push entry
    | none => acc

private structure MetadataAudit where
  linkedPrs : Array MetadataEntryItem := #[]
  missingOwners : Array MetadataEntryItem := #[]
  missingEffort : Array MetadataEntryItem := #[]
  untaggedEntries : Array MetadataEntryItem := #[]

private def MetadataAudit.addEntry (audit : MetadataAudit)
    (state : Environment.State) (snapshot : Realizations.Capture.Snapshot)
    (label : Name) (node : Realizations.Node) : MetadataAudit :=
  let item := metadataEntryItem state snapshot label node
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
    audit.addEntry ctx.state ctx.snapshot label node

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
    let assessment := ctx.snapshot.assessmentFor label
    let proseRealizations := ctx.snapshot.registry.realizations.filter fun realization =>
      realization.key.node == label && realization.context.language == `verso
    let hasStatement := proseRealizations.any fun realization => realization.facets.any fun facet =>
      facet.name == `statement && facetHasAvailableSource ctx.snapshot facet
    let hasProof := proseRealizations.any fun realization => realization.facets.any fun facet =>
      facet.name == `proof && facetHasAvailableSource ctx.snapshot facet
    let hasCode := assessment.hasNativeDeclarations
    let statusFlags := entryStatusFlags assessment node
    let leanSummary := nodeLeanSummary ctx.snapshot label node
    let renderFailures := nodeRenderFailures ctx.state ctx.snapshot label node
    -- This is authored prose coverage inventory, not a validation requirement:
    -- prose can remain unassessed without erasing the fact that it is absent.
    let missingProseCoverage := hasCode &&
      ((node.kind.isTheoremLike && !hasProof) || !hasStatement)
    let pendingInformalEntries :=
      if missingProseCoverage then mkIndexItem label node.kind leanSummary.leanObjects :: acc.pendingInformalEntries
      else acc.pendingInformalEntries
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
      incompleteDecls := acc.incompleteDecls + leanSummary.incompleteDecls
      incompleteDetails := leanSummary.incompleteDetails ++ acc.incompleteDetails
      missingLeanDecls := leanSummary.missingLeanDecls ++ acc.missingLeanDecls
      renderFailures := renderFailures ++ acc.renderFailures
      definitionIndex
      theoremLikeIndex
      axiomIndex
    }
    acc.bumpNodeKindStatus node.kind statusFlags
    |>.bumpAxiomStatus statusFlags

private def collectTheoremLikeByParent (ctx : SummaryBuildContext) : List ParentTheoremGroup :=
  let grouped := ctx.entries.foldl (init := ({} : NameMap (List IndexItem))) fun acc (label, node) =>
    if node.kind.isTheoremLike then
      let leanObjects := nodeLeanObjects ctx.snapshot label
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

private def collectActionableItems (ctx : SummaryBuildContext) : List PriorityItem :=
  let items := ctx.entries.foldl (init := #[]) fun acc (label, node) =>
    match ctx.actionableItem? label node with
    | none => acc
    | some item => acc.push item
  (sortPriorityItems items).toList

private def usageItem? (ctx : SummaryBuildContext) (label : Name) (node : Realizations.Node) : Option UsageItem :=
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
      leanObjects := nodeLeanObjects ctx.snapshot label
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
    (ctx : SummaryBuildContext) (child : Name) (node : Realizations.Node) : GroupHealthCounts :=
  let assessment := ctx.snapshot.assessmentFor child
  let statusFlags := entryStatusFlags assessment node
  let readyNow := (Informal.Graph.actionableStageForAssessment? assessment).isSome
  let blockedNow := assessment.hasNativeDeclarations && !statusFlags.completed &&
    !statusFlags.completedDepsNo && !readyNow
  let incompleteLeanNow := assessment.hasNativeDeclarations &&
    (!assessment.nativeStatementComplete || !assessment.nativeProofComplete)
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
          match ctx.actionableItem? child node with
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
  ctx.entries.foldl (init := ({} : CoverageSplit)) fun acc (label, _) =>
    let assessment := ctx.snapshot.assessmentFor label
    if !assessment.hasNativeDeclarations then
      acc
    else if assessment.requiredComplete then
      { acc with requirementsComplete := acc.requirementsComplete + 1 }
    else if assessment.nativeStatementComplete && assessment.nativeProofComplete then
      { acc with nativeCompleteRequirementsPending := acc.nativeCompleteRequirementsPending + 1 }
    else if (Informal.Graph.actionableStageForAssessment? assessment).isSome then
      { acc with readyToFormalize := acc.readyToFormalize + 1 }
    else
      { acc with blockedOrIncomplete := acc.blockedOrIncomplete + 1 }

private def collectDependencyLoadItems (ctx : SummaryBuildContext) : List DependencyLoadItem :=
  let items := ctx.entries.foldl (init := #[]) fun acc (label, node) =>
    let statementDeps := (Informal.Graph.capturedUses ctx.snapshot label `statement).map (·.label)
    let proofDeps := (Informal.Graph.capturedUses ctx.snapshot label `proof).map (·.label)
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
        leanObjects := nodeLeanObjects ctx.snapshot label
      }
  (sortDependencyLoadItems items).toList

private def collectIndexItems (ctx : SummaryBuildContext) (keep : Name → Realizations.Node → Bool) :
    List IndexItem :=
  ctx.entries.foldl (init := []) fun acc (label, node) =>
    if keep label node then
      mkIndexItem label node.kind (nodeLeanObjects ctx.snapshot label) :: acc
    else
      acc
  |>.reverse

private structure ProofDebtCounts where
  affectedEntries : Nat := 0
  incompleteDecls : Nat := 0
  missingDecls : Nat := 0

private def ProofDebtCounts.addNode (counts : ProofDebtCounts)
    (snapshot : Realizations.Capture.Snapshot) (label : Name) : ProofDebtCounts :=
  let incompleteDeclCount := nodeIncompleteLeanDeclCount snapshot label
  let missingDeclCount := nodeMissingLeanDeclCount snapshot label
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
        counts.addNode ctx.snapshot child
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
      let actionableItem? := ctx.actionableItem? label node
      let actionable := actionableItem?.isSome
      let quickWin := actionableItem?.map priorityItemIsQuickWin |>.getD false
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
    let actionableItem? := ctx.actionableItem? label node
    let actionable := actionableItem?.isSome
    let quickWin := actionableItem?.map priorityItemIsQuickWin |>.getD false
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

def buildSummary (snapshot : Realizations.Capture.Snapshot) : CoreM Summary := do
  reportImportedConflicts
  let showDebugDiagnostics :=
    (← getOptions).get
      verso.blueprint.summary.debugDiagnostics.name
      verso.blueprint.summary.debugDiagnostics.defValue
  let env ← getEnv
  let state := informalExt.getState env
  let ctx := mkSummaryBuildContext state snapshot
  let summary := collectSummaryOverview ctx
  let actionableItems := collectActionableItems ctx
  let actionablePriorities := actionableItems.filter (·.downstreamUses > 0)
  let metadataAudit := collectMetadataAudit ctx
  return {
    summary with
      showDebugDiagnostics := showDebugDiagnostics
      theoremLikeByParent := collectTheoremLikeByParent ctx
      actionablePriorities := actionablePriorities
      mostUsed := collectUsageItems ctx
      groupHealth := collectGroupHealth ctx
      coverageSplit := collectCoverageSplit ctx
      heaviestPrerequisites := collectDependencyLoadItems ctx
      noPrerequisites := collectIndexItems ctx fun label _ =>
        (Informal.Graph.capturedUses snapshot label `statement ++
          Informal.Graph.capturedUses snapshot label `proof).isEmpty
      noDependents := collectIndexItems ctx fun label _ =>
        (ctx.usageMap.getD label {}).directUses == 0
      proofDebtHotspots := collectProofDebtHotspots ctx
      quickWins := actionableItems.filter priorityItemIsQuickWin
      ownerRollups := collectOwnerRollups ctx
      tagRollups := collectTagRollups ctx
      linkedPrs := metadataAudit.sortedLinkedPrs
      missingOwners := metadataAudit.sortedMissingOwners
      missingEffort := metadataAudit.sortedMissingEffort
      untaggedEntries := metadataAudit.sortedUntaggedEntries
  }

end Informal.Commands
