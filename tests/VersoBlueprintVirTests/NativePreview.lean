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

private def renderView (method : String) (input : Input) : ReactM (Js Node) := do
  let checked ← StateTuple.toState (← Hooks.useState (← JsValue.ofBool false))
  let response ← StateTuple.toState
    (← Hooks.useState (← LeanRef.toJSL ({} : ResponseState)))
  let message ← JsValue.ofString input.message
  let fail ← JsValue.ofBool input.fail
  -- Native session identity and primitive request inputs, not a fresh props object.
  let effect ← EffectCallback.ofLean {
    setup := do
      let active ← RuntimeRef.new true
      let params ← Js.Object.empty
      Js.Object.set params (← JsValue.ofString "message") message
      Js.Object.set params (← JsValue.ofString "fail") fail
      Js.Object.set params (← JsValue.ofString "waitForCancellation") (← JsValue.ofBool false)
      State.modify response fun previous => do
        let previous : ResponseState ← LeanRef.fromJSL previous
        LeanRef.toJSL { previous with status := "loading" }
      -- Keep this baseline on call; cancellation is a separate integration gate.
      -- It guards stale publication without claiming transport cancellation.
      let request : Js.Promise Js.Any.Value ← Infoview.RpcSession.call
        input.session (← JsValue.ofString method) params
      let success ← Js.Function.ofLeanVoid fun (reply : Js.Any) => do
        if ← active.get then
          let text ← Js.String.fromAny (← Js.Object.get reply (← JsValue.ofString "message"))
          State.set response (← LeanRef.toJSL {
            message := ← JsValue.toString text, status := "ready" : ResponseState })
      let failure ← Js.Function.ofLeanVoid fun (_error : Js.Any) => do
        if ← active.get then
          State.modify response fun previous => do
            let previous : ResponseState ← LeanRef.fromJSL previous
            LeanRef.toJSL { previous with status := "error" }
      let handled ← Js.Promise.thenVoid request success
      let finished ← Js.Function.ofLeanVoid fun (_ : Js.Undefined) => pure ()
      -- Observe RPC rejection and checked-field failures from the success handler.
      let _ ← Js.Promise.thenVoidWithRejection handled finished failure
      LeanRef.toJSL active
    cleanup := fun resource => do
      let active : RuntimeRef Bool ← LeanRef.fromJSL resource
      active.set false
  }
  let deps ← Hooks.DependencyList.ofArray
    #[Js.erase input.session, Js.erase message, Js.erase fail]
  Hooks.useEffect effect (Js.UndefinedOr.ofJs deps)
  let current : ResponseState ← LeanRef.fromJSL response.value
  let onChange ← Callback.ofUnary fun (_ : Js Lean.Vir.Browser.Event) =>
    State.modify checked fun previous => do
      JsValue.ofBool (!(← JsValue.toBool previous))
  let checkboxProps ← js%{ "id" := (← js#"native-preview-checkbox"), "type" := (← js#"checkbox"), "checked" := checked.value, "onChange" := onChange }
  let checkbox ← <input @props={checkboxProps}/>
  let label ← <label htmlFor="native-preview-checkbox">{pure checkbox}{Node.text (← js#" Keep this option across preview updates")}</label>
  let text ← <p id="native-preview-message">{Node.text (← JsValue.ofString current.message)}</p>
  let status ← <p id="native-preview-status">{Node.text (← JsValue.ofString current.status)}</p>
  return ← <section data-preview-status={← JsValue.ofString current.status}>{pure label}{pure text}{pure status}</section>

/-- Construct once per runtime, then keep this exact native React component type. -/
@[vir_export]
def createComponent (method : String) : RuntimeM (FunctionComponent (Props.WithData Input)) :=
  FunctionComponent.ofLean fun props => do
    renderView method (← LeanRef.fromJSL (← Props.WithData.data props))

/-- The browser test owns its ordinary React root; there is no VBP runtime wrapper. -/
@[vir_export]
def render (component : FunctionComponent (Props.WithData Input)) (input : Input) : ReactM (Js Node) := do
  let props ← Props.WithData.make (← LeanRef.toJSL input)
  Node.functionComponent component props (← js#[])

end VersoBlueprintVirTests.NativePreview
