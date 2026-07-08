/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Commands.Summary.Collect
import VersoBlueprint.Commands.Summary.Order
import VersoBlueprint.Informal.LeanCodeLink
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Informal.MetadataView
import VersoBlueprint.Lib.HoverRender

/-!
HTML primitives, row builders, and asset wiring used by the Blueprint summary renderer.
-/

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment

private def triageVisibleLimit : Nat := 10

def statusCountsText (counts : EntryStatusCounts) : String :=
  s!"completed: {counts.completed}; deps incomplete: {counts.completedDepsNo}; sorries: {counts.withSorries}; no proof: {counts.noProof}"

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

def Summary.previewLabels (data : Summary) : Array Name :=
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
def summaryCss := include_str "../summary.css"

def summaryAssetBundle : BlueprintAssetBundle :=
  previewPanelInlinePreviewAssetBundle (cssExtras := [summaryCss])

open Verso Doc Html Genre Manual
open Verso.Output.Html
open Verso.Multi (AllRemotes)

abbrev SummaryHtmlM := HtmlT Manual (ReaderT AllRemotes (ReaderT ExtensionImpls (BuildLogT IO)))

structure SummaryHtmlContext where
  entryHref? : Name → Option String
  declHref? : Name → Name → Option String
  declPreviewLookupKey? : Name → Name → Option String
  previewLookupKey? : Name → Option String

structure SummaryRows where
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
    (href? : Option String) (linkTitle? : Option String := Option.none)
    (previewLookupKey? : Option String := Option.none) : Output.Html :=
  match href? with
  | some href =>
    Informal.LeanCodeLink.renderResolved
      target node "" (some href) linkTitle?
      (previewTitle := Informal.LeanCodePreview.title target)
      (previewLookupKey? := previewLookupKey?)
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
    let declNode := summaryRenderLeanDeclLink decl {{<code>s!"{decl}"</code>}}
      (ctx.declHref? label decl) (previewLookupKey? := ctx.declPreviewLookupKey? label decl)
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

private def summaryMetricBadge [ToString α] (label : String) (value : α)
    (warning : Bool := false) : Output.Html :=
  let text := s!"{label}: {value}"
  if warning then
    summaryWarnBadge text
  else
    summaryBadge text

private def summaryWarnMetricBadge [ToString α] (label : String) (value : α) : Output.Html :=
  summaryMetricBadge label value (warning := true)

private def summaryOptionalMetricBadge (label value : String) : Array Output.Html :=
  if value.isEmpty then
    #[]
  else
    #[summaryMetricBadge label value]

private def summaryUsageBadges (directUses downstreamUses : Nat) : Array Output.Html :=
  #[
    summaryMetricBadge "direct uses" directUses,
    summaryMetricBadge "downstream unlocks" downstreamUses
  ]

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

def summaryCardClass : String := "bp_summary_card"

def summaryCardWarnClass : String :=
  s!"{summaryCardClass} bp_summary_card_warn"

def summaryCard (label value : String) (status? : Option String := Option.none)
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

def summaryOptionalCard (visible : Bool) (label value : String)
    (status? : Option String := Option.none) (className : String := summaryCardClass) :
    Output.Html :=
  if visible then
    summaryCard label value status? className
  else
    .empty

def summaryWarnCard (label value : String) (status? : Option String := Option.none) :
    Output.Html :=
  summaryCard label value status? summaryCardWarnClass

def summaryOptionalWarnCard (visible : Bool) (label value : String)
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

def summaryDetailsList (title : String) (rows : Array Output.Html)
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

def summarySection (title : String) (content : Output.Html)
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

def summaryOptionalDetailsList (visible : Bool) (title : String) (rows : Array Output.Html)
    (className : String := "bp_summary_subsection") (open? : Bool := false) : Output.Html :=
  if visible then
    summaryDetailsList title rows className open?
  else
    .empty

def summaryCappedDetailsList (title : String) (rows : Array Output.Html) (noun : String)
    (className : String := "bp_summary_subsection") (open? : Bool := false) : Output.Html :=
  summaryDetailsList title (summaryCapRows rows noun) className open?

def summaryOptionalCappedDetailsList (visible : Bool) (title : String)
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
    summaryRenderLeanDeclLink item.decl {{<code>s!"{item.decl}"</code>}}
      (ctx.declHref? item.label item.decl)
      (previewLookupKey? := ctx.declPreviewLookupKey? item.label item.decl)
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
      (previewLookupKey? := ctx.declPreviewLookupKey? label canonical)
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
  let proofBadges := summaryOptionalMetricBadge "proof" item.proofStatus
  let actionLinks := summaryMetadataActionLinks metadata
  let badges :=
    metadataBadges ++ #[
      summaryMetricBadge "stage" item.stage,
      summaryMetricBadge "statement" item.statementStatus
    ] ++ summaryUsageBadges item.directUses item.downstreamUses ++ proofBadges
  summaryItemShell entryRef (some (.text true s!"({item.kind})"))
    (summaryItemTextBody s!"Ready for {item.stage} work.")
    badges
    #[ctx.associatedDecls item.label item.leanObjects, summaryActionLinksRow actionLinks]

private def SummaryHtmlContext.usageRow (ctx : SummaryHtmlContext) (item : UsageItem)
    (bodyText primaryLabel secondaryLabel : String) (primaryCount secondaryCount : Nat) : Output.Html :=
  let entryRef := ctx.entryRef item.label
  let badges :=
    #[
      summaryWarnMetricBadge primaryLabel primaryCount,
      summaryMetricBadge secondaryLabel secondaryCount
    ] ++ summaryUsageBadges item.directUses item.downstreamUses
  summaryItemShell entryRef (some (.text true s!"({item.kind})"))
    (summaryItemTextBody bodyText)
    badges
    #[ctx.associatedDecls item.label item.leanObjects]

private def SummaryHtmlContext.usageRowsForAxis (ctx : SummaryHtmlContext)
    (items : Array UsageItem) (bodyText primaryLabel secondaryLabel : String)
    (primaryUses secondaryUses : UsageItem → Nat) : Array UsageItem × Array Output.Html :=
  let usedItems :=
    sortUsageItemsByAxis
      (items.filter fun item => primaryUses item > 0)
      primaryUses
  let rows :=
    usedItems.map fun item =>
      ctx.usageRow item bodyText primaryLabel secondaryLabel (primaryUses item) (secondaryUses item)
  (usedItems, rows)

private def SummaryHtmlContext.dependencyLoadRow (ctx : SummaryHtmlContext)
    (item : DependencyLoadItem) : Output.Html :=
  let entryRef := ctx.entryRef item.label
  let badges :=
    #[
      summaryWarnMetricBadge "total deps" item.totalDeps,
      summaryMetricBadge "statement deps" item.statementDeps,
      summaryMetricBadge "proof deps" item.proofDeps
    ] ++ summaryUsageBadges item.directUses item.downstreamUses
  summaryItemShell entryRef (some (.text true s!"({item.kind})"))
    (summaryItemTextBody "Prerequisite fan-in measured from the current statement/proof dependency graph.")
    badges
    #[ctx.associatedDecls item.label item.leanObjects]

private def summaryProofDebtHotspotRow (item : DebtHotspotItem) : Output.Html :=
  let badges :=
    #[
      summaryWarnMetricBadge "affected entries" item.affectedEntries,
      summaryMetricBadge "incomplete decls" item.incompleteDecls,
      summaryMetricBadge "missing decls" item.missingDecls,
      summaryMetricBadge "total debt" item.totalDebt
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
    summaryMetricBadge "entries" totalEntries,
    summaryWarnMetricBadge "actionable" actionableEntries,
    summaryMetricBadge "quick wins" quickWins,
    summaryMetricBadge "linked PRs" linkedPrs
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
    (summaryWarnMetricBadge "tag" item.tag)
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
      summaryMetricBadge "total" item.totalEntries,
      summaryMetricBadge "closed" item.closedEntries,
      summaryMetricBadge "local-only" item.localOnlyEntries,
      summaryWarnMetricBadge "ready" item.readyEntries,
      summaryMetricBadge "blocked" item.blockedEntries,
      summaryMetricBadge "incomplete Lean" item.incompleteLeanEntries,
      summaryMetricBadge "unlock score" item.unlockScore
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
      | Option.some priority => #[summaryWarnMetricBadge "priority" priority]
      | Option.none => #[]
    summaryItemShell
      (.text true item.header)
      (some {{<code>s!"{item.parent}"</code>}})
      (summaryItemTextBody "Grouped view over entries sharing the same parent.")
      badges
      #[summaryItemActions {{
          "Next: " {{nextRef}} " "
          {{priorityBadges ++ #[
            summaryMetricBadge "stage" next.stage,
            summaryMetricBadge "downstream unlocks" next.downstreamUses
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
  let (statementUsedItems, statementUsedRows) :=
    ctx.usageRowsForAxis
      data.mostUsed.toArray
      "Reverse dependencies recorded in statement dependencies."
      "statement uses"
      "proof uses"
      (fun item => item.statementUses)
      (fun item => item.proofUses)
  let (proofUsedItems, proofUsedRows) :=
    ctx.usageRowsForAxis
      data.mostUsed.toArray
      "Reverse dependencies recorded in proof dependencies."
      "proof uses"
      "statement uses"
      (fun item => item.proofUses)
      (fun item => item.statementUses)
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

def SummaryRows.render (ctx : SummaryHtmlContext) (data : Summary) : SummaryHtmlM SummaryRows := do
  let rows ← ({} : SummaryRows).withOverviewRows ctx data
  let rows := rows.withDependencyRows ctx data
  let rows := rows.withMetadataRows ctx data
  let rows := rows.withDiagnosticsRows ctx data
  let rows := rows.withStructureRows ctx data
  let rows := rows.withIndexRows ctx data
  pure rows

end Informal.Commands
