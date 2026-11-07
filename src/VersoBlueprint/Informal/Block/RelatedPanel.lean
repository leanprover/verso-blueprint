/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.CodeSummary
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
  previewKeys : Array Informal.PreviewKey := #[]
  previewTitle : String
  label : Data.Label
  href : Option String := none
  dependencies : Array Relation.Dependency := #[]
  active : Bool := false
  /-- The block whose panel this is, listed among its group but not previewed. -/
  current : Bool := false
  /-- The row's Lean status mark, when the block's assessment is known. -/
  status? : Option CodeSummary.StatusVisual := none

/-- Finds a related block's heading status mark. Renderers without traversal state
derive it from the related block's own manifest entry, so the mark has one source. -/
abbrev StatusLookup := Data.Label → Option CodeSummary.StatusVisual

/-- The block or group a related-entry panel belongs to, named in its header. -/
structure PanelOwner where
  title : String
  label : Data.Label
  href : Option String := none

/--
How related-entry popups open. `pinned` opens on click and stays until closed;
`hover` opens on hover and closes when the pointer leaves. A click pins either way.
-/
def relationPanelOpenMode : Informal.HoverRender.PreviewMode := .pinned

/-- Rendering configuration for a Blueprint related-entry panel. -/
structure PanelConfig where
  chipText : Nat → String
  chipTitle : Nat → String
  /-- Names the kind of popup and its size in the panel header, e.g. "Statement uses · 2". -/
  eyebrow : Nat → String
  /-- A warning shown above the list, for example for an undeclared group. -/
  note? : Option String := none
  /-- Statement/proof badges on rows; a panel for one facet already says which. -/
  showAxisBadges : Bool := true
  chipClass : String := "bp_relation_chip"
  emptyChipClass : String := "bp_relation_chip bp_relation_chip_empty"
  wrapClass : String := "bp_relation_wrap"
  openMode : Informal.HoverRender.PreviewMode := relationPanelOpenMode
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
  eyebrow := fun n => s!"Used by · {n}"
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
  eyebrow := fun n => s!"{scope.titlecase} uses · {n}"
  showAxisBadges := false
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
  eyebrow := fun n => s!"Group · {n} {if n == 1 then "block" else "blocks"}"
  note? := if declared then none else
    some s!"No :::group declaration was found for '{groupLabel}'; these blocks share it as their parent."
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

private def mergeUsedByEntry (existing : UsedByEntry) (useRef : Data.UseRef) (facet : PreviewCache.Facet) :
    UsedByEntry :=
  {
    existing with
      dependencies := Relation.addUse existing.dependencies useRef facet
  }

private def addUsedByEntry
    (acc : Array UsedByEntry) (source : BlockData) (useRef : Data.UseRef) (facet : PreviewCache.Facet)
    (target : Data.Label) : Array UsedByEntry :=
  if useRef.label != target then
    acc
  else if acc.any (·.source.label == source.label) then
    acc.map fun entry =>
      if entry.source.label == source.label then
        mergeUsedByEntry entry useRef facet
      else
        entry
  else
    acc.push <| mergeUsedByEntry { source } useRef facet

private def addUsedByCacheEntry
    (cache : Data.LabelMap (Array UsedByEntry)) (source : BlockData)
    (useRef : Data.UseRef) (facet : PreviewCache.Facet) : Data.LabelMap (Array UsedByEntry) :=
  if source.label == useRef.label then
    cache
  else
    let entries := cache.find? useRef.label |>.getD #[]
    cache.insert useRef.label (addUsedByEntry entries source useRef facet useRef.label)

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
      addUsedByCacheEntry cache source useRef .statement
    source.proofUses.foldl (init := cache) fun cache useRef =>
      addUsedByCacheEntry cache source useRef .proof
  unsorted.foldl
      (init := (Std.TreeMap.empty : Data.LabelMap (Array UsedByEntry))) fun cache label entries =>
    cache.insert label (sortUsedByEntries entries)

private def buildGroupMembersCache (blocks : Array BlockData) :
    Data.LabelMap (Array Data.Label) :=
  blocks.foldl
      (init := (Std.TreeMap.empty : Data.LabelMap (Array Data.Label))) fun cache block =>
    match block.parent with
    | some parent =>
        let members := cache.find? parent |>.getD #[]
        if members.contains block.label then cache else cache.insert parent (members.push block.label)
    | none => cache

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
              addUsedByEntry acc source useRef .statement target
          source.proofUses.foldl (init := acc) fun acc useRef =>
            addUsedByEntry acc source useRef .proof target

private def mergeUsesEntry (existing : UsesEntry) (useRef : Data.UseRef) (facet : PreviewCache.Facet) :
    UsesEntry :=
  {
    existing with
      dependencies := Relation.addUse existing.dependencies useRef facet
  }

private def addUsesEntry
    (state : TraverseState) (acc : Array UsesEntry) (useRef : Data.UseRef) (facet : PreviewCache.Facet) :
    Array UsesEntry :=
  if acc.any (·.label == useRef.label) then
    acc.map fun entry =>
      if entry.label == useRef.label then
        mergeUsesEntry entry useRef facet
      else
        entry
  else
    acc.push <| mergeUsesEntry {
      label := useRef.label
      target? := Informal.TraversalIndex.Nodes.capturedData? state useRef.label
    } useRef facet

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
  let entries := statement.foldl (fun acc useRef => addUsesEntry state acc useRef .statement) #[]
  proof.foldl (fun acc useRef => addUsesEntry state acc useRef .proof) entries
    |>.qsort usesEntryLess

/-- Group members in traversal order, including the block itself. -/
private def collectGroupEntries
    (state : TraverseState) (group : GroupRenderInfo) :
    Array BlockData :=
  match Informal.TraversalIndex.RelatedPanelGroupMembersCache.data? state group.label with
  | some labels => labels.filterMap fun label => Informal.TraversalIndex.Nodes.capturedData? state label
  | none =>
      collectStoredBlocks state |>.filter fun source =>
        source.parent == some group.label && !source.isProof

private def usedByPreviewId (targetLabel sourceLabel : Data.Label) : String :=
  s!"bp-used-by-{Informal.HoverRender.previewKey (toString targetLabel)}-{Informal.HoverRender.previewKey (toString sourceLabel)}"

private def usesPreviewId (sourceLabel targetLabel : Data.Label) : String :=
  s!"bp-uses-{Informal.HoverRender.previewKey (toString sourceLabel)}-{Informal.HoverRender.previewKey (toString targetLabel)}"

private def groupPreviewId (targetLabel sourceLabel : Data.Label) : String :=
  s!"bp-group-{Informal.HoverRender.previewKey (toString targetLabel)}-{Informal.HoverRender.previewKey (toString sourceLabel)}"

/-! Badge codes are compact; the runtime renders each as a labelled badge. -/

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
  previewKeys := reference.previewKeys
  previewTitle := reference.title
  label
  href := reference.href
  dependencies
}

private def mkBlockEntry
    (state : TraverseState) (source : BlockData) (previewId : String)
    (dependencies : Array Relation.Dependency := #[]) : PanelEntry :=
  { mkEntry source.label (RenderingResolution.referenceOfData state source) previewId dependencies with
    status? := some (CodeSummary.blockStatusVisual source) }

private def mkLabelEntry
    (state : TraverseState) (label : Data.Label) (previewId : String)
    (dependencies : Array Relation.Dependency := #[]) : PanelEntry :=
  mkEntry label (RenderingResolution.referenceOrLabel state label) previewId dependencies

private def samePanelEntry (a b : PanelEntry) : Bool :=
  a.previewId == b.previewId && a.previewKeys == b.previewKeys

private def selectedPanelEntry? (cfg : PanelConfig) (entries : Array PanelEntry) : Option PanelEntry :=
  entries.find? (fun entry => entry.active && !entry.current) <|>
    if cfg.selectFirst then entries.find? (!·.current) else none

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

private def isAxisBadgeCode (code : String) : Bool :=
  code == statementAxisBadgeCode || code == proofAxisBadgeCode

private def statusJson : Option CodeSummary.StatusVisual → Json
  | some status => toJson #[status.symbol, status.classSuffix]
  | none => Json.null

/-- Runtime row: [title, previewKey?, label, href?, badgeCodes, active, status?, current],
where `status?` is `[symbol, classSuffix]`. Must match `createRelationItem`. -/
private def panelEntryDataHtml (cfg : PanelConfig) (renderPreview : PreviewResources.Render)
    (selectedEntry? : Option PanelEntry) (entry : PanelEntry) : Output.Html :=
  let badgeCodes := if cfg.showAxisBadges then entry.badgeCodes else
    entry.badgeCodes.filter (!isAxisBadgeCode ·)
  jsonArrayHtml #[
    scriptJson (.str entry.previewTitle),
    PreviewResources.select renderPreview entry.previewKeys
      (fun key => scriptJson (.str key.value)) (fun _ => scriptJson Json.null) (defaultOnly := true),
    scriptJson (.str (Data.Label.publicString entry.label)),
    scriptJson (optionStringJson entry.href),
    scriptJson (toJson badgeCodes),
    scriptJson (toJson (panelEntryActive selectedEntry? entry)),
    scriptJson (statusJson entry.status?),
    scriptJson (toJson entry.current)
  ]

/--
Render a relation chip and the data its popup is built from.

The runtime builds the popup from the shared preview panel shell on first open: the
header names the popup (`cfg.eyebrow`) and its `owner`, and the body lists the rows
beside a preview of the selected one. Rows keep their labels, links, badges and
status even when their preview resource is unavailable; only the optional preview
key depends on resource availability.
-/
def renderPanel (cfg : PanelConfig) (owner : PanelOwner) (entries : Array PanelEntry)
    (renderPreview : PreviewResources.Render := PreviewResources.immediate) : Output.Html :=
  open Verso.Output.Html in
  let listed := (entries.filter (!·.current)).size
  if listed == 0 then
    {{<span class={{cfg.emptyChipClass}} title={{cfg.chipTitle 0}}>{{.text true (cfg.chipText 0)}}</span>}}
  else
    let selectedEntry? := selectedPanelEntry? cfg entries
    let rowData := jsonArrayHtml (entries.map (panelEntryDataHtml cfg renderPreview selectedEntry?))
    let wrapAttrs := #[
      ("class", cfg.wrapClass),
      ("data-bp-preview-mode", cfg.openMode.dataValue),
      ("data-bp-relation-eyebrow", cfg.eyebrow entries.size),
      ("data-bp-relation-title", owner.title),
      ("data-bp-relation-label", Data.Label.publicString owner.label)
    ] ++ (owner.href.map (("data-bp-relation-href", ·))).toArray
      ++ (cfg.note?.map (("data-bp-relation-note", ·))).toArray
    .tag "div" wrapAttrs {{
      <button type="button" class={{cfg.chipClass}} title={{cfg.chipTitle listed}}
          "aria-haspopup"="dialog" "aria-expanded"="false">
        {{.text true (cfg.chipText listed)}}
      </button>
      <script type="application/json" class="bp-relation-entries">{{rowData}}</script>
    }}

private def blockOwner (state : TraverseState) (data : BlockData) : PanelOwner :=
  let reference := RenderingResolution.referenceOfData state data
  { title := reference.title, label := data.label, href := reference.href }

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
    renderPanel (usedByPanelConfig (some data.label)) (blockOwner state data)
      (usedByEntries state data) renderPreview

/-- Render the selected facet's dependency panel using the shared projection. -/
def renderUsesExtra (state : TraverseState) (data : BlockData)
    (renderPreview : PreviewResources.Render := PreviewResources.immediate) : Output.Html :=
  renderPanel (usesPanelConfigForBlock data) (blockOwner state data)
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
    let members := collectGroupEntries state group
    if group.declared && members.all (·.label == data.label) then
      return none
    let panelEntries := members.map fun source =>
      { mkBlockEntry state source (groupPreviewId data.label source.label) with
        current := source.label == data.label }
    let cfg := groupPanelConfig group.label group.title group.declared
    return some (renderPanel cfg { title := group.title, label := group.label } panelEntries renderPreview)

end RelatedPanel
end Informal
