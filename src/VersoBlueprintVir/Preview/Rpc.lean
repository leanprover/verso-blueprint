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

/-- State of one request stream. Refreshes and failures retain the last accepted
value; an error is a separate request outcome, not a replacement document. -/
structure RpcState (α : Type) where
  value? : Option α := none
  error? : Option String := none
  timing? : Option Session.ResponseTiming := none

private def renderRpc {α : Type} (method : String) (decodeReply : Js.Any → RuntimeM (Except String α))
    (clock? : Option (RuntimeM Float)) (view : FunctionComponent (Props.WithData (RpcState α)))
    (input : RpcInput) : ReactM (Js Node) := do
  let state ← StateTuple.toState
    (← Hooks.useState (← LeanRef.toJSL ({} : RpcState α)))
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
          let reply ← decodeReply reply
          let decoded ← clock?.getD (pure 0)
          React.Ref.set acceptedEdit (← JsValue.ofNat editCount)
          State.modify state fun previous => do
            let previous : RpcState α ← LeanRef.fromJSL previous
            LeanRef.toJSL (match reply with
              | .ok value => {
                  value? := some value
                  timing? := clock?.map fun _ => {
                    requestedMs := requested, receivedMs := received, decodedMs := decoded
                    notifiedMs? := notified?
                  }
                }
              | .error message => { previous with error? := some message, timing? := none })
      let failure ← Js.Function.ofLeanVoid fun (_error : Js.Any) => do
        if ← active.get then
          State.modify state fun previous => do
            let previous : RpcState α ← LeanRef.fromJSL previous
            LeanRef.toJSL { previous with
              error? := some "Preview RPC failed or returned an invalid response"
              timing? := none }
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

/-- Reuse the editor subscription, cancellation and stale-reply protection with
an explicitly chosen decoder and a caller-owned React view. -/
def createRpcComponentFor {α : Type} (method : String)
    (decodeReply : Js.Any → RuntimeM (Except String α))
    (view : FunctionComponent (Props.WithData (RpcState α)))
    (clock? : Option (RuntimeM Float) := none) :
    RuntimeM (FunctionComponent (Props.WithData RpcInput)) :=
  FunctionComponent.ofLean fun props => do
    renderRpc method decodeReply clock? view (← LeanRef.fromJSL (← Props.WithData.data props))

/-- Shared document-String RPC adapter. The selected runtime owns decoding and
the single document session; only native String/number props reach its component. -/
def createEncodedDocumentRpcComponent (method : String)
    (documentComponent : FunctionComponent EncodedDocumentProps)
    (clock? : Option (RuntimeM Float) := none) :
    RuntimeM (FunctionComponent (Props.WithData RpcInput)) := do
  let DocumentComponent := documentComponent
  let view ← FunctionComponent.ofLean fun (props : Js (Props.WithData (RpcState (Js String)))) => do
    let state : RpcState (Js String) ← LeanRef.fromJSL (← Props.WithData.data props)
    let document : Js Node ← match state.value? with
    | some encoded => do
      let number := fun (value : Option Float) => (do
        match value with
        | none => Js.UndefinedOr.undefined
        | some value => pure (Js.UndefinedOr.ofJs (← JsValue.ofFloat value))
        : RuntimeM (Js.UndefinedOr Float))
      let requested ← number (state.timing?.map (·.requestedMs))
      let received ← number (state.timing?.map (·.receivedMs))
      let notified ← number (state.timing?.bind (·.notifiedMs?))
      let node ← <DocumentComponent document={encoded} requestedMs={requested}
        receivedMs={received} notifiedMs={notified} />
      pure node
    | none => do Node.text (← js#"")
    let status : Js Node ← match state.error? with
      | some message => renderStatus "error" message
      | none => do
        if state.value?.isNone then renderStatus "loading" "Loading document"
        else Node.text (← js#"")
    let outcome := if state.error?.isSome then "error"
      else if state.value?.isNone then "loading" else "ready"
    -- Keep the document at the same child position through errors/recovery.
    -- This is request status only; the selected component owns the document shell.
    return ← <div data-verso-rpc-status={← JsValue.ofString outcome}>{status}{document}</div>
  createRpcComponentFor method (fun reply => Except.ok <$> Js.String.fromAny reply) view clock?

/-- Create once per runtime. The server method returns `Preview.encode preview`
as its String result. Decode once per accepted response, never during rendering.
Cleanup aborts obsolete requests and independently suppresses stale publication. -/
def createRpcComponent (method : String)
    (decodeReply : Js.Any → RuntimeM (Except String Preview) := decodeStringReply)
    (clock? : Option (RuntimeM Float) := none)
    (mathComponent? : Option (FunctionComponent Props) := none) :
    RuntimeM (FunctionComponent (Props.WithData RpcInput)) := do
  let content ← createTimedComponent (clock?.getD (pure 0)) mathComponent?
  let view ← FunctionComponent.ofLean fun (props : Js (Props.WithData (RpcState Preview))) => do
    let state : RpcState Preview ← LeanRef.fromJSL (← Props.WithData.data props)
    let preview := match state.error? with
      | some message => .error s!"Invalid preview response: {message}"
      | none => state.value?.getD (.loading "Loading document")
    let props ← Props.WithData.make (← LeanRef.toJSL ({ preview, timing? := state.timing? } : Session.Input))
    Node.functionComponent content props (← js#[])
  createRpcComponentFor method decodeReply view clock?

end VersoBlueprint.Experimental.VirPreview
