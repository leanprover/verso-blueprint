/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module

public import VersoBlueprintVir.Preview.Widget

public section
namespace FirJsonPreview
open Lean Lean.Vir Lean.Vir.React VersoBlueprint.Experimental.VirPreview
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

/-- Stable native component owned by the session-retained FIR runtime. -/
@[vir_js "previewDemo.componentFir"]
private opaque componentFir : RuntimeM (FunctionComponent Props)

def createComponent : RuntimeM (FunctionComponent Infoview.PanelWidgetProps) := do
  let documentComponent ← componentFir
  let view ← FunctionComponent.ofLean fun (props : Js (Props.WithData (RpcState (Js String)))) => do
    let input : RpcState (Js String) ← LeanRef.fromJSL (← Props.WithData.data props)
    let content ← match input.reply? with
      | some (.ok encoded) =>
        let documentProps ← js%{ "document" := encoded }
        Node.functionComponent documentComponent documentProps (← js#[])
      | none => renderStatus "loading" "Loading document"
      | some (.error message) => renderStatus "error" message
    -- The native component owns the single document shell and its controls.
    return ← <div data-verso-backend="fir">{pure content}</div>
  -- Keep the native JS String handle untouched: only FIR decodes the document.
  let rpc ← createRpcComponentFor "FirJsonPreview.Server.previewDocument"
    (fun reply => Except.ok <$> Js.String.fromAny reply) view
  createWidgetComponentWithRpc rpc

@[widget_module]
def widget : Widget.Module where
  javascript := include_str ".." / ".lake" / "build" / "fir-json-demo.js"

end FirJsonPreview
