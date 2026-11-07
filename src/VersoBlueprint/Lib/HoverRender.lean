/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Lib.HtmlId
import VersoBlueprint.TraversalIndex

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

def inlinePreviewRenderProperty : Name := Name.mkSimple "Informal.inlinePreview.rendering"

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

/--
Attributes that let the runtime bind template previews under one root element.

The runtime builds the root's preview panel from the shared shell: `panelClass`
names its role for sizing and placement, and `eyebrow` says what kind of popup it is.
-/
def templatePreviewDescriptorAttrs
    (panelClass templateSelector triggerSelector : String)
    (keyAttr : String := "data-bp-preview-label")
    (titleAttr? : Option String := none)
    (triggerBoundAttr : String := "data-bp-bound")
    (allowHtmlCache : Bool := false)
    (mode : PreviewMode := .hover)
    (placement : PreviewPlacement := .anchored)
    (eyebrow : String := "")
    (closeLabel : String := "Close preview") : Array (String × String) :=
  let attrs := #[
    ("data-bp-template-preview-root", "true"),
    ("data-bp-template-preview-panel-class", panelClass),
    ("data-bp-template-preview-template-selector", templateSelector),
    ("data-bp-template-preview-trigger-selector", triggerSelector),
    ("data-bp-template-preview-key-attr", keyAttr),
    ("data-bp-template-preview-title-attr", titleAttr?.getD keyAttr),
    ("data-bp-template-preview-trigger-bound-attr", triggerBoundAttr),
    ("data-bp-template-preview-mode", mode.dataValue),
    ("data-bp-template-preview-placement", placement.dataValue),
    ("data-bp-template-preview-close-label", closeLabel)
  ]
  let attrs := if eyebrow.isEmpty then attrs else attrs.push ("data-bp-template-preview-eyebrow", eyebrow)
  if allowHtmlCache then
    attrs.push ("data-bp-template-preview-allow-html-cache", "true")
  else
    attrs

def templatePreviewRoot
    (rootClass triggerClass activeTriggerClass templateClass keyAttr key previewTitle : String)
    (panelClass : String)
    (titleAttr? : Option String := none)
    (trigger body : Verso.Output.Html)
    (focusable : Bool := false)
    (ariaLabel? : Option String := none)
    (eyebrow : String := "")
    (closeLabel : String := "Close preview")
    (extraTriggerAttrs : Array (String × String) := #[]) :
    Verso.Output.Html :=
  let rootAttrs :=
    #[("class", rootClass)] ++
      templatePreviewDescriptorAttrs
        panelClass
        s!"template.{templateClass}[{keyAttr}]"
        s!".{activeTriggerClass}[{keyAttr}]"
        keyAttr
        titleAttr?
        (eyebrow := eyebrow)
        (closeLabel := closeLabel)
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
    pure (attrs ++ extraTriggerAttrs)
  let templateAttrs := #[("class", templateClass), (keyAttr, key)]
  {{
    <span {{rootAttrs}}>
      <span {{triggerAttrs}}>
        {{trigger}}
      </span>
      <template {{templateAttrs}}>
        {{body}}
      </template>
    </span>
  }}

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
not always the same value. The rest fill the shared panel header: `eyebrow?`
names the kind of popup, `status?` is the target's status mark (its symbol and
status class suffix), and `headerLabel?`/`headerHref?` are a label link.
-/
structure InlinePreviewTarget where
  triggerId : String
  title : String
  lookupKey? : Option String := none
  headerLabel? : Option String := none
  headerHref? : Option String := none
  eyebrow? : Option String := none
  status? : Option (String × String) := none

/-- Build a target whose trigger id and manifest lookup key are the same. -/
def InlinePreviewTarget.manifestBacked (lookupKey title : String) : InlinePreviewTarget :=
  { triggerId := lookupKey, title, lookupKey? := some lookupKey }

/-- Build a target with a distinct trigger id and manifest lookup key. -/
def InlinePreviewTarget.withLookupKey (triggerId title lookupKey : String) : InlinePreviewTarget :=
  { triggerId, title, lookupKey? := some lookupKey }

private def InlinePreviewTarget.attrs (target : InlinePreviewTarget) : Array (String × String) :=
  let optional (name : String) (value? : Option String) := (value?.map ((name, ·))).toArray
  #[("class", "bp_inline_preview_ref"),
    ("data-bp-preview-id", target.triggerId),
    ("data-bp-preview-title", target.title)] ++
    optional "data-bp-preview-key" target.lookupKey? ++
    optional "data-bp-preview-header-label" target.headerLabel? ++
    optional "data-bp-preview-header-href" target.headerHref? ++
    optional "data-bp-preview-eyebrow" target.eyebrow? ++
    optional "data-bp-preview-status-symbol" (target.status?.map (·.1)) ++
    optional "data-bp-preview-status-class" (target.status?.map (·.2))

/-- Render one inline preview trigger. Blueprint emits no page-local preview
templates: the runtime loads the body by `lookupKey?`. -/
def inlinePreviewTargetNode
    (node : Verso.Output.Html) (target : InlinePreviewTarget) : Verso.Output.Html :=
  .tag "span" target.attrs node

end Informal.HoverRender
