/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Vir.Js

public section

namespace VersoBlueprint.Experimental.VirPreview.JsStrings

open Lean.Vir

structure Keys where
  dataBpTexPrelude : Js String
  dataVersoInformalKind : Js String
  dataVersoInformalLabel : Js String
  dataVersoExternalMarkupLabel : Js String
  dataVersoExternalMarkupLanguage : Js String
  dataVersoExternalMarkupSlot : Js String
  dataVersoExternalMarkupDisplay : Js String
  dataVersoVersion : Js String
  dataVersoCorrelationId : Js String
  dataVersoCursorToken : Js String

structure Values where
  blueprintMathInlineClass : Js String
  blueprintMathDisplayClass : Js String
  summary : Js String
  source : Js String

structure Fixed where
  keys : Keys
  values : Values

private def createKeys : RuntimeM Keys := do
  return {
    dataBpTexPrelude := ← JsValue.ofString "data-bp-tex-prelude"
    dataVersoInformalKind := ← JsValue.ofString "data-verso-informal-kind"
    dataVersoInformalLabel := ← JsValue.ofString "data-verso-informal-label"
    dataVersoExternalMarkupLabel := ← JsValue.ofString "data-verso-external-markup-label"
    dataVersoExternalMarkupLanguage := ← JsValue.ofString "data-verso-external-markup-language"
    dataVersoExternalMarkupSlot := ← JsValue.ofString "data-verso-external-markup-slot"
    dataVersoExternalMarkupDisplay := ← JsValue.ofString "data-verso-external-markup-display"
    dataVersoVersion := ← JsValue.ofString "data-verso-version"
    dataVersoCorrelationId := ← JsValue.ofString "data-verso-correlation-id"
    dataVersoCursorToken := ← JsValue.ofString "data-verso-cursor-token"
  }

private def createValues : RuntimeM Values := do
  return {
    blueprintMathInlineClass := ← JsValue.ofString "vir-verso-math bp_math inline"
    blueprintMathDisplayClass := ← JsValue.ofString "vir-verso-math bp_math display"
    summary := ← JsValue.ofString "summary"
    source := ← JsValue.ofString "source"
  }

/-- Construct once after opening a runtime; Blueprint renderers borrow these handles. -/
def Fixed.create : RuntimeM Fixed := do
  return { keys := ← createKeys, values := ← createValues }

end VersoBlueprint.Experimental.VirPreview.JsStrings
