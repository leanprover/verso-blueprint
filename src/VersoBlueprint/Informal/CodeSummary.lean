/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Graph
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.LeanCodePreviewKey
import VersoBlueprint.Informal.LeanCodeLink
import VersoBlueprint.Lib.HoverRender

namespace Informal
namespace CodeSummary

open Verso Doc Elab
open Lean Elab

/-!
`CodeSummary` computes the heading-level Lean status/summary fragments for informal blocks.

This module intentionally owns the high-level overview for one informal node:
status marks from the captured realization assessment, plus declaration display
snapshots and code-panel indicators. The old per-declaration status payload remains
presentation only and cannot complete the node or certify a displayed sibling.

It does not own HTML-cache-backed code-preview hovers for explicit links to code;
that narrower responsibility lives in `Informal.LeanCodeLink` /
`Informal.LeanCodePreview`.

Public API:
- `ComputedData`: normalized code inputs for one block heading.
- `RenderParts`: rendered heading fragments consumed by callers.
- `renderParts`: main entry point that derives status badge + Lean link node.
-/

/-- All associated Lean inputs for a heading, or the inputs owned by an individual panel. -/
structure ComputedData where
  codeHref : Option String := none
  source : Option BlockCodeData := none
  /-- Traversed panels supply preview keys, independently of project declaration facts. -/
  inlineBlocks : InlineCodeBlocks := #[]

def ComputedData.ofInlineBlocks (blocks : InlineCodeBlocks) : ComputedData :=
  { source := (BlockCodeData.ofInlineBlocks blocks).nonempty?, inlineBlocks := blocks }

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
  /-- Reader-facing declaration kind, such as "theorem", or empty when unknown. -/
  kindText : String := ""
  status : Option Data.ProvedStatus := none
  present : Bool := true
deriving Inhabited, Repr

private def declSummaryStatusText (item : DeclSummaryItem) : String :=
  (declarationStatusPresentation item.status item.present).summaryText

private def declSummaryStatusClass (item : DeclSummaryItem) : String :=
  (declarationStatusPresentation item.status item.present).codeDeclClass

/-- One row per declaration: its status mark, name, kind, and status. -/
private def renderDeclSummaryItems (items : Array DeclSummaryItem) : Array Output.Html :=
  open Verso.Output.Html in
  items.map fun item =>
    let view := declarationStatusPresentation item.status item.present
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
        <span class={{s!"bp_code_decl_mark bp_code_link_status_{view.codeEntryClassSuffix}"}} "aria-hidden"="true">
          <span class="bp_code_status_symbol">{{.text true view.codeEntrySymbol}}</span>
        </span>
        <span class="bp_code_decl_name">{{nameNode}}</span>
        {{if item.kindText.isEmpty then .empty else
          {{<span class="bp_code_decl_kind">{{.text true item.kindText}}</span>}}}}
        <span class={{s!"bp_code_decl_status {view.codeDeclClass}"}}>
          {{.text true view.summaryText}}
        </span>
      </li>
    }}

private def renderExternalRenderFailureItems (failures : Array ExternalRenderFailure)
    (hrefOf : Name → Option String) : Array Output.Html :=
  open Verso.Output.Html in
  failures.map fun failure =>
    let href := failure.decl.href? hrefOf
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
      kindText := "definition"
      status := some decl.provedStatus
    }
  let theoremLikes := definedTheorems.map fun decl =>
    {
      displayName := decl.name
      previewName := decl.name
      previewLookupKey?
      href := hrefOf decl.name
      kindText := "theorem"
      status := some decl.provedStatus
    }
  defs ++ theoremLikes

private def incompleteSummaryItems (items : Array DeclSummaryItem) : Array DeclSummaryItem :=
  items.filter fun item => !item.present || item.status.any (·.isIncomplete)

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


private def externalDeclSummaryItems (decls : Array Data.ExternalRef)
    (hrefOf : Name → Option String) : Array DeclSummaryItem :=
  decls.map fun decl =>
    {
      displayName := decl.written
      previewName := decl.canonical
      href := decl.href? hrefOf
      kindText := (externalDeclKindText? decl).getD ""
      status := decl.provedStatus
      present := decl.present
    }

private def summaryPreviewItems (cdata : ComputedData)
    (hrefOf : Name → Option String) : Array DeclSummaryItem :=
  let source := cdata.source.getD {}
  let declarations := source.summaryLiterateDeclarations
  let previewKeys := cdata.inlineBlocks.foldl (init := ({} : Lean.NameMap String)) fun keys block =>
    let key := Informal.LeanCodePreviewKey.inlineLookupKey block.blockId
    block.declarations.foldl (fun keys decl => keys.insert decl.name key) keys
  let inlineItems := (inlineDeclSummaryItems declarations.definedDefs declarations.definedTheorems hrefOf).map fun item =>
    { item with previewLookupKey? := previewKeys.get? item.previewName }
  inlineItems ++ externalDeclSummaryItems source.summaryExternalDecls hrefOf

/--
The Lean code popup body: one row per declaration, then, for a heading, the plain
sentence saying what the block's status means, then any rendering diagnostics.
-/
private def renderSummaryPreview (cdata : ComputedData)
    (hrefOf : Name → Option String) (lead? : Option String := none) : Output.Html :=
  open Verso.Output.Html in
  let items := summaryPreviewItems cdata hrefOf
  let declarations : Output.Html :=
    if items.isEmpty then
      {{<p class="bp_code_hover_none">"No Lean declarations are associated with this block yet."</p>}}
    else
      {{<ul class="bp_code_decl_list">{{renderDeclSummaryItems items}}</ul>}}
  let lead : Output.Html := match lead? with
    | some sentence => {{<p class="bp_code_summary_status">{{.text true sentence}}</p>}}
    | none => .empty
  let failures := externalRenderFailures (cdata.source.getD {}).externalDecls
  let diagnostics : Output.Html :=
    if failures.isEmpty then .empty else
      codeHoverSection "Render diagnostics" (renderExternalRenderFailureItems failures hrefOf)
  {{
    <div class="bp_code_summary_preview_content">
      {{declarations}}
      {{lead}}
      {{diagnostics}}
    </div>
  }}

/-- How a block's Lean status shows: its symbol and the status class suffix that colours it.
Headings and previews that list blocks share it, so a block looks the same everywhere. -/
structure StatusVisual where
  classSuffix : String
  symbol : String
  absent : Bool := false
deriving Inhabited, Repr

private def statusVisual (hasSource : Bool) (statusMark : BlockStatusMark) : StatusVisual :=
  if !hasSource then
    { classSuffix := "absent", symbol := "○", absent := true }
  else if statusMark.requirementsOpen then
    { classSuffix := "requirements_open", symbol := "◐" }
  else
    let view := statusMark.status.presentation
    { classSuffix := view.codeEntryClassSuffix
      symbol := statusMark.symbolOverride?.getD view.codeEntrySymbol }

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

private def renderCodeEntryNode (href : Option String) (title : String) (visual : StatusVisual)
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
    (body : Output.Html) (focusable : Bool := false) (ariaLabel? : Option String := none)
    (triggerAttrs : Array (String × String) := #[]) : Output.Html :=
  Informal.HoverRender.templatePreviewRoot
    "bp_code_summary_preview_root"
    "bp_code_summary_preview_wrap"
    "bp_code_summary_preview_wrap_active"
    "bp_code_summary_preview_tpl"
    "data-bp-preview-id"
    codeSummaryPreviewId
    previewTitle
    "bp_code_summary_preview_panel"
    (titleAttr? := some "data-bp-preview-title")
    trigger
    body
    (focusable := focusable)
    (ariaLabel? := ariaLabel?)
    (eyebrow := "Lean code")
    (closeLabel := "Close Lean code preview")
    (extraTriggerAttrs := triggerAttrs)

/-- The heading's Lean code entry. Its popup names the block, links its label, and
offers the block's Lean code in the footer. -/
private def renderCodeEntryWrap (href : Option String) (title previewTitle label : String)
    (previewBody : Output.Html) (visual : StatusVisual)
    (renderHealth : ExternalRenderHealth := {}) : Output.Html :=
  open Verso.Output.Html in
  let footer := href.map fun href =>
    ({{<a class="bp_code_summary_go" href={{href}}>"Go to Lean code"</a>}} : Output.Html).asString
  renderCodeSummaryPreview previewTitle
    (renderCodeEntryNode href title visual renderHealth)
    previewBody
    (focusable := href.isNone)
    (ariaLabel? := if href.isNone then some title else none)
    (triggerAttrs := #[("data-bp-preview-header-label", label)] ++
      (footer.map (("data-bp-preview-footer-html", ·))).toArray)

/-- Heading completion is read only from the admitted realization assessment.
Declaration snapshots remain useful for the code panel, but are not a fallback
source of proof or dependency completion. `missingDeclaration` is a resolution fact,
not completion: it reports a named declaration that does not exist, which the
assessment cannot tell apart from an unfinished statement, and it never marks a
heading complete. -/
private def statusMarkFromAssessment (missingDeclaration : Bool)
    (assessment? : Option Realizations.NodeAssessment) : BlockStatusMark := Id.run do
  let some assessment := assessment?
    | return {
        status := .incomplete {}
        lead := "Lean status is unavailable for this block."
        title := "Validation unavailable: this occurrence has no captured realization assessment"
        symbolOverride? := some "?" }
  let details := assessment.nativeStatusMessage
  if missingDeclaration then
    let lead := "A Lean declaration named here was not found."
    return { status := .missing, lead, title := lead ++ " " ++ details }
  if !assessment.hasNativeDeclarations then
    return {
      status := .incomplete {}
      lead := "This block's Lean code has not been assessed."
      title := assessment.leanRequirementMessage
      symbolOverride? := some "?" }
  let complete := assessment.nativeLocallyComplete && assessment.requiredComplete && !assessment.hasAxiomLike
  let requirementsOpen := assessment.nativeLocallyComplete && !assessment.hasAxiomLike &&
    !assessment.requiredComplete
  let lead :=
    if assessment.hasAxiomLike then
      "This block relies on an axiom-like declaration, so it is assumed rather than proved."
    else if complete then "This block's Lean code checks, and so does everything it relies on."
    else if requirementsOpen then
      "This block's Lean code checks, but something it relies on is unfinished."
    else "This block's Lean code is unfinished."
  let status := if assessment.hasAxiomLike then .axiomLike else if complete then .proved else .incomplete {}
  return {
    status
    lead
    title := lead ++ " " ++ details
    symbolOverride? := if complete || assessment.hasAxiomLike || requirementsOpen then none else some "⚠"
    requirementsOpen }

private def sortDeclsByCommand (decls : Array CodeDeclData) : Array CodeDeclData :=
  decls.qsort (fun a b =>
    a.commandIndex < b.commandIndex ||
    (a.commandIndex == b.commandIndex && a.name.toString < b.name.toString))

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
    s!"{label}\nLean definitions: {defs}\nLean theorems/lemmas: {thms}\nIncomplete source snapshots: {sorriesTxt}"

private def isProvedStatus : Data.ProvedStatus → Bool
  | .proved => true
  | _ => false

/--
A code panel's summary: its declarations' names and one status for all of them.
This is the source snapshots' status, for display; the block's heading carries its
validated status.
-/
private def panelStatusNode (items : Array DeclSummaryItem) : Output.Html :=
  open Verso.Output.Html in
  let missing := (items.filter fun item => !item.present || item.status.any (·.isMissing)).size
  let unfinished := (items.filter fun item =>
    item.present && item.status.any fun status => !status.isMissing && !isProvedStatus status).size
  let awaiting := (items.filter fun item => item.present && item.status.isNone).size
  let singleView : Option (String × String × String) := match items with
    | #[item] =>
      let view := declarationStatusPresentation item.status item.present
      some (view.codeEntryClassSuffix, view.codeEntrySymbol, view.summaryText)
    | _ => none
  let (suffix, symbol, statusText) : String × String × String :=
    if missing > 0 then
      ("missing", "!", if items.size == 1 then "missing declaration" else s!"{missing} of {items.size} missing")
    else if unfinished > 0 then
      singleView.getD ("warning", "⚠", s!"{unfinished} of {items.size} unfinished")
    else if awaiting > 0 then
      singleView.getD ("awaiting", "…", s!"{awaiting} of {items.size} awaiting capture")
    else ("proved", "✓", "complete")
  let shown := items.toList.take 3
  let names : Array Output.Html := (shown.map fun item =>
    ({{<code>{{.text true s!"{item.displayName}"}}</code>}} : Output.Html)).toArray
  let names := (names.toList.intersperse (.text true ", ")).toArray
  let more : Output.Html :=
    if items.size > shown.length then .text true s!" and {items.size - shown.length} more" else .empty
  {{
    <span class="bp_code_panel_summary">
      <span class="bp_code_panel_decls">{{names}}{{more}}</span>
      <span class={{s!"bp_code_panel_status bp_code_link_status_{suffix}"}}>
        <span class="bp_code_status_symbol">{{.text true symbol}}</span>
        {{.text true statusText}}
      </span>
    </span>
  }}

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

private def renderInlinePanelIndicator (label : Data.Label) (cdata : ComputedData)
    (hrefOf : Name → Option String) : PanelIndicatorParts :=
  open Verso.Output.Html in
  let codeData := (cdata.source.getD {}).literateDeclarations
  let orderedDecls := if cdata.inlineBlocks.isEmpty then codeData.declarations else
    cdata.inlineBlocks.flatMap fun block => sortDeclsByCommand block.declarations
  let previewBody := renderSummaryPreview cdata hrefOf
  let summaryTitle := s!"Lean code for {label} (source snapshots, display only; not realization validation): " ++
    codeSummaryText label codeData.definedDefs codeData.definedTheorems
  let items := orderedDecls.map fun decl =>
    ({ displayName := decl.name, previewName := decl.name, status := decl.provedStatus } : DeclSummaryItem)
  let indicator : Output.Html :=
    if items.isEmpty then .empty else
      wrapPanelIndicator label summaryTitle (panelStatusNode items) previewBody
  {
    summaryTitle
    indicator
  }

private structure ExternalStatusCounts where
  totalDecls : Nat := 0
  missingDecls : Nat := 0
  awaitingCapture : Nat := 0
  incompleteDecls : Nat := 0

private def ExternalStatusCounts.presentDecls (counts : ExternalStatusCounts) : Nat :=
  counts.totalDecls - counts.missingDecls

private def countExternalStatuses (decls : Array Data.ExternalRef) : ExternalStatusCounts :=
  let statuses := decls.foldl (init := ({} : Lean.NameMap (Option Data.ProvedStatus))) fun statuses decl =>
    let name := decl.canonical.eraseMacroScopes
    statuses.insert name (Data.ExternalRef.mergeStatus (statuses.getD name none) decl.observedStatus)
  statuses.foldl (init := { totalDecls := statuses.size }) fun counts _ status =>
    match status with
    | none => { counts with awaitingCapture := counts.awaitingCapture + 1 }
    | some status => {
        counts with
        missingDecls := counts.missingDecls + if status.isMissing then 1 else 0
        incompleteDecls := counts.incompleteDecls + if !status.isMissing && status.isIncomplete then 1 else 0
      }

private def renderExternalPanelIndicator (decls : Array Data.ExternalRef)
    (label : Data.Label) (hrefOf : Name → Option String) : PanelIndicatorParts :=
  open Verso.Output.Html in
  let health := countExternalStatuses decls
  let renderHealth := externalRenderHealth decls
  let previewBody := renderSummaryPreview { source := some { externalDecls := decls } } hrefOf
  let summaryTitle :=
    s!"Lean declaration display for {label}: " ++
      appendRenderHealthSummary
      (externalCodeEntryTitle health.presentDecls health.totalDecls health.missingDecls health.incompleteDecls)
      renderHealth
  {
    summaryTitle
    indicator := wrapPanelIndicator label summaryTitle
      (panelStatusNode (externalDeclSummaryItems decls hrefOf)) previewBody
  }

/--
Render the code panel's summary row from canonical code-source data: the panel's
declarations and one status for them, shared by inline and external code.
-/
def renderPanelIndicator (label : Data.Label) (cdata : ComputedData)
    (hrefOf : Name → Option String) : PanelIndicatorParts :=
  match cdata.source with
  | none => { summaryTitle := s!"Lean code for {label}: no associated Lean declarations" }
  | some source =>
    let inlinePanel := renderInlinePanelIndicator label cdata hrefOf
    let externalPanel := renderExternalPanelIndicator source.displayExternalDecls label hrefOf
    if source.literateDeclarations.isEmpty then externalPanel else
    if source.externalDecls.isEmpty then inlinePanel else
      { summaryTitle := inlinePanel.summaryTitle ++ "\n" ++ externalPanel.summaryTitle
        indicator := .seq #[inlinePanel.indicator, externalPanel.indicator] }

private def headingStatusMark (data : BlockData) (source : BlockCodeData) : BlockStatusMark :=
  let missingDeclaration := source.externalDecls.any fun decl => !decl.present || decl.provedStatus.any (·.isMissing)
  statusMarkFromAssessment missingDeclaration data.assessment

/-- The status mark a block's heading shows, for previews that list the block. -/
def blockStatusVisual (data : BlockData) : StatusVisual :=
  let source := data.codeData.getD {}
  statusVisual (!source.isEmpty) (headingStatusMark data source)

/-- Heading status and tooltip cover every association, independent of panel layout.
`title?` is the block's reader-facing title, such as "Theorem 1.1.4", for the popup
header; without one the popup is titled by the label. -/
def renderParts (data : BlockData) (cdata : ComputedData) (hrefOf : Name → Option String)
    (title? : Option String := none) : RenderParts :=
  if data.isProof then {} else
  let source := cdata.source.getD {}
  let renderHealth := externalRenderHealth source.externalDecls
  let statusMark := headingStatusMark data source
  let title := if source.isEmpty then "No associated Lean declarations" else
    appendRenderHealthSummary (statusMark.title) renderHealth
  let label := Data.Label.publicString data.label
  let lead? := if source.isEmpty then none else some statusMark.lead
  { statusMark := if source.isEmpty then none else some statusMark
    codeEntry := renderCodeEntryWrap cdata.codeHref title (title?.getD label) label
      (renderSummaryPreview cdata hrefOf lead?) (statusVisual (!source.isEmpty) statusMark) renderHealth }

end CodeSummary
end Informal
