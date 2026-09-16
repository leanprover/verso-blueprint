/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module

public import VersoBlueprintVir.Preview.Widget

public section
namespace FirJsonPreview
open Lean Lean.Vir Lean.Vir.React VersoBlueprint.Experimental.VirPreview
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

/-- Stable native component owned by the session-retained FIR runtime. -/
@[vir_js "previewDemo.componentFir"]
private opaque componentFir : RuntimeM (FunctionComponent EncodedDocumentProps)

def createComponent : RuntimeM (FunctionComponent Infoview.PanelWidgetProps) := do
  let rpc ← createEncodedDocumentRpcComponent "FirJsonPreview.Server.previewDocument" (← componentFir)
  createWidgetComponentWithRpc rpc

@[widget_module]
def widget : Widget.Module where
  javascript := include_str ".." / ".lake" / "build" / "fir-json-demo.js"

end FirJsonPreview
