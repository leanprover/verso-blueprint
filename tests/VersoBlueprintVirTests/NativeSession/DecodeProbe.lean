/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

-- Keep the production RPC/renderer import environment in this diagnostic package.
public import VersoBlueprintVir.Preview.Rpc
public import VersoBlueprintVirTests.NativeSession.UpstreamJson.Js
public import VersoReact.Json
public import VersoReactTests.Fingerprint
meta import Vir.Attributes

public section

namespace VersoBlueprintVirTests.NativeSession.DecodeProbe

open Lean.Vir VersoBlueprint.Experimental.VirPreview
open Lean.Vir.React
open scoped Lean.Vir.Js
open scoped Lean.Vir.ProofWidgets.Jsx

@[vir_export]
def checkFingerprint : Bool :=
  VersoReactTests.Fingerprint.collisionChecks && VersoReactTests.Fingerprint.structuralChecks

private def identityParagraph (text : String) : Verso.Doc.Block Verso.Genre.Manual :=
  .para #[.text text]

private def identityDisclosure (label : String) (explicit : Bool := true)
    (text : String := "body") : Verso.Doc.Block Verso.Genre.Manual :=
  .other {
    name := if explicit then `Identity.labeled else `Identity.anonymous
    data := .str label
  } #[identityParagraph text]

private def identityPart (title : String) (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) :
    Verso.Doc.Part Verso.Genre.Manual := .mk #[.text title] title none blocks #[]

private def identityExtensions : VersoReact.Renderer.Extensions := {
  renderInline? := fun key ext => do
    if ext.name != `Identity.inline then return none
    return some (← <details key={← JsValue.ofString key} className="identity-inline-extension">
      <summary>{Node.text (← js#"Inline extension")}</summary>
      {Node.text (← js#"Extension body")}
    </details>)
  blockIdentity? := fun ext =>
    if ext.name == `Identity.labeled then ext.data.getStr?.toOption else none
  renderBlock? := fun _ attributes ext children => do
    let label := ext.data.getStr?.toOption.getD "missing"
    let props ← attributes "identity-fixture" (← js%{})
    Js.Object.set props (← js#"data-test-label") (← JsValue.ofString label)
    let nodes ← children ()
    return some (← <details @props={props}>
      <summary>{Node.text (← JsValue.ofString label)}</summary>{Js.Array.ofArray nodes}
    </details>)
}

private def identityScenarioDocument (scenario : Nat) : Verso.Doc.Part Verso.Genre.Manual := Id.run do
  let p := identityParagraph
  let d := identityDisclosure
  let rich : Array (Verso.Doc.Block Verso.Genre.Manual) := #[
    .para #[.footnote "note" #[.text "Footnote body"],
      .math .inline "x + y", .emph #[.text "Emphasis"],
      .concat #[.bold #[.text "Nested bold"]],
      .other { name := `Identity.inline } #[],
      .other { name := `Identity.unsupported } #[.code "Fallback child"]],
    .ul #[.mk #[d "unordered"]],
    .ol 1 #[.mk #[d "ordered"]],
    .dl #[.mk #[.text "Term"] #[d "description"]]
  ]
  let blocks := match scenario with
    | 0 => #[p "A", p "B", p "C"]
    | 1 => #[p "A", p "B edited", p "C"]
    | 2 => #[p "X", p "A", p "B", p "C"]
    | 3 => #[p "C", p "A", p "B"]
    | 4 => #[d "A", d "B"]
    | 5 => #[identityDisclosure "A" true "body edited", d "B"]
    | 6 => #[p "X", d "A", d "B"]
    | 7 => #[d "B", d "A"]
    | 8 => #[identityDisclosure "A" false, identityDisclosure "B" false]
    | 9 => #[identityDisclosure "X" false, identityDisclosure "A" false, identityDisclosure "B" false]
    | 10 => #[identityDisclosure "B" false]
    | 11 => #[identityDisclosure "A" false "body edited", identityDisclosure "B" false]
    | 12 => #[identityDisclosure "same" false, identityDisclosure "same" false]
    | 13 => #[identityDisclosure "same" false, identityDisclosure "same" false, identityDisclosure "same" false]
    | 16 => #[.blockquote #[p "old", d "nested"]]
    | 17 => #[.blockquote #[p "new", d "nested"]]
    | 18 => rich
    | 19 => #[p "Inserted"] ++ rich
    | _ => #[]
  let doc := if scenario == 14 || scenario == 15 then
    { identityPart "Root" #[] with subParts :=
      #[identityPart (if scenario == 14 then "Section" else "Renamed") #[d "nested"]] }
    else identityPart "Root" blocks
  return doc

/-- Browser-only identity experiment; disclosures hold native DOM state. -/
@[vir_export]
def renderIdentityScenario (scenario : Nat) : ReactM (Js Node) :=
  VersoReact.Renderer.render (identityScenarioDocument scenario) {} identityExtensions

@[vir_export]
def emptyIdentityState : RuntimeM (JSL VersoReact.Fingerprint.State) :=
  LeanRef.toJSL (default : VersoReact.Fingerprint.State)

@[vir_export]
def advanceIdentityScenario (previous : JSL VersoReact.Fingerprint.State) (scenario : Nat) :
    RuntimeM (JSL VersoReact.Fingerprint.State) := do
  LeanRef.toJSL (VersoReact.Renderer.prepareIdentities (← LeanRef.fromJSL previous)
    (identityScenarioDocument scenario) identityExtensions)

@[vir_export]
def renderIdentityScenarioRetained (state : JSL VersoReact.Fingerprint.State) (scenario : Nat) :
    ReactM (Js Node) := do
  VersoReact.Renderer.render (identityScenarioDocument scenario)
    { identities? := some (← LeanRef.fromJSL state) } identityExtensions

/-- Untimed byte-equivalence gate for the experimental serializer. -/
@[vir_export]
def checkCompression (source : Js String) : RuntimeM Bool := do
  let text ← JsValue.toString source
  return match Lean.Json.parse text with
    | .error _ => false
    | .ok json => VersoReact.Json.compress json == json.compress

/-- Build deep/wide inputs without asking the JSON parser to recurse over them. -/
@[vir_export]
def checkCompressionStress : RuntimeM Bool := do
  let mut deep : Lean.Json := .null
  for _ in [:5000] do
    deep := .arr #[deep]
  let wide := Lean.Json.arr (Array.replicate 5000 (.str "α\\\"\n\t"))
  return VersoReact.Json.compress deep == deep.compress &&
    VersoReact.Json.compress wide == wide.compress

@[vir_export]
def createView : RuntimeM (FunctionComponent (Props.WithData Preview)) :=
  createComponent

/-- Render a decoded response through the real retained preview component. -/
@[vir_export]
def renderDecoded (view : FunctionComponent (Props.WithData Preview))
    (decoded : JSL (Except String Preview)) : ReactM (Js Node) := do
  let preview := match ← LeanRef.fromJSL decoded with
    | .ok preview => preview
    | .error message => .error message
  let props ← Props.WithData.make (← LeanRef.toJSL preview)
  Node.functionComponent view props (← js#[])

/-- Browser parsing happens before entry; the measured call includes conversion
and the original typed decoder, separated by one existing Bool host boundary. -/
@[vir_export]
def browserParsed (input : Js.Any) : RuntimeM (JSL (Except String Preview)) := do
  let parsed ← Lean.Vir.JsonValue.fromJs input
  let _ ← JsValue.ofBool (match parsed with | .ok _ => true | .error _ => false)
  LeanRef.toJSL (parsed.bind fun json => (Lean.fromJson? json : Except String Preview))

/-- Check the producer-side exact-number domain before JSON.parse can round it.
This is an untimed fixture gate, not a second parser in the candidate path. -/
@[vir_export]
def validateSource (source : Js String) : RuntimeM Bool := do
  let text ← JsValue.toString source
  return match Lean.Json.parse text >>= Lean.Vir.JsonValue.validate with
    | .ok () => true
    | .error _ => false

/-- Full JSON equality, independent of which fields Preview's decoder uses. -/
@[vir_export]
def jsonEquivalent (source : Js String) (input : Js.Any) : RuntimeM Bool := do
  let text ← JsValue.toString source
  let converted ← Lean.Vir.JsonValue.fromJs input
  return match Lean.Json.parse text, converted with
    | .ok parsed, .ok converted => parsed == converted
    | _, _ => false

/-- Control: the exact decoder used by the response callback. -/
@[vir_export]
def whole (input : Js String) : RuntimeM (JSL (Except String Preview)) := do
  let source ← JsValue.toString input
  LeanRef.toJSL (Preview.decode source)

/-- One host boundary separates parsing from typed reconstruction. Its Bool
argument forces the parse result before the marker. No JSON tree crosses into
JavaScript, and no additional reference to that tree is retained by the probe. -/
@[vir_export]
def split (input : Js String) : RuntimeM (JSL (Except String Preview)) := do
  let source ← JsValue.toString input
  let parsed := Lean.Json.parse source
  let _ ← JsValue.ofBool (match parsed with | .ok _ => true | .error _ => false)
  LeanRef.toJSL (parsed.bind fun json => (Lean.fromJson? json : Except String Preview))

/-- Semantic comparison stays outside the timed decoder calls. -/
@[vir_export]
def equivalent (a b : JSL (Except String Preview)) : RuntimeM Bool := do
  return match ← LeanRef.fromJSL a, ← LeanRef.fromJSL b with
    | .ok a, .ok b => a == b
    | .error a, .error b => a == b
    | _, _ => false

@[vir_export]
def describe (result : JSL (Except String Preview)) : RuntimeM String := do
  return match ← LeanRef.fromJSL result with
    | .ok (.ready document) => s!"ready:{document.version}"
    | .ok _ => "other preview"
    | .error message => s!"error:{message}"

end VersoBlueprintVirTests.NativeSession.DecodeProbe
