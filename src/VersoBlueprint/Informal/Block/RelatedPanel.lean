/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.PreviewResources
import VersoBlueprint.RenderingResolution
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

open Lean
open Verso
open Verso.Genre Manual
open Verso.Output.Html

private def resolveStoredGroupData?
    (state : TraverseState) (label : Data.Label) : Option GroupBlockData :=
  Informal.TraversalIndex.Groups.data? state label

private structure GroupRenderInfo where
  label : Data.Label
  title : String
  declared : Bool := false

private def groupRenderInfo?
    (state : TraverseState) (data : BlockData) : Option GroupRenderInfo := do
  let parent ← data.parent
  match resolveStoredGroupData? state parent with
  | some groupData => some { label := parent, title := groupData.header, declared := true }
  | none => some { label := parent, title := parent.toString, declared := false }

/-- One previewable row in a Blueprint related-entry panel. -/
structure PanelEntry where
  previewId : String
  previewKey : Option Informal.PreviewKey := none
  previewTitle : String
  label : Data.Label
  href : Option String := none
  dependencies : Array Relation.Dependency := #[]
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
  match data.isProof with
  | true => proofUsesPanelConfig data.label
  | false => statementUsesPanelConfig data.label

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
  dependencies : Array Relation.Dependency := #[]

private def UsedByEntry.toCacheEntry (entry : UsedByEntry) :
    Informal.TraversalIndex.RelatedPanelUsedByCache.Entry := {
  sourceLabel := entry.source.label
  dependencies := entry.dependencies
}

private def UsedByEntry.ofCacheEntry?
    (state : TraverseState)
    (entry : Informal.TraversalIndex.RelatedPanelUsedByCache.Entry) : Option UsedByEntry := do
  let source ← Informal.TraversalIndex.Nodes.capturedData? state entry.sourceLabel
  return {
    source
    dependencies := entry.dependencies
  }

private structure UsesEntry where
  label : Data.Label
  target? : Option BlockData := none
  dependencies : Array Relation.Dependency := #[]

private def sortUsedByEntries (entries : Array UsedByEntry) : Array UsedByEntry :=
  entries.qsort fun a b =>
    BlockData.traversalOrderLess a.source b.source

private def pushUnique [DecidableEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

private def mergeUsedByEntry (existing : UsedByEntry) (useRef : Data.UseRef) (isProof : Bool) :
    UsedByEntry :=
  {
    existing with
      dependencies := Relation.addUse existing.dependencies useRef isProof
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

private def addUsedByCacheEntry
    (cache : Data.LabelMap (Array UsedByEntry)) (source : BlockData)
    (useRef : Data.UseRef) (isProof : Bool) : Data.LabelMap (Array UsedByEntry) :=
  if source.label == useRef.label then
    cache
  else
    let entries := cache.find? useRef.label |>.getD #[]
    cache.insert useRef.label (addUsedByEntry entries source useRef isProof useRef.label)

private def buildUsedByCache (blocks : Array BlockData) :
    Data.LabelMap (Array UsedByEntry) :=
  let seeded := blocks.foldl
      (init := (Std.TreeMap.empty : Data.LabelMap (Array UsedByEntry))) fun cache block =>
    match block.isProof with
    | false => cache.insert block.label #[]
    | true => cache
  let unsorted := blocks.foldl
      (init := seeded) fun cache source =>
    let cache := source.statementUses.foldl (init := cache) fun cache useRef =>
      addUsedByCacheEntry cache source useRef false
    source.proofUses.foldl (init := cache) fun cache useRef =>
      addUsedByCacheEntry cache source useRef true
  unsorted.foldl
      (init := (Std.TreeMap.empty : Data.LabelMap (Array UsedByEntry))) fun cache label entries =>
    cache.insert label (sortUsedByEntries entries)

private def buildGroupMembersCache (blocks : Array BlockData) :
    Data.LabelMap (Array Data.Label) :=
  blocks.foldl
      (init := (Std.TreeMap.empty : Data.LabelMap (Array Data.Label))) fun cache block =>
    match block.isProof, block.parent with
    | false, some parent =>
        let members := cache.find? parent |>.getD #[]
        cache.insert parent (members.push block.label)
    | _, _ => cache

/--
Cache relation-panel indexes in traversal domains before HTML emission.

Block renderers are called once per rendered block. Without these caches, each
renderer rebuilds or scans the full stored-block list for group and reverse
dependency panels.
-/
def patchRelationCaches (state : TraverseState) : TraverseState :=
  let blocks := collectStoredBlocks state
  let usedByCache := buildUsedByCache blocks
  let groupMembersCache := buildGroupMembersCache blocks
  let state :=
    usedByCache.foldl (init := state) fun state label entries =>
      Informal.TraversalIndex.RelatedPanelUsedByCache.saveData state label
        (entries.map fun entry => entry.toCacheEntry)
  groupMembersCache.foldl (init := state) fun state label entries =>
    Informal.TraversalIndex.RelatedPanelGroupMembersCache.saveData state label entries

private def collectUsedByEntries
    (state : TraverseState) (target : Data.Label) : Array UsedByEntry :=
  match Informal.TraversalIndex.RelatedPanelUsedByCache.data? state target with
  | some entries => entries.filterMap (UsedByEntry.ofCacheEntry? state)
  | none =>
      sortUsedByEntries <| collectStoredBlocks state |>.foldl (init := #[]) fun acc source =>
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
      dependencies := Relation.addUse existing.dependencies useRef isProof
  }

private def addUsesEntry
    (state : TraverseState) (acc : Array UsesEntry) (useRef : Data.UseRef) (isProof : Bool) :
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
      target? := Informal.TraversalIndex.Nodes.capturedData? state useRef.label
    } useRef isProof

private def usesEntryLess (a b : UsesEntry) : Bool :=
  match a.target?, b.target? with
  | some aTarget, some bTarget => BlockData.traversalOrderLess aTarget bTarget
  | some _, none => true
  | none, some _ => false
  | none, none => a.label.toString < b.label.toString

private def collectUsesEntries
    (state : TraverseState) (data : BlockData) (facet? : Option PreviewCache.Facet) : Array UsesEntry :=
  let source := (Informal.TraversalIndex.Nodes.capturedData? state data.label).getD data
  let statement := if facet? == some .proof then #[] else source.statementUses
  let proof := if facet? == some .statement then #[] else source.proofUses
  let entries := statement.foldl (fun acc useRef => addUsesEntry state acc useRef false) #[]
  proof.foldl (fun acc useRef => addUsesEntry state acc useRef true) entries
    |>.qsort usesEntryLess

private def collectGroupEntries
    (state : TraverseState) (target : BlockData) (group : GroupRenderInfo) :
    Array BlockData :=
  match Informal.TraversalIndex.RelatedPanelGroupMembersCache.data? state group.label with
  | some labels => labels.filterMap fun label =>
      if label == target.label then none else Informal.TraversalIndex.Nodes.capturedData? state label
  | none =>
      collectStoredBlocks state |>.foldl (init := #[]) fun acc source =>
        if source.label == target.label then
          acc
        else if source.parent == some group.label then
          match source.isProof with
          | false => acc.push source
          | true => acc
        else
          acc

private def usedByPreviewId (targetLabel sourceLabel : Data.Label) : String :=
  s!"bp-used-by-{Informal.HoverRender.previewKey (toString targetLabel)}-{Informal.HoverRender.previewKey (toString sourceLabel)}"

private def usesPreviewId (sourceLabel targetLabel : Data.Label) : String :=
  s!"bp-uses-{Informal.HoverRender.previewKey (toString sourceLabel)}-{Informal.HoverRender.previewKey (toString targetLabel)}"

private def groupPreviewId (targetLabel sourceLabel : Data.Label) : String :=
  s!"bp-group-{Informal.HoverRender.previewKey (toString targetLabel)}-{Informal.HoverRender.previewKey (toString sourceLabel)}"

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

/-- Compact relation-row payload code for a statement dependency axis. -/
def statementAxisBadgeCode : String := "s"

/-- Compact relation-row payload code for a proof dependency axis. -/
def proofAxisBadgeCode : String := "p"

private def useOriginBadgeCode? : Data.UseOrigin → Option String
  | .manual => none
  | .automatic => some "oa"

private def useIntentBadgeCode? : Data.UseIntent → Option String
  | .regular => none
  | .auxiliary => some "ia"
  | .technical => some "it"

/-- Statement-axis badge used by normal and manifest-backed relation panels. -/
private def statementAxisBadge : Output.Html :=
  relationBadge
    (relationAxisBadgeClass "statement")
    "Declared in the statement"
    "statement"

/-- Proof-axis badge used by normal and manifest-backed relation panels. -/
private def proofAxisBadge : Output.Html :=
  relationBadge
    (relationAxisBadgeClass "proof")
    "Declared in the proof"
    "proof"

private def relationBadgeHtml? : String → Option Output.Html
  | "s" => some statementAxisBadge
  | "p" => some proofAxisBadge
  | "oa" =>
      some <| relationBadge
        (useOriginBadgeClass .automatic)
        "Origin: automatic"
        "automatic"
  | "ia" =>
      some <| relationBadge
        (useIntentBadgeClass .auxiliary)
        "Intent: auxiliary"
        "auxiliary"
  | "it" =>
      some <| relationBadge
        (useIntentBadgeClass .technical)
        "Intent: technical"
        "technical"
  | _ => none

/-- Render compact relation-row badge codes for inline, server-rendered relation chips. -/
private def renderRelationBadgeCodes (codes : Array String) : Output.Html :=
  .seq <| codes.filterMap relationBadgeHtml?

private def axisBadgeCodes (inStatement inProof : Bool) : Array String :=
  let statementBadge : Array String :=
    if inStatement then #[statementAxisBadgeCode] else #[]
  let proofBadge : Array String :=
    if inProof then #[proofAxisBadgeCode] else #[]
  statementBadge ++ proofBadge

/-- Derive presentation codes from the same facet-bound facts in both adapters. -/
def dependencyBadgeCodes (dependencies : Array Relation.Dependency) : Array String :=
  let axes := axisBadgeCodes (dependencies.any (·.facet == .statement))
    (dependencies.any (·.facet == .proof))
  let origins := dependencies.filterMap (fun dep => useOriginBadgeCode? dep.origin)
  let intents := dependencies.filterMap (fun dep => useIntentBadgeCode? dep.intent)
  (axes ++ origins ++ intents).foldl (fun acc code => pushUnique acc code) #[]

def PanelEntry.badgeCodes (entry : PanelEntry) : Array String :=
  dependencyBadgeCodes entry.dependencies

private def mkEntry
    (label : Data.Label) (reference : RenderingResolution.Reference)
    (previewId : String) (dependencies : Array Relation.Dependency) : PanelEntry := {
  previewId
  previewKey := reference.previewKey
  previewTitle := reference.title
  label
  href := reference.href
  dependencies
}

private def mkBlockEntry
    (state : TraverseState) (source : BlockData) (previewId : String)
    (dependencies : Array Relation.Dependency := #[]) : PanelEntry :=
  mkEntry source.label (RenderingResolution.referenceOfData state source) previewId dependencies

private def mkLabelEntry
    (state : TraverseState) (label : Data.Label) (previewId : String)
    (dependencies : Array Relation.Dependency := #[]) : PanelEntry :=
  mkEntry label (RenderingResolution.referenceOrLabel state label) previewId dependencies

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

private def optionStringJson (value? : Option String) : Json :=
  match value? with
  | some value => Json.str value
  | none => Json.null

private def panelEntryActive (selectedEntry? : Option PanelEntry) (entry : PanelEntry) : Bool :=
  match selectedEntry? with
  | some selected => samePanelEntry selected entry
  | none => entry.active

private def scriptJson (json : Json) : Output.Html :=
  .text false (json.compress.replace "<" "\\u003c")

/-- Assemble JSON leaves structurally so preview keys can be selected before
serialization. No HTML or JSON string is parsed during resource finalization. -/
private def jsonArrayHtml (values : Array Output.Html) : Output.Html :=
  .seq (#[.text false "["] ++
    (values.toList.intersperse (.text false ",")).toArray ++ #[.text false "]"])

/-- Runtime row: [title, previewKey?, label, href?, badgeCodes, active]. -/
private def panelEntryDataHtml (renderPreview : PreviewResources.Render)
    (selectedEntry? : Option PanelEntry) (entry : PanelEntry) : Output.Html :=
  jsonArrayHtml #[
    scriptJson (.str entry.previewTitle),
    match entry.previewKey with
    | none => scriptJson Json.null
    | some key => renderPreview key (fun _ => scriptJson (.str key.value))
        (fun _ => scriptJson Json.null),
    scriptJson (.str s!"{entry.label}"),
    scriptJson (optionStringJson entry.href),
    scriptJson (toJson entry.badgeCodes),
    scriptJson (toJson (panelEntryActive selectedEntry? entry))
  ]

/-- Keep relation rows, labels, links and badges even when their preview resource
is unavailable. Only the optional preview key depends on resource availability. -/
def renderPanel (cfg : PanelConfig) (entries : Array PanelEntry)
    (renderPreview : PreviewResources.Render := PreviewResources.immediate) : Output.Html :=
  open Verso.Output.Html in Id.run do
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
      let html := renderRelationBadgeCodes entry.badgeCodes |>.asString
      if html.isEmpty then none else some html
    Informal.HoverRender.inlinePreviewNode
      chipNode entry.previewId entry.previewTitle
      (previewLookupKey? := entry.previewKey.map (toString ·))
      (previewHeaderLabel? := some s!"{entry.label}")
      (previewHeaderHref? := entry.href)
      (previewFooterHtml? := previewFooterHtml?)
  if entries.isEmpty then
    return renderChip cfg.emptyChipClass (cfg.chipTitle 0) 0
  let renderPanelShell (_ : Unit) : Output.Html := Id.run do
    let selectedEntry? := selectedPanelEntry? cfg entries
    let previewTitle :=
      match selectedEntry? with
      | some entry => entry.previewTitle
      | none => cfg.previewDefaultTitle
    let previewBody : Output.Html := loadingBody cfg.previewEmptyText
    let rowData := jsonArrayHtml (entries.map (panelEntryDataHtml renderPreview selectedEntry?))
    let rowList : Output.Html :=
      .tag "ul" #[("class", "bp_relation_list")] <|
        {{
          <script type="application/json" class="bp-relation-entries">
            {{rowData}}
          </script>
        }}
    let panel : Output.Html :=
      .tag "div" (#[("class", cfg.panelClass)] ++ cfg.panelAttrs) <|
        {{
          <div class="bp_relation_panel_header">
            <div class="bp_relation_panel_title">{{.text true (cfg.panelTitle entries.size)}}</div>
            <div class={{cfg.panelMetaClass}}>{{.text true cfg.panelMeta}}</div>
          </div>
          <div class="bp_relation_panel_body">
            {{rowList}}
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
    return panelShell
  if let #[entry] := entries then
    if cfg.singleMode == .inlinePreview then
      if let some key := entry.previewKey then
        return renderPreview key (fun _ => renderInlinePreview entry) renderPanelShell
  return renderPanelShell ()


/-- Shared reverse-relation projection, independent of HTML and resource availability. -/
def usedByEntries (state : TraverseState) (data : BlockData) : Array PanelEntry :=
  (collectUsedByEntries state data.label).map fun entry =>
    mkBlockEntry state entry.source (usedByPreviewId data.label entry.source.label) entry.dependencies

/-- Shared forward-relation projection. `none` retains both facets for export;
renderers select a facet before deriving badges. -/
def usesEntries (state : TraverseState) (data : BlockData)
    (facet? : Option PreviewCache.Facet) : Array PanelEntry :=
  (collectUsesEntries state data facet?).map fun entry =>
    match entry.target? with
    | some target => mkBlockEntry state target (usesPreviewId data.label entry.label) entry.dependencies
    | none => mkLabelEntry state entry.label (usesPreviewId data.label entry.label) entry.dependencies

/-- Render the reverse-dependency header extra for a statement block. -/
def renderUsedByExtra (state : TraverseState) (data : BlockData)
    (renderPreview : PreviewResources.Render := PreviewResources.immediate) : Output.Html :=
  if data.isProof then .empty else
    renderPanel (usedByPanelConfig (some data.label)) (usedByEntries state data) renderPreview

/-- Render the selected facet's dependency panel using the shared projection. -/
def renderUsesExtra (state : TraverseState) (data : BlockData)
    (renderPreview : PreviewResources.Render := PreviewResources.immediate) : Output.Html :=
  renderPanel (usesPanelConfigForBlock data)
    (usesEntries state data (some (if data.isProof then .proof else .statement))) renderPreview

/-- Render the group-membership header extra, if the block belongs to a group. -/
def renderGroupExtra
    (state : TraverseState)
    (data : BlockData)
    (renderPreview : PreviewResources.Render := PreviewResources.immediate) :
    Option Output.Html := Id.run do
  match data.isProof, groupRenderInfo? state data with
  | true, _ => return none
  | false, none => return none
  | false, some group =>
    let siblings := collectGroupEntries state data group
    if group.declared && siblings.isEmpty then
      return none
    let panelEntries := siblings.map fun source =>
      mkBlockEntry state source
        (groupPreviewId data.label source.label)
    let cfg := groupPanelConfig group.label group.title group.declared
    return some (renderPanel cfg panelEntries renderPreview)

end RelatedPanel
end Informal
