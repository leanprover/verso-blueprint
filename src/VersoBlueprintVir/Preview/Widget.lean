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
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

/-- Adapt native panel position props to an existing RPC component. Create once;
VIR owns the shell, editor context and root lifecycle. -/
def createWidgetComponentWithRpc (preview : FunctionComponent (Props.WithData RpcInput)) :
    RuntimeM (FunctionComponent Infoview.PanelWidgetProps) := do
  FunctionComponent.ofLean fun props => do
    let session ← Infoview.useRpcSession
    let position ← Infoview.PanelWidgetProps.pos props
    let uri ← Infoview.PanelPosition.uri position
    let line ← Infoview.PanelPosition.line position
    let character ← Infoview.PanelPosition.character position
    -- Retain the complete child element through unchanged shell progress updates.
    -- Convert URI and construct request/Lean-backed props only when the native
    -- session or position changes. The child still receives context and its own
    -- edit/control state updates normally.
    let calculate ← Js.Function.ofLean0 do
      -- Native position fields are already JavaScript numbers.
      let params ← Js.Object.empty
      Js.Object.set params (← JsValue.ofString "line") line
      Js.Object.set params (← JsValue.ofString "character") character
      let previewProps ← Props.WithData.make (← LeanRef.toJSL ({
        session
        params := Js.erase params
        uri := ← JsValue.toString uri
        revision := ""
      } : RpcInput))
      Node.functionComponent preview previewProps (← js#[])
    let deps ← js#[Js.erase preview, Js.erase session, Js.erase uri, Js.erase line, Js.erase character]
    Hooks.useMemo calculate deps

/-- Standard Preview-codec widget. Alternative reply types reuse the same panel
adapter with `createRpcComponentFor` and `createWidgetComponentWithRpc`. -/
def createWidgetComponent (method : String)
    (decodeReply : Js.Any → RuntimeM (Except String Preview) := decodeStringReply)
    (clock? : Option (RuntimeM Float) := none)
    (mathComponent? : Option (FunctionComponent Props) := none) :
    RuntimeM (FunctionComponent Infoview.PanelWidgetProps) := do
  createWidgetComponentWithRpc (← createRpcComponent method decodeReply clock? mathComponent?)

end VersoBlueprint.Experimental.VirPreview
