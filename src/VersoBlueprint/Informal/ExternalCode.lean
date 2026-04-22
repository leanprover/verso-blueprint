/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.LeanCodeLink
import VersoBlueprint.LeanNameParsing

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
    (LeanNameParsing.splitCommaSeparatedList s).foldl (init := (#[], #[])) fun (acc, invalid) ref =>
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

private def externalDeclSorryLocation (decl : LinkedExternalDecl) : String :=
  if decl.decl.present then
    provedStatusLocationText decl.decl.provedStatus
  else
    "location unknown"

private def externalDeclGapStatusText? (item : LinkedExternalDecl) : Option String :=
  if externalDeclHasGap item.decl then
    if provedStatusContainsSorry item.decl.provedStatus then
      some s!"contains sorry {externalDeclSorryLocation item}"
    else
      some (externalDeclSorryLocation item)
  else
    none

private def externalDeclStatusClass (item : LinkedExternalDecl) : String :=
  if !item.decl.present then
    "bp_external_decl_missing"
  else if (externalRenderFailure? item.decl).isSome then
    "bp_external_decl_error"
  else if externalDeclHasGap item.decl then
    "bp_external_decl_sorry"
  else
    "bp_external_decl_ok"

private def externalDeclPanelStatusText (item : LinkedExternalDecl) : String :=
  if !item.decl.present then
    "missing declaration"
  else if (externalRenderFailure? item.decl).isSome then
    "render failed"
  else
    (externalDeclGapStatusText? item).getD "complete"

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

private def externalDeclHead (item : LinkedExternalDecl) (statusTxt : String) : Output.Html :=
  open Verso.Output.Html in
  let statusClass := externalDeclStatusClass item
  {{
    <div class="bp_external_decl_head">
      {{externalDeclNode item}}
      <span class={{statusClass}}>{{.text true statusTxt}}</span>
    </div>
  }}

/--
TODO(external-code): revisit footer/status semantics once we surface real
out-of-workspace declarations and can distinguish "declaration complete" from
"declaration plus dependencies complete". For now, keep the footer minimal and
avoid repeating declaration kind/provenance that is either redundant or
misleading in Noperthedron.
-/
private def externalDeclRenderedMetaText (_item : LinkedExternalDecl) (statusTxt : String) : String :=
  let parts :=
    #[
      some statusTxt
    ].filterMap id
  String.intercalate " · " parts.toList

private def externalDeclRenderedMeta
    (item : LinkedExternalDecl) (statusTxt : String) : Output.Html :=
  open Verso.Output.Html in
  let metaText := externalDeclRenderedMetaText item statusTxt
  let statusClass := externalDeclStatusClass item
  {{
    <div class="bp_external_decl_meta bp_external_decl_rendered_meta">
      {{if !metaText.isEmpty then
        {{<span class={{s!"bp_external_status_badge bp_external_decl_footer_status {statusClass}"}}>{{.text true metaText}}</span>}}
       else .empty}}
      {{if let some sourceRef := externalDeclSourceRef? item then
        {{<span class="bp_external_decl_rendered_source">{{sourceRef}}</span>}}
       else .empty}}
    </div>
  }}

private def externalDeclRendered (item : LinkedExternalDecl) : Output.Html :=
  open Verso.Output.Html in
  match item.decl.render with
  | .ok renderedHtml =>
    {{
      <div class="bp_external_decl_rendered">{{.text false renderedHtml}}</div>
    }}
  | .error err =>
    {{
      <pre class="bp_external_decl_stmt bp_external_decl_render_error">{{.text true s!"Render failed: {err.message}"}}</pre>
    }}

private def missingExternalDeclBody : Output.Html :=
  open Verso.Output.Html in
  {{
    <pre class="bp_external_decl_stmt bp_code_hover_none">
      {{.text true s!"declaration not found ({Data.ExternalDeclLookupError.message .notPresentAtRegistration})"}}
    </pre>
  }}

private def externalDeclRowData (item : LinkedExternalDecl) : ExternalDeclRowData :=
  let statusTxt := externalDeclPanelStatusText item
  if !item.decl.present then
    {
      liAttrs := #[("class", "bp_external_decl_item")] ++ item.anchorAttrs
      head := externalDeclHead item statusTxt
      body := missingExternalDeclBody
    }
  else if (externalRenderFailure? item.decl).isSome then
    {
      liAttrs := #[("class", "bp_external_decl_item")] ++ item.anchorAttrs
      head := externalDeclHead item statusTxt
      body := externalDeclRendered item
      footer := externalDeclRenderedMeta item statusTxt
    }
  else
    {
      liAttrs := #[("class", "bp_external_decl_item bp_external_decl_item_rendered")] ++ item.anchorAttrs
      body := externalDeclRendered item
      footer := externalDeclRenderedMeta item statusTxt
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
Rendered fragments produced by `ExternalCode.renderParts` for external panel content.
-/
structure RenderParts where
  externalCodePanel : Output.Html := .empty

/--
Render the canonical hover-preview body for external Lean code references.

This is shared by the external code panel and the manifest-backed code-preview
path used by explicit Lean-code links.
-/
def renderPreviewHtml
    (externalDecls : Array Data.ExternalRef)
    (getDeclHref : Name → Option String := fun _ => none) : Output.Html :=
  open Verso.Output.Html in
  if externalDecls.isEmpty then
    .empty
  else
    let linkedDecls := externalDecls.map fun decl =>
      let href :=
        if decl.present then
          match getDeclHref decl.canonical with
          | some href => some href
          | none => getDeclHref decl.written
        else
          getDeclHref decl.written
      { decl, href }
    {{
      <ul class="bp_code_hover_list bp_external_decl_list">
        {{.seq <| linkedDecls.map (renderExternalDeclRow ∘ externalDeclRowData)}}
      </ul>
    }}

/--
Render external-code UI fragments for an informal block.

This function only renders optional external code panel body for `(lean := ...)` references.
-/
def renderParts (panelHeader : CodePanelHeader)
    (summaryTitle : String) (indicator : Output.Html)
    (externalDecls : Array Data.ExternalRef) (getDeclHref : Name → Option String)
    (getDeclAnchorAttrs : Data.ExternalRef → Array (String × String) := fun _ => #[]) : RenderParts :=
  open Verso.Output.Html in
  if externalDecls.isEmpty then
    {}
  else
    let linkedDecls := externalDecls.map fun decl =>
      let href :=
        if decl.present then
          match getDeclHref decl.canonical with
          | some href => some href
          | none => getDeclHref decl.written
        else
          getDeclHref decl.written
      { decl, href, anchorAttrs := getDeclAnchorAttrs decl }
    let externalCodePanel : Output.Html :=
      mkCodePanel panelHeader summaryTitle indicator
        {{<ul class="bp_code_hover_list bp_external_decl_list">
            {{.seq <| linkedDecls.map (renderExternalDeclRow ∘ externalDeclRowData)}}
          </ul>}}
    { externalCodePanel }

end ExternalCode
end Informal
