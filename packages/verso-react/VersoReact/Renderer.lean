/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Vir.React
public import Vir.ProofWidgets.Jsx
public import VersoManual.Basic
public import VersoReact.RenderPath
public import VersoReact.Fingerprint
public meta import VersoReact.RenderPath

public section

namespace VersoReact.Renderer

open Lean.Vir
open Lean.Vir.React
open Lean.Doc.Syntax
open _root_.Verso
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

namespace Style

private def vscodeColor (name fallback : String) : String :=
  "var(--vscode-" ++ name ++ ", " ++ fallback ++ ")"

private def border (color : String) : String :=
  "1px solid " ++ color

def foreground : String := vscodeColor "editor-foreground" "#24292f"
def muted : String := vscodeColor "descriptionForeground" "#57606a"
def background : String := vscodeColor "editor-background" "#ffffff"
def codeBackground : String := vscodeColor "textCodeBlock-background" "#f6f8fa"
def borderColor : String := vscodeColor "panel-border" "#d0d7de"

def document : ReactM (Js Props) := js%{ "display" := (← js#"grid"), "gap" := (← js#"10px"), "minWidth" := (← js#"0"), "padding" := (← js#"10px 12px"), "border" := (← JsValue.ofString (border borderColor)), "borderRadius" := (← js#"6px"), "background" := (← JsValue.ofString background), "color" := (← JsValue.ofString foreground), "colorScheme" := (← js#"light dark"), "fontFamily" := (← js#"Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"), "overflowWrap" := (← js#"anywhere") }
def part : ReactM (Js Props) := js%{ "display" := (← js#"grid"), "gap" := (← js#"10px"), "minWidth" := (← js#"0") }
def heading : ReactM (Js Props) := js%{ "margin" := (← js#"0"), "fontSize" := (← js#"1.12rem"), "lineHeight" := (← js#"1.3") }
def paragraph : ReactM (Js Props) := js%{ "margin" := (← js#"0"), "lineHeight" := (← js#"1.5") }
def list : ReactM (Js Props) := js%{ "display" := (← js#"grid"), "gap" := (← js#"6px"), "margin" := (← js#"0"), "paddingLeft" := (← js#"1.5rem") }
def listItem : ReactM (Js Props) := js%{ "paddingLeft" := (← js#"0.15rem") }
def blockquote : ReactM (Js Props) := js%{ "display" := (← js#"grid"), "gap" := (← js#"8px"), "margin" := (← js#"0"), "padding" := (← js#"2px 0 2px 12px"), "borderLeft" := (← JsValue.ofString (border borderColor)), "color" := (← JsValue.ofString muted) }
def descriptionList : ReactM (Js Props) := js%{ "display" := (← js#"grid"), "gridTemplateColumns" := (← js#"max-content minmax(0, 1fr)"), "gap" := (← js#"6px 10px"), "margin" := (← js#"0") }
def descriptionTerm : ReactM (Js Props) := js%{ "fontWeight" := (← js#"700") }
def descriptionValue : ReactM (Js Props) := js%{ "margin" := (← js#"0") }
def inlineCode : ReactM (Js Props) := js%{ "padding" := (← js#"0.08em 0.3em"), "borderRadius" := (← js#"3px"), "background" := (← JsValue.ofString codeBackground), "fontFamily" := (← js#"ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"), "fontSize" := (← js#"0.92em") }
def codeBlock : ReactM (Js Props) := js%{ "margin" := (← js#"0"), "padding" := (← js#"9px 10px"), "overflow" := (← js#"auto"), "borderRadius" := (← js#"5px"), "background" := (← JsValue.ofString codeBackground), "fontFamily" := (← js#"ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"), "fontSize" := (← js#"0.78rem"), "lineHeight" := (← js#"1.45"), "whiteSpace" := (← js#"pre") }
def mathInline : ReactM (Js Props) := js%{ "padding" := (← js#"0 0.08em"), "fontFamily" := (← js#"KaTeX_Main, Cambria Math, STIX Two Math, serif"), "fontSize" := (← js#"1.02em"), "whiteSpace" := (← js#"pre-wrap") }
def mathDisplay : ReactM (Js Props) := js%{ "display" := (← js#"block"), "padding" := (← js#"8px 10px"), "overflowX" := (← js#"auto"), "borderRadius" := (← js#"5px"), "background" := (← JsValue.ofString codeBackground), "fontFamily" := (← js#"KaTeX_Main, Cambria Math, STIX Two Math, serif"), "fontSize" := (← js#"1.02em"), "lineHeight" := (← js#"1.5"), "textAlign" := (← js#"center"), "whiteSpace" := (← js#"pre-wrap") }
def unsupported : ReactM (Js Props) := js%{ "padding" := (← js#"7px 9px"), "border" := (← JsValue.ofString (border borderColor)), "borderRadius" := (← js#"5px"), "color" := (← JsValue.ofString muted) }

end Style

/-- Constant styles owned by one component factory. Treat these objects as read-only;
node attributes remain fresh. CSS variables keep theme changes independent of React updates. -/
structure Styles where
  document : Js Props
  part : Js Props
  heading : Js Props
  paragraph : Js Props
  list : Js Props
  listItem : Js Props
  blockquote : Js Props
  descriptionList : Js Props
  descriptionTerm : Js Props
  descriptionValue : Js Props
  inlineCode : Js Props
  codeBlock : Js Props
  mathInline : Js Props
  mathDisplay : Js Props
  unsupported : Js Props

def Styles.create : ReactM Styles := do
  return {
    document := ← Style.document, part := ← Style.part, heading := ← Style.heading
    paragraph := ← Style.paragraph, list := ← Style.list, listItem := ← Style.listItem
    blockquote := ← Style.blockquote, descriptionList := ← Style.descriptionList
    descriptionTerm := ← Style.descriptionTerm, descriptionValue := ← Style.descriptionValue
    inlineCode := ← Style.inlineCode, codeBlock := ← Style.codeBlock
    mathInline := ← Style.mathInline, mathDisplay := ← Style.mathDisplay
    unsupported := ← Style.unsupported
  }

/--
Application-owned Manual extensions. Unhandled extensions remain visible together
with their children. The callbacks construct ordinary React nodes, not components
or hook scopes. Children are lazy so hidden extensions need not render them.
-/
structure Extensions where
  /-- Optional stable leaf component. It receives source, mode and caller attributes. -/
  mathComponent? : Option (FunctionComponent Props) := none
  /-- Replace an inline extension using its sibling-local React key (not a source path),
  or return `none` for the visible fallback. -/
  renderInline? : (key : String) → Genre.Manual.Inline → ReactM (Option (Js Node)) :=
    fun _ _ => pure none
  /--
  Replace a block extension, or return `none` for the visible fallback.
  `attributes kind style` supplies the existing key, identity, focus and change
  markers. Call `children ()` once when needed; hidden blocks can skip it.
  -/
  renderBlock? : (key : String) → (attributes : String → Js Props → ReactM (Js Props)) →
      Genre.Manual.Block → (children : Unit → ReactM (Array (Js Node))) →
      ReactM (Option (Js Node)) :=
    fun _ _ _ _ => pure none
  /-- Optional semantic identity; sibling duplicates are disambiguated by the renderer. -/
  blockIdentity? : Genre.Manual.Block → Option String := fun _ => none

private inductive IdentityOrigin where
  | structural
  | explicit
  | verso
  | fingerprint
  | positional
  deriving BEq, Inhabited

private def IdentityOrigin.label : IdentityOrigin → String
  | .structural => "structural"
  | .explicit => "explicit"
  | .verso => "verso"
  | .fingerprint => "fingerprint"
  | .positional => "positional"

/--
Identity sources are ordered from strongest to weakest. Ordinary Manual blocks
reach the fingerprint branch; extension metadata can provide stronger semantic
identities where the application owns their meaning.
-/
private structure IdentityHints where
  explicitId? : Option String := none
  versoId? : Option String := none
  fingerprint? : Option String := none
  deriving Inhabited

private structure IdentityBase where
  reactKey : String
  friendlyId : String
  origin : IdentityOrigin

private structure Identity where
  reactKey : String
  debugPath : String
  semanticKey : String
  friendlyId : String
  origin : IdentityOrigin
  deriving Inhabited

private def fingerprintFriendlyId (value : String) : String :=
  s!"fp-{(hash value : UInt64)}"

private def IdentityHints.resolve
    (kind : String) (index : Nat) (debugPath : String) (hints : IdentityHints) : IdentityBase :=
  match hints.explicitId?, hints.versoId?, hints.fingerprint? with
  | some value, _, _ =>
      { reactKey := s!"explicit:{value}", friendlyId := value, origin := .explicit }
  | none, some value, _ =>
      { reactKey := s!"verso:{value}", friendlyId := value, origin := .verso }
  | none, none, some value =>
      -- The full canonical value stays in the React key. The short hash is
      -- human-facing only, so collisions cannot alias siblings.
      { reactKey := s!"fingerprint:{kind}:{value.length}:{value}"
        friendlyId := fingerprintFriendlyId value
        origin := .fingerprint }
  | none, none, none =>
      { reactKey := s!"position:{kind}:{index}", friendlyId := debugPath, origin := .positional }

private def allocateSiblingIdentities
    (parentSemanticKey debugParent segment kind : String)
    (hints : Array IdentityHints) : Array Identity := Id.run do
  let mut seen : Std.HashMap String Nat := {}
  let mut identities := #[]
  for index in [:hints.size] do
    let debugPath := RenderPath.child debugParent segment index
    let base := hints[index]!.resolve kind index debugPath
    let occurrence := seen.getD base.reactKey 0
    seen := seen.insert base.reactKey (occurrence + 1)
    let reactKey := s!"{base.reactKey}:occurrence:{occurrence}"
    let friendlyId :=
      if occurrence == 0 then base.friendlyId else s!"{base.friendlyId}~{occurrence}"
    identities := identities.push {
      reactKey
      debugPath
      semanticKey := s!"{parentSemanticKey}/{segment}/{reactKey}"
      friendlyId
      origin := base.origin
    }
  return identities

private partial def blockIdentitySource (extensions : Extensions)
    (block : _root_.Verso.Doc.Block Genre.Manual) : String ⊕ Doc.Block Genre.Manual :=
  match block with
  | .concat content =>
      if content.size == 1 then
        blockIdentitySource extensions content[0]!
      else
        .inr block
  | .other extension _ =>
      match extensions.blockIdentity? extension with
      | some identity => .inl identity
      | none => .inr block
  | _ => .inr block

private def blockIdentityHints (extensions : Extensions) (block : Doc.Block Genre.Manual)
    (fingerprint : Fingerprint.Value → String) : IdentityHints :=
  match blockIdentitySource extensions block with
  | .inl identity => { explicitId? := some identity }
  | .inr block => { fingerprint? := some (fingerprint (.inl block)) }

private def partIdentityHints
    (part : _root_.Verso.Doc.Part Genre.Manual)
    (fingerprint : Fingerprint.Value → String) : IdentityHints :=
  -- A section title identifies the section without coupling its key to body edits.
  { fingerprint? := some (fingerprint (.inr part.title)) }

private def blockIdentities (extensions : Extensions)
    (parentSemanticKey debugParent : String)
    (blocks : Array (_root_.Verso.Doc.Block Genre.Manual))
    (fingerprint : Fingerprint.Value → String := Fingerprint.canonicalKey) : Array Identity :=
  allocateSiblingIdentities parentSemanticKey debugParent "block" "block"
    (blocks.map (fun block => blockIdentityHints extensions block fingerprint))

private def partIdentities
    (parentSemanticKey debugParent : String)
    (parts : Array (_root_.Verso.Doc.Part Genre.Manual))
    (fingerprint : Fingerprint.Value → String := Fingerprint.canonicalKey) : Array Identity :=
  allocateSiblingIdentities parentSemanticKey debugParent "part" "part"
    (parts.map (fun part => partIdentityHints part fingerprint))

private partial def appendFingerprintValues (extensions : Extensions)
    (values : Array Fingerprint.Value) (block : Doc.Block Genre.Manual) : Array Fingerprint.Value := Id.run do
  let values := match blockIdentitySource extensions block with
    | .inl _ => values
    | .inr value => values.push (.inl value)
  match block with
  | .para _ | .code _ => return values
  | .concat blocks | .blockquote blocks | .other _ blocks =>
    return blocks.foldl (appendFingerprintValues extensions) values
  | .ul items | .ol _ items =>
    return items.foldl (fun values item => item.contents.foldl (appendFingerprintValues extensions) values) values
  | .dl items =>
    return items.foldl (fun values item => item.desc.foldl (appendFingerprintValues extensions) values) values

private partial def partFingerprintValues (extensions : Extensions)
    (values : Array Fingerprint.Value) (part : Doc.Part Genre.Manual) : Array Fingerprint.Value :=
  let values := part.content.foldl (appendFingerprintValues extensions) (values.push (.inr part.title))
  part.subParts.foldl (partFingerprintValues extensions) values

/-- Advance one mounted preview's content identities. Explicit labels retain
their existing policy. Preparation visits document blocks but never renders
extension children or invokes JavaScript. Retain the result in React state. -/
def prepareIdentities (previous : Fingerprint.State) (document : Doc.Part Genre.Manual)
    (extensions : Extensions := {}) : Fingerprint.State :=
  previous.advance (partFingerprintValues extensions #[] document)

private def rootIdentity : Identity := {
  reactKey := "structural:root"
  debugPath := RenderPath.root
  semanticKey := "root"
  friendlyId := "root"
  origin := .structural
}

private def headingIdentity (part : Identity) : Identity := {
  reactKey := "structural:heading"
  debugPath := RenderPath.heading part.debugPath
  semanticKey := s!"{part.semanticKey}/heading"
  friendlyId := s!"{part.friendlyId}/heading"
  origin := .structural
}

private inductive SnapshotValue where
  | heading (content : Array (_root_.Verso.Doc.Inline Genre.Manual))
  | block (content : _root_.Verso.Doc.Block Genre.Manual)
  deriving BEq

private structure Snapshot where
  debugPath : String
  semanticKey : String
  value : SnapshotValue

private partial def appendBlockSnapshots (extensions : Extensions)
    (snapshots : Array Snapshot)
    (identity : Identity) : _root_.Verso.Doc.Block Genre.Manual → Array Snapshot
  | .concat content =>
      appendChildBlockSnapshots extensions snapshots identity.semanticKey identity.debugPath content
  | block@(.other _ content) =>
      let snapshots := snapshots.push {
        debugPath := identity.debugPath
        semanticKey := identity.semanticKey
        value := .block block
      }
      appendChildBlockSnapshots extensions snapshots identity.semanticKey identity.debugPath content
  | block => snapshots.push {
      debugPath := identity.debugPath
      semanticKey := identity.semanticKey
      value := .block block
    }
where
  appendChildBlockSnapshots (extensions : Extensions)
      (snapshots : Array Snapshot)
      (parentSemanticKey debugParent : String)
      (content : Array (_root_.Verso.Doc.Block Genre.Manual)) : Array Snapshot := Id.run do
    let identities := blockIdentities extensions parentSemanticKey debugParent content
    let mut snapshots := snapshots
    for index in [:content.size] do
      snapshots := appendBlockSnapshots extensions snapshots identities[index]! content[index]!
    return snapshots

private partial def appendSnapshots (extensions : Extensions)
    (snapshots : Array Snapshot)
    (identity : Identity)
    (part : _root_.Verso.Doc.Part Genre.Manual) : Array Snapshot := Id.run do
  let heading := headingIdentity identity
  let mut snapshots := snapshots.push {
    debugPath := heading.debugPath
    semanticKey := heading.semanticKey
    value := .heading part.title
  }
  let blocks := blockIdentities extensions identity.semanticKey identity.debugPath part.content
  for index in [:part.content.size] do
    snapshots := appendBlockSnapshots extensions snapshots blocks[index]! part.content[index]!
  let subParts := partIdentities identity.semanticKey identity.debugPath part.subParts
  for index in [:part.subParts.size] do
    snapshots := appendSnapshots extensions snapshots subParts[index]! part.subParts[index]!
  return snapshots

private def snapshots (extensions : Extensions) (document : Doc.Part Genre.Manual) : Array Snapshot :=
  appendSnapshots extensions #[] rootIdentity document

/--
Renderer paths changed relative to the optional previous document, together
with the current renderer-node count. The current snapshot tree is collected
once so change highlighting and diagnostics share the same traversal.
-/
def changedBlockIdsAndCount
    (previous : Option (Doc.Part Genre.Manual))
    (current : Doc.Part Genre.Manual)
    (extensions : Extensions := {}) : Array String × Nat :=
  let currentSnapshots := snapshots extensions current
  let changedIds :=
    match previous with
    | none => currentSnapshots.map (·.debugPath)
    | some previous =>
        let previousByKey := snapshots extensions previous |>.foldl
          (init := ({} : Std.HashMap String SnapshotValue)) fun entries snapshot =>
            entries.insert snapshot.semanticKey snapshot.value
        currentSnapshots.filterMap fun snapshot =>
          match previousByKey.get? snapshot.semanticKey with
          | some prior => if prior == snapshot.value then none else some snapshot.debugPath
          | none => some snapshot.debugPath
  (changedIds, currentSnapshots.size)

/-- Structural renderer paths used to highlight a newly mounted document. -/
def renderBlockIds (document : Doc.Part Genre.Manual)
    (extensions : Extensions := {}) : Array String :=
  (changedBlockIdsAndCount none document extensions).1

/-- Renderer paths whose semantic nodes are new or changed in `current`. -/
def changedBlockIds (previous current : Doc.Part Genre.Manual)
    (extensions : Extensions := {}) : Array String :=
  (changedBlockIdsAndCount (some previous) current extensions).1

private def blockProps
    (identity : Identity)
    (kind : String)
    (style : Js Props)
    (changed focused : Bool) : ReactM (Js Props) := do
  let props ← js%{ "style" := style }
  let classes := if focused then
    if changed then "vir-verso-block vir-verso-block-changed vir-verso-block-focused"
    else "vir-verso-block vir-verso-block-focused"
  else if changed then "vir-verso-block vir-verso-block-changed" else "vir-verso-block"
  Js.Object.set props (← js#"key") (← JsValue.ofString identity.reactKey)
  Js.Object.set props (← js#"className") (← JsValue.ofString classes)
  Js.Object.set props (← js#"data-verso-block") (← JsValue.ofString identity.debugPath)
  Js.Object.set props (← js#"data-verso-render-id") (← JsValue.ofString identity.friendlyId)
  Js.Object.set props (← js#"data-verso-identity-origin") (← JsValue.ofString identity.origin.label)
  Js.Object.set props (← js#"data-verso-kind") (← JsValue.ofString kind)
  Js.Object.set props (← js#"title") (← JsValue.ofString s!"render path: {identity.debugPath}\nidentity: {identity.friendlyId} ({identity.origin.label})")
  if changed then Js.Object.set props (← js#"data-verso-change") (← js#"changed")
  if focused then Js.Object.set props (← js#"data-verso-focus") (← js#"cursor")
  pure props

private def listItemProps
    (key path kind : String)
    (style : Js Props)
    (focused : Bool) : ReactM (Js Props) := do
  let props ← js%{ "style" := style }
  Js.Object.set props (← js#"key") (← JsValue.ofString key)
  Js.Object.set props (← js#"className") (← JsValue.ofString (if focused then "vir-verso-list-item vir-verso-block-focused" else "vir-verso-list-item"))
  Js.Object.set props (← js#"data-verso-list-item") (← JsValue.ofString path)
  Js.Object.set props (← js#"data-verso-kind") (← JsValue.ofString kind)
  Js.Object.set props (← js#"title") (← JsValue.ofString s!"source list item: {path}")
  if focused then Js.Object.set props (← js#"data-verso-focus") (← js#"cursor")
  pure props

/-- Source-preserving math node with a sibling-local React key;
callers may add attributes for their typesetter. -/
def renderMath
    (styles : Styles)
    (key : String)
    (mode : Lean.Doc.MathMode)
    (source : String)
    (attributes : Option (Js Props) := none)
    (component? : Option (FunctionComponent Props) := none) : ReactM (Lean.Vir.Js Node) := do
  let modeClass := match mode with
    | Lean.Doc.MathMode.inline => "inline"
    | Lean.Doc.MathMode.display => "display"
  let style := match mode with
    | Lean.Doc.MathMode.inline => styles.mathInline
    | Lean.Doc.MathMode.display => styles.mathDisplay
  let props ← match attributes with
    | some attributes => do
      Js.Object.set attributes (← js#"style") style
      pure attributes
    | none => js%{ "style" := style }
  Js.Object.set props (← js#"key") (← JsValue.ofString key)
  let className ← Js.Object.get props (← js#"className")
  if ← JsValue.toBool (← Js.UndefinedOr.isUndefined (Js.UndefinedOr.ofJs className)) then
    Js.Object.set props (← js#"className") (← JsValue.ofString s!"vir-verso-math {modeClass}")
  Js.Object.set props (← js#"data-verso-math-mode") (← JsValue.ofString modeClass)
  if let some component := component? then
    Js.Object.set props (← js#"source") (← JsValue.ofString source)
    return ← Node.functionComponent component props (← js#[])
  return ← <code @props={props}>{Lean.Vir.React.Node.text (← JsValue.ofString source)}</code>

private partial def renderInline (styles : Styles) (extensions : Extensions)
    (key : String) : _root_.Verso.Doc.Inline Genre.Manual → ReactM (Lean.Vir.Js Node)
  | .text value | .linebreak value => do Node.text (← JsValue.ofString value)
  | .code value => do
      let style := styles.inlineCode
      let props ← js%{ "style" := style }
      Js.Object.set props (← js#"key") (← JsValue.ofString key)
      return ← <code @props={props}>{Lean.Vir.React.Node.text (← JsValue.ofString value)}</code>
  | .math mode value => renderMath styles key mode value none extensions.mathComponent?
  | .emph content => do
      let children ← renderInlines styles extensions content
      return ← <em key={← JsValue.ofString key}>{Js.Array.ofArray children}</em>
  | .bold content => do
      let children ← renderInlines styles extensions content
      return ← <strong key={← JsValue.ofString key}>{Js.Array.ofArray children}</strong>
  | .link content destination => do
      let children ← renderInlines styles extensions content
      return ← <a key={← JsValue.ofString key} href={← JsValue.ofString destination}>{Js.Array.ofArray children}</a>
  | .footnote name content => do
      let label ← Node.text (← JsValue.ofString s!"[{name}]")
      let summary ← <summary key="structural:summary">{pure label}</summary>
      let children ← renderInlines styles extensions content
      return ← <details key={← JsValue.ofString key} className="vir-verso-footnote">{pure summary}{Js.Array.ofArray children}</details>
  | .image alt destination => do return ← <img key={← JsValue.ofString key} src={← JsValue.ofString destination} alt={← JsValue.ofString alt}/>
  | .concat content => do
      let props ← js%{ "key" := (← JsValue.ofString key) }
      Node.fragment props (← Js.Array.ofArray (← renderInlines styles extensions content))
  | .other extension content => do
      match ← extensions.renderInline? key extension with
      | some rendered => pure rendered
      | none =>
          let style := styles.inlineCode
          let props ← js%{ "style" := style }
          Js.Object.set props (← js#"key") (← js#"structural:extension")
          Js.Object.set props (← js#"className") (← js#"vir-verso-extension-unsupported")
          Js.Object.set props (← js#"data-verso-extension") (← JsValue.ofString extension.name.toString)
          let marker ← <code @props={props}>{Lean.Vir.React.Node.text (← JsValue.ofString s!"[inline extension: {extension.name}]")}</code>
          let fragmentProps ← js%{ "key" := (← JsValue.ofString key) }
          Node.fragment fragmentProps
            (← Js.Array.ofArray (#[marker] ++ (← renderInlines styles extensions content)))

where
  renderInlines (styles : Styles) (extensions : Extensions)
      (content : Array (_root_.Verso.Doc.Inline Genre.Manual)) : ReactM (Array (Lean.Vir.Js Node)) :=
    content.mapIdxM fun index inline => renderInline styles extensions s!"inline:{index}" inline

private partial def renderInlines (styles : Styles) (extensions : Extensions)
    (content : Array (_root_.Verso.Doc.Inline Genre.Manual)) : ReactM (Array (Lean.Vir.Js Node)) :=
  content.mapIdxM fun index inline => renderInline styles extensions s!"inline:{index}" inline

private def headingNode
    (styles : Styles)
    (identity : Identity)
    (level : Nat)
    (content : Array (Lean.Vir.Js Node))
    (changed focused : Bool) : ReactM (Lean.Vir.Js Node) := do
  let props ← blockProps identity "heading" (styles.heading) changed focused
  match level with
  | 1 => <h1 @props={props}>{Js.Array.ofArray content}</h1>
  | 2 => <h2 @props={props}>{Js.Array.ofArray content}</h2>
  | 3 => <h3 @props={props}>{Js.Array.ofArray content}</h3>
  | 4 => <h4 @props={props}>{Js.Array.ofArray content}</h4>
  | 5 => <h5 @props={props}>{Js.Array.ofArray content}</h5>
  | _ => <h6 @props={props}>{Js.Array.ofArray content}</h6>

private partial def renderBlock (styles : Styles) (extensions : Extensions) (fingerprint : Fingerprint.Value → String)
    (changedIds : Array String)
    (focus : Option String)
    (identity : Identity) : _root_.Verso.Doc.Block Genre.Manual → ReactM (Lean.Vir.Js Node)
  | .para content => do
      let props ← blockProps identity "paragraph" (styles.paragraph) (changedIds.contains identity.debugPath) (focus == some identity.debugPath)
      let children ← renderInlines styles extensions content
      return ← <p @props={props}>{Js.Array.ofArray children}</p>
  | .code source => do
      let text ← Node.text (← JsValue.ofString source)
      let codeProps ← js%{ "data-language" := (← js#"") }
      let code ← <code @props={codeProps}>{pure text}</code>
      let props ← blockProps identity "code" (styles.codeBlock) (changedIds.contains identity.debugPath) (focus == some identity.debugPath)
      return ← <pre @props={props}>{pure code}</pre>
  | .ul items => do
      let props ← blockProps identity "unordered-list" (styles.list) (changedIds.contains identity.debugPath) (focus == some identity.debugPath)
      let children ← items.mapIdxM fun index item => renderListItem styles extensions fingerprint changedIds focus identity.semanticKey s!"item:{index}" s!"{identity.debugPath}-item-{index}" item
      return ← <ul @props={props}>{Js.Array.ofArray children}</ul>
  | .ol start items => do
      let props ← blockProps identity "ordered-list" (styles.list) (changedIds.contains identity.debugPath) (focus == some identity.debugPath)
      Js.Object.set props (← js#"start") (← JsValue.ofString (toString (max start 0)))
      let children ← items.mapIdxM fun index item => renderListItem styles extensions fingerprint changedIds focus identity.semanticKey s!"item:{index}" s!"{identity.debugPath}-item-{index}" item
      return ← <ol @props={props}>{Js.Array.ofArray children}</ol>
  | .dl items => do
      let children ← items.mapIdxM fun index item =>
        renderDescItem styles extensions fingerprint changedIds focus identity.semanticKey s!"item:{index}" s!"{identity.debugPath}-item-{index}" item
      let props ← blockProps identity "description-list" (styles.descriptionList) (changedIds.contains identity.debugPath) (focus == some identity.debugPath)
      return ← <dl @props={props}>{Js.Array.ofArray children.flatten}</dl>
  | .blockquote content => do
      let props ← blockProps identity "blockquote" (styles.blockquote) (changedIds.contains identity.debugPath) (focus == some identity.debugPath)
      let children ← renderBlocks styles extensions fingerprint changedIds focus identity.semanticKey identity.debugPath content
      return ← <blockquote @props={props}>{Js.Array.ofArray children}</blockquote>
  | .concat content => do
      -- Concatenations are React fragments, not DOM nodes. A source block may
      -- expand to several children; mark those children without adding a wrapper.
      let props ← js%{ "key" := (← JsValue.ofString identity.reactKey) }
      Node.fragment props
        (← Js.Array.ofArray
          (← renderBlocks styles extensions fingerprint changedIds focus identity.semanticKey identity.debugPath content
            (focusChildren := focus == some identity.debugPath)))
  | .other extension content => do
      let changed := changedIds.contains identity.debugPath
      let focused := focus == some identity.debugPath
      let attributes := fun kind style => blockProps identity kind style changed focused
      let children := fun _ : Unit =>
        renderBlocks styles extensions fingerprint changedIds focus identity.semanticKey identity.debugPath content
      match ← extensions.renderBlock? identity.reactKey attributes extension children with
      | some rendered => pure rendered
      | none =>
          let markerStyle := styles.inlineCode
          let markerProps ← js%{ "style" := markerStyle }
          let marker ← <code @props={markerProps}>{Lean.Vir.React.Node.text (← JsValue.ofString s!"[block extension: {extension.name}]")}</code>
          let props ← attributes "unsupported-extension" (styles.unsupported)
          Js.Object.set props (← js#"data-verso-extension") (← JsValue.ofString extension.name.toString)
          let childNodes ← children ()
          return ← <div @props={props}>{pure marker}{Js.Array.ofArray childNodes}</div>

where
  renderListItem (styles : Styles) (extensions : Extensions) (fingerprint : Fingerprint.Value → String)
      (changedIds : Array String)
      (focus : Option String)
      (parentSemanticKey key path : String)
      (item : Lean.Doc.ListItem (_root_.Verso.Doc.Block Genre.Manual)) :
      ReactM (Lean.Vir.Js Node) := do
    let .mk content := item
    let props ← listItemProps key path "list-item" (styles.listItem) (focus == some path)
    let children ← renderBlocks styles extensions fingerprint changedIds focus s!"{parentSemanticKey}/{key}" path content
    return ← <li @props={props}>{Js.Array.ofArray children}</li>

  renderDescItem (styles : Styles) (extensions : Extensions) (fingerprint : Fingerprint.Value → String)
      (changedIds : Array String)
      (focus : Option String)
      (parentSemanticKey key path : String)
      (item : Lean.Doc.DescItem
        (_root_.Verso.Doc.Inline Genre.Manual) (_root_.Verso.Doc.Block Genre.Manual)) :
      ReactM (Array (Lean.Vir.Js Node)) := do
    let .mk term description := item
    let termProps ← listItemProps s!"{key}:term" s!"{path}-term" "description-term" (styles.descriptionTerm) (focus == some path)
    let termChildren ← renderInlines styles extensions term
    let termNode ← <dt @props={termProps}>{Js.Array.ofArray termChildren}</dt>
    let descriptionProps ← listItemProps s!"{key}:description" s!"{path}-description" "description-value" (styles.descriptionValue) (focus == some path)
    let descriptionChildren ← renderBlocks styles extensions fingerprint changedIds focus s!"{parentSemanticKey}/{key}/description" s!"{path}-description" description
    let descriptionNode ← <dd @props={descriptionProps}>{Js.Array.ofArray descriptionChildren}</dd>
    pure #[termNode, descriptionNode]

  renderBlocks (styles : Styles) (extensions : Extensions) (fingerprint : Fingerprint.Value → String)
      (changedIds : Array String)
      (focus : Option String)
      (parentSemanticKey debugParent : String)
      (content : Array (_root_.Verso.Doc.Block Genre.Manual))
      (focusChildren : Bool := false) :
      ReactM (Array (Lean.Vir.Js Node)) := do
    let identities := blockIdentities extensions parentSemanticKey debugParent content fingerprint
    content.mapIdxM fun index block =>
      let identity := identities[index]!
      renderBlock styles extensions fingerprint changedIds
        (if focusChildren then some identity.debugPath else focus) identity block

private partial def renderPart (styles : Styles) (extensions : Extensions) (fingerprint : Fingerprint.Value → String)
    (changedIds : Array String)
    (focus : Option String)
    (identity : Identity)
    (level : Nat)
    (part : _root_.Verso.Doc.Part Genre.Manual) : ReactM (Lean.Vir.Js Node) := do
  let headingIdentity := headingIdentity identity
  let heading ← headingNode styles headingIdentity level
    (← renderInlines styles extensions part.title)
    (changedIds.contains headingIdentity.debugPath) (focus == some headingIdentity.debugPath)
  let identities := blockIdentities extensions identity.semanticKey identity.debugPath part.content fingerprint
  let content ← part.content.mapIdxM fun index block =>
    renderBlock styles extensions fingerprint changedIds focus identities[index]! block
  let partIdentities := partIdentities identity.semanticKey identity.debugPath part.subParts fingerprint
  let subParts ← part.subParts.mapIdxM fun index child =>
    renderPart styles extensions fingerprint changedIds focus partIdentities[index]! (level + 1) child
  let style := styles.part
  let props ← js%{ "style" := style }
  Js.Object.set props (← js#"key") (← JsValue.ofString identity.reactKey)
  Js.Object.set props (← js#"className") (← js#"vir-verso-part")
  Js.Object.set props (← js#"data-verso-part") (← JsValue.ofString identity.debugPath)
  Js.Object.set props (← js#"data-verso-render-id") (← JsValue.ofString identity.friendlyId)
  Js.Object.set props (← js#"data-verso-identity-origin") (← JsValue.ofString identity.origin.label)
  Js.Object.set props (← js#"title") (← JsValue.ofString s!"render path: {identity.debugPath}\nidentity: {identity.friendlyId} ({identity.origin.label})")
  return ← <section @props={props}>{pure heading}{Js.Array.ofArray content}{Js.Array.ofArray subParts}</section>

/-- Options computed by the stateful component before constructing the Verso VDOM. -/
structure Options where
  changedIds : Array String := #[]
  focus : Option String := none
  attributes : Option (Js Props) := none
  /-- State prepared for this document. Omit for stateless exact-content keys. -/
  identities? : Option Fingerprint.State := none

/-- Construct the native React subtree for a Verso Manual document. -/
def render (styles : Styles) (input : Doc.Part Genre.Manual) (options : Options := {})
    (extensions : Extensions := {}) : ReactM (Lean.Vir.Js Node) := do
  let fingerprint := options.identities?.map (fun state => state.key) |>.getD Fingerprint.canonicalKey
  let rootPart ← renderPart styles extensions fingerprint options.changedIds options.focus rootIdentity 1 input
  let props ← match options.attributes with
    | some attributes => pure attributes
    | none => do
      let style := styles.document
      js%{ "style" := style }
  Js.Object.set props (← js#"id") (← js#"vir-verso-document")
  Js.Object.set props (← js#"className") (← js#"vir-verso-document")
  Js.Object.set props (← js#"data-verso-changed-block-count") (← JsValue.ofString (toString options.changedIds.size))
  Js.Object.set props (← js#"data-verso-focus-block") (← JsValue.ofString (options.focus.getD ""))
  return ← <article @props={props}>{pure rootPart}</article>

#guard
  let explicit := ({
    explicitId? := some "author"
    versoId? := some "verso"
    fingerprint? := some "content"
  } : IdentityHints).resolve "block" 0 "part-root-block-0"
  let verso := ({
    versoId? := some "verso"
    fingerprint? := some "content"
  } : IdentityHints).resolve "block" 0 "part-root-block-0"
  let fingerprint := ({ fingerprint? := some "content" } : IdentityHints).resolve
    "block" 0 "part-root-block-0"
  let positional := ({} : IdentityHints).resolve "block" 0 "part-root-block-0"
  explicit.origin == .explicit && explicit.reactKey == "explicit:author" &&
  verso.origin == .verso && verso.reactKey == "verso:verso" &&
  fingerprint.origin == .fingerprint && positional.origin == .positional

#guard
  let duplicate := ({ fingerprint? := some "same" } : IdentityHints)
  let identities := allocateSiblingIdentities "root" "part-root" "block" "block"
    #[duplicate, duplicate]
  identities[0]!.reactKey != identities[1]!.reactKey &&
  identities[0]!.friendlyId != identities[1]!.friendlyId

#guard
  let before := allocateSiblingIdentities "same-parent" "part-root-block-0" "block" "block" #[{}, {}]
  let moved := allocateSiblingIdentities "same-parent" "part-root-block-1" "block" "block" #[{}, {}]
  before[0]!.reactKey == moved[0]!.reactKey &&
  before[0]!.semanticKey == moved[0]!.semanticKey &&
  before[0]!.debugPath != moved[0]!.debugPath &&
  before[0]!.reactKey != before[1]!.reactKey

end VersoReact.Renderer
