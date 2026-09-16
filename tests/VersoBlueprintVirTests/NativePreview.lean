/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Vir.Infoview.Client
public import Vir.React
public import Vir.ProofWidgets.Jsx
meta import Vir.Attributes

public section

/-!
Transport-first migration fixture, not a new preview format or public client API.
The existing VIR real-server fixture supplies a message and an exact RPC reference.
This component checks only the message field and never copies the reference.
The full Manual string-RPC campaign, including editor notifications and request
cancellation, lives in `StringPreview`. This fixture retains the scalar baseline.
-/

namespace VersoBlueprintVirTests.NativePreview

open Lean.Vir Lean.Vir.React
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

structure Input where
  session : Js Infoview.RpcSession
  message : String
  fail : Bool := false

private structure ResponseState where
  message : String := ""
  status : String := "loading"

private def renderView (initialChecked : Js Bool) (initialResponse : JSL ResponseState)
    (method : String) (input : Input) : ReactM (Js Node) := do
  let checked ← Hooks.useState initialChecked
  let checkedValue ← Js.Tuple2.first checked
  let checkedSetter ← Js.Tuple2.second checked
  let response ← Hooks.useState initialResponse
  let responseValue ← Js.Tuple2.first response
  let responseSetter ← Js.Tuple2.second response
  let message ← JsValue.ofString input.message
  let fail ← JsValue.ofBool input.fail
  -- Native session identity and primitive request inputs, not a fresh props object.
  let effect ← Js.Function.ofLean0 do
    let active ← RuntimeRef.new true
    let params ← Js.Object.empty
    Js.Object.set params (← JsValue.ofString "message") message
    Js.Object.set params (← JsValue.ofString "fail") fail
    Js.Object.set params (← JsValue.ofString "waitForCancellation") (← JsValue.ofBool false)
    let loading ← Js.Function.ofLean fun previous => do
      let previous : ResponseState ← LeanRef.fromJSL previous
      LeanRef.toJSL { previous with status := "loading" }
    Js.Function.callVoid responseSetter (SetStateAction.ofUpdater loading)
    -- This scalar baseline guards stale publication; transport cancellation
    -- remains a separate full-document integration gate.
    let request : Js.Promise Js.Any.Value ← Infoview.RpcSession.call
      input.session (← JsValue.ofString method) params
    let success ← Js.Function.ofLeanVoid fun (reply : Js.Any) => do
      if ← active.get then
        let text ← Js.String.fromAny (← Js.Object.get reply (← JsValue.ofString "message"))
        let value ← LeanRef.toJSL {
          message := ← JsValue.toString text, status := "ready" : ResponseState }
        Js.Function.callVoid responseSetter (SetStateAction.ofValue value)
    let failure ← Js.Function.ofLeanVoid fun (_error : Js.Any) => do
      if ← active.get then
        let action ← Js.Function.ofLean fun previous => do
          let previous : ResponseState ← LeanRef.fromJSL previous
          LeanRef.toJSL { previous with status := "error" }
        Js.Function.callVoid responseSetter (SetStateAction.ofUpdater action)
    let handled ← Js.Promise.thenVoid request success
    let finished ← Js.Function.ofLeanVoid fun (_ : Js.Undefined) => pure ()
    let _ ← Js.Promise.thenVoidWithRejection handled finished failure
    let cleanup ← Js.Function.ofLean0Void (active.set false)
    pure (Js.UndefinedOr.ofJs cleanup)
  let deps ← js#[Js.erase input.session, Js.erase message, Js.erase fail]
  Hooks.useEffect effect (Js.UndefinedOr.ofJs deps)
  let current : ResponseState ← LeanRef.fromJSL responseValue
  let onChange ← Js.Function.ofLeanVoid fun (_ : Js SyntheticEvent) => do
    let action ← Js.Function.ofLean fun previous => do
      JsValue.ofBool (!(← JsValue.toBool previous))
    Js.Function.callVoid checkedSetter (SetStateAction.ofUpdater action)
  let checkboxProps ← js%{ "id" := (← js#"native-preview-checkbox"), "type" := (← js#"checkbox"), "checked" := checkedValue, "onChange" := onChange }
  let checkbox ← <input @props={checkboxProps}/>
  let label ← <label htmlFor="native-preview-checkbox">{pure checkbox}{Node.text (← js#" Keep this option across preview updates")}</label>
  let text ← <p id="native-preview-message">{Node.text (← JsValue.ofString current.message)}</p>
  let status ← <p id="native-preview-status">{Node.text (← JsValue.ofString current.status)}</p>
  return ← <section data-preview-status={← JsValue.ofString current.status}>{pure label}{pure text}{pure status}</section>

/-- Construct once per runtime, then keep this exact native React component type. -/
@[vir_export]
def createComponent (method : String) : RuntimeM (FunctionComponent (Props.WithData Input)) := do
  let initialChecked ← JsValue.ofBool false
  let initialResponse ← LeanRef.toJSL ({} : ResponseState)
  FunctionComponent.ofLean fun props => do
    renderView initialChecked initialResponse method (← LeanRef.fromJSL (← Props.WithData.data props))

/-- The browser test owns its ordinary React root; there is no VBP runtime wrapper. -/
@[vir_export]
def render (component : FunctionComponent (Props.WithData Input)) (input : Input) : ReactM (Js Node) := do
  let props ← Props.WithData.make (← LeanRef.toJSL input)
  Node.functionComponent component props (← js#[])

end VersoBlueprintVirTests.NativePreview
