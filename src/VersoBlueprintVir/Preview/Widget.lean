/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Rpc
public import Vir.Infoview.Widget

public section

namespace VersoBlueprint.Experimental.VirPreview

open Lean.Vir Lean.Vir.React

/-- Adapt the standard infoview surface to a preview RPC taking `Lean.Lsp.Position`
and returning `Preview.encode preview`. Create once, then register with
`vir_proof_widget`; VIR owns the shell, editor context, and root lifecycle. -/
def createWidgetComponent (method : String) : RuntimeM (Js (Component Infoview.Surface)) := do
  let preview ← createRpcComponent method
  Component.ofLean fun props => do
    let surface : Infoview.Surface ← LeanRef.fromJSL props
    let line ← JsValue.ofNat surface.cursor.line
    let character ← JsValue.ofNat surface.cursor.character
    -- A fresh parameter object on each shell render would restart the RPC effect.
    let calculate ← MemoCalculation.ofLean do
      -- Nat resources are native bigints; JSON-RPC positions require numbers.
      let some line ← JsValue.ofNatNumber? surface.cursor.line
        | return ← LeanRef.toJSL (none : Option Js.Object)
      let some character ← JsValue.ofNatNumber? surface.cursor.character
        | return ← LeanRef.toJSL (none : Option Js.Object)
      let params ← Js.Object.empty
      Js.Object.set params (← JsValue.ofString "line") line
      Js.Object.set params (← JsValue.ofString "character") character
      LeanRef.toJSL (some params)
    let deps ← Hooks.DependencyList.ofArray #[Js.erase line, Js.erase character]
    let result ← Hooks.useMemo calculate deps
    let some params : Option Js.Object ← LeanRef.fromJSL result
      | return ← Node.text (← JsValue.ofString "Invalid preview cursor: position exceeds the JSON number range")
    Node.component preview (← LeanRef.toJSL ({
      session := surface.rpcSession
      params := Js.erase params
      uri := surface.cursor.uri
      revision := ""
    } : RpcInput))

end VersoBlueprint.Experimental.VirPreview
