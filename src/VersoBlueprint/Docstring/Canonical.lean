/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Elab.DocString.Builtin
import Lean.Elab.DocString.Builtin.Keywords
import VersoBlueprint.Docstring.Compiled
import VersoBlueprint.Realizations
import Vir.Package.Name

namespace Informal.Docstring

open Lean

private def tagged (tag : String) (fields : Array Json := #[]) : Json :=
  .arr (#[.str tag] ++ fields)

private def name (n : Name) : Json := .str (Vir.nameKey n)

private partial def formatData : Format → Json
  | .nil => tagged "nil"
  | .line => tagged "line"
  | .align force => tagged "align" #[toJson force]
  | .text text => tagged "text" #[.str text]
  | .nest indent body => tagged "nest" #[toJson indent, formatData body]
  | .append left right => tagged "append" #[formatData left, formatData right]
  | .group body behavior => tagged "group" #[
      .str (match behavior with | .allOrNone => "allOrNone" | .fill => "fill"), formatData body]
  | .tag index body => tagged "tag" #[toJson index, formatData body]

-- SourceInfo is compiler location metadata, not the parsed content of a role.
private partial def syntaxData : Syntax → Json
  | .missing => tagged "missing"
  | .node _ kind children => tagged "node" #[name kind, .arr (children.map syntaxData)]
  | .atom _ text => tagged "atom" #[.str text]
  | .ident _ raw resolved bindings => tagged "ident" #[
      .str raw.toString, name resolved, .arr (bindings.toArray.map fun
        | .namespace n => tagged "namespace" #[name n]
        | .decl n fields => tagged "decl" #[name n, toJson fields])]

private partial def levelData : Level → Json
  | .zero => tagged "zero"
  | .succ level => tagged "succ" #[levelData level]
  | .max left right => tagged "max" #[levelData left, levelData right]
  | .imax left right => tagged "imax" #[levelData left, levelData right]
  | .param n => tagged "param" #[name n]
  | .mvar id => tagged "mvar" #[name id.name]

private def binderData : BinderInfo → Json
  | .default => .str "default"
  | .implicit => .str "implicit"
  | .strictImplicit => .str "strictImplicit"
  | .instImplicit => .str "instImplicit"

private def metadataValue : DataValue → Json
  | .ofString text => tagged "string" #[.str text]
  | .ofBool value => tagged "bool" #[toJson value]
  | .ofName n => tagged "name" #[name n]
  | .ofNat value => tagged "nat" #[toJson value]
  | .ofInt value => tagged "int" #[toJson value]
  | .ofSyntax value => tagged "syntax" #[syntaxData value]

private def unsupported (subject message : String) : Realizations.Diagnostic :=
  { code := "unsupported-docstring-extension", subject, message }

-- An ID found in two contexts at different positions cannot identify a binder
-- for a highlight with no context of its own.
private abbrev DocLocalPositions := Std.HashMap FVarId (Option Nat)

private def highlightData (positions : DocLocalPositions) :
    Lean.Doc.DocHighlight → Except Realizations.Diagnostic Json
  | .const n signature => pure (tagged "const" #[name n, formatData signature])
  | .var n id type =>
    match positions[id]? with
    | some (some position) => pure (tagged "lctx-binder" #[toJson position, name n, formatData type])
    | _ => throw (unsupported n.toString "Compiled highlighted local variable has no captured local-context binder identity")
  | .field n signature => pure (tagged "field" #[name n, formatData signature])
  | .option n decl => pure (tagged "option" #[name n, name decl])
  | .keyword => pure (tagged "keyword")
  | .literal kind type => pure (tagged "literal" #[name kind, (type.map formatData).getD .null])

private def codeData (positions : DocLocalPositions) (code : Lean.Doc.DocCode) :
    Except Realizations.Diagnostic Json := do
  let encoded ← code.code.mapM fun (text, highlight) => do
    let data ← Option.mapM (highlightData positions) highlight
    pure (Json.arr #[.str text, data.getD .null])
  return .arr encoded

private def binderPosition (positions : Std.HashMap FVarId Nat) (id : FVarId) :
    Except Realizations.Diagnostic Nat :=
  match positions[id]? with
  | some position => .ok position
  | none => .error (unsupported "local binder" "Compiled docstring refers to a local outside its captured scope")

private partial def exprData (positions : Std.HashMap FVarId Nat) :
    Expr → Except Realizations.Diagnostic Json
  | .bvar index => pure (tagged "bvar" #[toJson index])
  | .fvar id => return tagged "fvar" #[toJson (← binderPosition positions id)]
  | .mvar id => pure (tagged "mvar" #[name id.name])
  | .sort level => pure (tagged "sort" #[levelData level])
  | .const n levels => pure (tagged "const" #[name n, .arr (levels.toArray.map levelData)])
  | .app fn arg => return tagged "app" #[← exprData positions fn, ← exprData positions arg]
  | .lam n type body info =>
    return tagged "lam" #[name n, ← exprData positions type, ← exprData positions body, binderData info]
  | .forallE n type body info =>
    return tagged "forall" #[name n, ← exprData positions type, ← exprData positions body, binderData info]
  | .letE n type value body nondep =>
    return tagged "let" #[name n, ← exprData positions type, ← exprData positions value,
      ← exprData positions body, toJson nondep]
  | .lit (.natVal value) => pure (tagged "nat" #[toJson value])
  | .lit (.strVal value) => pure (tagged "string" #[.str value])
  | .mdata data expr => return tagged "metadata" #[
      .arr (data.entries.toArray.map fun (n, value) => .arr #[name n, metadataValue value]),
      ← exprData positions expr]
  | .proj type index value => return tagged "proj" #[name type, toJson index, ← exprData positions value]

private def localKindData : LocalDeclKind → Json
  | .default => .str "default"
  | .implDetail => .str "implDetail"
  | .auxDecl => .str "auxDecl"

private def localDeclData (positions : Std.HashMap FVarId Nat) :
    LocalDecl → Except Realizations.Diagnostic Json
  | .cdecl _ _ n type info kind =>
    return tagged "cdecl" #[name n, ← exprData positions type, binderData info, localKindData kind]
  | .ldecl _ _ n type value nondep kind =>
    return tagged "ldecl" #[name n, ← exprData positions type, ← exprData positions value,
      toJson nondep, localKindData kind]

private def activeLocalDecls (context : LocalContext) : Array LocalDecl :=
  context.decls.toArray.filterMap id

private def collectPayloadPositions (payload : Dynamic) : StateM DocLocalPositions Unit := do
  let some value := payload.get? Lean.Doc.Data.Local | return ()
  for (declaration, position) in (activeLocalDecls value.lctx).zipIdx do
    modify fun positions => positions.alter declaration.fvarId fun
      | none => some (some position)
      | some previous => some (if previous == some position then previous else none)

private partial def collectInlinePositions : Lean.Doc.Inline ElabInline → StateM DocLocalPositions Unit
  | .emph children | .bold children | .link children _ | .footnote _ children | .concat children =>
    children.forM collectInlinePositions
  | .other extension children => do
    if let .custom payload := extension then collectPayloadPositions payload
    children.forM collectInlinePositions
  | _ => pure ()

private partial def collectBlockPositions :
    Lean.Doc.Block ElabInline ElabBlock → StateM DocLocalPositions Unit
  | .para inlines => inlines.forM collectInlinePositions
  | .ul items | .ol _ items => items.forM fun item => item.contents.forM collectBlockPositions
  | .dl items => items.forM fun item => do
    item.term.forM collectInlinePositions
    item.desc.forM collectBlockPositions
  | .blockquote children | .concat children => children.forM collectBlockPositions
  | .other extension children => do
    if let .custom payload := extension then collectPayloadPositions payload
    children.forM collectBlockPositions
  | .code _ => pure ()

private partial def collectPartPositions (part : Lean.Doc.Part ElabInline ElabBlock Empty) :
    StateM DocLocalPositions Unit := do
  part.title.forM collectInlinePositions
  part.content.forM collectBlockPositions
  part.subParts.forM collectPartPositions

private def docLocalPositions (doc : Lean.VersoDocString) : DocLocalPositions :=
  let collect : StateM DocLocalPositions Unit := do
    doc.text.forM collectBlockPositions
    doc.subsections.forM collectPartPositions
  (collect.run {}).2

-- The live declaration order defines binder positions. The compiler's lookup
-- indexes and allocated names do not contribute to docstring identity.
private def localData (value : Lean.Doc.Data.Local) : Except Realizations.Diagnostic Json := do
  let declarations := activeLocalDecls value.lctx
  let positions : Std.HashMap FVarId Nat := declarations.foldl
    (fun positions declaration => positions.insert declaration.fvarId positions.size) {}
  return .arr #[name value.name, toJson (← binderPosition positions value.fvarId),
    ← exprData positions value.type, .arr (← declarations.mapM (localDeclData positions))]

private def referenceData (reference : Reference) : Json :=
  .arr #[
    match reference.target with
    | .inl label => tagged "link" #[name label]
    | .inr use => tagged "use" #[name use.label, toJson use.origin, toJson use.intent],
    toJson reference.hasCustomText]

private def payloadData (positions : DocLocalPositions) (payload : Dynamic) : Except Realizations.Diagnostic Json := do
  let encode (data : Json) : Except Realizations.Diagnostic Json :=
    .ok (tagged "custom" #[name payload.typeName, data])
  if let some value := payload.get? Reference then return ← encode (referenceData value)
  if let some value := payload.get? Lean.Doc.Data.Const then return ← encode (name value.name)
  if let some value := payload.get? Lean.Doc.Data.Local then return ← encode (← localData value)
  if let some value := payload.get? Lean.Doc.Data.Atom then
    return ← encode (.arr #[name value.name, name value.category])
  if let some value := payload.get? Lean.Doc.Data.ModuleName then return ← encode (name value.module)
  if let some value := payload.get? Lean.Doc.Data.Tactic then return ← encode (name value.name)
  if let some value := payload.get? Lean.Doc.Data.ConvTactic then return ← encode (name value.name)
  if let some value := payload.get? Lean.Doc.Data.Option then
    return ← encode (.arr #[name value.name, name value.declName])
  if let some value := payload.get? Lean.Doc.Data.SyntaxCat then return ← encode (name value.name)
  if let some value := payload.get? Lean.Doc.Data.Syntax then
    return ← encode (.arr #[name value.category, syntaxData value.stx])
  if let some value := payload.get? Lean.Doc.Data.Attribute then return ← encode (syntaxData value.stx)
  if let some value := payload.get? Lean.Doc.Data.Attributes then return ← encode (syntaxData value.stx)
  if let some value := payload.get? Lean.Doc.Data.LeanTerm then return ← encode (← codeData positions value.term)
  if let some value := payload.get? Lean.Doc.Data.LeanBlock then return ← encode (← codeData positions value.commands)
  if let some value := payload.get? Lean.Doc.Data.SetOption then return ← encode (← codeData positions value.term)
  throw (unsupported payload.typeName.toString s!"No compiled docstring encoder for '{payload.typeName}'")

private partial def inlineData (positions : DocLocalPositions) :
    Lean.Doc.Inline ElabInline → Except Realizations.Diagnostic Json
  | .text text => pure (tagged "text" #[.str text])
  | .emph children => return tagged "emph" #[.arr (← children.mapM (inlineData positions))]
  | .bold children => return tagged "bold" #[.arr (← children.mapM (inlineData positions))]
  | .code code => pure (tagged "code" #[.str code])
  | .math mode text => pure (tagged "math" #[
      .str (match mode with | .inline => "inline" | .display => "display"), .str text])
  | .linebreak text => pure (tagged "linebreak" #[.str text])
  | .link children url => return tagged "link" #[.arr (← children.mapM (inlineData positions)), .str url]
  | .footnote title children => return tagged "footnote" #[.str title, .arr (← children.mapM (inlineData positions))]
  | .image alt url => pure (tagged "image" #[.str alt, .str url])
  | .concat children => return tagged "concat" #[.arr (← children.mapM (inlineData positions))]
  | .other (.custom payload) children =>
    return tagged "other" #[← payloadData positions payload, .arr (← children.mapM (inlineData positions))]
  | .other (.deferred index) _ =>
    throw (unsupported (toString index) "Compiled docstring contains an unresolved inline check")

private partial def blockData (positions : DocLocalPositions) :
    Lean.Doc.Block ElabInline ElabBlock → Except Realizations.Diagnostic Json
  | .para contents => return tagged "para" #[.arr (← contents.mapM (inlineData positions))]
  | .code code => pure (tagged "code" #[.str code])
  | .ul items =>
    return tagged "ul" #[.arr (← items.mapM fun item => return .arr (← item.contents.mapM (blockData positions)))]
  | .ol start items =>
    return tagged "ol" #[toJson start, .arr (← items.mapM fun item => return .arr (← item.contents.mapM (blockData positions)))]
  | .dl items =>
    return tagged "dl" #[.arr (← items.mapM fun item =>
      return .arr #[.arr (← item.term.mapM (inlineData positions)), .arr (← item.desc.mapM (blockData positions))])]
  | .blockquote contents => return tagged "blockquote" #[.arr (← contents.mapM (blockData positions))]
  | .concat contents => return tagged "concat" #[.arr (← contents.mapM (blockData positions))]
  | .other (.custom payload) contents =>
    return tagged "other" #[← payloadData positions payload, .arr (← contents.mapM (blockData positions))]
  | .other (.deferred index) _ =>
    throw (unsupported (toString index) "Compiled docstring contains an unresolved block check")

private partial def partData (positions : DocLocalPositions) (part : Lean.Doc.Part ElabInline ElabBlock Empty) :
    Except Realizations.Diagnostic Json := do
  let metadata := part.metadata.elim Json.null Empty.elim
  return .arr #[.arr (← part.title.mapM (inlineData positions)), .str part.titleString, metadata,
    .arr (← part.content.mapM (blockData positions)), .arr (← part.subParts.mapM (partData positions))]

/-- A structural encoding of the compiled document and supported extension
payloads. Each node has a constructor tag and ordered fields. Rendered text and
`Repr` omit extension identities and cannot serve as content bindings. A local
highlight requires an exact binder identity from the compiled docstring. -/
def canonicalVersoDocstring (doc : Lean.VersoDocString) : Except Realizations.Diagnostic String := do
  let positions := docLocalPositions doc
  return (tagged "vbp-verso-docstring-v1" #[
    .arr (← doc.text.mapM (blockData positions)), .arr (← doc.subsections.mapM (partData positions))]).compress

end Informal.Docstring
