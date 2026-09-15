/- Copyright (c) 2026 Lean FRO LLC. Released under Apache 2.0 license. -/
module

public import VersoBlueprintVir.Preview.Widget
public import VersoBlueprintVirTests.NativeSession.UpstreamJson.Js

public section

-- Temporary, explicitly selected demo codec. Remove when VIR ships the JSON bridge.
namespace CheckedJsonPreview
open Lean Lean.Vir VersoBlueprint.Experimental.VirPreview

@[vir_js "previewDemo.parse"]
private opaque parse (source : @& Js String) : RuntimeM Js.Any

/-- Demo-only browser clock. Delete when the matched VIR SDK exposes it. -/
@[vir_js "previewDemo.now"]
private opaque nowJs : RuntimeM (Js Float)

def now : RuntimeM Float := do JsValue.toFloat (← nowJs)

@[vir_js "previewDemo.mathComponent"]
private opaque mathComponent : RuntimeM (React.FunctionComponent React.Props)

def decodeReply (reply : Js.Any) : RuntimeM (Except String Preview) := do
  let value ← parse (← Js.String.fromAny reply)
  return (← JsonValue.fromJs value).bind fun json => fromJson? json

def createComponent : RuntimeM (React.FunctionComponent Infoview.PanelWidgetProps) := do
  createWidgetComponent "CheckedJsonPreview.Server.previewDocument" decodeReply
    (some now) (some (← mathComponent))

@[widget_module]
def widget : Widget.Module where
  javascript := include_str ".." / ".lake" / "build" / "checked-json-demo.js"

end CheckedJsonPreview
