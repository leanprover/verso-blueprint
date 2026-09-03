/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import Verso
public import VersoManual
public import VersoBlueprint.Lib.HtmlId
public import VersoBlueprint.TraversalIndex

public section

namespace Informal.HoverRender

open Lean
open Verso.Output.Html

/--
Preview visibility behavior:
- `hover`: transient panel, auto-hide on leave/focusout, no close control.
- `pinned`: persistent panel, explicit close control.
-/
inductive PreviewMode where
  | hover
  | pinned
deriving Inhabited, Repr, BEq, ToJson, FromJson, Quote

def PreviewMode.dataValue : PreviewMode → String
  | .hover => "hover"
  | .pinned => "pinned"

/--
Preview placement behavior:
- `anchored`: positioned relative to the active trigger.
- `docked`: pinned to a stable panel location.
-/
inductive PreviewPlacement where
  | anchored
  | docked
deriving Inhabited, Repr, BEq, ToJson, FromJson, Quote

def PreviewPlacement.dataValue : PreviewPlacement → String
  | .anchored => "anchored"
  | .docked => "docked"

def previewKey (s : String) : String :=
  Informal.HtmlId.key s

def previewId (idPrefix value : String) : String :=
  Informal.HtmlId.prefixed idPrefix value

abbrev inlinePreviewRenderProperty : Name := Name.mkSimple "Informal.inlinePreview.rendering"

def inlinePreviewMarkerBlock : Verso.Genre.Manual.Block := {
  name := Name.mkSimple "Informal.inlinePreview.marker"
  properties := ({} : Verso.NameMap String).insert inlinePreviewRenderProperty "1"
}

def inInlinePreviewRender [Monad m] :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Bool := do
  let ctxt ← Verso.Doc.Html.HtmlT.context
  pure <| match ctxt.propertyValue inlinePreviewRenderProperty with
    | some "1" => true
    | _ => false

def withInlinePreviewRenderContext {m α}
    (act : Verso.Doc.Html.HtmlT Verso.Genre.Manual m α) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m α :=
  withReader
    (fun ctx =>
      let tctx := ctx.traverseContext
      { ctx with
        traverseContext := {
          tctx with
          blockContext := tctx.blockContext.push (.other inlinePreviewMarkerBlock)
        }
      })
    act

private def previewPanel
    (rootClass headerClass titleClass closeClass bodyClass closeLabel : String)
    (mode : PreviewMode) (placement : PreviewPlacement) : Verso.Output.Html := {{
  <aside class={{rootClass}}
      "data-bp-preview-mode"={{mode.dataValue}}
      "data-bp-preview-placement"={{placement.dataValue}}
      hidden>
    <div class={{headerClass}}>
      <div class={{titleClass}}></div>
      <button type="button" class={{closeClass}} aria-label={{closeLabel}}>"Close"</button>
    </div>
    <div class={{bodyClass}}></div>
  </aside>
}}

private def mkPreviewPanel
    (rootClass headerClass titleClass closeClass bodyClass closeLabel : String)
    (mode : PreviewMode) (placement : PreviewPlacement) : Verso.Output.Html :=
  previewPanel
    rootClass
    headerClass
    titleClass
    closeClass
    bodyClass
    closeLabel
    mode placement

def templatePreviewDescriptorAttrs
    (panelSelector templateSelector triggerSelector titleSelector bodySelector closeSelector : String)
    (keyAttr : String := "data-bp-preview-label")
    (titleAttr? : Option String := none)
    (triggerBoundAttr : String := "data-bp-bound")
    (allowHtmlCache : Bool := false)
    (mode : PreviewMode := .hover)
    (placement : PreviewPlacement := .anchored) : Array (String × String) :=
  let attrs := #[
    ("data-bp-template-preview-root", "true"),
    ("data-bp-template-preview-panel-selector", panelSelector),
    ("data-bp-template-preview-template-selector", templateSelector),
    ("data-bp-template-preview-trigger-selector", triggerSelector),
    ("data-bp-template-preview-key-attr", keyAttr),
    ("data-bp-template-preview-title-attr", titleAttr?.getD keyAttr),
    ("data-bp-template-preview-title-selector", titleSelector),
    ("data-bp-template-preview-body-selector", bodySelector),
    ("data-bp-template-preview-close-selector", closeSelector),
    ("data-bp-template-preview-trigger-bound-attr", triggerBoundAttr),
    ("data-bp-template-preview-mode", mode.dataValue),
    ("data-bp-template-preview-placement", placement.dataValue)
  ]
  if allowHtmlCache then
    attrs.push ("data-bp-template-preview-allow-html-cache", "true")
  else
    attrs

def templatePreviewRoot
    (rootClass triggerClass activeTriggerClass templateClass keyAttr key previewTitle : String)
    (panelSelector titleSelector bodySelector closeSelector : String)
    (titleAttr? : Option String := none)
    (trigger body panel : Verso.Output.Html)
    (focusable : Bool := false)
    (ariaLabel? : Option String := none) :
    Verso.Output.Html :=
  let rootAttrs :=
    #[("class", rootClass)] ++
      templatePreviewDescriptorAttrs
        panelSelector
        s!"template.{templateClass}[{keyAttr}]"
        s!".{activeTriggerClass}[{keyAttr}]"
        titleSelector
        bodySelector
        closeSelector
        keyAttr
        titleAttr?
  let triggerAttrs := Id.run do
    let mut attrs := #[
      ("class", s!"{triggerClass} {activeTriggerClass}"),
      (keyAttr, key),
      ("data-bp-preview-title", previewTitle)
    ]
    if focusable then
      attrs := attrs.push ("tabindex", "0")
      attrs := attrs.push ("role", "button")
    if let some ariaLabel := ariaLabel? then
      attrs := attrs.push ("aria-label", ariaLabel)
    pure attrs
  let templateAttrs := #[("class", templateClass), (keyAttr, key)]
  {{
    <span {{rootAttrs}}>
      <span {{triggerAttrs}}>
        {{trigger}}
      </span>
      <template {{templateAttrs}}>
        {{body}}
      </template>
      {{panel}}
    </span>
  }}

def graphPreviewPanel
    (mode : PreviewMode := .pinned) (placement : PreviewPlacement := .docked) :
    Verso.Output.Html :=
  mkPreviewPanel
    "bp_graph_preview bp_preview_panel"
    "bp_graph_preview_header bp_preview_panel_header"
    "bp_graph_preview_title bp_preview_panel_title"
    "bp_graph_preview_close bp_preview_panel_close"
    "bp_graph_preview_body bp_preview_panel_body"
    "Close informal preview"
    mode placement

def summaryPreviewPanel
    (mode : PreviewMode := .hover) (placement : PreviewPlacement := .anchored) :
    Verso.Output.Html :=
  mkPreviewPanel
    "bp_summary_preview_panel bp_preview_panel"
    "bp_summary_preview_panel_header bp_preview_panel_header"
    "bp_summary_preview_panel_title bp_preview_panel_title"
    "bp_summary_preview_panel_close bp_preview_panel_close"
    "bp_summary_preview_panel_body bp_preview_panel_body"
    "Close summary preview"
    mode placement

def codeSummaryPreviewPanel
    (mode : PreviewMode := .hover) (placement : PreviewPlacement := .anchored) :
    Verso.Output.Html :=
  mkPreviewPanel
    "bp_code_summary_preview_panel bp_preview_panel"
    "bp_code_summary_preview_header bp_preview_panel_header"
    "bp_code_summary_preview_title bp_preview_panel_title"
    "bp_code_summary_preview_close bp_preview_panel_close"
    "bp_code_summary_preview_body bp_preview_panel_body"
    "Close Lean summary preview"
    mode placement

def graphGroupPreviewPanel
    (mode : PreviewMode := .pinned) (placement : PreviewPlacement := .docked) :
    Verso.Output.Html :=
  mkPreviewPanel
    "bp_group_hover_preview bp_preview_panel"
    "bp_group_hover_preview_header bp_preview_panel_header"
    "bp_group_hover_preview_title bp_preview_panel_title"
    "bp_group_hover_preview_close bp_preview_panel_close"
    "bp_group_hover_preview_graph bp_preview_panel_body"
    "Close group preview"
    mode placement

def summaryPreviewWrap
    (labelNode : Verso.Output.Html)
    (previewLabel? : Option Name)
    (previewLookupKey? : Option String := none) : Verso.Output.Html :=
  match previewLabel? with
  | some label =>
      let attrs := Id.run do
        let mut attrs := #[
          ("class", "bp_summary_preview_wrap bp_summary_preview_wrap_active"),
          ("data-bp-preview-label", s!"{label}")
        ]
        if let some previewKey := previewLookupKey? then
          attrs := attrs.push ("data-bp-preview-key", previewKey)
        pure attrs
      .tag "span" attrs labelNode
  | none => {{
      <span class="bp_summary_preview_wrap">
        {{labelNode}}
      </span>
    }}

/--
All attributes needed to bind one inline preview trigger to its runtime panel.

`triggerId` is the page-local UI id used for hover state. `lookupKey?` is the
shared preview-data key used to load the preview body; the two are often but
not always the same value. `headerLabel?` and `headerHref?` carry an optional
label link for the preview header. `footerHtml?` carries optional,
already-rendered metadata for the inline preview chrome below the preview body.
-/
structure InlinePreviewTarget where
  triggerId : String
  title : String
  lookupKey? : Option String := none
  headerLabel? : Option String := none
  headerHref? : Option String := none
  footerHtml? : Option String := none

/-- Attributes consumed by the shared preview-header label-link renderer. -/
def previewHeaderLinkAttrs
    (headerLabel? : Option String := none)
    (headerHref? : Option String := none) :
    Array (String × String) := Id.run do
  let mut attrs := #[]
  if let some label := headerLabel? then
    attrs := attrs.push ("data-bp-preview-header-label", label)
  if let some href := headerHref? then
    attrs := attrs.push ("data-bp-preview-header-href", href)
  pure attrs

/-- Build a target whose trigger id and manifest lookup key are the same. -/
def InlinePreviewTarget.manifestBacked
    (lookupKey title : String)
    (headerLabel? : Option String := none)
    (headerHref? : Option String := none)
    (footerHtml? : Option String := none) : InlinePreviewTarget :=
  {
    triggerId := lookupKey
    title
    lookupKey? := some lookupKey
    headerLabel?
    headerHref?
    footerHtml?
  }

/-- Build a target with a distinct trigger id and manifest lookup key. -/
def InlinePreviewTarget.withLookupKey
    (triggerId title lookupKey : String)
    (headerLabel? : Option String := none)
    (headerHref? : Option String := none)
    (footerHtml? : Option String := none) : InlinePreviewTarget :=
  {
    triggerId
    title
    lookupKey? := some lookupKey
    headerLabel?
    headerHref?
    footerHtml?
  }

private def inlinePreviewRefAttrs
    (previewId previewTitle : String)
    (previewLookupKey? : Option String := none)
    (previewHeaderLabel? : Option String := none)
    (previewHeaderHref? : Option String := none)
    (previewFooterHtml? : Option String := none) :
    Array (String × String) := Id.run do
  let mut attrs := #[
    ("class", "bp_inline_preview_ref"),
    ("data-bp-preview-id", previewId),
    ("data-bp-preview-title", previewTitle)
  ]
  if let some previewKey := previewLookupKey? then
    attrs := attrs.push ("data-bp-preview-key", previewKey)
  for attr in previewHeaderLinkAttrs previewHeaderLabel? previewHeaderHref? do
    attrs := attrs.push attr
  if let some footerHtml := previewFooterHtml? then
    attrs := attrs.push ("data-bp-preview-footer-html", footerHtml)
  pure attrs

def inlinePreviewRef
    (node : Verso.Output.Html)
    (previewId previewTitle : String)
    (previewLookupKey? : Option String := none)
    (previewHeaderLabel? : Option String := none)
    (previewHeaderHref? : Option String := none)
    (previewFooterHtml? : Option String := none) :
    Verso.Output.Html :=
  .tag "span"
    (inlinePreviewRefAttrs previewId previewTitle previewLookupKey? previewHeaderLabel?
      previewHeaderHref? previewFooterHtml?)
    node

/--
Render one inline preview trigger.

`previewId` is the local UI identifier used to keep panel state stable, while
`previewLookupKey?` is the shared-manifest key used to load the preview body.
Blueprint no longer emits page-local inline preview templates.
-/
def inlinePreviewNode (node : Verso.Output.Html)
    (previewId previewTitle : String)
    (previewLookupKey? : Option String := none)
    (previewHeaderLabel? : Option String := none)
    (previewHeaderHref? : Option String := none)
    (previewFooterHtml? : Option String := none) : Verso.Output.Html :=
  inlinePreviewRef node previewId previewTitle previewLookupKey? previewHeaderLabel?
    previewHeaderHref? previewFooterHtml?

/-- Render one inline preview trigger from a bundled preview target. -/
def inlinePreviewTargetNode
    (node : Verso.Output.Html) (target : InlinePreviewTarget) : Verso.Output.Html :=
  inlinePreviewNode node target.triggerId target.title target.lookupKey?
    target.headerLabel? target.headerHref? target.footerHtml?

end Informal.HoverRender
