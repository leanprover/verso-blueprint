/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.Data.Json.FromToJson.Basic
meta import Verso.Instances.Deriving

public section

namespace Informal

open Lean

inductive ExternalDeclRenderError where
  | moduleUnavailable (decl : Name)
  | exception (decl : Name) (message : String)
  deriving Repr, Inhabited, Lean.ToJson, Lean.FromJson, Lean.Quote

def ExternalDeclRenderError.message : ExternalDeclRenderError → String
  | .moduleUnavailable decl => s!"module unavailable for {decl}"
  | .exception decl message => s!"{decl}: {message}"

/--
One hover payload captured while rendering an external declaration snippet.

External declarations are rendered before the final page `Html.State` exists, so
their highlighted-code hovers cannot be inserted into Verso's page hover table
immediately. Each payload records the snippet-local id plus the hover body that
the page renderer can later deduplicate against all other page hovers.
-/
structure ExternalDeclHoverPayload where
  localId : Nat
  html : String
deriving Repr, Inhabited, Lean.ToJson, Lean.FromJson, Lean.Quote

/--
Rendered external declaration HTML in both forms needed by Blueprint.

`html` is a compact template: it uses Blueprint-local hover ids, carries hover
bodies separately in `hoverPayloads`, and contains a tiny marker where the
standalone hover body should be reinserted. The final page and generated-cache
renderers rewrite the local ids into Verso hover ids and remove the markers;
isolated preview paths inline the payloads at the markers to recover standalone
HTML.

The local ids in `html` are not stable semantic ids. They are only positions in
the isolated highlighted-code hover table produced while rendering this snippet.
The page renderer must therefore translate them before emitting normal
`data-verso-hover` attributes.
-/
structure ExternalDeclRenderedHtml where
  html : String
  hoverPayloads : Array ExternalDeclHoverPayload
deriving Repr, Inhabited, Lean.ToJson, Lean.FromJson, Lean.Quote

def externalDeclHoverLocalAttrName : String := "data-bp-external-hover-local"

def externalDeclHoverInlineMarkerAttrName : String := "data-bp-external-hover-inline-local"

/-- Replacement pair for one snippet-local external-declaration hover id. -/
structure ExternalDeclHoverRewrite where
  localId : Nat
  attrReplacement : String
  inlineReplacement : String
deriving Repr, Inhabited

private def externalDeclHoverLocalAttrPrefix : String :=
  s!"{externalDeclHoverLocalAttrName}=\""

private def externalDeclHoverInlineMarkerPrefix : String :=
  s!"<span {externalDeclHoverInlineMarkerAttrName}=\""

private def externalDeclHoverInlineMarkerSuffix : String :=
  "></span>"

private def externalDeclHoverMarkerNamePrefix : String :=
  "data-bp-external-hover-"

private inductive ExternalDeclHoverMarkerKind where
  | attr
  | inline

private def findExternalDeclHoverRewrite?
    (rewrites : Array ExternalDeclHoverRewrite) (localId : Nat) :
    Option ExternalDeclHoverRewrite :=
  rewrites.find? (fun rewrite => rewrite.localId == localId)

private def parseExternalDeclHoverMarker?
    (html : String) (markerPrefix : String) (start : html.Pos) :
    Option (Nat × html.Pos) := do
  let idStart := start.nextn markerPrefix.length
  let quotePos ← idStart.find? "\""
  let localId ← (html.extract idStart quotePos).toNat?
  let afterQuote ← quotePos.next?
  some (localId, afterQuote)

private def parseExternalDeclHoverInlineMarker?
    (html : String) (start : html.Pos) : Option (Nat × html.Pos) := do
  let (localId, afterQuote) ←
    parseExternalDeclHoverMarker? html externalDeclHoverInlineMarkerPrefix start
  let markerEnd := afterQuote.nextn externalDeclHoverInlineMarkerSuffix.length
  if html.extract afterQuote markerEnd == externalDeclHoverInlineMarkerSuffix then
    some (localId, markerEnd)
  else
    none

private partial def findNextExternalDeclHoverMarker?
    (html : String) (pos : html.Pos) :
    Option (ExternalDeclHoverMarkerKind × html.Pos) := do
  let markerNamePos ← pos.find? externalDeclHoverMarkerNamePrefix
  if (html.sliceFrom markerNamePos).startsWith externalDeclHoverLocalAttrPrefix then
    some (.attr, markerNamePos)
  else
    let inlinePos := markerNamePos.prevn "<span ".length
    if (html.sliceFrom inlinePos).startsWith externalDeclHoverInlineMarkerPrefix then
      some (.inline, inlinePos)
    else
      markerNamePos.next?.bind (findNextExternalDeclHoverMarker? html)

private partial def rewriteExternalDeclHoverTemplateLoop
    (html : String)
    (rewrites : Array ExternalDeclHoverRewrite)
    (pos : html.Pos)
    (parts : Array String) : Array String :=
  match findNextExternalDeclHoverMarker? html pos with
  | none =>
      parts.push (html.extract pos html.endPos)
  | some (kind, markerPos) =>
      let parts := parts.push (html.extract pos markerPos)
      let fallback : Unit → Array String := fun _ =>
        match markerPos.next? with
        | some nextPos =>
            rewriteExternalDeclHoverTemplateLoop html rewrites nextPos
              (parts.push (html.extract markerPos nextPos))
        | none =>
            parts.push (html.extract markerPos html.endPos)
      let parsed? :=
        match kind with
        | .attr =>
            parseExternalDeclHoverMarker? html externalDeclHoverLocalAttrPrefix markerPos
        | .inline =>
            parseExternalDeclHoverInlineMarker? html markerPos
      match parsed? with
      | none => fallback ()
      | some (localId, nextPos) =>
          match findExternalDeclHoverRewrite? rewrites localId with
          | none => fallback ()
          | some rewrite =>
              let replacement :=
                match kind with
                | .attr => rewrite.attrReplacement
                | .inline => rewrite.inlineReplacement
              let parts :=
                if replacement.isEmpty then parts else parts.push replacement
              rewriteExternalDeclHoverTemplateLoop html rewrites nextPos parts

def ExternalDeclRenderedHtml.rewriteHovers
    (rendered : ExternalDeclRenderedHtml)
    (rewrites : Array ExternalDeclHoverRewrite) : String :=
  String.join <|
    (rewriteExternalDeclHoverTemplateLoop rendered.html rewrites rendered.html.startPos #[]).toList

def ExternalDeclRenderedHtml.selfContained (rendered : ExternalDeclRenderedHtml) : String :=
  rendered.rewriteHovers <|
    rendered.hoverPayloads.map fun payload => {
      localId := payload.localId
      attrReplacement := ""
      inlineReplacement := s!"<span class=\"hover-info\">{payload.html}</span>"
    }

abbrev ExternalDeclRenderResult := Except ExternalDeclRenderError ExternalDeclRenderedHtml

structure ExternalDeclHeaderBadge where
  className : String
  text : String

structure ExternalDeclHeaderSource where
  text : String
  href? : Option String := none

end Informal
