/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Component.Content

public section

namespace VersoBlueprint.Experimental.VirPreview

open Lean.Vir
open Lean.Vir.React
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

/-- One session's previous input and its derived change flags, not a document format. -/
private structure ChangeState where
  input? : Option Preview := none
  timing? : Option Session.ResponseTiming := none
  lastDocument? : Option Document := none
  identities : VersoReact.Fingerprint.State := default
  changedIds : Array String := #[]
  blockCount? : Option Nat := none
  revision : Nat := 0
  highlightChanges : Bool := Session.Options.initial.highlightChanges
  diagnostics : Bool := false
  inputChanged : Bool := false
  preparationMs : Float := 0

private def useChangedBlockInfo (initial : JSL ChangeState) (clock : RuntimeM Float)
    (preview : Preview) (timing? : Option Session.ResponseTiming)
    (highlightChanges diagnostics : Bool) : ReactM ChangeState := do
  let state ← Hooks.useState initial
  let previous ← LeanRef.fromJSL (← Js.Tuple2.first state)
  let inputChanged := previous.input? != some preview || previous.timing? != timing?
  if !inputChanged && previous.highlightChanges == highlightChanges &&
      previous.diagnostics == diagnostics then
    return previous
  let started ← if diagnostics then clock else pure 0
  let document? := preview.document?
  -- Content assignments are session state, not cursor/version/debug state.
  -- This pure transition is safe to replay; no IDs escape an abandoned render.
  let identities := match document? with
    | some document =>
        if previous.lastDocument?.map (·.document) == some document.document then
          previous.identities
        else
          VersoReact.Renderer.prepareIdentities previous.identities document.document Renderer.extensions
    | none => previous.identities
  let analyze := highlightChanges && document?.isSome &&
    (previous.blockCount?.isNone || previous.lastDocument? != document?)
  let (changedIds, blockCount?) :=
    if !highlightChanges then (#[], none)
    else if analyze then
      document?.map (fun document =>
        let (ids, count) := Renderer.changedBlockIdsAndCount previous.lastDocument? document
        (ids, some count)) |>.getD (#[], none)
    else (previous.changedIds, previous.blockCount?)
  let finished ← if diagnostics then clock else pure 0
  let next := {
    input? := some preview
    timing?
    lastDocument? := document?.or previous.lastDocument?
    identities
    changedIds
    blockCount?
    revision := previous.revision + 1
    highlightChanges
    diagnostics
    inputChanged
    preparationMs := finished - started
    : ChangeState
  }
  -- Guarded adjustment of this component's own state: React retries before
  -- rendering children. Unlike refs, this state participates in render replay.
  let value ← LeanRef.toJSL next
  Js.Function.callVoid (← Js.Tuple2.second state) (SetStateAction.ofValue value)
  return next

private def renderSession (stylesheet : Js Node) (contentComponent : FunctionComponent (Props.WithData Session.ContentProps))
    (initialOptions : JSL Session.Options) (initialSample : JSL Session.DebugSample)
    (initialChanges : JSL ChangeState)
    (clock : RuntimeM Float) (preview : Preview)
    (timing? : Option Session.ResponseTiming := none) : ReactM (Js Node) := do
  let optionsState ← Hooks.useState initialOptions
  let options ← LeanRef.fromJSL (← Js.Tuple2.first optionsState)
  let optionsSetter ← Js.Tuple2.second optionsState
  let document? := preview.document?
  let changes ← useChangedBlockInfo initialChanges clock preview timing? options.highlightChanges options.debug
  let changedIds := if document?.isSome then changes.changedIds else #[]

  let debugSampleState ← Hooks.useState initialSample

  let label ← <p key="label" id="vir-verso-label">Verso React preview</p>
  let config ← Session.renderConfigPanel options optionsSetter
  -- Show one completed observation, including its own server timing. While the
  -- next document commits, retain this sample rather than briefly showing a
  -- server-only bar with a different scale and legend.
  let debugPanel ←
    if options.debug then
      let sample ← LeanRef.fromJSL (← Js.Tuple2.first debugSampleState)
      some <$> Session.renderDebugPanel options optionsSetter sample
    else
      pure none
  -- Retain the child element across shell-only updates. The revision covers the
  -- accepted response (including timing), identities and analysis/debug options;
  -- follow-cursor is the remaining content input. No document serialization or
  -- deep comparison is added to this boundary. React owns the memo's lifetime.
  let calculate ← Js.Function.ofLean0 do
    let debugSampleSetter ← Js.Tuple2.second debugSampleState
    let contentProps ← LeanRef.toJSL ({
      preview
      dependency := toString changes.revision
      changedIds
      identities := changes.identities
      blockCount := changes.blockCount?.getD 0
      followCursor := options.followCursor
      highlightChanges := options.highlightChanges
      diagnostics := options.debug
      inputChanged := changes.inputChanged
      timing? := if changes.inputChanged then timing? else none
      preparationMs := changes.preparationMs
      onCommit := Session.recordDebugSample debugSampleSetter
    } : Session.ContentProps)
    let nativeContentProps ← Props.WithData.make contentProps
    Node.functionComponent contentComponent nativeContentProps (← js#[])
  let contentDeps ← js#[
    Js.erase contentComponent, Js.erase (← JsValue.ofString (toString changes.revision)),
    Js.erase (← JsValue.ofBool options.followCursor)]
  let content ← Hooks.useMemo calculate contentDeps
  let version := document?.map (·.version) |>.getD 0
  let correlationId := document?.map (·.correlationId) |>.getD ""
  let focus :=
    if options.followCursor then document?.bind (·.focus)
    else none
  let status := match preview with
    | .loading _ => "loading"
    | .unavailable _ => "unavailable"
    | .ready _ => "ready"
    | .error _ => "error"
  let headerChildren := #[label, config] ++ debugPanel.toArray
  let attributes ← js%{
    "data-verso-render-mode" := (← JsValue.ofString (if options.debug then "debug" else "document")),
    "data-verso-preview-status" := (← JsValue.ofString status),
    "data-verso-version" := (← JsValue.ofString (toString version)),
    "data-verso-correlation-id" := (← JsValue.ofString correlationId),
    "data-verso-changed-block-count" := (← JsValue.ofString (toString changedIds.size)),
    "data-verso-focus-block" := (← JsValue.ofString (focus.getD ""))
  }
  renderShell stylesheet attributes headerChildren content

/-- Runtime-owned immutable initial values and presentation are created once,
not converted again on every render. Each mount still owns separate React state;
updates replace these values and never mutate the shared initial objects. -/
private def createSession (clock : RuntimeM Float := pure 0)
    (mathComponent? : Option (FunctionComponent Props) := none) :
    RuntimeM (Preview → Option Session.ResponseTiming → ReactM (Js Node)) := do
  let stylesheet ← ComponentStyle.createStylesheet
  let content ← Session.createContentComponent clock mathComponent?
  let initialOptions ← LeanRef.toJSL Session.Options.initial
  let initialSample ← LeanRef.toJSL Session.DebugSample.initial
  let initialChanges ← LeanRef.toJSL ({} : ChangeState)
  pure fun preview timing? =>
    renderSession stylesheet content initialOptions initialSample initialChanges clock preview timing?

/--
Create once per runtime and reuse this native React component type. Prop updates
retain options and diagnostics; only unmounting resets them. Both component types
are created outside render, so parent rerenders never remount the content.
-/
def createComponent : RuntimeM (FunctionComponent (Props.WithData Preview)) := do
  let render ← createSession
  FunctionComponent.ofLean fun props => do
    render (← LeanRef.fromJSL (← Props.WithData.data props)) none

/-- Explicit optional clock, supplied by the experimental demo only. -/
def createTimedComponent (clock : RuntimeM Float)
    (mathComponent? : Option (FunctionComponent Props) := none) :
    RuntimeM (FunctionComponent (Props.WithData Session.Input)) := do
  let render ← createSession clock mathComponent?
  FunctionComponent.ofLean fun props => do
    let input ← LeanRef.fromJSL (← Props.WithData.data props)
    render input.preview input.timing?

/-- Explicit native props shared by interpreted and compiled document components.
Timing numbers use the same browser clock; undefined means no observation.
No decoded document or Lean reference crosses the runtime boundary. -/
structure EncodedDocumentProps where
  document : Js String
  requestedMs : Js.UndefinedOr Float
  receivedMs : Js.UndefinedOr Float
  notifiedMs : Js.UndefinedOr Float

/-- Native backend boundary: `document` is the existing Document.encode String.
Create this type once and let React retain its controls and identity state.
Only native JS props cross runtimes; decoded documents and Lean refs belong to
the runtime executing this component. Math remains an explicit native component.
RPC timing is optional native metadata, separate from the document codec. -/
def createEncodedDocumentComponent
    (mathComponent? : Option (FunctionComponent Props) := none)
    (clock? : Option (RuntimeM Float) := none) :
    RuntimeM (FunctionComponent EncodedDocumentProps) := do
  let clock := clock?.getD (pure 0)
  let render ← createSession clock mathComponent?
  FunctionComponent.ofLean fun props => do
    let encoded ← js_field% props "document"
    let calculate ← Js.Function.ofLean0 do
      let source ← JsValue.toString encoded
      let preview := match Document.decode source with
        | .ok document => Preview.ready document
        | .error message => Preview.error message
      LeanRef.toJSL preview
    let deps ← js#[Js.erase encoded]
    let preview ← LeanRef.fromJSL (← Hooks.useMemo calculate deps)
    let timing? ← match clock? with
      | none => pure none
      | some clock => do
        let requested ← js_field% props "requestedMs"
        let received ← js_field% props "receivedMs"
        let notified ← js_field% props "notifiedMs"
        -- Separate from decoding: a new request can return an unchanged String.
        -- Retain this timestamp across control and post-commit shell renders.
        let observe ← Js.Function.ofLean0 do
          let timing? ← match (← Js.UndefinedOr.toOption requested),
              (← Js.UndefinedOr.toOption received) with
            | some requested, some received => do
              let notified? ← match ← Js.UndefinedOr.toOption notified with
                | none => pure none
                | some value => some <$> JsValue.toFloat value
              pure (some {
                requestedMs := ← JsValue.toFloat requested
                receivedMs := ← JsValue.toFloat received
                decodedMs := ← clock
                notifiedMs? := notified?
              } : Option Session.ResponseTiming)
            | _, _ => pure none
          LeanRef.toJSL timing?
        let deps ← js#[Js.erase encoded, Js.erase requested, Js.erase received, Js.erase notified]
        LeanRef.fromJSL (← Hooks.useMemo observe deps)
    render preview timing?

end VersoBlueprint.Experimental.VirPreview
