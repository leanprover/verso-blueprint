/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.MetadataView

namespace Informal

open Verso.Output.Html

structure BlockKindRenderStyle where
  kindText : String
  showLabel : Bool := true
  kindCss : String
  wrapperCss : String
  headingCss : String
  captionCss : String
  labelCss : String
  contentCss : String

namespace BlockKindRenderStyle

def ofInProgressKind : Data.InProgressKind → BlockKindRenderStyle
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
    | .proposition =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "proposition"
        wrapperCss := "proposition_thmwrapper theorem-style-plain bp_kind_proposition bp_style_plain"
        headingCss := "proposition_thmheading"
        captionCss := "proposition_thmcaption"
        labelCss := "proposition_thmlabel"
        contentCss := "proposition_thmcontent"
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

end BlockKindRenderStyle

private def blockKindRenderStyle (data : BlockData) : BlockKindRenderStyle :=
  BlockKindRenderStyle.ofInProgressKind data.kind

/-- Render the caption/label row shared by informal block shells. -/
def renderBlockTitleRow (style : BlockKindRenderStyle)
    (labelText numberText captionText : String) :
    Verso.Output.Html :=
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
      <span class={{captionClass}} title={{labelText}}> {{.text true captionText}} </span>
      {{ if style.showLabel then {{<span class={{labelClass}}> {{.text true numberText}} </span>}} else .empty }}
    </div>
  }}

/-- Standard and custom Blueprint block header extra kinds. -/
inductive HeaderExtraKind where
  | source
  | group
  | uses
  | code
  | usedBy
  | markup
  | custom (key : Lean.Name)
deriving Repr, Inhabited, BEq

def HeaderExtraKind.defaultOrder : HeaderExtraKind → Nat
  | .source => 5
  | .group => 10
  | .uses => 20
  | .usedBy => 30
  | .markup => 35
  | .code => 40
  | .custom _ => 100

private def headerExtraCssSegment (raw : String) : String :=
  raw
    |>.replace "." "_"
    |>.replace ":" "_"
    |>.replace "/" "_"
    |>.replace " " "_"

def HeaderExtraKind.slotKey : HeaderExtraKind → String
  | .source => "source"
  | .group => "group"
  | .uses => "uses"
  | .code => "code"
  | .usedBy => "used_by"
  | .markup => "markup"
  | .custom key => s!"custom_{headerExtraCssSegment key.toString}"

def HeaderExtraKind.slotClass (kind : HeaderExtraKind) : String :=
  match kind with
  | .custom _ => s!"bp_extra_slot bp_extra_slot_custom bp_extra_slot_{kind.slotKey}"
  | _ => s!"bp_extra_slot bp_extra_slot_{kind.slotKey}"

/--
Rendered header content for a Blueprint block.

The block renderer owns layout and lifecycle-sensitive wrappers; callers provide
already-rendered content for standard extras or ordered project-specific extras.
-/
structure HeaderExtra where
  kind : HeaderExtraKind
  html : Verso.Output.Html
  order : Nat := kind.defaultOrder
  wrapperClass : String := ""

def HeaderExtra.ofHtml (kind : HeaderExtraKind) (html : Verso.Output.Html)
    (order : Nat := kind.defaultOrder) (wrapperClass : String := "") : HeaderExtra :=
  { kind, html, order, wrapperClass }

def HeaderExtra.source (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .source html

def HeaderExtra.group (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .group html

def HeaderExtra.uses (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .uses html

def HeaderExtra.code (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .code html

def HeaderExtra.usedBy (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .usedBy html

def HeaderExtra.markup (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .markup html

def HeaderExtra.custom (key : Lean.Name) (html : Verso.Output.Html)
    (order : Nat := HeaderExtraKind.defaultOrder (.custom key)) (wrapperClass : String := "") :
    HeaderExtra :=
  HeaderExtra.ofHtml (.custom key) html (order := order) (wrapperClass := wrapperClass)

/--
Standard Blueprint header extras plus a controlled extension point for
project-specific extras.
-/
structure HeaderExtras where
  source? : Option HeaderExtra := none
  group? : Option HeaderExtra := none
  uses? : Option HeaderExtra := none
  code? : Option HeaderExtra := none
  usedBy? : Option HeaderExtra := none
  markup? : Option HeaderExtra := none
  custom : Array HeaderExtra := #[]

private def HeaderExtra.asStandard (kind : HeaderExtraKind) (extra : HeaderExtra) : HeaderExtra :=
  { extra with kind, order := kind.defaultOrder }

private def HeaderExtras.renderable (extras : HeaderExtras) : Array HeaderExtra :=
  let standard : Array HeaderExtra :=
    #[
      extras.source?.map (·.asStandard .source),
      extras.group?.map (·.asStandard .group),
      extras.uses?.map (·.asStandard .uses),
      extras.usedBy?.map (·.asStandard .usedBy),
      extras.markup?.map (·.asStandard .markup),
      extras.code?.map (·.asStandard .code)
    ].filterMap id
  (standard ++ extras.custom).qsort fun a b =>
    a.order < b.order || (a.order == b.order && a.kind.slotKey < b.kind.slotKey)

private def HeaderExtras.wrapperClass (extras : HeaderExtras) : String :=
  let classes := Id.run do
    let mut classes := #["bp_extras", "thm_header_extras"]
    if extras.source?.isSome then
      classes := classes.push "bp_extras_with_source"
    if extras.group?.isSome then
      classes := classes.push "bp_extras_with_group"
    if extras.uses?.isSome then
      classes := classes.push "bp_extras_with_uses"
    if extras.usedBy?.isSome then
      classes := classes.push "bp_extras_with_used_by"
    if extras.markup?.isSome then
      classes := classes.push "bp_extras_with_markup"
    if extras.code?.isSome then
      classes := classes.push "bp_extras_with_code"
    if !extras.custom.isEmpty then
      classes := classes.push "bp_extras_with_custom"
    return classes
  String.intercalate " " classes.toList

private def renderHeaderExtraSlot (extra : HeaderExtra) : Verso.Output.Html :=
  open Verso.Output.Html in
  let slotClass :=
    if extra.wrapperClass.isEmpty then
      extra.kind.slotClass
    else
      s!"{extra.kind.slotClass} {extra.wrapperClass}"
  {{<span class={{slotClass}}>{{extra.html}}</span>}}

def renderHeaderExtras (extras : HeaderExtras) : Verso.Output.Html :=
  open Verso.Output.Html in
  let renderable := extras.renderable
  if renderable.isEmpty then
    .empty
  else
    {{
      <div class={{extras.wrapperClass}}>
        {{renderable.map renderHeaderExtraSlot}}
      </div>
    }}

private def externalMarkupBadgeText : Data.ExternalMarkupLanguage → String
  | .markdown => "MD"
  | .tex => "TeX"

private def pushUniqueString (values : Array String) (value : String) : Array String :=
  if values.contains value then values else values.push value

private def externalMarkupLanguages (markup : Array Data.ExternalMarkup) :
    Array Data.ExternalMarkupLanguage :=
  markup.foldl
    (init := #[])
    fun acc item =>
      if acc.any (fun current => decide (current = item.language)) then
        acc
      else
        acc.push item.language

private def externalMarkupSlotsFor
    (markup : Array Data.ExternalMarkup) (language : Data.ExternalMarkupLanguage) :
    Array String :=
  markup.foldl
    (init := #[])
    fun acc item =>
      if decide (item.language = language) then
        pushUniqueString acc item.slot
      else
        acc

private def externalMarkupBadgeTitle
    (language : Data.ExternalMarkupLanguage) (slots : Array String) : String :=
  let slotText :=
    if slots.isEmpty then
      ""
    else
      s!" ({String.intercalate ", " slots.toList})"
  s!"External {language.displayName} source markup attached{slotText}"

private def renderExternalMarkupBadge
    (language : Data.ExternalMarkupLanguage) (slots : Array String) :
    Verso.Output.Html :=
  let title := externalMarkupBadgeTitle language slots
  let cls := s!"bp_external_markup_badge bp_external_markup_badge_{language.key}"
  let slotAttr := String.intercalate "," slots.toList
  let prefixHtml :=
    Verso.Output.Html.tag "span"
      #[("class", "bp_external_markup_badge_prefix")]
      (.text true "markup")
  let languageText :=
    Verso.Output.Html.tag "span"
      #[("class", "bp_external_markup_badge_language")]
      (.text true (externalMarkupBadgeText language))
  Verso.Output.Html.tag "span"
    #[("class", cls),
      ("title", title),
      ("aria-label", title),
      ("data-bp-external-markup-language", language.key),
      ("data-bp-external-markup-slots", slotAttr)]
    (.seq #[prefixHtml, languageText])

def renderExternalMarkupBadges (markup : Array Data.ExternalMarkup) : Verso.Output.Html :=
  let languages := externalMarkupLanguages markup
  if languages.isEmpty then
    .empty
  else
    let badges := languages.map fun language =>
      renderExternalMarkupBadge language (externalMarkupSlotsFor markup language)
    Verso.Output.Html.tag "span"
      #[("class", "bp_external_markup_badges"),
        ("title", "External source markup attached")]
      (.seq badges)

def renderExternalMarkupHeaderExtra? (markup : Array Data.ExternalMarkup) :
    Option HeaderExtra :=
  if markup.isEmpty then
    none
  else
    some <| HeaderExtra.markup (renderExternalMarkupBadges markup)

private def renderMetadataItem (key : String) (value : Verso.Output.Html) (extraClass : String := "") :
    Verso.Output.Html :=
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

private def renderMetadataTextValue (value : String) : Verso.Output.Html :=
  {{<span class="bp_metadata_value">{{.text true value}}</span>}}

private def renderMetadataLinkValue (href : String) (label : String) : Verso.Output.Html :=
  {{<a class="bp_metadata_link bp_metadata_value" href={{href}}>{{.text true label}}</a>}}

private def renderMetadataCodeValue (value : Data.AuthorId) : Verso.Output.Html :=
  {{<span class="bp_metadata_value"><code>s!"{value}"</code></span>}}

private def renderMetadataCodeLinkValue (href : String) (value : Data.AuthorId) : Verso.Output.Html :=
  {{<a class="bp_metadata_link bp_metadata_value" href={{href}}><code>s!"{value}"</code></a>}}

private def sourceSpanPages (spans : Array Source.Span) : Array String :=
  spans.foldl
    (init := #[])
    fun pages span =>
      match span.page with
      | none => pages
      | some rawPage =>
          let page := rawPage.trimAscii.toString
          if page.isEmpty then pages else pushUniqueString pages page

private def sourcePagesSummary (pages : Array String) : String :=
  match pages.toList with
  | [] => ""
  | [page] => s!"p. {page}"
  | _ => s!"pp. {String.intercalate ", " pages.toList}"

private def sourceTextRangeSummary (range : Source.TextRange) : String :=
  let lineSummary :=
    if range.startLine == range.endLine then
      s!"{range.startLine}"
    else
      s!"{range.startLine}-{range.endLine}"
  s!"text {range.path}:{lineSummary}"

private def sourcePdfSpanSummary (span : Source.PdfSpan) : String :=
  match span.image with
  | Option.some image => s!"pdf {span.path}; image {image}"
  | Option.none => s!"pdf {span.path}"

private def sourceSpanSummary (span : Source.Span) : String :=
  let parts : Array String := #[]
  let parts :=
    match span.citation with
    | Option.some citation =>
        let citation := citation.trimAscii.toString
        if citation.isEmpty then parts else parts.push s!"citation {citation}"
    | Option.none => parts
  let parts :=
    match span.anchor with
    | Option.some anchor =>
        let anchor := anchor.trimAscii.toString
        if anchor.isEmpty then parts else parts.push s!"anchor {anchor}"
    | Option.none => parts
  let parts :=
    match span.page with
    | Option.some rawPage =>
        let page := rawPage.trimAscii.toString
        if page.isEmpty then parts else parts.push s!"page {page}"
    | Option.none => parts
  let parts :=
    match span.text with
    | Option.some textRange => parts.push (sourceTextRangeSummary textRange)
    | Option.none => parts
  let parts :=
    match span.pdf with
    | Option.some pdf => parts.push (sourcePdfSpanSummary pdf)
    | Option.none => parts
  String.intercalate "; " parts.toList

private def sourceSpanCitations (spans : Array Source.Span) : Array String :=
  spans.foldl
    (init := #[])
    fun citations span =>
      match span.citation with
      | none => citations
      | some rawCitation =>
          let citation := rawCitation.trimAscii.toString
          if citation.isEmpty then citations else pushUniqueString citations citation

private def sourceRefsCitations (sourceRefs : Array Source.Ref) : Array String :=
  sourceRefs.foldl
    (init := #[])
    fun citations sourceRef =>
      (sourceSpanCitations sourceRef.spans).foldl pushUniqueString citations

private def sourceRefSummary (sourceRef : Source.Ref) : String :=
  let pages := sourceSpanPages sourceRef.spans
  let pageSummary := sourcePagesSummary pages
  if pageSummary.isEmpty then
    sourceRef.document
  else
    s!"{sourceRef.document} {pageSummary}"

private def sourceRefTitle (sourceRef : Source.Ref) : String :=
  let spanSummary :=
    sourceRef.spans.map sourceSpanSummary |>.toList |>.filter (fun summary => !summary.isEmpty)
  if spanSummary.isEmpty then
    s!"Original source document {sourceRef.document}"
  else
    s!"Original source document {sourceRef.document}: {String.intercalate " | " spanSummary}"

private def sourceRefsChipText (sourceRefs : Array Source.Ref) : String :=
  match sourceRefsCitations sourceRefs |>.toList with
  | [citation] => s!"source: {citation}"
  | _ =>
      if sourceRefs.size == 1 then
        "source 1"
      else
        s!"sources {sourceRefs.size}"

private def sourceRefsPanelTitle (sourceRefs : Array Source.Ref) : String :=
  if sourceRefs.size == 1 then
    "Original source"
  else
    s!"Original sources ({sourceRefs.size})"

private def sourceRefsPanelMeta (sourceRefs : Array Source.Ref) : String :=
  if sourceRefs.size == 1 then
    "Source provenance preview"
  else
    "Source provenance previews"

private def sourceRefsChipTitle (sourceRefs : Array Source.Ref) : String :=
  let summaries := sourceRefs.map sourceRefSummary |>.toList
  if summaries.isEmpty then
    "Original source provenance"
  else
    s!"Original source provenance: {String.intercalate " | " summaries}"

private def sourceSpanPreviewText (span : Source.Span) : String :=
  let summary := sourceSpanSummary span
  if summary.isEmpty then
    "Source span recorded without page, anchor, text, or PDF location"
  else
    summary

private def renderSourceSpanPreview (span : Source.Span) : Verso.Output.Html :=
  open Verso.Output.Html in
  let summary := sourceSpanPreviewText span
  {{
    <li class="bp_source_ref_panel_span">
      <span class="bp_source_ref_panel_span_text">{{.text true summary}}</span>
    </li>
  }}

private def renderSourceRefPreviewItem (sourceRef : Source.Ref) : Verso.Output.Html :=
  open Verso.Output.Html in
  let summary := sourceRefSummary sourceRef
  let title := sourceRefTitle sourceRef
  let spanNodes :=
    if sourceRef.spans.isEmpty then
      #[{{
        <li class="bp_source_ref_panel_span bp_source_ref_panel_span_empty">
          "No source span recorded."
        </li>
      }}]
    else
      sourceRef.spans.map renderSourceSpanPreview
  {{
    <li class="bp_source_ref_panel_item"
        title={{title}}
        data-bp-source-document={{sourceRef.document}}>
      <div class="bp_source_ref_panel_document">
        <span class="bp_source_ref_panel_key">"Document"</span>
        <code>{{.text true sourceRef.document}}</code>
      </div>
      <div class="bp_source_ref_panel_summary">{{.text true summary}}</div>
      <ul class="bp_source_ref_panel_spans">
        {{spanNodes}}
      </ul>
    </li>
  }}

private def renderSourceRefPreview (sourceRefs : Array Source.Ref) : Verso.Output.Html :=
  open Verso.Output.Html in
  let chipText := sourceRefsChipText sourceRefs
  let chipTitle := sourceRefsChipTitle sourceRefs
  let panelTitle := sourceRefsPanelTitle sourceRefs
  let panelMeta := sourceRefsPanelMeta sourceRefs
  let previewItems := sourceRefs.map renderSourceRefPreviewItem
  {{
    <div class="bp_relation_wrap bp_source_ref_wrap">
      <button type="button"
          class="bp_relation_chip bp_source_ref_chip"
          title={{chipTitle}}
          aria-expanded="false">
        {{.text true chipText}}
      </button>
      <div class="bp_relation_panel bp_source_ref_panel">
        <div class="bp_relation_panel_header">
          <div class="bp_relation_panel_title">{{.text true panelTitle}}</div>
          <div class="bp_relation_panel_meta">{{.text true panelMeta}}</div>
        </div>
        <div class="bp_relation_panel_body bp_source_ref_panel_body">
          <div class="bp_relation_preview_surface bp_source_ref_preview_surface">
            <div class="bp_relation_preview_header">
              <div class="bp_relation_preview_label">"Preview"</div>
              <div class="bp_relation_preview_heading bp_preview_header_heading">
                <div class="bp_relation_preview_title">{{.text true panelTitle}}</div>
                <a class="bp_relation_preview_header_label bp_preview_header_label" hidden></a>
              </div>
            </div>
            <div class="bp_relation_preview_body bp_source_ref_preview_body">
              <ul class="bp_source_ref_panel_list">
                {{previewItems}}
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
  }}

def renderSourceHeaderExtra? (sourceRefs : Array Source.Ref) : Option HeaderExtra :=
  if sourceRefs.isEmpty then
    none
  else
    some <| HeaderExtra.source (renderSourceRefPreview sourceRefs)

private def HeaderExtras.withSourceRefs (extras : HeaderExtras) (sourceRefs : Array Source.Ref) :
    HeaderExtras :=
  match extras.source? with
  | some _ => extras
  | none => { extras with source? := renderSourceHeaderExtra? sourceRefs }

private def renderOwnerMetadataItem (data : BlockData) : Verso.Output.Html :=
  open Verso.Output.Html in
  let avatar : Verso.Output.Html :=
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

private def renderStatementMetadataPanel (data : BlockData) : Verso.Output.Html :=
  open Verso.Output.Html in
  let metadata := data.metadataPresentation
  let ownerItem := renderOwnerMetadataItem data
  let effortNode : Verso.Output.Html :=
    match metadata.effort with
    | some effort => renderMetadataItem "Effort" (renderMetadataTextValue effort)
    | none => .empty
  let priorityNode : Verso.Output.Html :=
    match metadata.priority with
    | some priority => renderMetadataItem "Priority" (renderMetadataTextValue priority)
    | none => .empty
  let prNode : Verso.Output.Html :=
    match metadata.prUrl with
    | some href => renderMetadataItem "PR" (renderMetadataLinkValue href "link")
    | none => .empty
  let tagNodes : Verso.Output.Html :=
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

/--
Context needed to render the reusable HTML shell for an informal Blueprint block.

Manual traversal remains responsible for resolving the values in this context:
HTML IDs, header extras, and the resolved display number.
-/
structure InformalBlockRenderContext where
  numberText : String
  captionText? : Option String := none
  attrs : Array (String × String) := #[]
  titleRowAttrs? : Option (Array (String × String)) := none
  headerExtras : HeaderExtras := {}
  sourceRefs : Array Source.Ref := #[]
  folded : Bool := false

/--
Build shell context for a concrete informal block.

Statement and proof headings use different fallback captions. This helper keeps
that policy out of phase-specific renderers: callers provide the caption they
resolved for each block kind, and the shared renderer chooses the one that
matches the block.
-/
def InformalBlockRenderContext.forBlock
    (data : BlockData)
    (numberText : String)
    (statementCaption? : Option String := none)
    (proofCaption? : Option String := none)
    (attrs : Array (String × String) := #[])
    (titleRowAttrs? : Option (Array (String × String)) := none)
    (headerExtras : HeaderExtras := {})
    (sourceRefs : Array Source.Ref := #[])
    (folded : Bool := false) :
    InformalBlockRenderContext :=
  let captionText? :=
    match data.kind with
    | .proof => proofCaption?
    | .statement _ => statementCaption?
  let sourceRefs :=
    if sourceRefs.isEmpty then
      match data.sourceRef with
      | Option.some sourceRef => #[sourceRef]
      | Option.none => #[]
    else
      sourceRefs
  {
    numberText
    captionText?
    attrs
    titleRowAttrs?
    headerExtras
    sourceRefs
    folded
  }

/--
Complete render model for one informal Blueprint block.

The block shell is shared by normal Manual rendering and manifest-backed
renderers such as slides. Phase-specific callers still own data lookup and body
rendering, but the final assembly order is centralized here: the informal block
shell first, followed by any rendered companion panels, optionally wrapped for a
particular embedding surface.
-/
structure InformalBlockRenderModel where
  data : BlockData
  context : InformalBlockRenderContext
  content : Array Verso.Output.Html := #[]
  companionPanels : Array Verso.Output.Html := #[]
  wrapperClass? : Option String := none
  showHeader : Bool := true

/--
Genre-neutral inputs for the reusable Blueprint informal-block shell.

Callers own phase-specific data lookup and body rendering. This shell owns the
stable Blueprint wrapper, heading, title row, extras slot, metadata slot, and
content container assembly.
-/
structure InformalBlockShell where
  style : BlockKindRenderStyle
  labelText : String
  numberText : String
  captionText : String
  attrs : Array (String × String) := #[]
  titleRowAttrs? : Option (Array (String × String)) := none
  headerExtras : HeaderExtras := {}
  metadataPanel : Verso.Output.Html := .empty
  folded : Bool := false
  showHeader : Bool := true

private def renderShellTitleRow (shell : InformalBlockShell) : Verso.Output.Html :=
  let titleRow := renderBlockTitleRow shell.style shell.labelText shell.numberText shell.captionText
  match shell.titleRowAttrs? with
  | some attrs => .tag "a" attrs titleRow
  | none => titleRow

def renderInformalBlockShell (shell : InformalBlockShell)
    (content : Verso.Output.Html) : Verso.Output.Html :=
  open Verso.Output.Html in
  let style := shell.style
  let wrapperClass := s!"bp_wrapper bp_kind_{style.kindCss}_wrapper {style.kindCss}_thmwrapper {style.wrapperCss}"
  let headingClass := s!"bp_heading bp_kind_{style.kindCss}_heading {style.headingCss}"
  let contentClass := s!"bp_content bp_kind_{style.kindCss}_content {style.contentCss}"
  let titleRow := renderShellTitleRow shell
  let extras := renderHeaderExtras shell.headerExtras
  if !shell.showHeader then
    {{
      <div class={{wrapperClass}} title={{shell.labelText}} {{shell.attrs}}>
        {{shell.metadataPanel}}
        <div class={{contentClass}}> {{content}} </div>
      </div>
    }}
  else if shell.folded then
    {{
      <details class={{wrapperClass}} title={{shell.labelText}} {{shell.attrs}}>
        <summary class={{headingClass}}>
          {{titleRow}}
          {{extras}}
        </summary>
        {{shell.metadataPanel}}
        <div class={{contentClass}}> {{content}} </div>
      </details>
    }}
  else
    {{
      <div class={{wrapperClass}} title={{shell.labelText}} {{shell.attrs}}>
        <div class={{headingClass}}>
          {{titleRow}}
          {{extras}}
        </div>
        {{shell.metadataPanel}}
        <div class={{contentClass}}> {{content}} </div>
      </div>
    }}

/--
Render the reusable HTML shell for an informal Blueprint block.

This deliberately has no dependency on Manual traversal state. Callers provide
already-rendered content plus the resolved metadata in
{name}`InformalBlockRenderContext`.
-/
def renderInformalBlockHtml (data : BlockData) (ctx : InformalBlockRenderContext)
    (content : Array Verso.Output.Html) (showHeader : Bool := true) : Verso.Output.Html :=
  open Verso.Output.Html in
  let style := blockKindRenderStyle data
  let labelText := s!"{data.label}"
  let metadataPanel : Verso.Output.Html :=
    match data.kind with
    | .proof => .empty
    | .statement _ => renderStatementMetadataPanel data
  let headerExtras := ctx.headerExtras.withSourceRefs ctx.sourceRefs
  renderInformalBlockShell
    {
      style
      labelText
      numberText := ctx.numberText
      captionText := ctx.captionText?.getD style.kindText
      attrs := ctx.attrs
      titleRowAttrs? := ctx.titleRowAttrs?
      headerExtras
      metadataPanel
      folded := ctx.folded
      showHeader
    }
    (.seq content)

/-- HTML attributes for an optional CSS class string. -/
def htmlClassAttrs (className : String) : Array (String × String) :=
  if className.isEmpty then #[] else #[("class", className)]

/-- Render a complete informal block model, including companion panels. -/
def renderInformalBlockModel (model : InformalBlockRenderModel) : Verso.Output.Html :=
  let blockHtml := renderInformalBlockHtml model.data model.context model.content
    (showHeader := model.showHeader)
  let html := Verso.Output.Html.seq (#[blockHtml] ++ model.companionPanels)
  match model.wrapperClass? with
  | some className => Verso.Output.Html.tag "div" (htmlClassAttrs className) html
  | none => html

end Informal
