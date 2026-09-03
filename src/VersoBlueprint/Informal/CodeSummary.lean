/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import Verso
public import VersoManual
public import VersoBlueprint.Graph
public import VersoBlueprint.Informal.Block.Common
public import VersoBlueprint.Informal.LeanCodePreviewKey
public import VersoBlueprint.Informal.LeanCodeLink
public import VersoBlueprint.Lib.HoverRender

public section

namespace Informal
namespace CodeSummary

open Verso Doc Elab
open Lean Elab

/-!
`CodeSummary` computes the heading-level Lean status/summary fragments for informal blocks.

This module intentionally owns the high-level overview for one informal node:
status marks, declaration-summary tooltips, and code-panel indicators.

It does not own HTML-cache-backed code-preview hovers for explicit links to code;
that narrower responsibility lives in `Informal.LeanCodeLink` /
`Informal.LeanCodePreview`.

Public API:
- `ComputedData`: normalized code inputs for one block heading.
- `RenderParts`: rendered heading fragments consumed by callers.
- `renderParts`: main entry point that derives status badge + Lean link node.
-/

/--
Presentation inputs used to compute Lean summary UI for one informal block.

`source` is the optional source selected for this particular heading or panel
summary (`none` / `some inline` / `some external`). It is not the complete set of
Lean associations owned by the label; semantic association data lives in
`Data.Node.leanCode`.

Callers that need a single heading source should pass `source` after applying
the presentation selection rule, typically via `BlockCodeData.ofHintAndInline`.
-/
structure ComputedData where
  /-- URL to the rendered Lean panel for this block, when available. -/
  codeHref : Option String := none
  /-- Presentation source used for status and tooltip semantics. -/
  source : Option BlockCodeData := none

/--
Rendered fragments produced by `CodeSummary.renderParts` for an informal block heading.
-/
structure RenderParts where
  /-- Optional status icon rendered next to the statement heading. -/
  statusMark : Option BlockStatusMark := none
  /-- Optional Lean badge/link node (`L∃∀N`) with tooltip wrapper. -/
  codeEntry : Output.Html := .empty

structure PanelIndicatorParts where
  /-- Summary text exposed on the enclosing code-panel `<summary>` title. -/
  summaryTitle : String := ""
  /-- Top-right indicator node for the code panel summary row. -/
  indicator : Output.Html := .empty

inductive DeclSummaryKind where
  | definition
  | theoremLike
deriving Inhabited, Repr, BEq

/--
Normalized declaration summary row shared by inline and external Lean summary UI.

`present = false` is used only for external references that failed to resolve.
-/
structure DeclSummaryItem where
  /-- Name shown in the code-summary panel. -/
  displayName : Name
  /--
  Canonical declaration name used for the default Lean-code preview lookup.

  External references may be written with an opened or namespace-local name, but
  traversal stores rendered Lean-code previews under the resolved canonical name.
  -/
  previewName : Name
  /-- Explicit HTML-cache preview lookup key, when it differs from `previewName`. -/
  previewLookupKey? : Option String := none
  href : Option String := none
  kind : DeclSummaryKind := .definition
  status : Data.ProvedStatus := .proved
  present : Bool := true
deriving Inhabited, Repr

private structure SummaryTooltipSection where
  title : String := ""
  items : Array DeclSummaryItem := #[]
  emptyText : String := "No associated Lean declarations."

private def declSummaryStatusText (item : DeclSummaryItem) : String :=
  (item.status.presentation (present := item.present)).summaryText

private def declSummaryStatusClass (item : DeclSummaryItem) : String :=
  (item.status.presentation (present := item.present)).codeDeclClass

private def renderDeclSummaryItems (items : Array DeclSummaryItem) : Array Output.Html :=
  open Verso.Output.Html in
  items.map fun item =>
    let nameNode : Output.Html :=
      let txt := {{<code>{{.text true s!"{item.displayName}"}}</code>}}
      match item.href with
      | some href =>
        Informal.LeanCodeLink.renderResolved
          item.previewName txt "" (some href)
          (previewTitle := s!"{item.displayName}")
          (previewLookupKey? := item.previewLookupKey?)
      | none => txt
    {{
      <li class="bp_code_decl_item">
        <span class="bp_code_decl_name">{{nameNode}}</span>
        <span class={{s!"bp_code_decl_status {declSummaryStatusClass item}"}}>
          {{.text true s!"[{declSummaryStatusText item}]"}}
        </span>
      </li>
    }}

private def summaryTooltipSection (tooltipSection : SummaryTooltipSection) : Output.Html :=
  let items :=
    if tooltipSection.items.isEmpty then
      #[codeHoverEmptyItem tooltipSection.emptyText]
    else
      renderDeclSummaryItems tooltipSection.items
  codeHoverSection tooltipSection.title items

private def renderSummaryPreviewBody (sections : Array SummaryTooltipSection) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_code_summary_preview_content">
      {{.seq (sections.map summaryTooltipSection)}}
    </div>
  }}

private def renderExternalRenderFailureItems (failures : Array ExternalRenderFailure)
    (hrefOf : Name → Option String) : Array Output.Html :=
  open Verso.Output.Html in
  failures.map fun failure =>
    let href :=
      if failure.decl.present then
        match hrefOf failure.decl.canonical with
        | some href => some href
        | none => hrefOf failure.decl.written
      else
        hrefOf failure.decl.written
    let declNode :=
      let txt := {{<code>{{.text true s!"{failure.decl.written}"}}</code>}}
      match href with
      | some href =>
        Informal.LeanCodeLink.renderResolved
          failure.decl.canonical txt "" (some href)
          (previewTitle := s!"{failure.decl.canonical}")
      | none => txt
    codeHoverListItem {{
      <span>{{declNode}}": " {{.text true failure.message}}</span>
    }}

private def inlineDeclSummaryItems (definedDefs definedTheorems : Array CodeDeclData)
    (hrefOf : Name → Option String) (previewLookupKey? : Option String := none) :
    Array DeclSummaryItem :=
  let defs := definedDefs.map fun decl =>
    {
      displayName := decl.name
      previewName := decl.name
      previewLookupKey?
      href := hrefOf decl.name
      kind := .definition
      status := decl.provedStatus
    }
  let theoremLikes := definedTheorems.map fun decl =>
    {
      displayName := decl.name
      previewName := decl.name
      previewLookupKey?
      href := hrefOf decl.name
      kind := .theoremLike
      status := decl.provedStatus
    }
  defs ++ theoremLikes

private def incompleteSummaryItems (items : Array DeclSummaryItem) : Array DeclSummaryItem :=
  items.filter fun item => !item.present || item.status.isIncomplete

def externalDeclKindText? (decl : Data.ExternalRef) : Option String :=
  if !decl.present then
    none
  else
    match decl.kind with
    | .definition => some "definition"
    | .proposition => some "proposition"
    | .lemma => some "lemma"
    | .theorem => some "theorem"
    | .corollary => some "corollary"

private def externalSummaryKind (decl : Data.ExternalRef) : DeclSummaryKind :=
  match decl.kind with
  | .definition => .definition
  | .proposition | .lemma | .theorem | .corollary => .theoremLike

private def externalDeclHref (decl : Data.ExternalRef) (hrefOf : Name → Option String) : Option String :=
  if decl.present then
    match hrefOf decl.canonical with
    | some href => some href
    | none => hrefOf decl.written
  else
    hrefOf decl.written

private def externalDeclSummaryItems (decls : Array Data.ExternalRef)
    (hrefOf : Name → Option String) : Array DeclSummaryItem :=
  decls.map fun decl =>
    {
      displayName := decl.written
      previewName := decl.canonical
      href := externalDeclHref decl hrefOf
      kind := externalSummaryKind decl
      status := decl.provedStatus
      present := decl.present
    }

private def summaryPreviewItems (label : Data.Label) (cdata : ComputedData)
    (hrefOf : Name → Option String) : Array DeclSummaryItem :=
  match cdata.source with
  | some (.inline codeData) =>
    inlineDeclSummaryItems codeData.definedDefs codeData.definedTheorems hrefOf
      (some <| Informal.LeanCodePreviewKey.inlineLookupKey label)
  | some (.external decls) =>
    externalDeclSummaryItems decls hrefOf
  | none =>
    #[]

private def summaryPreviewEmptyText (_cdata : ComputedData) : String :=
  "No associated Lean code or declarations."

private def renderSummaryPreview (label : Data.Label) (cdata : ComputedData)
    (hrefOf : Name → Option String) : Output.Html :=
  let items := summaryPreviewItems label cdata hrefOf
  let sectionTitle :=
    if items.isEmpty then "Lean status" else "Associated Lean declarations"
  let sections := #[{
    title := sectionTitle
    items
    emptyText := summaryPreviewEmptyText cdata
  }]
  let failures :=
    match cdata.source with
    | some (.external decls) => externalRenderFailures decls
    | _ => #[]
  if failures.isEmpty then
    renderSummaryPreviewBody sections
  else
    let failureSection := codeHoverSection "Render diagnostics" (renderExternalRenderFailureItems failures hrefOf)
    open Verso.Output.Html in
    {{
      <div class="bp_code_summary_preview_content">
        {{.seq (sections.map summaryTooltipSection)}}
        {{failureSection}}
      </div>
    }}

private structure CodeEntryVisual where
  classSuffix : String
  symbol : String
  absent : Bool := false
deriving Inhabited

private def codeEntryVisual (hasSource : Bool) (statusMark : BlockStatusMark) : CodeEntryVisual :=
  if !hasSource then
    { classSuffix := "absent", symbol := "X", absent := true }
  else
    let view := statusMark.status.presentation
    { classSuffix := view.codeEntryClassSuffix, symbol := view.codeEntrySymbol }

private structure ExternalRenderHealth where
  failureCount : Nat := 0
deriving Inhabited

private def ExternalRenderHealth.hasFailures (health : ExternalRenderHealth) : Bool :=
  health.failureCount > 0

private def ExternalRenderHealth.summaryText (health : ExternalRenderHealth) : String :=
  externalRenderFailureSummaryText health.failureCount

private def externalRenderHealth (decls : Array Data.ExternalRef) : ExternalRenderHealth :=
  { failureCount := externalRenderFailureCount decls }

private def appendRenderHealthSummary (title : String) (health : ExternalRenderHealth) : String :=
  appendExternalRenderFailureSummary title health.failureCount

private def renderCodeHeadingRenderHealthBadge (health : ExternalRenderHealth) : Output.Html :=
  open Verso.Output.Html in
  if !health.hasFailures then
    .empty
  else
    {{<span class="bp_render_warning_badge bp_code_render_warning_badge" title={{health.summaryText}}>"!"</span>}}

private def renderCodeEntryNode (href : Option String) (title : String) (visual : CodeEntryVisual)
    (renderHealth : ExternalRenderHealth := {}) : Output.Html :=
  open Verso.Output.Html in
  let linkClass := s!"bp_code_link bp_code_link_status bp_code_link_status_{visual.classSuffix}" ++
    (if visual.absent then " bp_code_link_empty" else "")
  let body : Output.Html := {{
    {{renderCodeHeadingRenderHealthBadge renderHealth}}
    <span class="bp_code_status_symbol">{{.text true visual.symbol}}</span>
    <span class="bp_code_link_label">"L∃∀N"</span>
  }}
  match href with
  | some href =>
      {{<a class={{linkClass}} href={{href}} title={{title}}>{{body}}</a>}}
  | none =>
      {{<span class={{linkClass}} title={{title}}>{{body}}</span>}}

private def codeSummaryPreviewId : String := "bp-code-summary"

private def renderCodeSummaryPreview (previewTitle : String) (trigger : Output.Html)
    (body : Output.Html) (focusable : Bool := false) (ariaLabel? : Option String := none) : Output.Html :=
  Informal.HoverRender.templatePreviewRoot
    "bp_code_summary_preview_root"
    "bp_code_summary_preview_wrap"
    "bp_code_summary_preview_wrap_active"
    "bp_code_summary_preview_tpl"
    "data-bp-preview-id"
    codeSummaryPreviewId
    previewTitle
    ".bp_code_summary_preview_panel"
    ".bp_code_summary_preview_title"
    ".bp_code_summary_preview_body"
    ".bp_code_summary_preview_close"
    (titleAttr? := some "data-bp-preview-title")
    trigger
    body
    Informal.HoverRender.codeSummaryPreviewPanel
    (focusable := focusable)
    (ariaLabel? := ariaLabel?)

private def renderCodeEntryWrap (href : Option String) (title previewTitle : String)
    (previewBody : Output.Html) (visual : CodeEntryVisual)
    (renderHealth : ExternalRenderHealth := {}) : Output.Html :=
  renderCodeSummaryPreview previewTitle
    (renderCodeEntryNode href title visual renderHealth)
    previewBody
    (focusable := href.isNone)
    (ariaLabel? := if href.isNone then some title else none)

private def axisCompletionText : Nat → String
  | 0 => "completed"
  | _ + 1 => "with sorries"

private def completionAxisText (statementSorryCount proofSorryCount : Nat) : String :=
  s!"Statement: {axisCompletionText statementSorryCount}; Proof: {axisCompletionText proofSorryCount}"

/--
Build completion status from declaration-level axis counts.

Counts are only used as presence signals (non-zero means "with sorries" on that axis);
they are not interpreted as precise sorry-reference totals.
-/
private def completionStatusFromCounts (statementSorryCount proofSorryCount : Nat) : Data.ProvedStatus :=
  Data.ProvedStatus.ofSorryFlags (statementSorryCount > 0) (proofSorryCount > 0)

private def completionStatusMark (statementSorryCount proofSorryCount : Nat) : BlockStatusMark :=
  let status := completionStatusFromCounts statementSorryCount proofSorryCount
  if status.isProved then
    {
      status
      title := completionAxisText statementSorryCount proofSorryCount
    }
  else
    {
      status
      title := completionAxisText statementSorryCount proofSorryCount
      symbolOverride? := some "⚠"
    }

private def statusMarkFromHealth (health : Informal.Graph.CodeHealth) : BlockStatusMark :=
  if health.hasMissingExternalDecls then
    {
      status := .missing
      title := s!"External Lean names: {health.presentDecls} present, {health.missingDecls} missing (statement/proof completion unknown)"
    }
  else
    if health.hasAxiomLike then
      {
        status := .axiomLike
        title := "Lean declarations include at least one axiom-like constant (no body)"
      }
    else
      completionStatusMark health.statementAxisCount health.proofAxisCount

private def inlineStatusMark (codeData : InlineCodeData) : BlockStatusMark :=
  let health := Informal.Graph.codeHealthOfBlockSource .definition {} (some (.inline codeData))
  if health.hasAxiomLike then
    {
      status := .axiomLike
      title := "Lean declarations include at least one axiom-like constant (no body)"
    }
  else
    statusMarkFromHealth health

/--
Compute heading status semantics from canonical block code source using explicit
statement/proof axis wording.

Case semantics:
- `.inline`: evaluates statement (`type`) and proof (`body`) sorries independently.
- `.external`: uses `externalHeadingAggregate` + `externalStatusMark`
  (missing references dominate).
- `none`: defaults to a completed statement/proof mark.

This function computes mark semantics only. Visibility gating
(for example requiring a `codeHref` in some inline/no-hint paths) is handled by
`renderParts`.
-/
private def statusMarkFromResolvedCodeSource : BlockCodeData → BlockStatusMark
  | .external decls =>
    statusMarkFromHealth (Informal.Graph.codeHealthOfBlockSource .definition {} (some (.external decls)))
  | .inline codeData =>
    inlineStatusMark codeData

private def statusMarkFromCodeSource
    (source? : Option BlockCodeData) : BlockStatusMark :=
  source?.map statusMarkFromResolvedCodeSource |>.getD (completionStatusMark 0 0)

private def sortDeclsByCommand (decls : Array CodeDeclData) : Array CodeDeclData :=
  decls.qsort (fun a b =>
    a.commandIndex < b.commandIndex ||
    (a.commandIndex == b.commandIndex && a.name.toString < b.name.toString))

private def progressSegmentClass (missing hasSorry : Bool) : String :=
  if missing then
    "bp_code_progress_segment bp_code_progress_segment_missing"
  else if hasSorry then
    "bp_code_progress_segment bp_code_progress_segment_sorry"
  else
    "bp_code_progress_segment bp_code_progress_segment_ok"

private def codeSummaryText (label : Data.Label)
    (definedDefs definedTheorems : Array CodeDeclData) : String :=
  if definedDefs.isEmpty && definedTheorems.isEmpty then
    s!"{label}"
  else
    let definedDefNames := definedDefs.map (·.name)
    let definedTheoremNames := definedTheorems.map (·.name)
    let defs :=
      if definedDefNames.isEmpty then
        "none"
      else
        String.intercalate ", " (definedDefNames.toList.map toString)
    let thms :=
      if definedTheoremNames.isEmpty then
        "none"
      else
        String.intercalate ", " (definedTheoremNames.toList.map toString)
    let summaryItems := inlineDeclSummaryItems definedDefs definedTheorems (fun _ => none)
    let sorries := incompleteSummaryItems summaryItems
    let sorriesTxt :=
      if sorries.isEmpty then
        "none"
      else
        String.intercalate ", " (sorries.toList.map fun item => s!"{item.displayName} [{declSummaryStatusText item}]")
    s!"{label}\nLean definitions: {defs}\nLean theorems/lemmas: {thms}\nSorries: {sorriesTxt}"

private def wrapPanelIndicator (label : Data.Label) (summaryTitle : String)
    (node previewBody : Output.Html) : Output.Html :=
  open Verso.Output.Html in
  {{
    <span class="bp_code_summary_indicator">
      {{renderCodeSummaryPreview
        s!"{label}"
        node
        previewBody
        (focusable := true)
        (ariaLabel? := some summaryTitle)}}
    </span>
  }}

private def renderInlinePanelIndicator (label : Data.Label) (codeData : InlineCodeData)
    (hrefOf : Name → Option String) : PanelIndicatorParts :=
  open Verso.Output.Html in
  let orderedDecls := sortDeclsByCommand (codeData.definedDefs ++ codeData.definedTheorems)
  let previewBody := renderSummaryPreview label { source := some (.inline codeData) } hrefOf
  let summaryTitle := s!"Lean code for {label}: {codeSummaryText label codeData.definedDefs codeData.definedTheorems}"
  let indicator : Output.Html :=
    if orderedDecls.isEmpty then
      .empty
    else
      let segments := orderedDecls.map fun decl =>
        let hasSorry := decl.provedStatus.isIncomplete
        let statusView := decl.provedStatus.presentation
        let cls := progressSegmentClass false hasSorry
        let weight := max decl.weight 1
        let title :=
          if hasSorry then
            if decl.provedStatus.containsExplicitSorry then
              s!"{decl.name}: {statusView.externalPanelText}"
            else
              s!"{decl.name}: {statusView.summaryText}"
          else
            s!"{decl.name}: complete"
        {{
          <span class={{cls}} title={{title}} style={{s!"flex: {weight} 1 0%"}}></span>
        }}
      let bar := {{<span class="bp_code_progress" aria-label="Lean declaration progress">{{segments}}</span>}}
      wrapPanelIndicator label summaryTitle bar previewBody
  {
    summaryTitle
    indicator
  }

private def pluralizeKindText (kind : String) : String :=
  match kind with
  | "lemma" => "lemmas"
  | "theorem" => "theorems"
  | "definition" => "definitions"
  | "corollary" => "corollaries"
  | _ => kind ++ "s"

private def externalIndicatorKindText?
    (decls : Array Data.ExternalRef) (health : Informal.Graph.CodeHealth) : Option String :=
  if health.missingDecls > 0 || decls.isEmpty then
    none
  else
    let kinds := decls.filterMap externalDeclKindText?
    if kinds.size != decls.size || kinds.isEmpty then
      none
    else
      let first := kinds[0]!
      if kinds.all (· == first) then
        some first
      else
        none

private def externalIndicatorText
    (decls : Array Data.ExternalRef) (health : Informal.Graph.CodeHealth) : String :=
  let declText :=
    match externalIndicatorKindText? decls health with
    | some kind =>
      if health.totalDecls == 1 then
        s!"1 {kind}"
      else
        s!"{health.totalDecls} {pluralizeKindText kind}"
    | none =>
      if health.totalDecls == 1 then
        "1 declaration"
      else
        s!"{health.totalDecls} declarations"
  if health.missingDecls > 0 then
    s!"{declText}, {health.missingDecls} missing"
  else if health.anyGapCount > 0 then
    if health.totalDecls == 1 then
      s!"{declText}, incomplete"
    else
      s!"{declText}, {health.anyGapCount} incomplete"
  else
    declText

private structure ExternalIndicatorPresentation where
  className : String
  iconText : String := "●"
  title : String
  badgeText : String
deriving Inhabited

private def externalIndicatorPresentation
    (decls : Array Data.ExternalRef) (health : Informal.Graph.CodeHealth) :
    ExternalIndicatorPresentation :=
  let badgeText := externalIndicatorText decls health
  if health.missingDecls > 0 then
    {
      className := "bp_external_status_missing"
      title := s!"Lean declarations: {health.presentDecls}/{health.totalDecls} present ({health.missingDecls} missing)"
      badgeText
    }
  else if health.anyGapCount > 0 then
    {
      className := "bp_external_status_sorry"
      title := s!"Lean declarations: all present, {health.anyGapCount} incomplete"
      badgeText
    }
  else
    {
      className := "bp_external_status_ok"
      title := s!"Lean declarations: all {health.totalDecls} present"
      badgeText
    }

private def renderExternalPanelIndicator (decls : Array Data.ExternalRef)
    (label : Data.Label) (hrefOf : Name → Option String) : PanelIndicatorParts :=
  open Verso.Output.Html in
  let health := Informal.Graph.codeHealthOfBlockSource .definition {} (some (.external decls))
  let renderHealth := externalRenderHealth decls
  let previewBody := renderSummaryPreview label { source := some (.external decls) } hrefOf
  let presentation := externalIndicatorPresentation decls health
  let summaryTitle :=
    s!"Lean code for {label}: " ++ appendRenderHealthSummary
      (externalCodeEntryTitle health.presentDecls health.totalDecls health.missingDecls health.anyGapCount)
      renderHealth
  let badgeTitle :=
    appendRenderHealthSummary presentation.title renderHealth
  let badge : Output.Html := {{
    <span class={{s!"bp_external_status_badge bp_external_status_badge_summary {presentation.className}"}} title={{badgeTitle}}>
      <span class={{s!"bp_external_status_icon {presentation.className}"}}>{{.text true presentation.iconText}}</span>
      <span class="bp_external_status_badge_text">{{.text true presentation.badgeText}}</span>
    </span>
  }}
  {
    summaryTitle
    indicator := wrapPanelIndicator label summaryTitle badge previewBody
  }

/--
Render the top-right code-panel indicator from canonical code-source data.

Inline blocks use the weighted progress bar; external references keep the pill-style
indicator for now, but both paths share the same normalized declaration summary model
for hover content.
-/
def renderPanelIndicator (label : Data.Label) (cdata : ComputedData)
    (hrefOf : Name → Option String) : PanelIndicatorParts :=
  match cdata.source with
  | some (.inline codeData) =>
    renderInlinePanelIndicator label codeData hrefOf
  | some (.external decls) =>
    renderExternalPanelIndicator decls label hrefOf
  | none =>
    { summaryTitle := s!"Lean code for {label}: no associated Lean declarations" }

/--
Render Lean summary UI for an informal block heading.

Inputs come from canonical block/code data:
- `codeHref`: link to the generated Lean code block when available.
- `source`: resolved optional code source (inline/external).

Output policy:
- `.proof` headings return an empty `RenderParts`.
- statement headings with external refs always render a status mark and an external-summary tooltip.
- inline/no-hint headings hide the status mark when `codeHref` is absent.
-/
def renderParts (data : BlockData) (cdata : ComputedData) (hrefOf : Name → Option String) : RenderParts :=
  open Verso.Output.Html in
  match data.kind with
  | .proof => {}
  | .statement statementKind =>
    let externalDecls := cdata.source.map BlockCodeData.externalDecls |>.getD #[]
    let codeEntryPreviewBody := renderSummaryPreview data.label cdata hrefOf
    let previewTitle := s!"{data.label}"
    if !externalDecls.isEmpty then
      let health := Informal.Graph.codeHealthOfBlockSource statementKind {} cdata.source
      let renderHealth := externalRenderHealth externalDecls
      let codeEntryTitle :=
        appendRenderHealthSummary
          (externalCodeEntryTitle health.presentDecls health.totalDecls health.missingDecls health.anyGapCount)
          renderHealth
      let statusMark := statusMarkFromCodeSource cdata.source
      {
        statusMark := some statusMark
        codeEntry := renderCodeEntryWrap cdata.codeHref codeEntryTitle previewTitle codeEntryPreviewBody
          (codeEntryVisual true statusMark)
          renderHealth
      }
    else
      let inlineData? := cdata.source.bind BlockCodeData.inlineData?
      let hasInline := cdata.codeHref.isSome || inlineData?.isSome
      let hasSource := hasInline
      let codeEntryTitle : String :=
        if hasInline then
          "Lean declarations"
        else
          "No associated Lean declarations"
      let statusMarkCandidate := statusMarkFromCodeSource cdata.source
      let codeEntry : Output.Html :=
        renderCodeEntryWrap cdata.codeHref codeEntryTitle previewTitle codeEntryPreviewBody
          (codeEntryVisual hasSource statusMarkCandidate)
      let statusMark : Option BlockStatusMark :=
        if cdata.codeHref.isNone then
          none
        else
          some statusMarkCandidate
      { statusMark, codeEntry }

end CodeSummary
end Informal
