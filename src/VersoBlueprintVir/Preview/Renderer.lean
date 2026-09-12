/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoReact
public import VersoBlueprint.Informal.Block.Model
public import VersoBlueprint.Informal.Code.Data
public import VersoBlueprint.Informal.ExternalMarkupView
public import VersoBlueprint.Math.Data
public import VersoBlueprintVir.Preview.Model

public section

namespace VersoBlueprint.Experimental.VirPreview.Renderer

open Lean.Vir Lean.Vir.React
open _root_.Verso

namespace Style

open VersoReact.Renderer.Style

private def style := Props.stylePairs
private def border (color : String) := "1px solid " ++ color

def informalBlock : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "0"),
  ("overflow", "hidden"),
  ("border", border borderColor),
  ("borderRadius", "6px"),
  ("background", background)
]

def informalHeader : Props.Entry := style #[
  ("display", "flex"),
  ("alignItems", "baseline"),
  ("gap", "8px"),
  ("padding", "7px 10px"),
  ("borderBottom", border borderColor),
  ("background", codeBackground)
]

def informalKind : Props.Entry := style #[
  ("fontWeight", "700")
]

def informalLabel : Props.Entry := style #[
  ("color", muted),
  ("fontFamily", "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"),
  ("fontSize", "0.78rem")
]

def informalBody : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "8px"),
  ("padding", "9px 10px")
]

def externalMarkup : Props.Entry := style #[
  ("overflow", "hidden"),
  ("border", border borderColor),
  ("borderRadius", "6px"),
  ("background", background)
]

def externalMarkupSummary : Props.Entry := style #[
  ("margin", "0"),
  ("padding", "7px 10px"),
  ("background", codeBackground),
  ("fontWeight", "600")
]

def externalMarkupSource : Props.Entry := style #[
  ("margin", "0"),
  ("padding", "9px 10px"),
  ("overflow", "auto"),
  ("borderTop", border borderColor),
  ("fontFamily", "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"),
  ("fontSize", "0.78rem"),
  ("lineHeight", "1.45"),
  ("whiteSpace", "pre")
]

end Style

private def decodeExtension? [Lean.FromJson α] (data : Lean.Json) : Option α :=
  match Lean.fromJson? data with
  | .ok value => some value
  | .error _ => none

private def isBlueprintMath (extension : Genre.Manual.Inline) : Bool :=
  extension.name == `Informal.Math.Inline.bpMath

private def isInformalBlock (extension : Genre.Manual.Block) : Bool :=
  extension.name == `Informal.Block.informal

private def isExternalMarkupBlock (extension : Genre.Manual.Block) : Bool :=
  extension.name == `Informal.Block.externalMarkup

private def blockIdentity? (extension : Genre.Manual.Block) : Option String :=
  if isInformalBlock extension then
    (decodeExtension? extension.data).map fun (data : Informal.BlockOccurrence) =>
      s!"informal:{data.label}"
  else if isExternalMarkupBlock extension then
    (decodeExtension? extension.data).map fun (data : Informal.ExternalMarkupBlockData) =>
      s!"external-markup:{data.label}:{data.markup.language.key}:{data.markup.slot}"
  else none

private def renderInline? (path : String) (extension : Genre.Manual.Inline) :
    ReactM (Option (Js Node)) := do
  if !isBlueprintMath extension then return none
  let node ← match decodeExtension? extension.data with
    | some (data : Informal.Math.BpMathData) => do
        let mode := if data.mode == .inline then "inline" else "display"
        let attributes := #[Props.className s!"vir-verso-math bp_math {mode}"]
        let attributes := if data.texPrelude.isEmpty then attributes else
          attributes.push (Props.string "data-bp-tex-prelude" data.texPrelude)
        VersoReact.Renderer.renderMath path data.mode data.source attributes
    | none =>
        Node.codeText #[
          Props.key path,
          Props.className "vir-verso-extension-unsupported",
          Props.string "data-verso-extension" extension.name.toString,
          VersoReact.Renderer.Style.inlineCode
        ] s!"[malformed math extension: {extension.name}]"
  return some node

private def malformedBlock (message : String) (extension : Genre.Manual.Block)
    (attributes : String → Props.Entry → Array Props.Entry)
    (children : Unit → ReactM (Array (Js Node))) : ReactM (Js Node) := do
  let marker ← Node.codeText #[VersoReact.Renderer.Style.inlineCode] message
  Node.divWith
    ((attributes "unsupported-extension" VersoReact.Renderer.Style.unsupported).push
      (Props.string "data-verso-extension" extension.name.toString))
    (#[marker] ++ (← children ()))

private def renderBlock? (key : String)
    (attributes : String → Props.Entry → Array Props.Entry)
    (extension : Genre.Manual.Block)
    (children : Unit → ReactM (Array (Js Node))) : ReactM (Option (Js Node)) := do
  if isInformalBlock extension then
    let node ← match decodeExtension? extension.data with
      | some (data : Informal.BlockOccurrence) => do
          -- Occurrences carry the facet, not the canonical node's mathematical
          -- kind. A Part-only preview must not invent a theorem/lemma title.
          let kindLabel := if data.isProof then "Proof" else "Statement"
          let kind ← Node.strongWith #[Style.informalKind] #[← Node.text (← JsValue.ofString kindLabel)]
          let label ← Node.codeText #[Style.informalLabel] data.label.toString
          let header ← Node.elementWith "header" #[Style.informalHeader] #[kind, label]
          let body ← Node.divWith #[Style.informalBody] (← children ())
          Node.elementWith "article"
            (attributes "informal" Style.informalBlock ++ #[
              Props.string "data-verso-informal-kind" kindLabel,
              Props.string "data-verso-informal-label" data.label.toString,
              Props.string "data-verso-extension" extension.name.toString
            ]) #[header, body]
      | none =>
          malformedBlock s!"[malformed informal block: {extension.name}]"
            extension attributes children
    return some node
  else if isExternalMarkupBlock extension then
    let node ← match decodeExtension? extension.data with
      | some (data : Informal.ExternalMarkupBlockData) => do
          let markup := data.markup
          let summary := Informal.ExternalMarkupView.displaySummary markup
          let extensionProps (display : String) (style : Props.Entry) :=
            attributes "external-markup" style ++ #[
              Props.string "data-verso-extension" extension.name.toString,
              Props.string "data-verso-external-markup-label" data.label.toString,
              Props.string "data-verso-external-markup-language" markup.language.key,
              Props.string "data-verso-external-markup-slot" markup.slot,
              Props.string "data-verso-external-markup-display" display
            ]
          match data.display with
          | .hidden => Node.fragment (← Props.fromEntries #[Props.key key]) (← Js.Array.empty)
          | .summary =>
              Node.pWith (extensionProps "summary" Style.externalMarkupSummary)
                #[← Node.text (← JsValue.ofString summary)]
          | .source =>
              let summaryNode ← Node.elementWith "summary" #[Style.externalMarkupSummary]
                #[← Node.text (← JsValue.ofString summary)]
              let source ← Node.codeText
                #[Props.className s!"language-{markup.language.key}"] markup.raw
              let sourceNode ← Node.preWith #[Style.externalMarkupSource] #[source]
              Node.elementWith "details" (extensionProps "source" Style.externalMarkup)
                #[summaryNode, sourceNode]
      | none =>
          malformedBlock s!"[malformed external markup block: {extension.name}]"
            extension attributes children
    return some node
  else return none

/-- Blueprint extension semantics; the independent package knows none of these names. -/
def extensions : VersoReact.Renderer.Extensions := {
  renderInline?, renderBlock?, blockIdentity?
}

/-- Session metadata belongs to VBP, not the reusable Part-to-React renderer. -/
def render (input : Document) (options : VersoReact.Renderer.Options := {}) :
    ReactM (Js Node) :=
  VersoReact.Renderer.render input.document
    { options with attributes := options.attributes ++ #[
        Props.string "data-verso-version" (toString input.version),
        Props.string "data-verso-correlation-id" input.correlationId,
        Props.string "data-verso-cursor-token" input.cursorToken
      ] } extensions

def changedBlockIdsAndCount (previous : Option Document) (current : Document) :
    Array String × Nat :=
  VersoReact.Renderer.changedBlockIdsAndCount (previous.map (·.document))
    current.document extensions

def renderBlockIds (document : Document) : Array String :=
  VersoReact.Renderer.renderBlockIds document.document extensions

def changedBlockIds (previous current : Document) : Array String :=
  VersoReact.Renderer.changedBlockIds previous.document current.document extensions

end VersoBlueprint.Experimental.VirPreview.Renderer
