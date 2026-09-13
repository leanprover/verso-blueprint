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

/-- Adapt native infoview panel props to a preview RPC taking `Lean.Lsp.Position`
and returning `Preview.encode preview`. Create once, then register with
`vir_proof_widget`; VIR owns the shell, editor context, and root lifecycle. -/
def createWidgetComponent (method : String) : RuntimeM (FunctionComponent Infoview.PanelWidgetProps) := do
  let preview ← createRpcComponent method
  FunctionComponent.ofLean fun props => do
    let session ← Infoview.useRpcSession
    let position ← Infoview.PanelWidgetProps.pos props
    let uri ← JsValue.toString (← Infoview.PanelPosition.uri position)
    let line ← Infoview.PanelPosition.line position
    let character ← Infoview.PanelPosition.character position
    -- A fresh parameter object on each shell render would restart the RPC effect.
    let calculate ← MemoCalculation.ofLean do
      -- Native position fields are already JavaScript numbers.
      let params ← Js.Object.empty
      Js.Object.set params (← JsValue.ofString "line") line
      Js.Object.set params (← JsValue.ofString "character") character
      pure (Js.erase params)
    let deps ← Hooks.DependencyList.ofArray #[Js.erase line, Js.erase character]
    let params ← Hooks.useMemo calculate deps
    Node.component preview (← LeanRef.toJSL ({
      session
      params
      uri
      revision := ""
    } : RpcInput))

end VersoBlueprint.Experimental.VirPreview
