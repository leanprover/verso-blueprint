/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Component
public import Vir.Infoview.Surface

public section

namespace VersoBlueprint.Experimental.VirPreview

open Lean.Vir Lean.Vir.React Lean.Vir.Browser

/-- Native RPC inputs under the infoview's `EditorContext`. Keep `params` identity
stable until the request changes. Matching editor edits refresh automatically;
`revision` permits an explicit refresh without an edit. -/
structure RpcInput where
  session : Js Infoview.RpcSession
  params : Js.Any
  uri : String
  revision : String

private def renderRpc (method : String) (view : Js (Component Preview))
    (input : RpcInput) : ReactM (Js Node) := do
  let state ← StateTuple.toState
    (← Hooks.useState (← LeanRef.toJSL (Preview.loading "Loading document")))
  let edits ← StateTuple.toState (← Hooks.useState (← JsValue.ofNat 0))
  let changed ← Js.Function.ofLeanVoid fun (params : Js.Any) => do
    let document ← Js.Object.get params (← JsValue.ofString "textDocument")
    let uri ← Js.String.fromAny (← Js.Object.get document (← JsValue.ofString "uri"))
    if (← JsValue.toString uri) == input.uri then
      State.modify edits fun previous => do JsValue.ofNat ((← JsValue.toNat previous) + 1)
  -- Follow the current URI and replacement editor context on every render.
  Infoview.useClientNotificationEffect (← JsValue.ofString "textDocument/didChange") changed
    (← Js.UndefinedOr.undefined)
  let revision ← JsValue.ofString input.revision
  let uri ← JsValue.ofString input.uri
  let effect ← EffectCallback.ofLean {
    setup := do
      let active ← RuntimeRef.new true
      let abort ← AbortController.create
      let options ← Infoview.ClientRequestOptions.empty
      Infoview.ClientRequestOptions.setAbortSignal options (← AbortController.getSignal abort)
      let request : Js.Promise Js.Any.Value ← Infoview.RpcSession.callWithOptions
        input.session (← JsValue.ofString method) input.params options
      let success ← Js.Function.ofLeanVoid fun (reply : Js.Any) => do
        -- Ignore obsolete replies before string conversion or document decoding.
        if ← active.get then
          let source ← JsValue.toString (← Js.String.fromAny reply)
          let preview := match Preview.decode source with
            | .ok preview => preview
            | .error message => .error s!"Invalid preview response: {message}"
          State.set state (← LeanRef.toJSL preview)
      let failure ← Js.Function.ofLeanVoid fun (_error : Js.Any) => do
        if ← active.get then
          State.set state (← LeanRef.toJSL
            (Preview.error "Preview RPC failed or returned a non-string response"))
      let handled ← Js.Promise.thenVoid request success
      let finished ← Js.Function.ofLeanVoid fun (_ : Js.Undefined) => pure ()
      let _ ← Js.Promise.thenVoidWithRejection handled finished failure
      LeanRef.toJSL (active, abort)
    cleanup := fun resource => do
      let (active, abort) : RuntimeRef Bool × Js AbortController ← LeanRef.fromJSL resource
      active.set false
      AbortController.abort abort
  }
  let deps ← Hooks.DependencyList.ofArray
    #[Js.erase input.session, input.params, Js.erase uri, Js.erase revision, Js.erase edits.value]
  Hooks.useEffect effect (Js.UndefinedOr.ofJs deps)
  -- Retain the last accepted preview while refreshing. The stable child type
  -- keeps controls alive through requests, errors, and document replacement.
  Node.component view state.value

/-- Create once per runtime. The server method returns `Preview.encode preview`
as its String result. Decode once per accepted response, never during rendering.
Cleanup aborts obsolete requests and independently suppresses stale publication. -/
def createRpcComponent (method : String) : RuntimeM (Js (Component RpcInput)) := do
  let view ← createComponent
  Component.ofLean fun props => do renderRpc method view (← LeanRef.fromJSL props)

end VersoBlueprint.Experimental.VirPreview
