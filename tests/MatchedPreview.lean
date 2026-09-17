/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module
public import VersoBlueprintVir.Preview.Widget

public section
namespace MatchedPreview
open Lean Lean.Vir Lean.Vir.React VersoBlueprint.Experimental.VirPreview
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

@[vir_js "previewDemo.matchedComponent"]
private opaque component : RuntimeM (FunctionComponent EncodedDocumentProps)

def createView : RuntimeM (FunctionComponent Infoview.PanelWidgetProps) := do
  let rpc ← createEncodedDocumentRpcComponent "MatchedPreview.Server.previewDocument" (← component)
  createWidgetComponentWithRpc rpc

vir_proof_widget MatchedPreview.createView

def panelProps : Infoview.WidgetProps := {
  widgetProps with
  wasmPath := ".lake/build/vir/sdk/wasm/vir-upstream.wasm"
  autoReloadMs := 0
  setupHint := "Build the matched SDK with lake build :virSdk, then restart the Lean server."
}

@[widget_module]
def virWidget : Widget.Module where
  javascript := include_str ".." / ".lake" / "build" / "matched-vir-demo.js"

@[widget_module]
def firWidget : Widget.Module where
  javascript := include_str ".." / ".lake" / "build" / "matched-fir-demo.js"

end MatchedPreview
