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

private def useChangedBlockInfo (clock : RuntimeM Float)
    (preview : Preview) (timing? : Option Session.ResponseTiming)
    (highlightChanges diagnostics : Bool) : ReactM ChangeState := do
  let initial ← LeanRef.toJSL ({} : ChangeState)
  let state ← StateTuple.toState (← Hooks.useState initial)
  let previous ← LeanRef.fromJSL state.value
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
  State.set state value
  return next

private def renderSession (contentComponent : FunctionComponent (Props.WithData Session.ContentProps))
    (clock : RuntimeM Float) (preview : Preview)
    (timing? : Option Session.ResponseTiming := none) : ReactM (Js Node) := do
  let optionsState ← StateTuple.toState
    (← Hooks.useState (← LeanRef.toJSL Session.Options.initial))
  let options ← LeanRef.fromJSL optionsState.value
  let document? := preview.document?
  let changes ← useChangedBlockInfo clock preview timing? options.highlightChanges options.debug
  let changedIds := if document?.isSome then changes.changedIds else #[]

  let debugSampleState ← StateTuple.toState
    (← Hooks.useState (← LeanRef.toJSL Session.DebugSample.initial))

  let label ← <p key="label" id="vir-verso-label" style={(← ComponentStyle.label)}>Verso React preview</p>
  let config ← Session.renderConfigPanel options optionsState
  -- Show one completed observation, including its own server timing. While the
  -- next document commits, retain this sample rather than briefly showing a
  -- server-only bar with a different scale and legend.
  let debugPanel ←
    if options.debug then
      let sample ← LeanRef.fromJSL debugSampleState.value
      some <$> Session.renderDebugPanel options optionsState sample
    else
      pure none
  -- Retain the child element across shell-only updates. The revision covers the
  -- accepted response (including timing), identities and analysis/debug options;
  -- follow-cursor is the remaining content input. No document serialization or
  -- deep comparison is added to this boundary. React owns the memo's lifetime.
  let calculate ← MemoCalculation.ofLean do
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
      onCommit := Session.recordDebugSample debugSampleState
    } : Session.ContentProps)
    let nativeContentProps ← Props.WithData.make contentProps
    Node.functionComponent contentComponent nativeContentProps (← js#[])
  let contentDeps ← Hooks.DependencyList.ofArray #[
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
  renderShell attributes headerChildren content

/--
Create once per runtime and reuse this native React component type. Prop updates
retain options and diagnostics; only unmounting resets them. Both component types
are created outside render, so parent rerenders never remount the content.
-/
def createComponent : RuntimeM (FunctionComponent (Props.WithData Preview)) := do
  let content ← Session.createContentComponent
  FunctionComponent.ofLean fun props => do
    renderSession content (pure 0) (← LeanRef.fromJSL (← Props.WithData.data props))

/-- Explicit optional clock, supplied by the experimental demo only. -/
def createTimedComponent (clock : RuntimeM Float)
    (mathComponent? : Option (FunctionComponent Props) := none) :
    RuntimeM (FunctionComponent (Props.WithData Session.Input)) := do
  let content ← Session.createContentComponent clock mathComponent?
  FunctionComponent.ofLean fun props => do
    let input ← LeanRef.fromJSL (← Props.WithData.data props)
    renderSession content clock input.preview input.timing?

/-- Native backend boundary: `document` is the existing Document.encode String.
Create this type once and let React retain its controls and identity state.
Only native JS props cross runtimes; decoded documents and Lean refs belong to
the runtime executing this component. Math remains an explicit native component.
No RPC timing is supplied by this document-only boundary. -/
def createEncodedDocumentComponent
    (mathComponent? : Option (FunctionComponent Props) := none) :
    RuntimeM (FunctionComponent Props) := do
  let content ← Session.createContentComponent (pure 0) mathComponent?
  FunctionComponent.ofLean fun props => do
    let encoded ← Js.String.fromAny (← Js.Object.get props (← js#"document"))
    let calculate ← MemoCalculation.ofLean do
      let source ← JsValue.toString encoded
      let preview := match Document.decode source with
        | .ok document => Preview.ready document
        | .error message => Preview.error message
      LeanRef.toJSL preview
    let deps ← Hooks.DependencyList.ofArray #[Js.erase encoded]
    let preview ← LeanRef.fromJSL (← Hooks.useMemo calculate deps)
    renderSession content (pure 0) preview

end VersoBlueprint.Experimental.VirPreview
