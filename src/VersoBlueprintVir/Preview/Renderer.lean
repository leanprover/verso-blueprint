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
public import VersoBlueprintVir.Preview.JsStrings

public section

namespace VersoBlueprint.Experimental.VirPreview.Renderer

open Lean.Vir Lean.Vir.React
open _root_.Verso
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

namespace Style

open VersoReact.Renderer.Style

private def border (color : String) := "1px solid " ++ color

def informalBlock : ReactM (Js Props) := js%{ "display" := (← js#"grid"), "gap" := (← js#"0"), "overflow" := (← js#"hidden"), "border" := (← JsValue.ofString (border borderColor)), "borderRadius" := (← js#"6px"), "background" := (← JsValue.ofString background) }
def informalHeader : ReactM (Js Props) := js%{ "display" := (← js#"flex"), "alignItems" := (← js#"baseline"), "gap" := (← js#"8px"), "padding" := (← js#"7px 10px"), "borderBottom" := (← JsValue.ofString (border borderColor)), "background" := (← JsValue.ofString codeBackground) }
def informalKind : ReactM (Js Props) := js%{ "fontWeight" := (← js#"700") }
def informalLabel : ReactM (Js Props) := js%{ "color" := (← JsValue.ofString muted), "fontFamily" := (← js#"ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"), "fontSize" := (← js#"0.78rem") }
def informalBody : ReactM (Js Props) := js%{ "display" := (← js#"grid"), "gap" := (← js#"8px"), "padding" := (← js#"9px 10px") }
def externalMarkup : ReactM (Js Props) := js%{ "overflow" := (← js#"hidden"), "border" := (← JsValue.ofString (border borderColor)), "borderRadius" := (← js#"6px"), "background" := (← JsValue.ofString background) }
def externalMarkupSummary : ReactM (Js Props) := js%{ "margin" := (← js#"0"), "padding" := (← js#"7px 10px"), "background" := (← JsValue.ofString codeBackground), "fontWeight" := (← js#"600") }
def externalMarkupSource : ReactM (Js Props) := js%{ "margin" := (← js#"0"), "padding" := (← js#"9px 10px"), "overflow" := (← js#"auto"), "borderTop" := (← JsValue.ofString (border borderColor)), "fontFamily" := (← js#"ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"), "fontSize" := (← js#"0.78rem"), "lineHeight" := (← js#"1.45"), "whiteSpace" := (← js#"pre") }

end Style

/-- Component-owned read-only styles for Blueprint presentation. -/
structure Styles where
  verso : VersoReact.Renderer.Styles
  strings : JsStrings.Fixed
  texPrelude : RuntimeRef (Option (String × Js String))
  informalBlock : Js Props
  informalHeader : Js Props
  informalKind : Js Props
  informalLabel : Js Props
  informalBody : Js Props
  externalMarkup : Js Props
  externalMarkupSummary : Js Props
  externalMarkupSource : Js Props

def Styles.create : ReactM Styles := do
  return {
    verso := ← VersoReact.Renderer.Styles.create
    strings := ← JsStrings.Fixed.create
    texPrelude := ← RuntimeRef.new none
    informalBlock := ← Style.informalBlock, informalHeader := ← Style.informalHeader
    informalKind := ← Style.informalKind, informalLabel := ← Style.informalLabel
    informalBody := ← Style.informalBody, externalMarkup := ← Style.externalMarkup
    externalMarkupSummary := ← Style.externalMarkupSummary
    externalMarkupSource := ← Style.externalMarkupSource
  }

private def Styles.cachedTexPrelude (styles : Styles) (prelude : String) : ReactM (Js String) := do
  match ← styles.texPrelude.get with
  | some (prior, value) =>
      if prior == prelude then return value
  | none => pure ()
  let value ← JsValue.ofString prelude
  styles.texPrelude.set (some (prelude, value))
  pure value

private def Styles.styleProps (styles : Styles) (style : Js Props) : ReactM (Js Props) := do
  let props ← Js.Object.empty
  Js.Object.set props styles.verso.strings.keys.style style
  pure props

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

/- These are deliberately renderer views, not copies of the source models.  In
particular labels remain strings: decoding a `Data.Label` would parse a Lean
name even though this preview only displays and keys its serialized spelling. -/
private structure InformalBlockView where
  label : String
  isProof : Bool := false
deriving Lean.FromJson

private structure ExternalMarkupBlockView where
  label : String
  markup : Informal.Data.ExternalMarkup
  display : Informal.ExternalMarkupDisplayMode := .hidden
deriving Lean.FromJson

private def blockIdentity? (extension : Genre.Manual.Block) : Option String :=
  if isInformalBlock extension then
    (decodeExtension? extension.data).map fun (data : InformalBlockView) =>
      s!"informal:{data.label}"
  else if isExternalMarkupBlock extension then
    (decodeExtension? extension.data).map fun (data : ExternalMarkupBlockView) =>
      s!"external-markup:{data.label}:{data.markup.language.key}:{data.markup.slot}"
  else none

private def renderInline? (styles : Styles) (component? : Option (FunctionComponent Props))
    (key : String) (extension : Genre.Manual.Inline) :
    ReactM (Option (Js Node)) := do
  if !isBlueprintMath extension then return none
  let node ← match decodeExtension? extension.data with
    | some (data : Informal.Math.BpMathData) => do
        let className := if data.mode == .inline then
          styles.strings.values.blueprintMathInlineClass
        else styles.strings.values.blueprintMathDisplayClass
        let attributes ← Js.Object.empty
        Js.Object.set attributes styles.verso.strings.keys.className className
        if !data.texPrelude.isEmpty then
          Js.Object.set attributes styles.strings.keys.dataBpTexPrelude
            (← styles.cachedTexPrelude data.texPrelude)
        VersoReact.Renderer.renderMath styles.verso key data.mode data.source (some attributes) component?
    | none => do
        let style := styles.verso.inlineCode
        let props ← styles.styleProps style
        Js.Object.set props styles.verso.strings.keys.key (← JsValue.ofString key)
        Js.Object.set props styles.verso.strings.keys.className
          styles.verso.strings.values.unsupportedExtensionClass
        Js.Object.set props styles.verso.strings.keys.dataVersoExtension
          (← JsValue.ofString extension.name.toString)
        return ← <code @props={props}>{Node.text (← JsValue.ofString s!"[malformed math extension: {extension.name}]")}</code>
  return some node

private def malformedBlock (styles : Styles) (message : String) (extension : Genre.Manual.Block)
    (attributes : String → Js Props → ReactM (Js Props))
    (children : Unit → ReactM (Array (Js Node))) : ReactM (Js Node) := do
  let markerStyle := styles.verso.inlineCode
  let markerProps ← styles.styleProps markerStyle
  let marker ← <code @props={markerProps}>{Node.text (← JsValue.ofString message)}</code>
  let props ← attributes "unsupported-extension" (styles.verso.unsupported)
  Js.Object.set props styles.verso.strings.keys.dataVersoExtension
    (← JsValue.ofString extension.name.toString)
  let childNodes ← children ()
  return ← <div @props={props}>{pure marker}{Js.Array.ofArray childNodes}</div>

private def renderBlock? (styles : Styles) (key : String)
    (attributes : String → Js Props → ReactM (Js Props))
    (extension : Genre.Manual.Block)
    (children : Unit → ReactM (Array (Js Node))) : ReactM (Option (Js Node)) := do
  if isInformalBlock extension then
    let node ← match decodeExtension? extension.data with
      | some (data : InformalBlockView) => do
          -- Occurrences carry the facet, not the canonical node's mathematical
          -- kind. A Part-only preview must not invent a theorem/lemma title.
          let kindLabel := if data.isProof then "Proof" else "Statement"
          let kindStyle := styles.informalKind
          let kindProps ← styles.styleProps kindStyle
          let kind ← <strong @props={kindProps}>{Node.text (← JsValue.ofString kindLabel)}</strong>
          let labelStyle := styles.informalLabel
          let labelProps ← styles.styleProps labelStyle
          let label ← <code @props={labelProps}>{Node.text (← JsValue.ofString data.label)}</code>
          let headerStyle := styles.informalHeader
          let headerProps ← styles.styleProps headerStyle
          let header ← <header @props={headerProps}>{pure kind}{pure label}</header>
          let bodyStyle := styles.informalBody
          let bodyProps ← styles.styleProps bodyStyle
          let bodyChildren ← children ()
          let body ← <div @props={bodyProps}>{Js.Array.ofArray bodyChildren}</div>
          let props ← attributes "informal" (styles.informalBlock)
          Js.Object.set props styles.strings.keys.dataVersoInformalKind (← JsValue.ofString kindLabel)
          Js.Object.set props styles.strings.keys.dataVersoInformalLabel (← JsValue.ofString data.label)
          Js.Object.set props styles.verso.strings.keys.dataVersoExtension
            (← JsValue.ofString extension.name.toString)
          return ← <article @props={props}>{pure header}{pure body}</article>
      | none =>
          malformedBlock styles s!"[malformed informal block: {extension.name}]"
            extension attributes children
    return some node
  else if isExternalMarkupBlock extension then
    let node ← match decodeExtension? extension.data with
      | some (data : ExternalMarkupBlockView) => do
          let markup := data.markup
          let summary := Informal.ExternalMarkupView.displaySummary markup
          let extensionProps (display : Js String) (style : Js Props) : ReactM (Js Props) := do
            let props ← attributes "external-markup" style
            Js.Object.set props styles.verso.strings.keys.dataVersoExtension
              (← JsValue.ofString extension.name.toString)
            Js.Object.set props styles.strings.keys.dataVersoExternalMarkupLabel
              (← JsValue.ofString data.label)
            Js.Object.set props styles.strings.keys.dataVersoExternalMarkupLanguage
              (← JsValue.ofString markup.language.key)
            Js.Object.set props styles.strings.keys.dataVersoExternalMarkupSlot
              (← JsValue.ofString markup.slot)
            Js.Object.set props styles.strings.keys.dataVersoExternalMarkupDisplay
              display
            pure props
          match data.display with
          | .hidden =>
              let props ← Js.Object.empty
              Js.Object.set props styles.verso.strings.keys.key (← JsValue.ofString key)
              Node.fragment props (← Js.Array.empty)
          | .summary =>
              let props ← extensionProps styles.strings.values.summary (styles.externalMarkupSummary)
              return ← <p @props={props}>{Node.text (← JsValue.ofString summary)}</p>
          | .source =>
              let summaryStyle := styles.externalMarkupSummary
              let summaryProps ← styles.styleProps summaryStyle
              let summaryNode ← <summary @props={summaryProps}>{Node.text (← JsValue.ofString summary)}</summary>
              let sourceProps ← Js.Object.empty
              Js.Object.set sourceProps styles.verso.strings.keys.className
                (← JsValue.ofString s!"language-{markup.language.key}")
              let source ← <code @props={sourceProps}>{Node.text (← JsValue.ofString markup.raw)}</code>
              let sourceNodeStyle := styles.externalMarkupSource
              let sourceNodeProps ← styles.styleProps sourceNodeStyle
              let sourceNode ← <pre @props={sourceNodeProps}>{pure source}</pre>
              let props ← extensionProps styles.strings.values.source (styles.externalMarkup)
              return ← <details @props={props}>{pure summaryNode}{pure sourceNode}</details>
      | none =>
          malformedBlock styles s!"[malformed external markup block: {extension.name}]"
            extension attributes children
    return some node
  else return none

/-- Blueprint semantic identities. Rendering adds callbacks owning the component's styles. -/
def extensions : VersoReact.Renderer.Extensions := {
  blockIdentity?
}

/-- Session metadata belongs to VBP, not the reusable Part-to-React renderer. -/
def render (styles : Styles) (input : Document) (options : VersoReact.Renderer.Options := {})
    (mathComponent? : Option (FunctionComponent Props) := none) :
    ReactM (Js Node) := do
  let attributes ← match options.attributes with
    | some attributes => pure attributes
    | none => do
      let style := styles.verso.document
      styles.styleProps style
  Js.Object.set attributes styles.strings.keys.dataVersoVersion
    (← JsValue.ofString (toString input.version))
  Js.Object.set attributes styles.strings.keys.dataVersoCorrelationId
    (← JsValue.ofString input.correlationId)
  Js.Object.set attributes styles.strings.keys.dataVersoCursorToken
    (← JsValue.ofString input.cursorToken)
  VersoReact.Renderer.render styles.verso input.document { options with attributes := some attributes }
    { extensions with mathComponent?, renderInline? := renderInline? styles mathComponent?, renderBlock? := renderBlock? styles }

def changedBlockIdsAndCount (previous : Option Document) (current : Document) :
    Array String × Nat :=
  VersoReact.Renderer.changedBlockIdsAndCount (previous.map (·.document))
    current.document extensions

def renderBlockIds (document : Document) : Array String :=
  VersoReact.Renderer.renderBlockIds document.document extensions

def changedBlockIds (previous current : Document) : Array String :=
  VersoReact.Renderer.changedBlockIds previous.document current.document extensions

end VersoBlueprint.Experimental.VirPreview.Renderer
