/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Vir.Js

public section

namespace VersoReact.JsStrings

open Lean.Vir

/-- JavaScript property names shared by every renderer invocation. -/
structure Keys where
  key : Js String
  className : Js String
  style : Js String
  title : Js String
  id : Js String
  source : Js String
  start : Js String
  dataLanguage : Js String
  dataVersoMathMode : Js String
  dataVersoBlock : Js String
  dataVersoListItem : Js String
  dataVersoPart : Js String
  dataVersoRenderId : Js String
  dataVersoIdentityOrigin : Js String
  dataVersoKind : Js String
  dataVersoChange : Js String
  dataVersoFocus : Js String
  dataVersoExtension : Js String
  dataVersoChangedBlockCount : Js String
  dataVersoFocusBlock : Js String

/-- Fixed JavaScript values shared by every renderer invocation. -/
structure Values where
  empty : Js String
  inline : Js String
  display : Js String
  changed : Js String
  cursor : Js String
  structural : Js String
  explicit : Js String
  verso : Js String
  fingerprint : Js String
  positional : Js String
  mathInlineClass : Js String
  mathDisplayClass : Js String
  unsupportedExtensionClass : Js String
  structuralExtension : Js String
  partClass : Js String
  documentId : Js String
  documentClass : Js String

structure Fixed where
  keys : Keys
  values : Values

private def createKeys : RuntimeM Keys := do
  return {
    key := ← JsValue.ofString "key"
    className := ← JsValue.ofString "className"
    style := ← JsValue.ofString "style"
    title := ← JsValue.ofString "title"
    id := ← JsValue.ofString "id"
    source := ← JsValue.ofString "source"
    start := ← JsValue.ofString "start"
    dataLanguage := ← JsValue.ofString "data-language"
    dataVersoMathMode := ← JsValue.ofString "data-verso-math-mode"
    dataVersoBlock := ← JsValue.ofString "data-verso-block"
    dataVersoListItem := ← JsValue.ofString "data-verso-list-item"
    dataVersoPart := ← JsValue.ofString "data-verso-part"
    dataVersoRenderId := ← JsValue.ofString "data-verso-render-id"
    dataVersoIdentityOrigin := ← JsValue.ofString "data-verso-identity-origin"
    dataVersoKind := ← JsValue.ofString "data-verso-kind"
    dataVersoChange := ← JsValue.ofString "data-verso-change"
    dataVersoFocus := ← JsValue.ofString "data-verso-focus"
    dataVersoExtension := ← JsValue.ofString "data-verso-extension"
    dataVersoChangedBlockCount := ← JsValue.ofString "data-verso-changed-block-count"
    dataVersoFocusBlock := ← JsValue.ofString "data-verso-focus-block"
  }

private def createValues : RuntimeM Values := do
  return {
    empty := ← JsValue.ofString ""
    inline := ← JsValue.ofString "inline"
    display := ← JsValue.ofString "display"
    changed := ← JsValue.ofString "changed"
    cursor := ← JsValue.ofString "cursor"
    structural := ← JsValue.ofString "structural"
    explicit := ← JsValue.ofString "explicit"
    verso := ← JsValue.ofString "verso"
    fingerprint := ← JsValue.ofString "fingerprint"
    positional := ← JsValue.ofString "positional"
    mathInlineClass := ← JsValue.ofString "vir-verso-math inline"
    mathDisplayClass := ← JsValue.ofString "vir-verso-math display"
    unsupportedExtensionClass := ← JsValue.ofString "vir-verso-extension-unsupported"
    structuralExtension := ← JsValue.ofString "structural:extension"
    partClass := ← JsValue.ofString "vir-verso-part"
    documentId := ← JsValue.ofString "vir-verso-document"
    documentClass := ← JsValue.ofString "vir-verso-document"
  }

/-- Construct once after opening a runtime; all renderer calls borrow these handles. -/
def Fixed.create : RuntimeM Fixed := do
  return { keys := ← createKeys, values := ← createValues }

end VersoReact.JsStrings
