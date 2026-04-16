/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual

open Lean Meta

namespace Informal

abbrev DocGenHtml := Verso.Output.Html

inductive DocGenRenderError where
  | moduleUnavailable (decl : Name)
  | exception (decl : Name) (message : String)
  deriving Repr, Inhabited

deriving instance Lean.ToJson for DocGenRenderError
deriving instance Lean.FromJson for DocGenRenderError

instance : Lean.Quote DocGenRenderError where
  quote
    | .moduleUnavailable decl =>
        Lean.Syntax.mkApp (Lean.mkCIdent ``DocGenRenderError.moduleUnavailable) #[Lean.quote decl]
    | .exception decl message =>
        Lean.Syntax.mkApp (Lean.mkCIdent ``DocGenRenderError.exception) #[Lean.quote decl, Lean.quote message]

abbrev DocGenRender := Except DocGenRenderError DocGenHtml

def DocGenRenderError.message : DocGenRenderError → String
  | .moduleUnavailable decl => s!"module unavailable for {decl}"
  | .exception decl message => s!"{decl}: {message}"

private def runHighlightedHtml
    (html : Verso.Code.HighlightHtmlM Verso.Genre.Manual DocGenHtml) : DocGenHtml :=
  let ctx : Verso.Code.HighlightHtmlM.Context Verso.Genre.Manual := {
    linkTargets := {}
    traverseContext := { logError := fun _ => pure () }
    definitionIds := {}
    options := {}
  }
  let (html, hoverState) := ((html.run ctx).run {})
  inlineVersoHoverAttrs html hoverState.dedup
where
  /-
  Direct external declaration rendering is isolated from the page-level Verso hover table,
  so deduplicated hover ids would otherwise point at unrelated page content. Inline the
  resolved hover payloads locally to keep the rendered snippet self-contained.
  -/
  inlineVersoHoverAttrs
      (html : DocGenHtml) (hoverDedup : Verso.Code.Hover.Dedup DocGenHtml) : DocGenHtml :=
    Id.run <|
      html.visitM (tag := fun name attrs contents => do
        let mut inlineHover? : Option DocGenHtml := none
        let mut attrs' : Array (String × String) := #[]
        for (attr, value) in attrs do
          if attr == "data-verso-hover" then
            inlineHover? := value.toNat? >>= hoverDedup.get?
          else
            attrs' := attrs'.push (attr, value)
        let contents :=
          match inlineHover? with
          | some hoverHtml => contents ++ .tag "span" #[("class", "hover-info")] hoverHtml
          | none => contents
        pure <| some <| .tag name attrs' contents)

private def highlightedToHtml (h : SubVerso.Highlighting.Highlighted) : DocGenHtml :=
  runHighlightedHtml (h.toHtml (g := Verso.Genre.Manual))

private def renderExternalDeclSignatureVariant
    (keywordText : String) (signature : SubVerso.Highlighting.Highlighted) : DocGenHtml :=
  open Verso.Output.Html in
  {{
    <pre class="bp_external_decl_signature signature hl lean block">
      <span class="keyword token">{{.text true keywordText}}</span> " " {{highlightedToHtml signature}}
    </pre>
  }}

private def signatureToHtml (keywordText : String) (sig : Verso.Genre.Manual.Signature) : DocGenHtml :=
  open Verso.Output.Html in
  {{
    <div class="bp_external_decl_signature_wrap">
      <div class="wide-only">{{renderExternalDeclSignatureVariant keywordText sig.wide}}</div>
      <div class="narrow-only">{{renderExternalDeclSignatureVariant keywordText sig.narrow}}</div>
    </div>
  }}

private def plainDocstringHtml (docs? : Option String) : DocGenHtml :=
  open Verso.Output.Html in
  match docs? with
  | none => .empty
  | some docs =>
    {{<pre class="docstring">{{.text true docs}}</pre>}}

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
    (signature : DocGenHtml) (body : DocGenHtml) : DocGenHtml :=
  open Verso.Output.Html in
  {{
    <div class={{s!"declaration decl {kindClass}"}} data-decl={{decl.toString}} data-kind={{kindMarker}}>
      {{signature}}
      <div class="bp_external_decl_body">{{body}}</div>
    </div>
  }}

private def visibilityHtml (v : Verso.Genre.Manual.Block.Docstring.Visibility) : DocGenHtml :=
  open Verso.Output.Html in
  match v with
  | .public => .empty
  | .private => {{<span class="keyword">"private"</span>" "}}
  | .protected => .empty

private def renderDocNameCtor (docName : Verso.Genre.Manual.Block.Docstring.DocName) : DocGenHtml :=
  open Verso.Output.Html in
  {{
    <div class="constructor">
      <pre class="name-and-type hl lean">{{highlightedToHtml docName.signature}}</pre>
      <div class="docs">{{plainDocstringHtml docName.docstring?}}</div>
    </div>
  }}

private def renderFieldSignature (field : Verso.Genre.Manual.Block.Docstring.FieldInfo) : DocGenHtml :=
  open Verso.Output.Html in
  let inheritedInfo : DocGenHtml :=
    if field.fieldFrom.isEmpty then
      .empty
    else
      let inheritedRows : Array DocGenHtml :=
        field.fieldFrom.toArray.map fun parent =>
          {{<li><code>{{.text true parent.name.toString}}</code></li>}}
      {{
        <div class="inheritance docs">
          "Inherited from "
          <ol>{{inheritedRows}}</ol>
        </div>
      }}
  {{
    <section class="subdocs">
      <pre class="name-and-type hl lean">
        {{visibilityHtml field.visibility}}{{highlightedToHtml field.fieldName}} " : " {{highlightedToHtml field.type}}
      </pre>
      {{inheritedInfo}}
      <div class="docs">{{plainDocstringHtml field.docString?}}</div>
    </section>
  }}

private def renderParentsSection
    (parents : Array Verso.Genre.Manual.Block.Docstring.ParentInfo) : Option DocGenHtml :=
  open Verso.Output.Html in
  if parents.isEmpty then
    none
  else
    let rows :=
      parents.map fun parent =>
        {{<li><code class="hl lean inline">{{highlightedToHtml parent.parent}}</code></li>}}
    some {{
      <h1>"Extends"</h1>
      <ul class="extends">{{rows}}</ul>
    }}

private def renderDeclHtmlDocstringFromInfoE
    (decl : Name) (cinfo : ConstantInfo) : MetaM DocGenRender :=
  open Verso.Output.Html in do
  let env ← getEnv
  let declType ←
    withOptions (verso.docstring.allowMissing.set · true) <|
      Verso.Genre.Manual.Block.Docstring.DeclType.ofName decl
  let signature ← Verso.Genre.Manual.Signature.forName decl
  let docs? ← liftM <| findDocString? env decl

  let ctorSection? : Option DocGenHtml :=
    match declType with
    | .structure isClass ctor? _ _ _ _ =>
      ctor?.map fun ctor =>
        let title := if isClass then "Instance Constructor" else "Constructor"
        {{
          <h1>{{.text true title}}</h1>
          {{renderDocNameCtor ctor}}
        }}
    | _ => none

  let methodsOrFieldsSection? : Option DocGenHtml :=
    match declType with
    | .structure isClass _ _ fieldInfo _ _ =>
      let rows := fieldInfo.filter (fun f => f.subobject?.isNone) |>.map renderFieldSignature
      if rows.isEmpty then
        none
      else
        let title := if isClass then "Methods" else "Fields"
        some {{
          <h1>{{.text true title}}</h1>
          {{rows}}
        }}
    | _ => none

  let parentsSection? : Option DocGenHtml :=
    match declType with
    | .structure _ _ _ _ parents _ => renderParentsSection parents
    | _ => none

  let inductiveCtorsSection? : Option DocGenHtml :=
    match declType with
    | .inductive ctors _ _ =>
      if ctors.isEmpty then
        none
      else
        let rows := ctors.map renderDocNameCtor
        some {{
          <h1>"Constructors"</h1>
          {{rows}}
        }}
    | _ => none

  let mut sections : Array DocGenHtml := #[]
  if let some s := ctorSection? then
    sections := sections.push s
  if let some s := parentsSection? then
    sections := sections.push s
  if let some s := methodsOrFieldsSection? then
    sections := sections.push s
  if let some s := inductiveCtorsSection? then
    sections := sections.push s

  let presentation := externalDeclPresentation declType cinfo
  let signatureHtml := signatureToHtml presentation.keywordText signature

  let body : DocGenHtml :=
    if sections.isEmpty then
      plainDocstringHtml docs?
    else
      {{ {{plainDocstringHtml docs?}} {{sections}} }}
  pure <| .ok <| renderExternalDeclWrapper
    decl presentation.kindClass presentation.kindMarker signatureHtml body

/--
Render one declaration directly from known declaration facts.
Errors represent rendering failures only; declaration lookup is handled by callers.
-/
def renderDeclHtmlDirectFromInfoE
    (decl : Name) (cinfo : ConstantInfo) : MetaM DocGenRender := do
  try
    renderDeclHtmlDocstringFromInfoE decl cinfo
  catch ex =>
    return .error (.exception decl (← ex.toMessageData.toString))

/--
String compatibility wrapper over `renderDeclHtmlDirectFromInfoE`.
Core external-rendering dataflow should use typed HTML payloads.
-/
def renderDeclHtmlStringDirectFromInfoE
    (decl : Name) (cinfo : ConstantInfo) : MetaM (Except DocGenRenderError String) := do
  return (← renderDeclHtmlDirectFromInfoE decl cinfo).map (·.asString)

/-- Render one declaration directly from the in-memory `Environment` (no database, no source parsing). -/
def renderDeclHtmlNodeDirect? (decl : Name) : MetaM (Option DocGenHtml) := do
  let decl := decl.eraseMacroScopes
  try
    let env ← getEnv
    let some cinfo := env.find? decl
      | return none
    match ← renderDeclHtmlDirectFromInfoE decl cinfo with
    | .ok html => return some html
    | .error err =>
      logError m!"External declaration rendering failed for {decl}: {err.message}"
      return none
  catch ex =>
    logError m!"External declaration rendering failed for {decl}: {← ex.toMessageData.toString}"
    return none

/-- String wrapper over `renderDeclHtmlNodeDirect?`. -/
def renderDeclHtmlStringDirect? (decl : Name) : MetaM (Option String) := do
  match ← renderDeclHtmlNodeDirect? decl with
  | some html => return some html.asString
  | none => return none

/--
Optional fallback path for non-`MetaM` contexts.
Database fallback is currently unavailable, so this returns `none`.
-/
def renderDeclHtmlNodeFromDb? (_dbPath : System.FilePath) (_decl : Name) : IO (Option DocGenHtml) := do
  IO.eprintln "[external render db] fallback unavailable"
  return none

/-- Smoke demo targets: theorem/def (`Nat.add`), structure (`Prod`), and a missing name. -/
def docGenNameRenderSmokeDecls : Array Name := #[`Nat.add, `Prod, `No.Such.Declaration]

/-- Measure textual payload length in rendered declaration HTML. -/
def DocGenHtml.textLength : DocGenHtml → Nat
  | .text _ s => s.length
  | .tag _ _ content => textLength content
  | .seq contents => contents.foldl (fun acc child => acc + textLength child) 0

/-- Smoke demo helper for quick direct-path checks. -/
def runDocGenNameRenderSmokeDirect : MetaM (Array (Name × Option DocGenHtml)) := do
  docGenNameRenderSmokeDecls.mapM fun decl => do
    let rendered? ← renderDeclHtmlNodeDirect? decl
    if let some html := rendered? then
      logInfo m!"[doc-gen direct smoke] {decl}: rendered ({DocGenHtml.textLength html} chars)"
    else
      logInfo m!"[doc-gen direct smoke] {decl}: none"
    pure (decl, rendered?)

end Informal
