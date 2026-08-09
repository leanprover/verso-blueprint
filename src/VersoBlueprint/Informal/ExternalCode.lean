/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.DirectiveArgParsing
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.LeanCodeLink
import VersoBlueprint.LeanNameParsing

/-!
Parsing and rendering support for external Lean declarations attached to an
informal block.

Directive authors write names with `(lean := "...")`. This module turns those
names into stable external references during elaboration, then renders the
shared external-code panel and hover-preview rows during HTML generation.
-/

namespace Informal

/--
If enabled, unresolved or ambiguous external Lean names in `(lean := "...")` are treated as
errors instead of warnings.
-/
register_option verso.blueprint.externalCode.strictResolve : Bool := {
  defValue := false
  descr := "Treat unresolved or ambiguous `(lean := ...)` external references as errors"
}

namespace ExternalCode

open Verso Doc Elab
open Lean Elab

/--
Parse and normalize `(lean := "a,b,c")` directive values into canonical external refs.

Returns `(refs, invalidEntries)` where invalid entries keep the original token plus parse error.
-/
def parseExternalCodeList (lean : Option String) :
    Array Data.ExternalRef × Array String :=
  match lean with
  | none => (#[], #[])
  | some s =>
    (DirectiveArgParsing.splitCommaSeparatedList s).foldl (init := (#[], #[])) fun (acc, invalid) ref =>
      match LeanNameParsing.parseE ref with
      | .ok name =>
        let extRef := Data.ExternalRef.ofName name .directiveLean
        (acc.push extRef, invalid)
      | .error err =>
        (acc, invalid.push s!"{ref} ({err})")

private def parsedExternalRef (ref : Data.ExternalRef) : Data.ExternalRef :=
  { ref with canonical := ref.written.eraseMacroScopes }

private def resolvedExternalRef (ref : Data.ExternalRef) (resolved : Name) : Data.ExternalRef :=
  { written := ref.written, canonical := resolved.eraseMacroScopes, origin := ref.origin }

section
variable {m : Type → Type} [Monad m]

private def markExternalRefSnapshot [MonadOptions m] [MonadLiftT CoreM m]
    (ref : Data.ExternalRef) : m Data.ExternalRef := do
  let opts ← getOptions
  liftM <| externalRefSnapshotAtCurrentDir opts ref

private def resolveExternalNameCandidates [MonadResolveName m] [MonadOptions m] [MonadEnv m]
    [MonadLog m] [AddMessageContext m]
    (name : Name) : m (Array Name) := do
  let resolved ← Lean.resolveGlobalName name (enableLog := false)
  return resolved.foldl (init := #[]) fun acc (candidate, fieldList) =>
    if fieldList.isEmpty && !acc.contains candidate then
      acc.push candidate
    else
      acc

private def pushExternalRefUnique [MonadError m]
    (label : Name) (labelSyntax : Syntax)
    (acc : Array Data.ExternalRef) (ref : Data.ExternalRef) : m (Array Data.ExternalRef) := do
  match acc.find? (fun entry => entry.canonical == ref.canonical) with
  | some prev =>
    throwErrorAt labelSyntax
      m!"Label {label} has duplicate external Lean reference '{ref.written}' (canonical '{ref.canonical}'); previously declared as '{prev.written}'"
  | none =>
    return acc.push ref

/--
Resolve parsed external refs in the current namespace/open scope.

Resolution keeps provenance snapshots and rejects duplicate canonical names as errors.
When strict mode is disabled, unresolved/ambiguous names are kept as parsed and reported as warnings.
-/
def resolveExternalCodeList [MonadResolveName m] [MonadOptions m] [MonadLiftT CoreM m] [MonadEnv m]
    [MonadLog m] [AddMessageContext m] [MonadError m]
    (label : Name) (labelSyntax : Syntax) (expectedKind : Data.NodeKind)
    (refs : Array Data.ExternalRef) : m (Array Data.ExternalRef) := do
  let strictResolve :=
    (← getOptions).get
      verso.blueprint.externalCode.strictResolve.name
      verso.blueprint.externalCode.strictResolve.defValue
  refs.foldlM (init := #[]) fun acc ref => do
    let ref := { ref with kind := expectedKind }
    let candidates ← resolveExternalNameCandidates ref.written
    match candidates.toList with
    | [] =>
      let msg := m!"Label {label}: external Lean name '{ref.written}' could not be resolved in current namespace/open declarations"
      if strictResolve then
        throwErrorAt labelSyntax msg
      else
        logWarningAt labelSyntax m!"{msg}; keeping parsed name"
        let ref ← markExternalRefSnapshot (parsedExternalRef ref)
        pushExternalRefUnique label labelSyntax acc ref
    | [resolved] =>
      let ref ← markExternalRefSnapshot (resolvedExternalRef ref resolved)
      pushExternalRefUnique label labelSyntax acc ref
    | many =>
      let msg := m!"Label {label}: external Lean name '{ref.written}' is ambiguous ({String.intercalate ", " (many.map toString)})"
      if strictResolve then
        throwErrorAt labelSyntax msg
      else
        logWarningAt labelSyntax m!"{msg}; keeping parsed name"
        let ref ← markExternalRefSnapshot (parsedExternalRef ref)
        pushExternalRefUnique label labelSyntax acc ref

end

private structure LinkedExternalDecl where
  decl : Data.ExternalRef
  href : Option String := none
  anchorAttrs : Array (String × String) := #[]

/--
Resolve the row link for an external reference.

For present declarations we prefer the canonical Lean name, but fall back to the
written name so older data and unresolved names still produce the best available
link. Missing declarations only have the written name to try.
-/
private def externalRefHref?
    (getDeclHref : Name → Option String) (decl : Data.ExternalRef) : Option String :=
  if decl.present then
    match getDeclHref decl.canonical with
    | some href => some href
    | none => getDeclHref decl.written
  else
    getDeclHref decl.written

/-- Build the small render model used by both preview and panel rows. -/
private def linkedExternalDecl
    (getDeclHref : Name → Option String)
    (getDeclAnchorAttrs : Data.ExternalRef → Array (String × String))
    (decl : Data.ExternalRef) : LinkedExternalDecl :=
  {
    decl
    href := externalRefHref? getDeclHref decl
    anchorAttrs := getDeclAnchorAttrs decl
  }

/--
Status-derived rendering data for one linked external declaration.

The panel badge and rendered footer intentionally share one view so status
wording and CSS classification cannot drift between compact and expanded rows.
-/
private structure ExternalDeclStatusView where
  className : String
  panelText : String

private def externalDeclStatusView (item : LinkedExternalDecl) : ExternalDeclStatusView :=
  let statusView := item.decl.provedStatus.presentation (present := item.decl.present)
  let (className, panelText) :=
    if item.decl.present && (externalRenderFailure? item.decl).isSome then
      ("bp_external_decl_error", "render failed")
    else
      (statusView.externalDeclClass, statusView.externalPanelText)
  { className, panelText }

private def externalDeclNode (item : LinkedExternalDecl) : Output.Html :=
  open Verso.Output.Html in
  let declTxt := {{<code>{{.text true s!"{item.decl.written}"}}</code>}}
  if let some href := item.href then
    Informal.LeanCodeLink.renderResolved
      item.decl.canonical declTxt "" (some href)
      (previewTitle := s!"{item.decl.canonical}")
  else
    declTxt

private def externalDeclSourceRef? (item : LinkedExternalDecl) : Option Output.Html :=
  open Verso.Output.Html in
  if !item.decl.present then
    none
  else
    item.decl.sourceHref?.map fun href =>
      {{<a class="bp_code_link" href={{href}}>"open source"</a>}}

private structure ExternalDeclRowData where
  liAttrs : Array (String × String) := #[]
  head : Output.Html := .empty
  body : Output.Html := .empty
  footer : Output.Html := .empty

private def externalDeclHead (item : LinkedExternalDecl) (status : ExternalDeclStatusView) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_external_decl_head">
      {{externalDeclNode item}}
      <span class={{status.className}}>{{.text true status.panelText}}</span>
    </div>
  }}

private def externalDeclRenderedMeta
    (item : LinkedExternalDecl) (status : ExternalDeclStatusView) : Output.Html :=
  open Verso.Output.Html in
  let metaText := status.panelText
  let statusBadge : Output.Html :=
    if !metaText.isEmpty then
      {{<span class={{s!"bp_external_status_badge bp_external_decl_footer_status {status.className}"}}>{{.text true metaText}}</span>}}
    else
      .empty
  let sourceRef? := externalDeclSourceRef? item
  {{
    <div class="bp_external_decl_meta bp_external_decl_rendered_meta">
      {{statusBadge}}
      {{if let some sourceRef := sourceRef? then
        {{<span class="bp_external_decl_rendered_source">{{sourceRef}}</span>}}
       else .empty}}
    </div>
  }}

/--
All external declaration body strategies share the same success wrapper and
render-failure presentation. They differ only in how successful rendered HTML
is adapted to its destination hover table.
-/
private def externalDeclRenderedWith [Monad m]
    (renderHtml : ExternalDeclRenderedHtml → m String)
    (item : LinkedExternalDecl) : m Output.Html := do
  match item.decl.render with
  | .ok renderedHtml =>
    let renderedHtml ← renderHtml renderedHtml
    pure <| .tag "div" #[("class", "bp_external_decl_rendered")] (.text false renderedHtml)
  | .error err =>
    pure <| .tag "pre"
      #[("class", "bp_external_decl_stmt bp_external_decl_render_error")]
      (.text true s!"Render failed: {err.message}")

private def externalDeclRendered (item : LinkedExternalDecl) : Output.Html :=
  Id.run <| externalDeclRenderedWith (fun renderedHtml => pure renderedHtml.selfContained) item

private def registerPageHoverPayload [Monad m]
    (payload : ExternalDeclHoverPayload) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Nat :=
  modifyGet fun st =>
    let (id, dedup) := st.dedup.insert (.text false payload.html)
    (id, { st with dedup })

private def renderedHtmlWithHoverTable [Monad m]
    (registerHoverPayload : ExternalDeclHoverPayload → m Nat)
    (renderedHtml : ExternalDeclRenderedHtml) : m String := do
  -- This is the local version of the future upstream Verso helper described in
  -- doc/ROADMAP.md: register portable fragment hovers, then remap local ids.
  let rewrites ← renderedHtml.hoverPayloads.mapM fun payload => do
    let hoverId ← registerHoverPayload payload
    pure {
      localId := payload.localId
      attrReplacement := s!"data-verso-hover=\"{hoverId}\""
      inlineReplacement := ""
    }
  pure <| renderedHtml.rewriteHovers rewrites

/--
Convert compact external declaration HTML into normal page HTML.

Each snippet-local hover payload is inserted into the real Verso page hover
table. Identical payloads therefore share a page hover id, while preview-only
HTML can still remain self-contained through `externalDeclRendered`.

The template rewrite is deliberately only an id-scope translation:
`data-bp-external-hover-local` means "this id is valid only for the external
declaration snapshot", and `data-verso-hover` means "this id is valid in the
current page's Verso hover table". The payload body is registered through
Verso's normal dedup table before the page id is emitted.
-/
private def renderedHtmlWithPageHovers [Monad m]
    (renderedHtml : ExternalDeclRenderedHtml) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m String := do
  renderedHtmlWithHoverTable registerPageHoverPayload renderedHtml

private def externalDeclRenderedWithPageHovers [Monad m]
    (item : LinkedExternalDecl) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Output.Html :=
  externalDeclRenderedWith renderedHtmlWithPageHovers item

private def missingExternalDeclBody : Output.Html :=
  open Verso.Output.Html in
  {{
    <pre class="bp_external_decl_stmt bp_code_hover_none">
      {{.text true s!"declaration not found ({Data.ExternalDeclLookupError.message .notPresentAtRegistration})"}}
    </pre>
  }}

private def externalDeclRowDataWith [Monad m]
    (renderBody : LinkedExternalDecl → m Output.Html)
    (item : LinkedExternalDecl) : m ExternalDeclRowData := do
  let status := externalDeclStatusView item
  if !item.decl.present then
    pure {
      liAttrs := #[("class", "bp_external_decl_item")] ++
        item.anchorAttrs
      head := externalDeclHead item status
      body := missingExternalDeclBody
    }
  else
    let body ← renderBody item
    if (externalRenderFailure? item.decl).isSome then
      pure {
        liAttrs := #[("class", "bp_external_decl_item")] ++
          item.anchorAttrs
        head := externalDeclHead item status
        body
        footer := externalDeclRenderedMeta item status
      }
    else
      pure {
        liAttrs := #[("class", "bp_external_decl_item bp_external_decl_item_rendered")] ++ item.anchorAttrs
        body
      }

private def renderExternalDeclRow (row : ExternalDeclRowData) : Output.Html :=
  open Verso.Output.Html in
  {{
    <li {{row.liAttrs}}>
      {{row.head}}
      {{row.body}}
      {{row.footer}}
    </li>
  }}

/--
Render external declaration rows while leaving the declaration body strategy
abstract.

Isolated preview rendering passes the self-contained body renderer. Normal page
rendering and generated-cache rendering pass hover-table body renderers, but all
paths share the row status, anchors, and footer layout.
-/
private def renderExternalDeclRowsWith [Monad m]
    (renderBody : LinkedExternalDecl → m Output.Html)
    (linkedDecls : Array LinkedExternalDecl) : m (Array Output.Html) :=
  linkedDecls.mapM fun item => do
    let rowData ← externalDeclRowDataWith renderBody item
    pure <| renderExternalDeclRow rowData

private def renderExternalDeclRows (linkedDecls : Array LinkedExternalDecl) : Array Output.Html :=
  Id.run <| renderExternalDeclRowsWith (fun item => pure <| externalDeclRendered item) linkedDecls

private def renderExternalDeclList (rows : Array Output.Html) : Output.Html :=
  open Verso.Output.Html in
  {{<ul class="bp_code_hover_list bp_external_decl_list">{{.seq rows}}</ul>}}

private abbrev ExternalDeclCacheHoverRender :=
  StateM (Verso.Code.Hover.State Output.Html)

private def registerCacheHoverPayload (payload : ExternalDeclHoverPayload) :
    ExternalDeclCacheHoverRender Nat :=
  modifyGet fun st =>
    let (id, dedup) := st.dedup.insert (.text false payload.html)
    (id, { st with dedup })

private def renderedHtmlWithCacheHovers
    (renderedHtml : ExternalDeclRenderedHtml) :
    ExternalDeclCacheHoverRender String := do
  renderedHtmlWithHoverTable registerCacheHoverPayload renderedHtml

private def externalDeclRenderedWithCacheHovers
    (item : LinkedExternalDecl) :
    ExternalDeclCacheHoverRender Output.Html :=
  externalDeclRenderedWith renderedHtmlWithCacheHovers item

/--
Render the canonical hover-preview body for external Lean code references.

This is the standalone variant for callers that do not have a page or generated
cache hover table. Generated HTML-cache entries should use
`renderPreviewHtmlWithCacheHovers` instead.
-/
def renderPreviewHtml
    (externalDecls : Array Data.ExternalRef)
    (getDeclHref : Name → Option String := fun _ => none) : Output.Html :=
  if externalDecls.isEmpty then
    .empty
  else
    let linkedDecls := externalDecls.map (linkedExternalDecl getDeclHref (fun _ => #[]))
    renderExternalDeclList <| renderExternalDeclRows linkedDecls

/--
Render the canonical hover-preview body for external Lean code references into
the generated HTML-cache hover table.

Unlike `renderPreviewHtml`, this does not expand isolated hover payloads inline.
Generated cache entries carry normal `data-verso-hover` attributes and the
payloads live in `HtmlCache.hoverDocs`, matching other cached Lean fragments.
-/
def renderPreviewHtmlWithCacheHovers
    (externalDecls : Array Data.ExternalRef)
    (hoverState : Verso.Code.Hover.State Output.Html)
    (getDeclHref : Name → Option String := fun _ => none) :
    Output.Html × Verso.Code.Hover.State Output.Html :=
  if externalDecls.isEmpty then
    (.empty, hoverState)
  else
    let linkedDecls := externalDecls.map (linkedExternalDecl getDeclHref (fun _ => #[]))
    let (rows, hoverState) :=
      (renderExternalDeclRowsWith externalDeclRenderedWithCacheHovers linkedDecls).run hoverState
    (renderExternalDeclList rows, hoverState)

/--
Render an external-code panel into a real page `Html.State`.

This is the normal page-rendering path for `(lean := ...)` references. It
remaps declaration-local highlighted-code hover ids into Verso's page hover
table, so repeated external declaration docstrings are emitted once per page
instead of once per occurrence.
-/
def renderPanelWithPageHovers [Monad m] (panelHeader : CodePanelHeader)
    (summaryTitle : String) (indicator : Output.Html)
    (externalDecls : Array Data.ExternalRef) (getDeclHref : Name → Option String)
    (getDeclAnchorAttrs : Data.ExternalRef → Array (String × String) := fun _ => #[])
    (folded : Bool := false) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Output.Html := do
  if externalDecls.isEmpty then
    pure .empty
  else
    let linkedDecls := externalDecls.map (linkedExternalDecl getDeclHref getDeclAnchorAttrs)
    let rows ← renderExternalDeclRowsWith externalDeclRenderedWithPageHovers linkedDecls
    pure <| mkCodePanel panelHeader summaryTitle indicator
      (renderExternalDeclList rows)
      (folded := folded)

end ExternalCode
end Informal
