/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Component
public import Vir.Infoview.Client

public section

namespace VersoBlueprint.Experimental.VirPreview

open Lean.Vir Lean.Vir.React Lean.Vir.Browser
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

/-- Native RPC inputs under the infoview's `EditorContext`. Keep `params` identity
stable until the request changes. Matching editor edits refresh automatically;
`revision` permits an explicit refresh without an edit. -/
structure RpcInput where
  session : Js Infoview.RpcSession
  params : Js.Any
  uri : String
  revision : String

/-- Default String reply decoder. Alternative explicit codecs run only for accepted replies. -/
def decodeStringReply (reply : Js.Any) : RuntimeM (Except String Preview) := do
  let source ← JsValue.toString (← Js.String.fromAny reply)
  pure (Preview.decode source)

private def renderRpc (method : String) (decodeReply : Js.Any → RuntimeM (Except String Preview))
    (clock? : Option (RuntimeM Float)) (view : FunctionComponent (Props.WithData Session.Input))
    (input : RpcInput) : ReactM (Js Node) := do
  let state ← StateTuple.toState
    (← Hooks.useState (← LeanRef.toJSL ({ preview := .loading "Loading document" } : Session.Input)))
  let edits ← StateTuple.toState
    (← Hooks.useState (← LeanRef.toJSL ((0, none) : Nat × Option Float)))
  -- Effect/callback bookkeeping only: never read or mutate this ref in render.
  -- An aborted request must not consume the edit's start; a later cursor-only
  -- refresh after acceptance must not reuse that old start either.
  let acceptedEdit ← Hooks.useRef (← JsValue.ofNat 0)
  let changed ← Js.Function.ofLeanVoid fun (params : Js.Any) => do
    let document ← Js.Object.get params (← JsValue.ofString "textDocument")
    let uri ← Js.String.fromAny (← Js.Object.get document (← JsValue.ofString "uri"))
    if (← JsValue.toString uri) == input.uri then
      let notified ← clock?.getD (pure 0)
      State.modify edits fun previous => do
        let (count, _) : Nat × Option Float ← LeanRef.fromJSL previous
        LeanRef.toJSL (count + 1, clock?.map fun _ => notified)
  -- Follow the current URI and replacement editor context on every render.
  Infoview.useClientNotificationEffect (← JsValue.ofString "textDocument/didChange") changed
    (← Js.UndefinedOr.undefined)
  let revision ← JsValue.ofString input.revision
  let uri ← JsValue.ofString input.uri
  let effect ← EffectCallback.ofLean {
    setup := do
      let (editCount, editNotified?) : Nat × Option Float ← LeanRef.fromJSL edits.value
      let notified? := if editCount > (← JsValue.toNat (← React.Ref.get acceptedEdit)) then
          editNotified?
        else none
      let active ← RuntimeRef.new true
      let abort ← AbortController.create
      let options ← Infoview.ClientRequestOptions.empty
      Infoview.ClientRequestOptions.setAbortSignal options (← AbortController.getSignal abort)
      let requested ← clock?.getD (pure 0)
      let request : Js.Promise Js.Any.Value ← Infoview.RpcSession.callWithOptions
        input.session (← JsValue.ofString method) input.params options
      let success ← Js.Function.ofLeanVoid fun (reply : Js.Any) => do
        -- Ignore obsolete replies before string conversion or document decoding.
        if ← active.get then
          let received ← clock?.getD (pure 0)
          let preview := match ← decodeReply reply with
            | .ok preview => preview
            | .error message => .error s!"Invalid preview response: {message}"
          let decoded ← clock?.getD (pure 0)
          React.Ref.set acceptedEdit (← JsValue.ofNat editCount)
          State.set state (← LeanRef.toJSL ({
            preview
            timing? := clock?.map fun _ => {
              requestedMs := requested, receivedMs := received, decodedMs := decoded
              notifiedMs? := notified?
            }
          } : Session.Input))
      let failure ← Js.Function.ofLeanVoid fun (_error : Js.Any) => do
        if ← active.get then
          State.set state (← LeanRef.toJSL
            ({ preview := .error "Preview RPC failed or returned a non-string response" } : Session.Input))
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
  -- An edit changes request state, not the accepted preview. Retain this child
  -- element so the pending request does not redraw the unchanged document.
  -- The child's own control state still renders normally. Only its element is
  -- memoized; document values are neither copied nor compared structurally.
  let child ← MemoCalculation.ofLean do
    let props ← Props.WithData.make state.value
    Node.functionComponent view props (← js#[])
  let childDeps ← Hooks.DependencyList.ofArray #[Js.erase view, Js.erase state.value]
  Hooks.useMemo child childDeps

/-- Create once per runtime. The server method returns `Preview.encode preview`
as its String result. Decode once per accepted response, never during rendering.
Cleanup aborts obsolete requests and independently suppresses stale publication. -/
def createRpcComponent (method : String)
    (decodeReply : Js.Any → RuntimeM (Except String Preview) := decodeStringReply)
    (clock? : Option (RuntimeM Float) := none)
    (mathComponent? : Option (FunctionComponent Props) := none) :
    RuntimeM (FunctionComponent (Props.WithData RpcInput)) := do
  let view ← createTimedComponent (clock?.getD (pure 0)) mathComponent?
  FunctionComponent.ofLean fun props => do
    renderRpc method decodeReply clock? view (← LeanRef.fromJSL (← Props.WithData.data props))

end VersoBlueprint.Experimental.VirPreview
