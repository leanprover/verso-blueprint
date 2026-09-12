/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Vir.Infoview.Surface
public import Vir.React
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
  let checkbox ← Node.elementWith "input" #[
    Props.id "native-preview-checkbox", Props.type "checkbox",
    Props.checked (← JsValue.toBool checked.value),
    Props.onChangeUnit <| State.modify checked fun previous => do
      JsValue.ofBool (!(← JsValue.toBool previous))
  ] #[]
  let label ← Node.elementWith "label" #[Props.htmlFor "native-preview-checkbox"]
    #[checkbox, ← Node.text (← JsValue.ofString " Keep this option across preview updates")]
  let text ← Node.pTextWith #[Props.id "native-preview-message"] current.message
  let status ← Node.pTextWith #[Props.id "native-preview-status"] current.status
  Node.elementWith "section" #[Props.string "data-preview-status" current.status]
    #[label, text, status]

/-- Construct once per runtime, then keep this exact native React component type. -/
@[vir_export]
def createComponent (method : String) : RuntimeM (Js (Component Input)) :=
  Component.ofLean fun props => do renderView method (← LeanRef.fromJSL props)

/-- The browser test owns its ordinary React root; there is no VBP runtime wrapper. -/
@[vir_export]
def render (component : Js (Component Input)) (input : Input) : ReactM (Js Node) := do
  Node.component component (← LeanRef.toJSL input)

end VersoBlueprintVirTests.NativePreview
