/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Vir.React
public import VersoManual.Basic
public import VersoReact.RenderPath
public meta import VersoReact.RenderPath

public section

namespace VersoReact.Renderer

open Lean.Vir
open Lean.Vir.React
open Lean.Doc.Syntax
open _root_.Verso

namespace Style

private def style (entries : Array (String × String)) : Props.Entry :=
  Props.stylePairs entries

private def vscodeColor (name fallback : String) : String :=
  "var(--vscode-" ++ name ++ ", " ++ fallback ++ ")"

private def border (color : String) : String :=
  "1px solid " ++ color

def foreground : String := vscodeColor "editor-foreground" "#24292f"
def muted : String := vscodeColor "descriptionForeground" "#57606a"
def background : String := vscodeColor "editor-background" "#ffffff"
def codeBackground : String := vscodeColor "textCodeBlock-background" "#f6f8fa"
def borderColor : String := vscodeColor "panel-border" "#d0d7de"

def document : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "10px"),
  ("minWidth", "0"),
  ("padding", "10px 12px"),
  ("border", border borderColor),
  ("borderRadius", "6px"),
  ("background", background),
  ("color", foreground),
  ("colorScheme", "light dark"),
  ("fontFamily", "Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"),
  ("overflowWrap", "anywhere")
]

def part : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "10px"),
  ("minWidth", "0")
]

def heading : Props.Entry := style #[
  ("margin", "0"),
  ("fontSize", "1.12rem"),
  ("lineHeight", "1.3")
]

def paragraph : Props.Entry := style #[
  ("margin", "0"),
  ("lineHeight", "1.5")
]

def list : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "6px"),
  ("margin", "0"),
  ("paddingLeft", "1.5rem")
]

def listItem : Props.Entry := style #[
  ("paddingLeft", "0.15rem")
]

def blockquote : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "8px"),
  ("margin", "0"),
  ("padding", "2px 0 2px 12px"),
  ("borderLeft", border borderColor),
  ("color", muted)
]

def descriptionList : Props.Entry := style #[
  ("display", "grid"),
  ("gridTemplateColumns", "max-content minmax(0, 1fr)"),
  ("gap", "6px 10px"),
  ("margin", "0")
]

def descriptionTerm : Props.Entry := style #[
  ("fontWeight", "700")
]

def descriptionValue : Props.Entry := style #[
  ("margin", "0")
]

def inlineCode : Props.Entry := style #[
  ("padding", "0.08em 0.3em"),
  ("borderRadius", "3px"),
  ("background", codeBackground),
  ("fontFamily", "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"),
  ("fontSize", "0.92em")
]

def codeBlock : Props.Entry := style #[
  ("margin", "0"),
  ("padding", "9px 10px"),
  ("overflow", "auto"),
  ("borderRadius", "5px"),
  ("background", codeBackground),
  ("fontFamily", "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"),
  ("fontSize", "0.78rem"),
  ("lineHeight", "1.45"),
  ("whiteSpace", "pre")
]

def mathInline : Props.Entry := style #[
  ("padding", "0 0.08em"),
  ("fontFamily", "KaTeX_Main, Cambria Math, STIX Two Math, serif"),
  ("fontSize", "1.02em"),
  ("whiteSpace", "pre-wrap")
]

def mathDisplay : Props.Entry := style #[
  ("display", "block"),
  ("padding", "8px 10px"),
  ("overflowX", "auto"),
  ("borderRadius", "5px"),
  ("background", codeBackground),
  ("fontFamily", "KaTeX_Main, Cambria Math, STIX Two Math, serif"),
  ("fontSize", "1.02em"),
  ("lineHeight", "1.5"),
  ("textAlign", "center"),
  ("whiteSpace", "pre-wrap")
]

def unsupported : Props.Entry := style #[
  ("padding", "7px 9px"),
  ("border", border borderColor),
  ("borderRadius", "5px"),
  ("color", muted)
]

end Style

/--
Application-owned Manual extensions. Unhandled extensions remain visible together
with their children. The callbacks construct ordinary React nodes, not components
or hook scopes. Children are lazy so hidden extensions need not render them.
-/
structure Extensions where
  /-- Replace an inline extension (including its contents), or retain the visible fallback. -/
  renderInline? : (path : String) → Genre.Manual.Inline → ReactM (Option (Js Node)) :=
    fun _ _ => pure none
  /--
  Replace a block extension, or return `none` for the visible fallback.
  `attributes kind style` supplies the existing key, identity, focus and change
  markers. Call `children ()` once when needed; hidden blocks can skip it.
  -/
  renderBlock? : (key : String) → (attributes : String → Props.Entry → Array Props.Entry) →
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
    (kind debugPath : String) (hints : IdentityHints) : IdentityBase :=
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
      { reactKey := s!"position:{debugPath}", friendlyId := debugPath, origin := .positional }

private def allocateSiblingIdentities
    (parentSemanticKey debugParent segment kind : String)
    (hints : Array IdentityHints) : Array Identity := Id.run do
  let mut seen : Std.HashMap String Nat := {}
  let mut identities := #[]
  for index in [:hints.size] do
    let debugPath := RenderPath.child debugParent segment index
    let base := hints[index]!.resolve kind debugPath
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

private partial def blockIdentityHints (extensions : Extensions)
    (block : _root_.Verso.Doc.Block Genre.Manual) : IdentityHints :=
  match block with
  | .concat content =>
      if content.size == 1 then
        blockIdentityHints extensions content[0]!
      else
        { fingerprint? := some (Lean.toJson block).compress }
  | .other extension _ =>
      match extensions.blockIdentity? extension with
      | some identity => { explicitId? := some identity }
      | none => { fingerprint? := some (Lean.toJson block).compress }
  | _ => { fingerprint? := some (Lean.toJson block).compress }

private def partIdentityHints
    (part : _root_.Verso.Doc.Part Genre.Manual) : IdentityHints :=
  -- A section title identifies the section without coupling its key to body edits.
  { fingerprint? := some (Lean.toJson part.title).compress }

private def blockIdentities (extensions : Extensions)
    (parentSemanticKey debugParent : String)
    (blocks : Array (_root_.Verso.Doc.Block Genre.Manual)) : Array Identity :=
  allocateSiblingIdentities parentSemanticKey debugParent "block" "block"
    (blocks.map (blockIdentityHints extensions))

private def partIdentities
    (parentSemanticKey debugParent : String)
    (parts : Array (_root_.Verso.Doc.Part Genre.Manual)) : Array Identity :=
  allocateSiblingIdentities parentSemanticKey debugParent "part" "part"
    (parts.map partIdentityHints)

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
    (style : Props.Entry)
    (changed focused : Bool) : Array Props.Entry := Id.run do
  let mut classes := #["vir-verso-block"]
  if changed then
    classes := classes.push "vir-verso-block-changed"
  if focused then
    classes := classes.push "vir-verso-block-focused"
  let mut props := #[
    Props.key identity.reactKey,
    Props.string "data-verso-block" identity.debugPath,
    Props.string "data-verso-render-id" identity.friendlyId,
    Props.string "data-verso-identity-origin" identity.origin.label,
    Props.string "data-verso-kind" kind,
    Props.title s!"render path: {identity.debugPath}\nidentity: {identity.friendlyId} ({identity.origin.label})",
    Props.classList classes
  ]
  if changed then
    props := props.push (Props.string "data-verso-change" "changed")
  if focused then
    props := props.push (Props.string "data-verso-focus" "cursor")
  return props.push style

private def listItemProps
    (path kind : String)
    (style : Props.Entry)
    (focused : Bool) : Array Props.Entry := Id.run do
  let classes :=
    if focused then #["vir-verso-list-item", "vir-verso-block-focused"]
    else #["vir-verso-list-item"]
  let mut props := #[
    Props.key path,
    Props.string "data-verso-list-item" path,
    Props.string "data-verso-kind" kind,
    Props.title s!"source list item: {path}",
    Props.classList classes,
    style
  ]
  if focused then
    props := props.push (Props.string "data-verso-focus" "cursor")
  return props

/-- Source-preserving math node; callers may add attributes for their typesetter. -/
def renderMath
    (path : String)
    (mode : Lean.Doc.MathMode)
    (source : String)
    (attributes : Array Props.Entry := #[]) : ReactM (Lean.Vir.Js Node) := do
  let modeClass := match mode with
    | Lean.Doc.MathMode.inline => "inline"
    | Lean.Doc.MathMode.display => "display"
  let style := match mode with
    | Lean.Doc.MathMode.inline => Style.mathInline
    | Lean.Doc.MathMode.display => Style.mathDisplay
  let props := #[
    Props.key path,
    Props.className s!"vir-verso-math {modeClass}",
    Props.string "data-verso-math-mode" modeClass,
    style
  ]
  Node.codeText (props ++ attributes) source

private partial def renderInline (extensions : Extensions)
    (path : String) : _root_.Verso.Doc.Inline Genre.Manual → ReactM (Lean.Vir.Js Node)
  | .text value | .linebreak value => do Node.text (← JsValue.ofString value)
  | .code value => Node.codeText #[Props.key path, Style.inlineCode] value
  | .math mode value => renderMath path mode value
  | .emph content => do
      Node.emWith #[Props.key path] (← renderInlines extensions path content)
  | .bold content => do
      Node.strongWith #[Props.key path] (← renderInlines extensions path content)
  | .link content destination => do
      Node.aWith #[Props.key path, Props.href destination] (← renderInlines extensions path content)
  | .footnote name content => do
      let label ← Node.text (← JsValue.ofString s!"[{name}]")
      let summary ← Node.elementWith "summary" #[Props.key s!"{path}-summary"] #[label]
      Node.elementWith "details" #[Props.key path, Props.className "vir-verso-footnote"]
        (#[summary] ++ (← renderInlines extensions path content))
  | .image alt destination =>
      Node.img #[Props.key path, Props.src destination, Props.alt alt]
  | .concat content => do
      Node.fragment (← Props.fromEntries #[Props.key path])
        (← Js.Array.ofArray (← renderInlines extensions path content))
  | .other extension content => do
      match ← extensions.renderInline? path extension with
      | some rendered => pure rendered
      | none =>
          let marker ← Node.codeText #[
            Props.key s!"{path}-extension",
            Props.className "vir-verso-extension-unsupported",
            Props.string "data-verso-extension" extension.name.toString,
            Style.inlineCode
          ] s!"[inline extension: {extension.name}]"
          Node.fragment (← Props.fromEntries #[Props.key path])
            (← Js.Array.ofArray (#[marker] ++ (← renderInlines extensions path content)))

where
  renderInlines (extensions : Extensions)
      (path : String)
      (content : Array (_root_.Verso.Doc.Inline Genre.Manual)) : ReactM (Array (Lean.Vir.Js Node)) :=
    content.mapIdxM fun index inline => renderInline extensions s!"{path}-inline-{index}" inline

private partial def renderInlines (extensions : Extensions)
    (path : String)
    (content : Array (_root_.Verso.Doc.Inline Genre.Manual)) : ReactM (Array (Lean.Vir.Js Node)) :=
  content.mapIdxM fun index inline => renderInline extensions s!"{path}-inline-{index}" inline

private def headingNode
    (identity : Identity)
    (level : Nat)
    (content : Array (Lean.Vir.Js Node))
    (changed focused : Bool) : ReactM (Lean.Vir.Js Node) :=
  let props := blockProps identity "heading" Style.heading changed focused
  match level with
  | 1 => Node.h1With props content
  | 2 => Node.h2With props content
  | 3 => Node.h3With props content
  | 4 => Node.h4With props content
  | 5 => Node.h5With props content
  | _ => Node.h6With props content

private partial def renderBlock (extensions : Extensions)
    (changedIds : Array String)
    (focus : Option String)
    (identity : Identity) : _root_.Verso.Doc.Block Genre.Manual → ReactM (Lean.Vir.Js Node)
  | .para content => do
      Node.pWith
        (blockProps identity "paragraph" Style.paragraph
          (changedIds.contains identity.debugPath) (focus == some identity.debugPath))
        (← renderInlines extensions identity.debugPath content)
  | .code source => do
      let text ← Node.text (← JsValue.ofString source)
      let code ← Node.codeWith #[Props.string "data-language" ""] #[text]
      Node.preWith
        (blockProps identity "code" Style.codeBlock
          (changedIds.contains identity.debugPath) (focus == some identity.debugPath))
        #[code]
  | .ul items => do
      Node.ulWith
        (blockProps identity "unordered-list" Style.list
          (changedIds.contains identity.debugPath) (focus == some identity.debugPath))
        (← items.mapIdxM fun index item =>
          renderListItem extensions changedIds focus identity.semanticKey s!"{identity.debugPath}-item-{index}" item)
  | .ol start items => do
      Node.olWith
        ((blockProps identity "ordered-list" Style.list
          (changedIds.contains identity.debugPath) (focus == some identity.debugPath)).push
            (Props.string "start" (toString (max start 0))))
        (← items.mapIdxM fun index item =>
          renderListItem extensions changedIds focus identity.semanticKey s!"{identity.debugPath}-item-{index}" item)
  | .dl items => do
      let children ← items.mapIdxM fun index item =>
        renderDescItem extensions changedIds focus identity.semanticKey s!"{identity.debugPath}-item-{index}" item
      Node.dlWith
        (blockProps identity "description-list" Style.descriptionList
          (changedIds.contains identity.debugPath) (focus == some identity.debugPath))
        children.flatten
  | .blockquote content => do
      Node.elementWith "blockquote"
        (blockProps identity "blockquote" Style.blockquote
          (changedIds.contains identity.debugPath) (focus == some identity.debugPath))
        (← renderBlocks extensions changedIds focus identity.semanticKey identity.debugPath content)
  | .concat content => do
      -- Concatenations are React fragments, not DOM nodes. A source block may
      -- expand to several children; mark those children without adding a wrapper.
      Node.fragment (← Props.fromEntries #[Props.key identity.reactKey])
        (← Js.Array.ofArray
          (← renderBlocks extensions changedIds focus identity.semanticKey identity.debugPath content
            (focusChildren := focus == some identity.debugPath)))
  | .other extension content => do
      let changed := changedIds.contains identity.debugPath
      let focused := focus == some identity.debugPath
      let attributes := fun kind style => blockProps identity kind style changed focused
      let children := fun _ : Unit =>
        renderBlocks extensions changedIds focus identity.semanticKey identity.debugPath content
      match ← extensions.renderBlock? identity.reactKey attributes extension children with
      | some rendered => pure rendered
      | none =>
          let marker ← Node.codeText #[Style.inlineCode]
            s!"[block extension: {extension.name}]"
          Node.divWith
            ((attributes "unsupported-extension" Style.unsupported).push
              (Props.string "data-verso-extension" extension.name.toString))
            (#[marker] ++ (← children ()))

where
  renderListItem (extensions : Extensions)
      (changedIds : Array String)
      (focus : Option String)
      (parentSemanticKey path : String)
      (item : Lean.Doc.ListItem (_root_.Verso.Doc.Block Genre.Manual)) :
      ReactM (Lean.Vir.Js Node) := do
    let .mk content := item
    Node.liWith (listItemProps path "list-item" Style.listItem (focus == some path))
      (← renderBlocks extensions changedIds focus s!"{parentSemanticKey}/item/{path}" path content)

  renderDescItem (extensions : Extensions)
      (changedIds : Array String)
      (focus : Option String)
      (parentSemanticKey path : String)
      (item : Lean.Doc.DescItem
        (_root_.Verso.Doc.Inline Genre.Manual) (_root_.Verso.Doc.Block Genre.Manual)) :
      ReactM (Array (Lean.Vir.Js Node)) := do
    let .mk term description := item
    let termNode ← Node.dtWith
      (listItemProps s!"{path}-term" "description-term" Style.descriptionTerm
        (focus == some path))
      (← renderInlines extensions s!"{path}-term" term)
    let descriptionNode ← Node.ddWith
      (listItemProps s!"{path}-description" "description-value" Style.descriptionValue
        (focus == some path))
      (← renderBlocks extensions changedIds focus s!"{parentSemanticKey}/item/{path}/description"
        s!"{path}-description" description)
    pure #[termNode, descriptionNode]

  renderBlocks (extensions : Extensions)
      (changedIds : Array String)
      (focus : Option String)
      (parentSemanticKey debugParent : String)
      (content : Array (_root_.Verso.Doc.Block Genre.Manual))
      (focusChildren : Bool := false) :
      ReactM (Array (Lean.Vir.Js Node)) := do
    let identities := blockIdentities extensions parentSemanticKey debugParent content
    content.mapIdxM fun index block =>
      let identity := identities[index]!
      renderBlock extensions changedIds
        (if focusChildren then some identity.debugPath else focus) identity block

private partial def renderPart (extensions : Extensions)
    (changedIds : Array String)
    (focus : Option String)
    (identity : Identity)
    (level : Nat)
    (part : _root_.Verso.Doc.Part Genre.Manual) : ReactM (Lean.Vir.Js Node) := do
  let headingIdentity := headingIdentity identity
  let heading ← headingNode headingIdentity level
    (← renderInlines extensions headingIdentity.debugPath part.title)
    (changedIds.contains headingIdentity.debugPath) (focus == some headingIdentity.debugPath)
  let identities := blockIdentities extensions identity.semanticKey identity.debugPath part.content
  let content ← part.content.mapIdxM fun index block =>
    renderBlock extensions changedIds focus identities[index]! block
  let partIdentities := partIdentities identity.semanticKey identity.debugPath part.subParts
  let subParts ← part.subParts.mapIdxM fun index child =>
    renderPart extensions changedIds focus partIdentities[index]! (level + 1) child
  Node.sectionWith #[
    Props.key identity.reactKey,
    Props.className "vir-verso-part",
    Props.string "data-verso-part" identity.debugPath,
    Props.string "data-verso-render-id" identity.friendlyId,
    Props.string "data-verso-identity-origin" identity.origin.label,
    Props.title s!"render path: {identity.debugPath}\nidentity: {identity.friendlyId} ({identity.origin.label})",
    Style.part
  ] (#[heading] ++ content ++ subParts)

/-- Options computed by the stateful component before constructing the Verso VDOM. -/
structure Options where
  changedIds : Array String := #[]
  focus : Option String := none
  attributes : Array Props.Entry := #[]

/-- Construct the native React subtree for a Verso Manual document. -/
def render (input : Doc.Part Genre.Manual) (options : Options := {})
    (extensions : Extensions := {}) : ReactM (Lean.Vir.Js Node) := do
  let rootPart ← renderPart extensions options.changedIds options.focus rootIdentity 1 input
  Node.articleWith (#[
    Props.id "vir-verso-document",
    Props.className "vir-verso-document",
    Props.string "data-verso-changed-block-count" (toString options.changedIds.size),
    Props.string "data-verso-focus-block" (options.focus.getD ""),
    Style.document
  ] ++ options.attributes) #[rootPart]

#guard
  let explicit := ({
    explicitId? := some "author"
    versoId? := some "verso"
    fingerprint? := some "content"
  } : IdentityHints).resolve "block" "part-root-block-0"
  let verso := ({
    versoId? := some "verso"
    fingerprint? := some "content"
  } : IdentityHints).resolve "block" "part-root-block-0"
  let fingerprint := ({ fingerprint? := some "content" } : IdentityHints).resolve
    "block" "part-root-block-0"
  let positional := ({} : IdentityHints).resolve "block" "part-root-block-0"
  explicit.origin == .explicit && explicit.reactKey == "explicit:author" &&
  verso.origin == .verso && verso.reactKey == "verso:verso" &&
  fingerprint.origin == .fingerprint && positional.origin == .positional

#guard
  let duplicate := ({ fingerprint? := some "same" } : IdentityHints)
  let identities := allocateSiblingIdentities "root" "part-root" "block" "block"
    #[duplicate, duplicate]
  identities[0]!.reactKey != identities[1]!.reactKey &&
  identities[0]!.friendlyId != identities[1]!.friendlyId

end VersoReact.Renderer
