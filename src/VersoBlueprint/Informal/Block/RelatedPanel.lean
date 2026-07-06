/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Group
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.PreviewCache
import VersoBlueprint.TraversalIndex

/-!
Rendering for the small relationship panels attached to informal blocks.

These panels answer local navigation questions: which group entries belong with
this block, which blocks this one uses, and which blocks use this one. The data
comes from traversal stores; this module keeps the HTML presentation separate
from the main block renderer.
-/

namespace Informal
namespace RelatedPanel

open Verso
open Verso.Genre Manual
open Verso.Output.Html

private def resolveStoredGroupData?
    (state : Verso.Genre.Manual.TraverseState) (label : Data.Label) : Option GroupBlockData :=
  Informal.TraversalIndex.Groups.data? state label

private structure GroupRenderInfo where
  label : Data.Label
  title : String
  declared : Bool := false

/-- Traversal-backed render context shared by group and dependency header panels. -/
structure RelationContext where
  state : Verso.Genre.Manual.TraverseState
  storedBlocks : Array BlockData

/-- Collect the traversal data needed to render related-block panels. -/
def RelationContext.ofState (state : Verso.Genre.Manual.TraverseState) : RelationContext := {
  state
  storedBlocks := collectStoredBlocks state
}

private def blockSummaryTitle (ctx : RelationContext) (data : BlockData) : String :=
  data.displayTitle ctx.state

private def storedBlockByLabel? (ctx : RelationContext) (label : Data.Label) : Option BlockData :=
  ctx.storedBlocks.find? (·.label == label)

private def groupRenderInfo?
    (ctx : RelationContext) (data : BlockData) : Option GroupRenderInfo := do
  let parent ← data.parent
  match resolveStoredGroupData? ctx.state parent with
  | some groupData => some { label := parent, title := groupData.header, declared := true }
  | none => some { label := parent, title := parent.toString, declared := false }

/-- One previewable row in a Blueprint related-entry panel. -/
structure PanelEntry where
  previewId : String
  previewKey : String
  previewTitle : String
  label : Data.Label
  href : Option String := none
  badgesHtml : Output.Html := .empty
  active : Bool := false

/-- Whether a one-entry related panel should stay as an inline preview chip or render the full panel. -/
inductive PanelSingleMode where
  | inlinePreview
  | panel
deriving Repr, Inhabited, BEq

/-- Rendering configuration for a Blueprint related-entry panel. -/
structure PanelConfig where
  chipText : Nat → String
  chipTitle : Nat → String
  singleTitle : PanelEntry → String
  panelTitle : Nat → String
  panelMeta : String
  panelMetaClass : String := "bp_relation_panel_meta"
  previewDefaultTitle : String := "Hover an entry"
  previewEmptyText : String := "Hover an entry to preview it."
  chipClass : String := "bp_relation_chip"
  emptyChipClass : String := "bp_relation_chip bp_relation_chip_empty"
  wrapClass : String := "bp_relation_wrap"
  panelClass : String := "bp_relation_panel"
  panelAttrs : Array (String × String) := #[]
  singleMode : PanelSingleMode := .inlinePreview
  selectFirst : Bool := true

def usedByChipText (count : Nat) : String :=
  s!"used by {count}"

/-- Human-facing statement/proof wording for forward dependency previews. -/
private structure UsesScopeText where
  lowercase : String
  titlecase : String

private def statementUsesScopeText : UsesScopeText :=
  { lowercase := "statement", titlecase := "Statement" }

private def proofUsesScopeText : UsesScopeText :=
  { lowercase := "proof", titlecase := "Proof" }

/-- Standard reverse-dependency panel presentation. -/
def usedByPanelConfig (targetLabel? : Option Data.Label := none) : PanelConfig := {
  chipText := usedByChipText
  chipTitle := fun n =>
    if n == 0 then
      "No reverse dependencies"
    else
      match targetLabel? with
      | some label => s!"Reverse dependencies for {label}"
      | none => "Reverse dependencies"
  singleTitle := fun entry => s!"Reverse dependency: {entry.previewTitle}"
  panelTitle := fun n => s!"Used by {n}"
  panelMeta := "Reverse dependency previews"
  previewDefaultTitle := "Reverse dependency preview"
  previewEmptyText := "Reverse dependency preview content is loaded from the rendered-fragment cache."
}

/-- Standard forward-dependency panel presentation for one dependency scope. -/
private def usesPanelConfigForScope (sourceLabel : Data.Label) (scope : UsesScopeText) :
    PanelConfig := {
  chipText := fun n => s!"uses {n}"
  chipTitle := fun n =>
    if n == 0 then
      s!"No declared {scope.lowercase} dependencies"
    else
      s!"{scope.titlecase} dependencies used by {sourceLabel}"
  singleTitle := fun entry =>
    s!"{scope.titlecase} dependency: {entry.previewTitle}"
  panelTitle := fun n =>
    s!"{scope.titlecase} uses {n}"
  panelMeta :=
    s!"{scope.titlecase} dependency previews"
  previewDefaultTitle :=
    s!"{scope.titlecase} dependency preview"
  previewEmptyText :=
    s!"{scope.titlecase} dependency preview content is loaded from the rendered-fragment cache."
}

/-- Standard forward-dependency panel presentation for statement dependencies. -/
def statementUsesPanelConfig (sourceLabel : Data.Label) : PanelConfig :=
  usesPanelConfigForScope sourceLabel statementUsesScopeText

/-- Standard forward-dependency panel presentation for proof dependencies. -/
def proofUsesPanelConfig (sourceLabel : Data.Label) : PanelConfig :=
  usesPanelConfigForScope sourceLabel proofUsesScopeText

/-- Standard forward-dependency panel presentation for a concrete informal block. -/
def usesPanelConfigForBlock (data : BlockData) : PanelConfig :=
  match data.kind with
  | .proof => proofUsesPanelConfig data.label
  | .statement _ => statementUsesPanelConfig data.label

private def groupChipClass (declared : Bool) : String :=
  if declared then
    "bp_relation_chip"
  else
    "bp_relation_chip bp_relation_chip_warn"

private def groupEmptyChipClass (declared : Bool) : String :=
  if declared then
    "bp_relation_chip bp_relation_chip_empty"
  else
    "bp_relation_chip bp_relation_chip_empty bp_relation_chip_warn"

private def groupPanelMeta (groupLabel : Data.Label) (declared : Bool) : String :=
  if declared then
    "Group member previews"
  else
    s!"No :::group declaration was found for parent '{groupLabel}'; showing entries that share this parent label."

/-- Standard group-membership panel presentation. -/
def groupPanelConfig (groupLabel : Data.Label) (groupTitle : String) (declared : Bool) :
    PanelConfig := {
  chipText := fun _ => "group"
  chipTitle := fun n =>
    if n == 0 then
      if declared then
        s!"Group: {groupTitle}. No other entries in this group."
      else
        s!"Parent group '{groupLabel}' is referenced here, but no :::group declaration was found."
    else if declared then
      s!"Other entries in group {groupTitle}"
    else
      s!"Undeclared group '{groupLabel}'"
  singleTitle := fun entry =>
    if declared then
      s!"Group member: {entry.previewTitle}"
    else
      s!"Undeclared group '{groupLabel}': {entry.previewTitle}"
  panelTitle := fun n => s!"Group: {groupTitle} ({n})"
  panelMeta := groupPanelMeta groupLabel declared
  panelMetaClass :=
    if declared then
      "bp_relation_panel_meta"
    else
      "bp_relation_panel_meta bp_relation_chip_warn"
  previewDefaultTitle := "Group member preview"
  previewEmptyText := "Group member preview content is loaded from the rendered-fragment cache."
  chipClass := groupChipClass declared
  emptyChipClass := groupEmptyChipClass declared
}

private structure UsedByEntry where
  source : BlockData
  inStatement : Bool := false
  inProof : Bool := false
  origins : Array Data.UseOrigin := #[]
  intents : Array Data.UseIntent := #[]

private structure UsesEntry where
  label : Data.Label
  target? : Option BlockData := none
  inStatement : Bool := false
  inProof : Bool := false
  origins : Array Data.UseOrigin := #[]
  intents : Array Data.UseIntent := #[]

private def sortUsedByEntries (entries : Array UsedByEntry) : Array UsedByEntry :=
  entries.qsort fun a b =>
    BlockData.traversalOrderLess a.source b.source

private def pushUnique [DecidableEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

private def mergeUsedByEntry (existing : UsedByEntry) (useRef : Data.UseRef) (isProof : Bool) :
    UsedByEntry :=
  {
    existing with
      inStatement := existing.inStatement || !isProof
      inProof := existing.inProof || isProof
      origins := pushUnique existing.origins useRef.origin
      intents := pushUnique existing.intents useRef.intent
  }

private def addUsedByEntry
    (acc : Array UsedByEntry) (source : BlockData) (useRef : Data.UseRef) (isProof : Bool)
    (target : Data.Label) : Array UsedByEntry :=
  if useRef.label != target then
    acc
  else if acc.any (·.source.label == source.label) then
    acc.map fun entry =>
      if entry.source.label == source.label then
        mergeUsedByEntry entry useRef isProof
      else
        entry
  else
    acc.push <| mergeUsedByEntry { source } useRef isProof

private def collectUsedByEntries
    (ctx : RelationContext) (target : Data.Label) : Array UsedByEntry :=
  sortUsedByEntries <| ctx.storedBlocks.foldl (init := #[]) fun acc source =>
    if source.label == target then
      acc
    else
      let acc :=
        source.statementUses.foldl (init := acc) fun acc useRef =>
          addUsedByEntry acc source useRef false target
      source.proofUses.foldl (init := acc) fun acc useRef =>
        addUsedByEntry acc source useRef true target

private def mergeUsesEntry (existing : UsesEntry) (useRef : Data.UseRef) (isProof : Bool) :
    UsesEntry :=
  {
    existing with
      inStatement := existing.inStatement || !isProof
      inProof := existing.inProof || isProof
      origins := pushUnique existing.origins useRef.origin
      intents := pushUnique existing.intents useRef.intent
  }

private def addUsesEntry
    (ctx : RelationContext) (acc : Array UsesEntry) (useRef : Data.UseRef) (isProof : Bool) :
    Array UsesEntry :=
  if acc.any (·.label == useRef.label) then
    acc.map fun entry =>
      if entry.label == useRef.label then
        mergeUsesEntry entry useRef isProof
      else
        entry
  else
    acc.push <| mergeUsesEntry {
      label := useRef.label
      target? := storedBlockByLabel? ctx useRef.label
    } useRef isProof

private def usesEntryLess (a b : UsesEntry) : Bool :=
  match a.target?, b.target? with
  | some aTarget, some bTarget => BlockData.traversalOrderLess aTarget bTarget
  | some _, none => true
  | none, some _ => false
  | none, none => a.label.toString < b.label.toString

private def collectUsesEntries
    (ctx : RelationContext) (data : BlockData) : Array UsesEntry :=
  let source := (storedBlockByLabel? ctx data.label).getD data
  let isProof :=
    match data.kind with
    | .proof => true
    | .statement _ => false
  let sourceUses :=
    if isProof then source.proofUses else source.statementUses
  sourceUses.foldl (init := #[]) (fun acc useRef =>
    addUsesEntry ctx acc useRef isProof)
  |>.qsort usesEntryLess

private def collectGroupEntries
    (ctx : RelationContext) (target : BlockData) (group : GroupRenderInfo) :
    Array BlockData :=
  ctx.storedBlocks.foldl (init := #[]) fun acc source =>
    if source.label == target.label then
      acc
    else if source.parent == some group.label then
      match source.kind with
      | .statement _ => acc.push source
      | .proof => acc
    else
      acc

private def usedByPreviewId (targetLabel sourceLabel : Data.Label) : String :=
  s!"bp-used-by-{Informal.HoverRender.previewKey (toString targetLabel)}-{Informal.HoverRender.previewKey (toString sourceLabel)}"

private def usesPreviewId (sourceLabel targetLabel : Data.Label) : String :=
  s!"bp-uses-{Informal.HoverRender.previewKey (toString sourceLabel)}-{Informal.HoverRender.previewKey (toString targetLabel)}"

private def groupPreviewId (targetLabel sourceLabel : Data.Label) : String :=
  s!"bp-group-{Informal.HoverRender.previewKey (toString targetLabel)}-{Informal.HoverRender.previewKey (toString sourceLabel)}"

private def previewLookupKey (source : BlockData) : String :=
  PreviewCache.key source.label (PreviewCache.Facet.ofInProgressKind source.kind)

private def nonEmptyPreviewLookupKey? (key : String) : Option String :=
  let key := key.trimAscii.toString
  if key.isEmpty then none else some key

/-- Render a relation-row badge with semantic relation styling classes. -/
private def relationBadge (className title text : String) : Output.Html :=
  open Verso.Output.Html in
  {{<span class={{className}} title={{title}}>{{.text true text}}</span>}}

private def relationBadgeBaseClass : String :=
  "bp_relation_axis_badge"

private def relationScopedBadgeClass (scope variant : String) : String :=
  s!"{relationBadgeBaseClass} bp_relation_badge_{scope} bp_relation_badge_{scope}_{variant}"

private def relationAxisBadgeClass (axis : String) : String :=
  s!"{relationBadgeBaseClass} bp_relation_badge_axis bp_relation_badge_{axis}"

private def useOriginBadgeClass : Data.UseOrigin → String
  | .manual => relationScopedBadgeClass "origin" "manual"
  | .automatic => relationScopedBadgeClass "origin" "automatic"

private def useIntentBadgeClass : Data.UseIntent → String
  | .regular => relationScopedBadgeClass "intent" "regular"
  | .auxiliary => relationScopedBadgeClass "intent" "auxiliary"
  | .technical => relationScopedBadgeClass "intent" "technical"

/-- Statement-axis badge used by normal and manifest-backed relation panels. -/
def statementAxisBadge : Output.Html :=
  relationBadge
    (relationAxisBadgeClass "statement")
    "Declared in the statement"
    "statement"

/-- Proof-axis badge used by normal and manifest-backed relation panels. -/
def proofAxisBadge : Output.Html :=
  relationBadge
    (relationAxisBadgeClass "proof")
    "Declared in the proof"
    "proof"

private def renderAxisBadges (inStatement inProof : Bool) : Output.Html :=
  let statementBadge : Array Output.Html :=
    if inStatement then #[statementAxisBadge] else #[]
  let proofBadge : Array Output.Html :=
    if inProof then #[proofAxisBadge] else #[]
  .seq (statementBadge ++ proofBadge)

private def renderUsedByAxisBadges (entry : UsedByEntry) : Output.Html :=
  renderAxisBadges entry.inStatement entry.inProof

private def renderUseAxisBadges (entry : UsesEntry) : Output.Html :=
  renderAxisBadges entry.inStatement entry.inProof

private def renderUseMetadataBadges
    (origins : Array Data.UseOrigin) (intents : Array Data.UseIntent) : Output.Html :=
  let originBadges :=
    origins.filter (· != .manual) |>.map fun origin =>
      let text := toString origin
      relationBadge (useOriginBadgeClass origin) s!"Origin: {text}" text
  let intentBadges :=
    intents.filter (· != .regular) |>.map fun intent =>
      let text := toString intent
      relationBadge (useIntentBadgeClass intent) s!"Intent: {text}" text
  .seq (originBadges ++ intentBadges)

private def mkBlockEntry {m}
    [Monad m]
    (ctx : RelationContext)
    (source : BlockData) (previewId : String)
    (badgesHtml : Output.Html := .empty) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m PanelEntry := do
  let previewTitle := blockSummaryTitle ctx source
  let href := Informal.TraversalIndex.Nodes.href? ctx.state source.label
  pure {
    previewId
    previewKey := previewLookupKey source
    previewTitle
    label := source.label
    href
    badgesHtml
  }

private def mkLabelEntry {m}
    [Monad m]
    (ctx : RelationContext)
    (label : Data.Label) (previewId : String)
    (badgesHtml : Output.Html := .empty) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m PanelEntry := do
  let previewTitle := s!"{label}"
  pure {
    previewId
    previewKey := (Informal.PreviewSource.traversalLookupKey? ctx.state label).getD ""
    previewTitle
    label
    href := Informal.TraversalIndex.Nodes.href? ctx.state label
    badgesHtml
  }

private def loadingBody (detail : String) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_relation_preview_message" "data-bp-preview-message"="loading">
      <div class="bp_relation_preview_message_title">"Loading preview"</div>
      <div class="bp_relation_preview_message_detail">{{.text true detail}}</div>
    </div>
  }}

private def samePanelEntry (a b : PanelEntry) : Bool :=
  a.previewId == b.previewId && a.previewKey == b.previewKey

private def selectedPanelEntry? (cfg : PanelConfig) (entries : Array PanelEntry) : Option PanelEntry :=
  entries.find? (fun entry => entry.active) <|>
    if cfg.selectFirst then entries[0]? else none

def renderPanel (cfg : PanelConfig) (entries : Array PanelEntry) : Output.Html :=
  open Verso.Output.Html in
  let renderChip (chipClass : String) (chipTitle : String) (n : Nat) : Output.Html :=
    {{<span class={{chipClass}} title={{chipTitle}}>{{.text true (cfg.chipText n)}}</span>}}
  let renderInlinePreview (entry : PanelEntry) : Output.Html :=
    let chipNode : Output.Html :=
      if let some href := entry.href then
        {{<a class={{s!"{cfg.chipClass} bp_code_link"}} href={{href}} title={{cfg.singleTitle entry}}>
            {{.text true (cfg.chipText 1)}}
          </a>}}
      else
        renderChip cfg.chipClass (cfg.singleTitle entry) 1
    let previewFooterHtml? :=
      let html := entry.badgesHtml.asString
      if html.isEmpty then none else some html
    Informal.HoverRender.inlinePreviewNode
      chipNode entry.previewId entry.previewTitle
      (previewLookupKey? := nonEmptyPreviewLookupKey? entry.previewKey)
      (previewHeaderLabel? := some s!"{entry.label}")
      (previewHeaderHref? := entry.href)
      (previewFooterHtml? := previewFooterHtml?)
  let selectedEntry? := selectedPanelEntry? cfg entries
  let renderRow (entry : PanelEntry) : Output.Html :=
    let itemClass :=
      match selectedEntry? with
      | some selected =>
        if samePanelEntry selected entry then
          "bp_relation_item bp_relation_item_active"
        else
          "bp_relation_item"
      | none =>
        if entry.active then "bp_relation_item bp_relation_item_active" else "bp_relation_item"
    let rowNode : Output.Html :=
      let titleNode := {{<span class="bp_relation_target_title">{{.text true entry.previewTitle}}</span>}}
      let metaNode := {{
        <span class="bp_relation_target_meta">
          <code>s!"{entry.label}"</code>
          {{entry.badgesHtml}}
        </span>
      }}
      if let some href := entry.href then
        {{<a class="bp_relation_target" href={{href}}>{{titleNode}}{{metaNode}}</a>}}
      else
        {{<span class="bp_relation_target">{{titleNode}}{{metaNode}}</span>}}
    let attrs := Id.run do
      let mut attrs := #[
        ("class", itemClass),
        ("data-bp-relation-preview-id", entry.previewId),
        ("data-bp-relation-preview-title", entry.previewTitle)
      ]
      if let some previewKey := nonEmptyPreviewLookupKey? entry.previewKey then
        attrs := attrs.push ("data-bp-relation-preview-key", previewKey)
      for attr in Informal.HoverRender.previewHeaderLinkAttrs (some s!"{entry.label}") entry.href do
        attrs := attrs.push attr
      pure attrs
    .tag "li" attrs rowNode
  let previewTitle :=
    match selectedEntry? with
    | some entry => entry.previewTitle
    | none => cfg.previewDefaultTitle
  let previewBody : Output.Html := loadingBody cfg.previewEmptyText
  let rows := entries.map renderRow
  let panel : Output.Html :=
    .tag "div" (#[("class", cfg.panelClass)] ++ cfg.panelAttrs) <|
      {{
        <div class="bp_relation_panel_header">
          <div class="bp_relation_panel_title">{{.text true (cfg.panelTitle entries.size)}}</div>
          <div class={{cfg.panelMetaClass}}>{{.text true cfg.panelMeta}}</div>
        </div>
        <div class="bp_relation_panel_body">
          <ul class="bp_relation_list">
            {{rows}}
          </ul>
          <div class="bp_relation_preview_surface">
            <div class="bp_relation_preview_header">
              <div class="bp_relation_preview_label">"Preview"</div>
              <div class="bp_relation_preview_heading bp_preview_header_heading">
                <div class="bp_relation_preview_title">{{.text true previewTitle}}</div>
                <a class="bp_relation_preview_header_label bp_preview_header_label" hidden></a>
              </div>
            </div>
            <div class="bp_relation_preview_body">
              {{previewBody}}
            </div>
          </div>
        </div>
      }}
  let panelShell : Output.Html :=
    .tag "div" #[("class", cfg.wrapClass)] <|
      {{
        <button type="button" class={{cfg.chipClass}} title={{cfg.chipTitle entries.size}} "aria-expanded"="false">
          {{.text true (cfg.chipText entries.size)}}
        </button>
        {{panel}}
      }}
  if entries.isEmpty then
    renderChip cfg.emptyChipClass (cfg.chipTitle 0) 0
  else if h : entries.size = 1 then
    let entry := entries[0]'(by simp [h])
    match cfg.singleMode with
    | .inlinePreview => renderInlinePreview entry
    | .panel => panelShell
  else
    panelShell

/-- Render the reverse-dependency header extra for a statement block. -/
def renderUsedByExtra {m}
    [Monad m]
    (ctx : RelationContext)
    (data : BlockData) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Output.Html := do
  match data.kind with
  | .proof => pure .empty
  | .statement _ =>
    let entries := collectUsedByEntries ctx data.label
    let panelEntries ← entries.mapM fun entry =>
      mkBlockEntry ctx entry.source
        (usedByPreviewId data.label entry.source.label)
        (badgesHtml := {{
          {{renderUsedByAxisBadges entry}}
          {{renderUseMetadataBadges entry.origins entry.intents}}
        }})
    pure <| renderPanel (usedByPanelConfig (some data.label)) panelEntries

/-- Render the forward-dependency header extra for a statement or proof block. -/
def renderUsesExtra {m}
    [Monad m]
    (ctx : RelationContext)
    (data : BlockData) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Output.Html := do
  let entries := collectUsesEntries ctx data
  let panelEntries ← entries.mapM fun entry => do
    let badgesHtml := {{
      {{renderUseAxisBadges entry}}
      {{renderUseMetadataBadges entry.origins entry.intents}}
    }}
    match entry.target? with
    | some target =>
      mkBlockEntry ctx target
        (usesPreviewId data.label entry.label)
        (badgesHtml := badgesHtml)
    | none =>
      mkLabelEntry ctx entry.label
        (usesPreviewId data.label entry.label)
        (badgesHtml := badgesHtml)
  pure <| renderPanel (usesPanelConfigForBlock data) panelEntries

/-- Render the group-membership header extra, if the block belongs to a group. -/
def renderGroupExtra {m}
    [Monad m]
    (ctx : RelationContext)
    (data : BlockData) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m (Option Output.Html) := do
  match data.kind, groupRenderInfo? ctx data with
  | .proof, _ => pure none
  | .statement _, none => pure none
  | .statement _, some group =>
    let siblings := collectGroupEntries ctx data group
    if group.declared && siblings.isEmpty then
      return none
    let panelEntries ← siblings.mapM fun source =>
      mkBlockEntry ctx source
        (groupPreviewId data.label source.label)
    let cfg := groupPanelConfig group.label group.title group.declared
    pure <| some (renderPanel cfg panelEntries)

end RelatedPanel
end Informal
