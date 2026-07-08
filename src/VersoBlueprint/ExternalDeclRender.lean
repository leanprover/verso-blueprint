/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Lib.HtmlId
import VersoBlueprint.Lib.HoverInline

open Lean Meta

namespace Informal

abbrev ExternalDeclHtml := Verso.Output.Html

inductive ExternalDeclRenderError where
  | moduleUnavailable (decl : Name)
  | exception (decl : Name) (message : String)
  deriving Repr, Inhabited

deriving instance Lean.ToJson for ExternalDeclRenderError
deriving instance Lean.FromJson for ExternalDeclRenderError

instance : Lean.Quote ExternalDeclRenderError where
  quote
    | .moduleUnavailable decl =>
        Lean.Syntax.mkApp (Lean.mkCIdent ``ExternalDeclRenderError.moduleUnavailable) #[Lean.quote decl]
    | .exception decl message =>
        Lean.Syntax.mkApp (Lean.mkCIdent ``ExternalDeclRenderError.exception) #[Lean.quote decl, Lean.quote message]

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

/--
Replacement pair for one snippet-local external-declaration hover id.
-/
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

private def findNextExternalDeclHoverMarker?
    (html : String) (pos : html.Pos) :
    Option (ExternalDeclHoverMarkerKind × html.Pos) :=
  let attrPos? := pos.find? externalDeclHoverLocalAttrPrefix
  let inlinePos? := pos.find? externalDeclHoverInlineMarkerPrefix
  match attrPos?, inlinePos? with
  | none, none => none
  | some attrPos, none => some (.attr, attrPos)
  | none, some inlinePos => some (.inline, inlinePos)
  | some attrPos, some inlinePos =>
      if attrPos <= inlinePos then
        some (.attr, attrPos)
      else
        some (.inline, inlinePos)

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

private abbrev ExternalDeclHighlightRender :=
  StateT (Verso.Code.Hover.State ExternalDeclHtml) Id

private def highlightedHtmlContext : Verso.Code.HighlightHtmlM.Context Verso.Genre.Manual := {
  linkTargets := {}
  traverseContext := { logError := fun _ => pure () }
  definitionIds := {}
  options := {}
}

private def runHighlightedHtml
    (html : Verso.Code.HighlightHtmlM Verso.Genre.Manual ExternalDeclHtml) :
    ExternalDeclHighlightRender ExternalDeclHtml := do
  let hoverState ← get
  let (html, hoverState) := ((html.run highlightedHtmlContext).run hoverState)
  set hoverState
  pure html

private def templateVersoHoverAttrs
    (html : ExternalDeclHtml) (hoverDedup : Verso.Code.Hover.Dedup ExternalDeclHtml) :
    ExternalDeclHtml :=
  Id.run <|
    html.visitM (tag := fun name attrs contents => do
      let mut marker? : Option Nat := none
      let mut attrs' : Array (String × String) := #[]
      for attr in attrs do
        match attr with
        | ("data-verso-hover", value) =>
            match value.toNat? with
            | some localId =>
                if (hoverDedup.get? localId).isSome then
                  marker? := some localId
                  attrs' := attrs'.push (externalDeclHoverLocalAttrName, value)
                else
                  attrs' := attrs'.push attr
            | none => attrs' := attrs'.push attr
        | attr => attrs' := attrs'.push attr
      let contents :=
        match marker? with
        | some localId =>
            contents ++ .tag "span" #[(externalDeclHoverInlineMarkerAttrName, toString localId)] .empty
        | none => contents
      pure <| some <| .tag name attrs' contents)

private def hoverPayloads
    (hoverDedup : Verso.Code.Hover.Dedup ExternalDeclHtml) : Array ExternalDeclHoverPayload :=
  hoverDedup.contentId.fold (init := #[]) (fun out localId html =>
    out.push { localId, html := html.asString })
  |>.qsort (fun a b => a.localId < b.localId)

/--
Run isolated highlighted-code rendering and preserve both useful outcomes.

The compact template is what normal pages should use: hover references are kept
as local ids so repeated payloads can be registered once in the page hover
table. The same template also reconstructs self-contained snippets for isolated
previews, where there is no surrounding page table to consult. Keeping one template avoids
holding both full HTML forms for every external declaration while a large
blueprint page is generated.

We do not assign final Verso hover ids here because there is no final page
`Html.State` yet. Assigning stable ids would require a separate Blueprint hover
lookup scheme for every highlighted token payload, duplicating Verso's page
dedup table instead of using it.
-/
private def renderWithHoverPayloads
    (html : ExternalDeclHighlightRender ExternalDeclHtml) : ExternalDeclRenderedHtml :=
  let (html, hoverState) := html.run {}
  {
    html := (templateVersoHoverAttrs html hoverState.dedup).asString
    hoverPayloads := hoverPayloads hoverState.dedup
  }

private def highlightedToHtml (h : SubVerso.Highlighting.Highlighted) :
    ExternalDeclHighlightRender ExternalDeclHtml :=
  runHighlightedHtml (h.toHtml (g := Verso.Genre.Manual))

private def renderExternalDeclSignatureVariant
    (keywordText : String) (signature : SubVerso.Highlighting.Highlighted) :
    ExternalDeclHighlightRender ExternalDeclHtml :=
  open Verso.Output.Html in do
  let signatureHtml ← highlightedToHtml signature
  pure {{
    <pre class="bp_external_decl_signature signature hl lean block">
      <span class="keyword token">{{.text true keywordText}}</span> " " {{signatureHtml}}
    </pre>
  }}

private def signatureToHtml (keywordText : String) (sig : Verso.Genre.Manual.Signature) :
    ExternalDeclHighlightRender ExternalDeclHtml :=
  open Verso.Output.Html in do
  let wide ← renderExternalDeclSignatureVariant keywordText sig.wide
  let narrow ← renderExternalDeclSignatureVariant keywordText sig.narrow
  pure {{
    <div class="bp_external_decl_signature_wrap">
      <div class="wide-only">{{wide}}</div>
      <div class="narrow-only">{{narrow}}</div>
    </div>
  }}

private def plainDocstringHtml (docs? : Option String) : ExternalDeclHtml :=
  open Verso.Output.Html in
  match docs? with
  | none => .empty
  | some docs =>
    {{<pre class="docstring">{{.text true docs}}</pre>}}

private def docsHtml (docs? : Option String) : ExternalDeclHtml :=
  open Verso.Output.Html in
  {{<div class="docs">{{plainDocstringHtml docs?}}</div>}}

private def externalDeclSectionLabelId (decl : Name) (title : String) : String :=
  Informal.HtmlId.prefixed "bp-external-decl-section" s!"{decl.toString}:{title}"

private def renderTitledSection? (decl : Name) (title : String) (rows : Array ExternalDeclHtml) :
    Option ExternalDeclHtml :=
  open Verso.Output.Html in
  if rows.isEmpty then
    none
  else
    let labelId := externalDeclSectionLabelId decl title
    some {{
      <div class="bp_external_decl_section" role="group" aria-labelledby={{labelId}}>
        <p class="bp_external_decl_section_label" id={{labelId}}>{{.text true title}}</p>
        {{rows}}
      </div>
    }}

private def kindMarkerOfDeclType : Verso.Genre.Manual.Block.Docstring.DeclType → String
  | .theorem => "theorem"
  | .axiom _ => "axiom"
  | .opaque _ => "opaque"
  | .def _ => "def"
  | .structure true .. => "class"
  | .structure false .. => "structure"
  | .inductive .. => "inductive"
  | .ctor .. => "constructor"
  | .recursor _ => "recursor"
  | .quotPrim _ => "primitive"
  | .other => "def"

private structure ExternalDeclPresentation where
  kindClass : String
  kindMarker : String
  keywordText : String

structure ExternalDeclHeaderBadge where
  className : String
  text : String

structure ExternalDeclHeaderSource where
  text : String
  href? : Option String := none

private def countMeta? (singular plural : String) (count : Nat) : Option String :=
  if count == 0 then
    none
  else
    some s!"{count} {if count == 1 then singular else plural}"

private def keywordTextOfDefinitionSafety (safety : DefinitionSafety) (base : String) : String :=
  match safety with
  | .unsafe => s!"unsafe {base}"
  | .partial => s!"partial {base}"
  | .safe => base

private def externalDeclPresentation
    (declType : Verso.Genre.Manual.Block.Docstring.DeclType) (cinfo : ConstantInfo) :
    ExternalDeclPresentation :=
  let kindMarker := kindMarkerOfDeclType declType
  match cinfo with
  | .defnInfo defn =>
    if defn.hints.isAbbrev then
      {
        kindClass := s!"{kindMarker} abbrev"
        kindMarker := "abbrev"
        keywordText := keywordTextOfDefinitionSafety defn.safety "abbrev"
      }
    else
      {
        kindClass := kindMarker
        kindMarker
        keywordText := keywordTextOfDefinitionSafety defn.safety "def"
      }
  | _ =>
      {
        kindClass := kindMarker
        kindMarker
        keywordText := kindMarker
      }

private def renderExternalDeclWrapper
    (decl : Name) (kindClass : String) (kindMarker : String)
    (signature : ExternalDeclHtml) (body : ExternalDeclHtml)
    (headerBadge? : Option ExternalDeclHeaderBadge := none)
    (headerMeta : Array String := #[])
    (headerSource? : Option ExternalDeclHeaderSource := none) : ExternalDeclHtml :=
  open Verso.Output.Html in
  let headerMetaHtml : ExternalDeclHtml :=
    if headerMeta.isEmpty then
      .empty
    else
      {{<span class="bp_external_decl_header_meta">{{.text true s!"({String.intercalate ", " headerMeta.toList})"}}</span>}}
  let headerSourceHtml : ExternalDeclHtml :=
    match headerSource? with
    | none => .empty
    | some source =>
      let sourceNode : ExternalDeclHtml :=
        match source.href? with
        | some href =>
          {{<a class="bp_external_decl_source_path" href={{href}}>{{.text true source.text}}</a>}}
        | none =>
          {{<span class="bp_external_decl_source_path">{{.text true source.text}}</span>}}
      {{
        <span class="bp_external_decl_source">
          "defined in " {{sourceNode}}
        </span>
      }}
  {{
    <div class={{s!"declaration decl {kindClass}"}} data-decl={{decl.toString}} data-kind={{kindMarker}}>
      <div class="bp_external_decl_kicker">
        <div class="bp_external_decl_kicker_main">
          <span class="bp_external_decl_kind">{{.text true kindMarker}}</span>
          {{headerMetaHtml}}
          {{headerSourceHtml}}
        </div>
        <div class="bp_external_decl_kicker_status">
          {{if let some badge := headerBadge? then
            {{<span class={{s!"bp_external_status_badge bp_external_decl_header_status {badge.className}"}}>{{.text true badge.text}}</span>}}
          else .empty}}
        </div>
      </div>
      {{signature}}
      <div class="bp_external_decl_body">{{body}}</div>
    </div>
  }}

private def visibilityHtml (v : Verso.Genre.Manual.Block.Docstring.Visibility) : ExternalDeclHtml :=
  open Verso.Output.Html in
  match v with
  | .public => .empty
  | .private => {{<span class="keyword">"private"</span>" "}}
  | .protected => .empty

private def renderDocNameCtor (docName : Verso.Genre.Manual.Block.Docstring.DocName) :
    ExternalDeclHighlightRender ExternalDeclHtml :=
  open Verso.Output.Html in do
  let signatureHtml ← highlightedToHtml docName.signature
  pure {{
    <div class="constructor">
      <pre class="name-and-type hl lean">{{signatureHtml}}</pre>
      {{docsHtml docName.docstring?}}
    </div>
  }}

private def renderFieldSignature (field : Verso.Genre.Manual.Block.Docstring.FieldInfo) :
    ExternalDeclHighlightRender ExternalDeclHtml :=
  open Verso.Output.Html in do
  let inheritedInfo : ExternalDeclHtml :=
    if field.fieldFrom.isEmpty then
      .empty
    else
      let inheritedRows : Array ExternalDeclHtml :=
        field.fieldFrom.toArray.map fun parent =>
          {{<li><code>{{.text true parent.name.toString}}</code></li>}}
      {{
        <div class="inheritance docs">
          "Inherited from "
          <ol>{{inheritedRows}}</ol>
        </div>
      }}
  let fieldNameHtml ← highlightedToHtml field.fieldName
  let fieldTypeHtml ← highlightedToHtml field.type
  pure {{
    <section class="subdocs">
      <pre class="name-and-type hl lean">
        {{visibilityHtml field.visibility}}{{fieldNameHtml}} " : " {{fieldTypeHtml}}
      </pre>
      {{inheritedInfo}}
      {{docsHtml field.docString?}}
    </section>
  }}

private def renderParentsSection
    (decl : Name)
    (parents : Array Verso.Genre.Manual.Block.Docstring.ParentInfo) :
    ExternalDeclHighlightRender (Option ExternalDeclHtml) :=
  open Verso.Output.Html in do
  if parents.isEmpty then
    pure none
  else
    let rows ← parents.mapM fun parent => do
      let parentHtml ← highlightedToHtml parent.parent
      pure {{<li><code class="hl lean inline">{{parentHtml}}</code></li>}}
    let labelId := externalDeclSectionLabelId decl "Extends"
    pure <| some {{
      <div class="bp_external_decl_section" role="group" aria-labelledby={{labelId}}>
        <p class="bp_external_decl_section_label" id={{labelId}}>"Extends"</p>
        <ul class="extends">{{rows}}</ul>
      </div>
    }}

private def safetyHeaderMeta (cinfo : ConstantInfo) : Array String :=
  match cinfo with
  | .defnInfo defn =>
    match defn.safety with
    | .unsafe => #["unsafe"]
    | .partial => #["partial"]
    | .safe => #[]
  | _ => #[]

private def renderExternalDeclHeaderMeta
    (declType : Verso.Genre.Manual.Block.Docstring.DeclType) :
    Array String := Id.run do
  let mut items : Array String := #[]
  match declType with
  | .structure isClass _ _ fieldInfo _ parents =>
    if !parents.isEmpty then
      items := items.push s!"extends {parents.size}"
    let visibleFields := fieldInfo.filter (fun f => f.subobject?.isNone)
    if let some fieldCount := countMeta?
        (if isClass then "method" else "field")
        (if isClass then "methods" else "fields")
        visibleFields.size then
      items := items.push fieldCount
  | .inductive ctors numArgs propOnly =>
    if let some ctorCount := countMeta? "constructor" "constructors" ctors.size then
      items := items.push ctorCount
    if propOnly then
      items := items.push "Prop"
    if let some paramCount := countMeta? "parameter" "parameters" numArgs then
      items := items.push paramCount
  | _ => pure ()
  return items

private def renderDeclHtmlDocstringFromInfoE
    (decl : Name) (cinfo : ConstantInfo)
    (headerBadge? : Option ExternalDeclHeaderBadge := none)
    (headerSource? : Option ExternalDeclHeaderSource := none) : MetaM ExternalDeclRenderResult :=
  open Verso.Output.Html in do
  let env ← getEnv
  let declType ←
    withOptions (verso.docstring.allowMissing.set · true) <|
      Verso.Genre.Manual.Block.Docstring.DeclType.ofName decl (hideStructureConstructor := true)
  let signature ← Verso.Genre.Manual.Signature.forName decl
  let docs? ← liftM <| findDocString? env decl

  let rendered := renderWithHoverPayloads <| do
    let ctorSection? : Option ExternalDeclHtml ←
      match declType with
      | .structure isClass ctor? _ _ _ _ =>
        match ctor? with
        | some ctor =>
          let title := if isClass then "Instance Constructor" else "Constructor"
          let ctorHtml ← renderDocNameCtor ctor
          pure <| renderTitledSection? decl title #[ctorHtml]
        | none => pure none
      | _ => pure none

    let methodsOrFieldsSection? : Option ExternalDeclHtml ←
      match declType with
      | .structure isClass _ _ fieldInfo _ _ =>
        let rows ← fieldInfo.filter (fun f => f.subobject?.isNone) |>.mapM renderFieldSignature
        pure <| renderTitledSection? decl (if isClass then "Methods" else "Fields") rows
      | _ => pure none

    let parentsSection? : Option ExternalDeclHtml ←
      match declType with
      | .structure _ _ _ _ parents _ => renderParentsSection decl parents
      | _ => pure none

    let inductiveCtorsSection? : Option ExternalDeclHtml ←
      match declType with
      | .inductive ctors _ _ =>
        let rows ← ctors.mapM renderDocNameCtor
        pure <| renderTitledSection? decl "Constructors" rows
      | _ => pure none

    let mut sections : Array ExternalDeclHtml := #[]
    if let some s := ctorSection? then
      sections := sections.push s
    if let some s := parentsSection? then
      sections := sections.push s
    if let some s := methodsOrFieldsSection? then
      sections := sections.push s
    if let some s := inductiveCtorsSection? then
      sections := sections.push s

    let presentation := externalDeclPresentation declType cinfo
    let signatureHtml ← signatureToHtml presentation.keywordText signature
    let headerMeta := safetyHeaderMeta cinfo ++ renderExternalDeclHeaderMeta declType

    let body : ExternalDeclHtml :=
      if sections.isEmpty then
        plainDocstringHtml docs?
      else
        {{ {{plainDocstringHtml docs?}} {{sections}} }}
    pure <| renderExternalDeclWrapper
      decl presentation.kindClass presentation.kindMarker signatureHtml body
      (headerBadge? := headerBadge?) (headerMeta := headerMeta) (headerSource? := headerSource?)
  pure <| .ok rendered

/--
Render one declaration directly from known declaration facts.
Errors represent rendering failures only; declaration lookup is handled by callers.
-/
def renderDeclHtmlDirectFromInfoE
    (decl : Name) (cinfo : ConstantInfo)
    (headerBadge? : Option ExternalDeclHeaderBadge := none)
    (headerSource? : Option ExternalDeclHeaderSource := none) : MetaM ExternalDeclRenderResult := do
  try
    renderDeclHtmlDocstringFromInfoE decl cinfo
      (headerBadge? := headerBadge?) (headerSource? := headerSource?)
  catch ex =>
    return .error (.exception decl (← ex.toMessageData.toString))

/-- Render one declaration directly from the in-memory `Environment` (no database, no source parsing). -/
def renderDeclHtmlNodeDirect? (decl : Name) : MetaM (Option ExternalDeclHtml) := do
  let decl := decl.eraseMacroScopes
  try
    let env ← getEnv
    let some cinfo := env.find? decl
      | return none
    match ← renderDeclHtmlDirectFromInfoE decl cinfo with
    | .ok html => return some (.text false html.selfContained)
    | .error err =>
      logError m!"External declaration rendering failed for {decl}: {err.message}"
      return none
  catch ex =>
    logError m!"External declaration rendering failed for {decl}: {← ex.toMessageData.toString}"
    return none

/--
Optional fallback path for non-`MetaM` contexts.
Database fallback is currently unavailable, so this returns `none`.
-/
def renderDeclHtmlNodeFromDb? (_dbPath : System.FilePath) (_decl : Name) :
    IO (Option ExternalDeclHtml) := do
  IO.eprintln "[external render db] fallback unavailable"
  return none

/-- Smoke demo targets: theorem/def (`Nat.add`), structure (`Prod`), and a missing name. -/
def externalDeclRenderSmokeDecls : Array Name := #[`Nat.add, `Prod, `No.Such.Declaration]

/-- Measure textual payload length in rendered declaration HTML. -/
def ExternalDeclHtml.textLength : ExternalDeclHtml → Nat
  | .text _ s => s.length
  | .tag _ _ content => textLength content
  | .seq contents => contents.foldl (fun acc child => acc + textLength child) 0

/-- Smoke demo helper for quick direct-path checks. -/
def runExternalDeclRenderSmokeDirect : MetaM (Array (Name × Option ExternalDeclHtml)) := do
  externalDeclRenderSmokeDecls.mapM fun decl => do
    let rendered? ← renderDeclHtmlNodeDirect? decl
    if let some html := rendered? then
      logInfo m!"[external decl render smoke] {decl}: rendered ({ExternalDeclHtml.textLength html} chars)"
    else
      logInfo m!"[external decl render smoke] {decl}: none"
    pure (decl, rendered?)

end Informal
