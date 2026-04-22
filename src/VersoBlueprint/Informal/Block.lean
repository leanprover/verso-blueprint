/-
Copyright (c) 2025 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias, David Thrane Christiansen
-/

-- XXX VersoManual is not module yet
-- module

-- Blueprint library extending the Verso `Manual` genre.

import Lean.Elab.InfoTree.Types

import VersoManual

import VersoBlueprint.Commands.Common
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.MetadataView
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Informal.CodeSummary
import VersoBlueprint.Informal.ExternalCode
import VersoBlueprint.Informal.Group
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.PreviewCache
import VersoBlueprint.PreviewRender
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex
import VersoBlueprint.Profiling

set_option doc.verso true

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Verso.Output.Html
open Lean.Doc.Syntax
open Lean Elab

namespace Informal
open CodeSummary

/- "Informal" Verso objects:

  - An informal verso object is identified by a label, and lives in the `informal` Verso domain.
  - For IO (Informal Object), we associate a `Data` entry, which mainly captures other objects the IO depends on
  - Objects are declared via directives / code blocks
  - Dependencies are declared via the {uses ...}`...` role, which _must_ be inside a directive.

Elaboration, traversal, and rendering are standard, using {ref VersoManual} helpers for custom blocks and inlines.

-/

/-- Configuration for directives / code-blocks. Q: should we allow non-labelled informal objects? -/
structure Config where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing
  lean : Option String := none
  parent : Option Data.Parent := none
  priority : Option String := none
  owner : Option Data.AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
  externalCode : Array Data.ExternalRef := #[]
  invalidExternalCode : Array String := #[]
--  hide : Bool := false

section
variable [Monad m] [MonadInfoTree m] [MonadLiftT CoreM m] [MonadEnv m] [MonadError m] [MonadFileMap m]

private def normalizePriority? (raw : String) : Option String :=
  match raw.trimAscii.toString.toLower with
  | "high" => some "high"
  | "medium" => some "medium"
  | "low" => some "low"
  | _ => none

private def normalizeEffort? (raw : String) : Option String :=
  match raw.trimAscii.toString.toLower with
  | "small" | "s" => some "small"
  | "medium" | "m" => some "medium"
  | "large" | "l" => some "large"
  | _ => none

private def normalizeTags (raw : String) : Array String :=
  raw.splitOn ","
    |>.toArray
    |>.map (fun tag => tag.trimAscii.toString.toLower)
    |>.filter (fun tag => !tag.isEmpty)
    |>.foldl (init := #[]) fun acc tag => if acc.contains tag then acc else acc.push tag

def Config.parse  : ArgParse m Config :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) lean parent priority owner tags effort prUrl =>
    let (externalCode, invalidExternalCode) := ExternalCode.parseExternalCodeList lean
    {
      label := LabelNameParsing.parse labelArg.val
      labelSyntax := labelArg.syntax
      lean := lean
      parent := parent.map LabelNameParsing.parse
      priority := priority
      owner := owner.map LabelNameParsing.parse
      tags := normalizeTags (tags.getD "")
      effort := effort
      prUrl := prUrl.map (·.trimAscii.toString)
      externalCode := externalCode
      invalidExternalCode := invalidExternalCode
    }) <$> .positional `label (.withSyntax .string) <*> .named `lean .string true
        <*> .named `parent .string true <*> .named `priority .string true <*> .named `owner .string true
        <*> .named `tags .string true <*> .named `effort .string true <*> .named `pr_url .string true

instance : FromArgs Config m where
  fromArgs := Config.parse

end

def shouldWritePreviewDataByIds [BEq α] (existingIds : Array α) (currentId : α) : Bool :=
  existingIds.isEmpty || existingIds.contains currentId

private def shouldWritePreviewData (existing? : Option Verso.Multi.Object) (id : Verso.Multi.InternalId) : Bool :=
  shouldWritePreviewDataByIds ((existing?.map (·.ids.toArray)).getD #[]) id

private def resolveStoredGroupData?
    (state : Verso.Genre.Manual.TraverseState) (label : Data.Label) : Option GroupBlockData :=
  Informal.TraversalIndex.Groups.data? state label

private structure GroupRenderInfo where
  label : Data.Label
  title : String
  declared : Bool := false

private structure RelatedPanelContext where
  state : Verso.Genre.Manual.TraverseState
  storedBlocks : Array BlockData

private def mkRelatedPanelContext (state : Verso.Genre.Manual.TraverseState) : RelatedPanelContext := {
  state
  storedBlocks := collectStoredBlocks state
}

private def blockSummaryTitle (ctx : RelatedPanelContext) (data : BlockData) : String :=
  data.displayTitle ctx.state

private def groupRenderInfo?
    (ctx : RelatedPanelContext) (data : BlockData) : Option GroupRenderInfo := do
  let parent ← data.parent
  match resolveStoredGroupData? ctx.state parent with
  | some groupData => some { label := parent, title := groupData.header, declared := true }
  | none => some { label := parent, title := parent.toString, declared := false }

private structure RelatedPanelEntry where
  source : BlockData
  previewId : String
  previewKey : String
  previewTitle : String
  href : Option String := none
  previewFallbackBody : Output.Html := .empty
  metaHtml : Output.Html := .empty

private structure RelatedPanelConfig where
  chipText : Nat → String
  chipTitle : Nat → String
  singleTitle : RelatedPanelEntry → String
  panelTitle : Nat → String
  panelMeta : String
  panelMetaClass : String := "bp_used_by_panel_meta"
  previewDefaultTitle : String := "Hover an entry"
  previewEmptyText : String := "Hover an entry to preview it."
  chipClass : String := "bp_used_by_chip"
  emptyChipClass : String := "bp_used_by_chip bp_used_by_chip_empty"

private structure UsedByEntry where
  source : BlockData
  inStatement : Bool := false
  inProof : Bool := false

private def sortUsedByEntries (entries : Array UsedByEntry) : Array UsedByEntry :=
  entries.qsort fun a b =>
    let aNum := a.source.globalCount.getD a.source.count
    let bNum := b.source.globalCount.getD b.source.count
    aNum < bNum ||
      (aNum == bNum && a.source.label.toString < b.source.label.toString)

private def collectUsedByEntries
    (ctx : RelatedPanelContext) (target : Data.Label) : Array UsedByEntry :=
  sortUsedByEntries <| ctx.storedBlocks.foldl (init := #[]) fun acc source =>
    if source.label == target then
      acc
    else
      let inStatement := source.statementDeps.contains target
      let inProof := source.proofDeps.contains target
      if !inStatement && !inProof then
        acc
      else
        acc.push { source, inStatement, inProof }

private def collectGroupEntries
    (ctx : RelatedPanelContext) (target : BlockData) (group : GroupRenderInfo) :
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

private def usedByPreviewLookupKey (source : BlockData) : String :=
  PreviewCache.key source.label (PreviewCache.Facet.ofInProgressKind source.kind)

private def usedByChipText (count : Nat) : String :=
  s!"used by {count}"

private def renderUsedByAxisBadges (entry : UsedByEntry) : Output.Html :=
  open Verso.Output.Html in
  let statementBadge : Array Output.Html :=
    if entry.inStatement then
      #[{{<span class="bp_used_by_axis_badge">"statement"</span>}}]
    else
      #[]
  let proofBadge : Array Output.Html :=
    if entry.inProof then
      #[{{<span class="bp_used_by_axis_badge">"proof"</span>}}]
    else
      #[]
  .seq (statementBadge ++ proofBadge)

private def usedByPreviewFallbackBody (entry : UsedByEntry) : Output.Html :=
  let useSiteItems : Array Output.Html :=
    (if entry.inStatement then #[codeHoverTextItem "statement"] else #[]) ++
    (if entry.inProof then #[codeHoverTextItem "proof"] else #[])
  .seq #[
    codeHoverSection "Blueprint label" #[codeHoverCodeItem s!"{entry.source.label}"],
    codeHoverSection "Uses target in" useSiteItems
  ]

private def groupPreviewFallbackBody (group : GroupRenderInfo) (entry : BlockData) : Output.Html :=
  .seq #[
    codeHoverSection "Blueprint label" #[codeHoverCodeItem s!"{entry.label}"],
    codeHoverSection "Group" #[codeHoverTextItem group.title]
  ]

private def groupMissingNotice (group : GroupRenderInfo) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_used_by_preview_notice">
      "No matching " <code>":::group"</code> " declaration was found for parent "
      <code>s!"{group.label}"</code> "."
    </div>
  }}

private def mkRelatedPanelEntry {m}
    [Monad m]
    (ctx : RelatedPanelContext)
    (source : BlockData) (previewId : String) (fallbackBody : Output.Html)
    (metaHtml : Output.Html := .empty) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m RelatedPanelEntry := do
  let previewTitle := blockSummaryTitle ctx source
  let href := Informal.TraversalIndex.Nodes.href? ctx.state source.label
  pure {
    source
    previewId
    previewKey := usedByPreviewLookupKey source
    previewTitle
    href
    previewFallbackBody := fallbackBody
    metaHtml
  }

private def renderRelatedPanel (cfg : RelatedPanelConfig) (entries : Array RelatedPanelEntry) :
    Output.Html :=
  open Verso.Output.Html in
  let renderChip (chipClass : String) (chipTitle : String) (n : Nat) : Output.Html :=
    {{<span class={{chipClass}} title={{chipTitle}}>{{.text true (cfg.chipText n)}}</span>}}
  if entries.isEmpty then
    renderChip cfg.emptyChipClass (cfg.chipTitle 0) 0
  else if h : entries.size = 1 then
    let entry := entries[0]'(by simp [h])
    let chipNode : Output.Html :=
      if let some href := entry.href then
        {{<a class={{s!"{cfg.chipClass} bp_code_link"}} href={{href}} title={{cfg.singleTitle entry}}>
            {{.text true (cfg.chipText 1)}}
          </a>}}
      else
        renderChip cfg.chipClass (cfg.singleTitle entry) 1
    Informal.HoverRender.inlinePreviewNode
      false chipNode .empty entry.previewId entry.previewTitle
      (previewLookupKey? := some entry.previewKey)
      (previewFallbackLabel? := some s!"{entry.source.label}")
  else
    let renderRow (itemClass : String) (entry : RelatedPanelEntry) : Output.Html :=
      let rowNode : Output.Html :=
        let titleNode := {{<span class="bp_used_by_target_title">{{.text true entry.previewTitle}}</span>}}
        let metaNode := {{
          <span class="bp_used_by_target_meta">
            {{entry.metaHtml}}
          </span>
        }}
        if let some href := entry.href then
          {{<a class="bp_used_by_target" href={{href}}>{{titleNode}}{{metaNode}}</a>}}
        else
          {{<span class="bp_used_by_target">{{titleNode}}{{metaNode}}</span>}}
      {{
        <li class={{itemClass}}
            "data-bp-used-preview-id"={{entry.previewId}}
            "data-bp-used-preview-key"={{entry.previewKey}}
            "data-bp-used-preview-title"={{entry.previewTitle}}>
          {{rowNode}}
          <template class="bp_used_by_preview_fallback_tpl" "data-bp-used-preview-id"={{entry.previewId}}>
            {{entry.previewFallbackBody}}
          </template>
        </li>
      }}
    let (selectedEntry?, rows) :=
      entries.foldl (init := (none, #[])) fun (selectedEntry?, acc) entry =>
        match selectedEntry? with
        | none =>
          (some entry, acc.push (renderRow "bp_used_by_item bp_used_by_item_active" entry))
        | some selectedEntry =>
          (some selectedEntry, acc.push (renderRow "bp_used_by_item" entry))
    let previewTitle :=
      match selectedEntry? with
      | some entry => entry.previewTitle
      | none => cfg.previewDefaultTitle
    let previewBody : Output.Html :=
      match selectedEntry? with
      | some entry => entry.previewFallbackBody
      | none => {{<div class="bp_used_by_preview_empty">{{.text true cfg.previewEmptyText}}</div>}}
    {{
      <div class="bp_used_by_wrap">
        <button type="button" class={{cfg.chipClass}} title={{cfg.chipTitle entries.size}} "aria-expanded"="false">
          {{.text true (cfg.chipText entries.size)}}
        </button>
        <div class="bp_used_by_panel">
          <div class="bp_used_by_panel_header">
            <div class="bp_used_by_panel_title">{{.text true (cfg.panelTitle entries.size)}}</div>
            <div class={{cfg.panelMetaClass}}>{{.text true cfg.panelMeta}}</div>
          </div>
          <div class="bp_used_by_panel_body">
            <ul class="bp_used_by_list">
              {{rows}}
            </ul>
            <div class="bp_used_by_preview_surface">
              <div class="bp_used_by_preview_header">
                <div class="bp_used_by_preview_label">"Preview"</div>
                <div class="bp_used_by_preview_title">{{.text true previewTitle}}</div>
              </div>
              <div class="bp_used_by_preview_body">
                {{previewBody}}
              </div>
            </div>
          </div>
        </div>
      </div>
    }}

private def renderUsedByEntry {m}
    [Monad m]
    (ctx : RelatedPanelContext)
    (data : BlockData) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Output.Html := do
  match data.kind with
  | .proof => pure .empty
  | .statement _ =>
    let entries := collectUsedByEntries ctx data.label
    let panelEntries ← entries.mapM fun entry =>
      mkRelatedPanelEntry ctx entry.source
        (usedByPreviewId data.label entry.source.label)
        (usedByPreviewFallbackBody entry)
        (metaHtml := {{
          <code>s!"{entry.source.label}"</code>
          {{renderUsedByAxisBadges entry}}
        }})
    let cfg : RelatedPanelConfig := {
      chipText := usedByChipText
      chipTitle := fun n =>
        if n == 0 then
          "No reverse dependencies"
        else
          s!"Reverse dependencies for {data.label}"
      singleTitle := fun entry => s!"Reverse dependency: {entry.previewTitle}"
      panelTitle := fun n => s!"Used by {n}"
      panelMeta := "Hover a use site to preview it."
      previewDefaultTitle := "Hover a use site"
      previewEmptyText := "Hover a use site to preview it."
    }
    pure <| renderRelatedPanel cfg panelEntries

private def renderGroupEntry {m}
    [Monad m]
    (ctx : RelatedPanelContext)
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
      let fallbackBody :=
        if group.declared then
          groupPreviewFallbackBody group source
        else
          .seq #[groupMissingNotice group, groupPreviewFallbackBody group source]
      mkRelatedPanelEntry ctx source
        (s!"bp-group-{Informal.HoverRender.previewKey (toString data.label)}-{Informal.HoverRender.previewKey (toString source.label)}")
        fallbackBody
        (metaHtml := {{<code>s!"{source.label}"</code>}})
    let chipClass :=
      if group.declared then
        "bp_used_by_chip"
      else
        "bp_used_by_chip bp_used_by_chip_warn"
    let emptyChipClass :=
      if group.declared then
        "bp_used_by_chip bp_used_by_chip_empty"
      else
        "bp_used_by_chip bp_used_by_chip_empty bp_used_by_chip_warn"
    let panelMeta :=
      if group.declared then
        "Hover another entry in this group to preview it."
      else
        s!"No :::group declaration was found for parent '{group.label}'; showing entries that share this parent label."
    let cfg : RelatedPanelConfig := {
      chipText := fun _ => "group"
      chipTitle := fun n =>
        if n == 0 then
          if group.declared then
            s!"Group: {group.title}. No other entries in this group."
          else
            s!"Parent group '{group.label}' is referenced here, but no :::group declaration was found."
        else if group.declared then
          s!"Other entries in group {group.title}"
        else
          s!"Undeclared group '{group.label}'"
      singleTitle := fun entry =>
        if group.declared then
          s!"Group member: {entry.previewTitle}"
        else
          s!"Undeclared group '{group.label}': {entry.previewTitle}"
      panelTitle := fun n => s!"Group: {group.title} ({n})"
      panelMeta
      panelMetaClass := if group.declared then "bp_used_by_panel_meta" else "bp_used_by_panel_meta bp_used_by_chip_warn"
      previewDefaultTitle := "Hover a group entry"
      previewEmptyText := "Hover a group entry to preview it."
      chipClass
      emptyChipClass
    }
    pure <| some (renderRelatedPanel cfg panelEntries)

private structure BlockKindRenderStyle where
  kindText : String
  showLabel : Bool := true
  kindCss : String
  wrapperCss : String
  headingCss : String
  captionCss : String
  labelCss : String
  contentCss : String

private def blockKindRenderStyle (data : BlockData) : BlockKindRenderStyle :=
  match data.kind with
  | .proof =>
    {
      kindText := "Proof"
      showLabel := false
      kindCss := "proof"
      wrapperCss := "proof_wrapper bp_kind_proof bp_style_proof"
      headingCss := "proof_heading"
      captionCss := "proof_caption"
      labelCss := "proof_label"
      contentCss := "proof_content"
    }
  | .statement nodeKind =>
    match nodeKind with
    | .definition =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "definition"
        wrapperCss := "definition_thmwrapper theorem-style-definition bp_kind_definition bp_style_definition"
        headingCss := "definition_thmheading"
        captionCss := "definition_thmcaption"
        labelCss := "definition_thmlabel"
        contentCss := "definition_thmcontent"
      }
    | .theorem =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "theorem"
        wrapperCss := "theorem_thmwrapper theorem-style-plain bp_kind_theorem bp_style_plain"
        headingCss := "theorem_thmheading"
        captionCss := "theorem_thmcaption"
        labelCss := "theorem_thmlabel"
        contentCss := "theorem_thmcontent"
      }
    | .lemma =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "lemma"
        wrapperCss := "lemma_thmwrapper theorem-style-plain bp_kind_lemma bp_style_plain"
        headingCss := "lemma_thmheading"
        captionCss := "lemma_thmcaption"
        labelCss := "lemma_thmlabel"
        contentCss := "lemma_thmcontent"
      }
    | .corollary =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "corollary"
        wrapperCss := "corollary_thmwrapper theorem-style-plain bp_kind_corollary bp_style_plain"
        headingCss := "corollary_thmheading"
        captionCss := "corollary_thmcaption"
        labelCss := "corollary_thmlabel"
        contentCss := "corollary_thmcontent"
      }

private def renderBlockTitleRow (style : BlockKindRenderStyle) (labelText numberText : String) : Output.Html :=
  open Verso.Output.Html in
  let titleRowClass :=
    if style.showLabel then
      "bp_heading_title_row bp_heading_title_row_statement"
    else
      "bp_heading_title_row"
  let captionClass := s!"bp_caption bp_kind_{style.kindCss}_caption {style.captionCss}"
  let labelClass := s!"bp_label bp_kind_{style.kindCss}_label {style.labelCss}"
  {{
    <div class={{titleRowClass}}>
      <span class={{captionClass}} title={{labelText}}> {{.text true style.kindText}} </span>
      {{ if style.showLabel then {{<span class={{labelClass}}> {{.text true numberText}} </span>}} else .empty }}
    </div>
  }}

private def renderStatementHeaderExtras
    (groupEntry? : Option Output.Html)
    (codeEntry usedByEntry : Output.Html) : Output.Html :=
  open Verso.Output.Html in
  let extrasClass :=
    if groupEntry?.isSome then
      "bp_extras bp_extras_with_group thm_header_extras"
    else
      "bp_extras thm_header_extras"
  {{
    <div class={{extrasClass}}>
      {{match groupEntry? with
        | some groupEntry => {{<span class="bp_extra_slot bp_extra_slot_group">{{groupEntry}}</span>}}
        | none => .empty}}
      <span class="bp_extra_slot bp_extra_slot_code">
        {{codeEntry}}
      </span>
      <span class="bp_extra_slot bp_extra_slot_used_by">
        {{usedByEntry}}
      </span>
    </div>
  }}

private def renderMetadataItem (key : String) (value : Output.Html) (extraClass : String := "") : Output.Html :=
  open Verso.Output.Html in
  let itemClass :=
    if extraClass.isEmpty then
      "bp_metadata_item"
    else
      s!"bp_metadata_item {extraClass}"
  {{
    <span class={{itemClass}}>
      <span class="bp_metadata_key">{{.text true key}}</span>
      {{value}}
    </span>
  }}

private def renderMetadataTextValue (value : String) : Output.Html :=
  {{<span class="bp_metadata_value">{{.text true value}}</span>}}

private def renderMetadataLinkValue (href : String) (label : String) : Output.Html :=
  {{<a class="bp_metadata_link bp_metadata_value" href={{href}}>{{.text true label}}</a>}}

private def renderMetadataCodeValue (value : Data.AuthorId) : Output.Html :=
  {{<span class="bp_metadata_value"><code>s!"{value}"</code></span>}}

private def renderMetadataCodeLinkValue (href : String) (value : Data.AuthorId) : Output.Html :=
  {{<a class="bp_metadata_link bp_metadata_value" href={{href}}><code>s!"{value}"</code></a>}}

private def renderOwnerMetadataItem (data : BlockData) : Output.Html :=
  open Verso.Output.Html in
  let avatar : Output.Html :=
    match data.ownerImageUrl with
    | some href => {{ <img class="bp_metadata_avatar" src={{href}} alt="" /> }}
    | none => .empty
  match data.ownerDisplayName, data.owner, data.ownerUrl with
  | some displayName, _, some href =>
    renderMetadataItem "Owner" (.seq #[avatar, renderMetadataLinkValue href displayName]) "bp_metadata_owner"
  | some displayName, _, none =>
    renderMetadataItem "Owner" (.seq #[avatar, renderMetadataTextValue displayName]) "bp_metadata_owner"
  | none, some owner, some href =>
    renderMetadataItem "Owner" (.seq #[avatar, renderMetadataCodeLinkValue href owner]) "bp_metadata_owner"
  | none, some owner, none =>
    renderMetadataItem "Owner" (.seq #[avatar, renderMetadataCodeValue owner]) "bp_metadata_owner"
  | _, _, _ => .empty

private def renderStatementMetadataPanel (data : BlockData) : Output.Html :=
  open Verso.Output.Html in
  let metadata := data.metadataPresentation
  let ownerItem := renderOwnerMetadataItem data
  let effortNode : Output.Html :=
    match metadata.effort with
    | some effort => renderMetadataItem "Effort" (renderMetadataTextValue effort)
    | none => .empty
  let priorityNode : Output.Html :=
    match metadata.priority with
    | some priority => renderMetadataItem "Priority" (renderMetadataTextValue priority)
    | none => .empty
  let prNode : Output.Html :=
    match metadata.prUrl with
    | some href => renderMetadataItem "PR" (renderMetadataLinkValue href "link")
    | none => .empty
  let tagNodes : Output.Html :=
    if metadata.tags.isEmpty then
      .empty
    else
      renderMetadataItem "Tags" {{
        <span class="bp_metadata_tags">
          {{metadata.tags.map (fun tag => {{ <span class="bp_metadata_tag">{{.text true tag}}</span> }})}}
        </span>
      }}
  if metadata.hasAny then
    {{
      <div class="bp_metadata_panel">
        {{ownerItem}}
        {{effortNode}}
        {{priorityNode}}
        {{tagNodes}}
        {{prNode}}
      </div>
    }}
  else
    .empty

private def renderInformalBlock (data : BlockData) (numberText : String) (attrs : Array (String × String))
    (codeEntry : Output.Html) (groupEntry? : Option Output.Html) (usedByEntry : Output.Html)
    (content : Array Output.Html) : Output.Html :=
  open Verso.Output.Html in
  let style := blockKindRenderStyle data
  let labelText := s!"{data.label}"
  let wrapperClass := s!"bp_wrapper bp_kind_{style.kindCss}_wrapper {style.kindCss}_thmwrapper {style.wrapperCss}"
  let headingClass := s!"bp_heading bp_kind_{style.kindCss}_heading {style.headingCss}"
  let contentClass := s!"bp_content bp_kind_{style.kindCss}_content {style.contentCss}"
  let titleRow := renderBlockTitleRow style labelText numberText
  let extras : Output.Html :=
    match data.kind with
    | .proof => .empty
    | .statement _ => renderStatementHeaderExtras groupEntry? codeEntry usedByEntry
  let metadataPanel : Output.Html :=
    match data.kind with
    | .proof => .empty
    | .statement _ => renderStatementMetadataPanel data
  {{
    <div class={{wrapperClass}} title={{labelText}} {{attrs}}>
      <div class={{headingClass}}>
        {{titleRow}}
        {{extras}}
      </div>
      {{metadataPanel}}
      <div class={{contentClass}}> {{ content }} </div>
    </div>
  }}

private def externalDeclsOfBlock (blockData : BlockData) : Array Data.ExternalRef :=
  match blockData.kind, blockData.codeData with
  | .statement _, some codeData => codeData.externalDecls
  | _, _ => #[]

private def registerBlockPreviewData
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (blockData : BlockData)
    (contents : Array (Verso.Doc.Block Verso.Genre.Manual)) :
    m Unit := do
  let previewFacet := PreviewCache.Facet.ofInProgressKind blockData.kind
  let previewKey := PreviewCache.key blockData.label previewFacet
  let previewData := toJson (PreviewCache.Entry.ofBlocks blockData.label previewFacet contents)
  let existingPreview? := Informal.TraversalIndex.TraversalPreviews.object? (← get) previewKey
  if shouldWritePreviewData existingPreview? id then
    modify λ s => Informal.TraversalIndex.TraversalPreviews.saveData s previewKey previewData
  if existingPreview?.isNone then
    let path := (← read).path
    let _ ← Verso.Genre.Manual.externalTag id path s!"--informal-preview-{previewKey}"
    modify λ s => Informal.TraversalIndex.TraversalPreviews.saveId s previewKey id

private def registerExternalCodePreview
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (decl : Data.ExternalRef) :
    m Unit := do
  let codePreviewKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey decl.canonical
  let codePreviewData := toJson (LeanCodePreview.Entry.ofExternalDecl decl.canonical decl)
  let existingCodePreview? := Informal.TraversalIndex.LeanCodePreviews.object? (← get) codePreviewKey
  if shouldWritePreviewData existingCodePreview? id then
    modify λ s => Informal.TraversalIndex.LeanCodePreviews.saveData s codePreviewKey codePreviewData
  if existingCodePreview?.isNone then
    let path := (← read).path
    let _ ← Verso.Genre.Manual.externalTag id path s!"--lean-code-preview-{codePreviewKey}"
    modify λ s => Informal.TraversalIndex.LeanCodePreviews.saveId s codePreviewKey id

private def registerExternalCodePreviews
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (decls : Array Data.ExternalRef) :
    m Unit := do
  for decl in decls do
    registerExternalCodePreview id decl

private def registerExternalDeclAnchor
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (label : Data.Label)
    (decl : Data.ExternalRef) :
    m Unit := do
  let key := Resolve.externalRenderedDeclTargetKey label decl.canonical
  if (Informal.TraversalIndex.ExternalDeclAnchors.object? (← get) key).isNone then
    let declId ← Verso.Genre.Manual.freshId
    let path := (← read).path
    let _ ← Verso.Genre.Manual.externalTag declId path
      s!"--informal-external-decl-{label}-{decl.canonical}"
    modify λ s => Informal.TraversalIndex.ExternalDeclAnchors.saveId s key declId

private def registerExternalDeclAnchors
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (label : Data.Label)
    (decls : Array Data.ExternalRef) :
    m Unit := do
  for decl in decls do
    registerExternalDeclAnchor label decl

private def storeTraversedBlockData
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (blockData : BlockData) :
    m Unit := do
  let label := blockData.label
  let storedBlockData := blockData.toStoredData
  match Informal.TraversalIndex.Nodes.storedData? (← get) label with
  | some existing =>
    let mergedData := mergeStoredBlockData existing storedBlockData
    modify λ s => Informal.TraversalIndex.Nodes.saveData s label (toJson mergedData)
  | none =>
    let path := (← read).path
    let _ ← Verso.Genre.Manual.externalTag id path s!"--informal-{label}"
    modify fun s =>
      let (globalCount, s) := reserveGlobalBlockNumber s
      let blockData := { storedBlockData with globalCount := storedBlockData.globalCount <|> some globalCount }
      s
        |> (fun s => Informal.TraversalIndex.Nodes.saveId s label id)
        |> (fun s => Informal.TraversalIndex.Nodes.saveData s label (toJson blockData))

/- Informal custom blocks -/
block_extension Block.informal (data : BlockData) where
  -- for TOC
  -- localContentItem _ _ _ := none
  data := toJson data
  traverse id data _contents := do
    -- XXX: (maybe) lift the Except into the main monad error thread
    match fromJson? (α := BlockData) data with
    | .error err =>
      logError s!"Malformed data ({err}): {data}"
      pure none
    | .ok blockData =>
      let partPrefix := numberedPartPrefix? (← read)
      let blockData := { blockData with partPrefix := blockData.partPrefix <|> partPrefix }
      let externalDecls := externalDeclsOfBlock blockData
      registerBlockPreviewData id blockData _contents
      registerExternalCodePreviews id externalDecls
      registerExternalDeclAnchors blockData.label externalDecls
      storeTraversedBlockData id blockData
      return none
  toTeX := none
  extraCss := Informal.Block.Assets.blockCssAssets
  extraJs := Informal.Block.Assets.blockJsAssets
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB id data blocks => do
      match fromJson? (α := BlockData) data with
      | .error err =>
        HtmlT.logError s!"Malformed data ({err}): {data}"
        pure .empty
      | .ok data =>
        let s ← HtmlT.state
        let ctxt ← HtmlT.context
        let data := data.withResolvedNumbering s (numberedPartPrefix? ctxt)
        let relatedPanelContext := mkRelatedPanelContext s
        let attrs := s.htmlId id
        let codeHref : Option String :=
          match Informal.TraversalIndex.InlineCode.object? s data.label with
          | some obj =>
            match obj.ids.toArray[0]? with
            | some codeId => s.externalTags[codeId]? |>.map (·.relativeLink)
            | none => none
          | none => none
        let codeData? : Option InlineCodeData ←
          pure <| Informal.TraversalIndex.InlineCode.data? s data.label
        let codeHint? :=
          match data.kind with
          | .proof => none
          | .statement _ => data.codeData
        let codeSource := BlockCodeData.ofHintAndInline codeHint? codeData?
        let getDeclHref (decl : Name) : Option String :=
          match Resolve.resolveRenderedExternalDeclHref? s data.label decl with
          | some href => some href
          | none => Resolve.resolveInlineLeanDeclHref? s decl
        let getDeclAnchorAttrs (decl : Data.ExternalRef) : Array (String × String) :=
          let attrsFor (declName : Name) : Array (String × String) :=
            let key := Resolve.externalRenderedDeclTargetKey data.label declName
            match Informal.TraversalIndex.ExternalDeclAnchors.object? s key with
            | none => #[]
            | some obj =>
              match obj.ids.toArray[0]? with
              | some targetId => s.htmlId targetId
              | none => #[]
          -- Targets are keyed by canonical declaration name; fallback to the written name keeps
          -- links stable if older cached objects were keyed before canonicalization.
          let canonicalAttrs := attrsFor decl.canonical
          if canonicalAttrs.isEmpty then attrsFor decl.written else canonicalAttrs
        let cdata := {
          codeHref
          source := codeSource
        }
        let panelSummary := CodeSummary.renderPanelIndicator data.label cdata getDeclHref
        let headingParts? : Option CodeSummary.RenderParts :=
          match data.kind with
          | .statement _ => some <| CodeSummary.renderParts data cdata getDeclHref
          | .proof => none
        let externalParts? : Option ExternalCode.RenderParts :=
          match data.kind, codeSource with
          | .statement _, some (.external decls) =>
            if decls.isEmpty then
              none
            else
              let panelHeader := codePanelHeader data (data.displayNumber s)
              some <| ExternalCode.renderParts
                panelHeader
                panelSummary.summaryTitle
                panelSummary.indicator
                decls
                getDeclHref
                getDeclAnchorAttrs
          | _, _ => none
        let externalPanel := (externalParts?.map (·.externalCodePanel)).getD .empty
        let content := (← blocks.mapM goB)
        let codeEntry := (headingParts?.map (·.codeEntry)).getD .empty
        let groupEntry ← renderGroupEntry relatedPanelContext data
        let usedByEntry ← renderUsedByEntry relatedPanelContext data
        let informalBlock :=
          renderInformalBlock data (data.displayNumber s) attrs codeEntry groupEntry usedByEntry content
        return .seq #[informalBlock, externalPanel]

private def expanderImpl (kind : Data.NodeKind) (isProof : Bool := false) : DirectiveExpanderOf Config
  | cfg, contents => do
    let blockRef ← getRef
    let label := cfg.label
    let envKind : Data.InProgressKind :=
      if isProof then .proof else .statement kind
    let resolvedExternalCode ← ExternalCode.resolveExternalCodeList label cfg.labelSyntax kind cfg.externalCode
    let hasExternalRaw := !resolvedExternalCode.isEmpty
    if !cfg.invalidExternalCode.isEmpty then
      logWarningAt cfg.labelSyntax m!"Label {label}: ignoring malformed names in '(lean := ...)' ({String.intercalate ", " cfg.invalidExternalCode.toList})"
    if isProof && hasExternalRaw then
      logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(lean := ...)' in a proof block"
    let priority : Option String ←
      match cfg.priority with
      | none => pure none
      | some raw =>
        match normalizePriority? raw with
        | some normalized =>
          if isProof then
            logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(priority := ...)' in a proof block"
            pure none
          else
            pure (some normalized)
        | none =>
          logErrorAt cfg.labelSyntax m!"Label {label} has invalid '(priority := \"{raw}\")'; expected one of \"high\", \"medium\", \"low\""
          pure none
    let owner : Option Data.AuthorId ←
      match cfg.owner with
      | none => pure none
      | some owner =>
        if isProof then
          logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(owner := ...)' in a proof block"
          pure none
        else if (← Environment.getAuthor? owner).isNone then
          logErrorAt cfg.labelSyntax m!"Label {label} references unknown owner '{owner}'; declare it first with ':::author'"
          pure none
        else
          pure (some owner)
    let effort : Option String ←
      match cfg.effort with
      | none => pure none
      | some raw =>
        match normalizeEffort? raw with
        | some normalized =>
          if isProof then
            logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(effort := ...)' in a proof block"
            pure none
          else
            pure (some normalized)
        | none =>
          logErrorAt cfg.labelSyntax m!"Label {label} has invalid '(effort := \"{raw}\")'; expected one of \"small\", \"medium\", \"large\""
          pure none
    let tags : Array String :=
      if isProof && !cfg.tags.isEmpty then
        #[]
      else
        cfg.tags
    if isProof && !cfg.tags.isEmpty then
      logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(tags := ...)' in a proof block"
    let prUrl : Option String :=
      if isProof then
        none
      else
        match cfg.prUrl with
        | some url =>
          let url := url.trimAscii.toString
          if url.isEmpty then
            none
          else if url.startsWith "http://" || url.startsWith "https://" then
            some url
          else
            none
        | none => none
    if isProof && cfg.prUrl.isSome then
      logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(pr_url := ...)' in a proof block"
    if !isProof then
      if let some url := cfg.prUrl then
        let url := url.trimAscii.toString
        if !url.isEmpty && !(url.startsWith "http://" || url.startsWith "https://") then
          logErrorAt cfg.labelSyntax m!"Label {label} has invalid '(pr_url := \"{url}\")'; expected an http(s) URL"
    let hasExternal := hasExternalRaw && !isProof
    let codeHint : Option Data.CodeRef :=
      if isProof then
        none
      else if hasExternal then
        some (.external resolvedExternalCode)
      else
        none
    let accepted ← Environment.push label envKind codeHint cfg.parent priority owner tags effort prUrl
    let contents ← contents.mapM elabBlock
    if !accepted then
      return ← ``(Block.concat #[$contents,*])
    let previewBlocks ← liftM <| Informal.evalElaboratedBlocks (contents.map (·.raw))
    Environment.setPreviewBlocks previewBlocks
    let count ← Environment.pop blockRef
    let node? ← Environment.getNode? label
    let nodeCodeRef? := node?.bind (·.code)
    let blockKind : Data.InProgressKind ←
      if isProof then
        pure .proof
      else
        let nodeKind ←
          match node? with
            | some node => pure node.kind
            | none =>
              logErrorAt cfg.labelSyntax m!"Internal error: missing node '{label}' after environment registration"
              pure kind
        pure <| .statement nodeKind
    let codeData :=
      match blockKind with
      | .proof => none
      | .statement _ => BlockCodeData.ofCodeRefHint nodeCodeRef?
    let statementDeps := node?.bind (·.statement.map (·.deps)) |>.getD #[]
    let proofDeps := node?.bind (·.proof.map (·.deps)) |>.getD #[]
    let owner := node?.bind (·.owner)
    let ownerInfo? ←
      match owner with
      | some owner => Environment.getAuthor? owner
      | none => pure none
    let data : BlockData := {
      kind := blockKind
      codeData
      label
      parent := node?.bind (·.parent)
      count
      numberingMode := numberingMode (← getOptions)
      statementDeps
      proofDeps
      owner
      ownerDisplayName := ownerInfo?.map (·.displayName)
      ownerUrl := ownerInfo?.bind (·.url)
      ownerImageUrl := ownerInfo?.bind (·.imageUrl)
      tags := node?.map (·.tags) |>.getD #[]
      effort := node?.bind (·.effort)
      priority := node?.bind (·.priority)
      prUrl := node?.bind (·.prUrl)
    }
    ``(Block.other (Block.informal $(quote data)) #[$contents,*])

private def directiveName (kind : Data.NodeKind) (isProof : Bool): String :=
  if isProof then "proof" else (toString kind).toLower

private def expander (kind : Data.NodeKind) (isProof : Bool := false) : DirectiveExpanderOf Config
  | cfg, contents => do
    let label := (directiveName kind isProof)
    Profile.withDocElab "directive" label <|
      (expanderImpl kind isProof) cfg contents

@[directive] def «definition» := expander .definition
@[directive] def «lemma_» := expander .lemma
@[directive] def «theorem» := expander .theorem
@[directive] def «corollary» := expander .corollary
@[directive] def «proof» := expander .lemma (isProof := true)

end Informal
