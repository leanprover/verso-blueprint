/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.TraversalIndex

namespace Informal.HoverRender

open Lean
open Verso.Output.Html

structure PreviewUi where
  store : Verso.Output.Html := .empty
  panel : Verso.Output.Html := .empty

abbrev GraphPreviewUi := PreviewUi
abbrev SummaryPreviewUi := PreviewUi
abbrev CodeSummaryPreviewUi := PreviewUi

/--
Preview visibility behavior:
- `hover`: transient panel, auto-hide on leave/focusout, no close control.
- `pinned`: persistent panel, explicit close control.
-/
inductive PreviewMode where
  | hover
  | pinned
deriving Inhabited, Repr, BEq, ToJson, FromJson

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
deriving Inhabited, Repr, BEq, ToJson, FromJson

def PreviewPlacement.dataValue : PreviewPlacement → String
  | .anchored => "anchored"
  | .docked => "docked"

private def hexDigits : Array Char := "0123456789ABCDEF".toList.toArray

private def toHex (n : Nat) : String := Id.run do
  let mut n := n
  let mut digits := #[]
  repeat
    if h : n < 16 then
      digits := digits.push hexDigits[n]
      break
    else
      digits := digits.push <| hexDigits[n % 16]'(by
        have : n % 16 < 16 := Nat.mod_lt _ (by decide)
        simpa using this)
      n := n >>> 4
  let padding := (4 - digits.size).fold (init := "") (fun _ _ p => p.push '0')
  digits.foldr (init := padding) fun c s => s.push c

def previewKey (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    if c.isAlphanum then
      acc.push c
    else if c == '-' then
      acc |>.push '-' |>.push '-'
    else
      acc ++ s!"-{toHex c.toNat}"

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

private def mkPreviewUi
    (rootClass headerClass titleClass closeClass bodyClass closeLabel : String)
    (mode : PreviewMode) (placement : PreviewPlacement) : PreviewUi :=
  {
    store := .empty
    panel := previewPanel
      rootClass
      headerClass
      titleClass
      closeClass
      bodyClass
      closeLabel
      mode placement
  }

def graphPreviewUi
    (mode : PreviewMode := .pinned) (placement : PreviewPlacement := .docked) : GraphPreviewUi :=
  mkPreviewUi
    "bp_graph_preview bp_preview_panel"
    "bp_graph_preview_header bp_preview_panel_header"
    "bp_graph_preview_title bp_preview_panel_title"
    "bp_graph_preview_close bp_preview_panel_close"
    "bp_graph_preview_body bp_preview_panel_body"
    "Close informal preview"
    mode placement

def summaryPreviewUi
    (mode : PreviewMode := .hover) (placement : PreviewPlacement := .anchored) : SummaryPreviewUi :=
  mkPreviewUi
    "bp_summary_preview_panel bp_preview_panel"
    "bp_summary_preview_panel_header bp_preview_panel_header"
    "bp_summary_preview_panel_title bp_preview_panel_title"
    "bp_summary_preview_panel_close bp_preview_panel_close"
    "bp_summary_preview_panel_body bp_preview_panel_body"
    "Close summary preview"
    mode placement

def codeSummaryPreviewUi
    (mode : PreviewMode := .hover) (placement : PreviewPlacement := .anchored) : CodeSummaryPreviewUi :=
  mkPreviewUi
    "bp_code_summary_preview_panel bp_preview_panel"
    "bp_code_summary_preview_header bp_preview_panel_header"
    "bp_code_summary_preview_title bp_preview_panel_title"
    "bp_code_summary_preview_close bp_preview_panel_close"
    "bp_code_summary_preview_body bp_preview_panel_body"
    "Close Lean summary preview"
    mode placement

def graphGroupPreviewUi
    (mode : PreviewMode := .pinned) (placement : PreviewPlacement := .docked) : PreviewUi :=
  mkPreviewUi
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

private def inlinePreviewRefAttrs
    (previewId previewTitle : String)
    (previewLookupKey? : Option String := none)
    (previewFallbackLabel? : Option String := none)
    (previewFallbackDetail? : Option String := none) :
    Array (String × String) := Id.run do
  let mut attrs := #[
    ("class", "bp_inline_preview_ref"),
    ("data-bp-preview-id", previewId),
    ("data-bp-preview-title", previewTitle)
  ]
  if let some previewKey := previewLookupKey? then
    attrs := attrs.push ("data-bp-preview-key", previewKey)
  if let some label := previewFallbackLabel? then
    attrs := attrs.push ("data-bp-preview-fallback-label", label)
  if let some detail := previewFallbackDetail? then
    attrs := attrs.push ("data-bp-preview-fallback-detail", detail)
  pure attrs

def inlinePreviewRef
    (node : Verso.Output.Html)
    (previewId previewTitle : String)
    (previewLookupKey? : Option String := none)
    (previewFallbackLabel? : Option String := none)
    (previewFallbackDetail? : Option String := none) :
    Verso.Output.Html :=
  .tag "span"
    (inlinePreviewRefAttrs previewId previewTitle previewLookupKey? previewFallbackLabel? previewFallbackDetail?)
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
    (previewFallbackLabel? : Option String := none)
    (previewFallbackDetail? : Option String := none) : Verso.Output.Html :=
  inlinePreviewRef node previewId previewTitle previewLookupKey? previewFallbackLabel? previewFallbackDetail?

end Informal.HoverRender
