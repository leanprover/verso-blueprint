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

/-- One session's previous input and its derived change flags, not a document format. -/
private structure ChangeState where
  input? : Option Preview := none
  lastDocument? : Option Document := none
  changedIds : Array String := #[]
  blockCount? : Option Nat := none
  revision : Nat := 0
  highlightChanges : Bool := Session.Options.initial.highlightChanges
  diagnostics : Bool := false
  inputChanged : Bool := false

private def useChangedBlockInfo
    (preview : Preview) (highlightChanges diagnostics : Bool) : ReactM ChangeState := do
  let initial ← LeanRef.toJSL ({} : ChangeState)
  let state ← StateTuple.toState (← Hooks.useState initial)
  let previous ← LeanRef.fromJSL state.value
  let inputChanged := previous.input? != some preview
  if !inputChanged && previous.highlightChanges == highlightChanges &&
      previous.diagnostics == diagnostics then
    return previous
  let document? := preview.document?
  let analyze := highlightChanges && document?.isSome &&
    (previous.blockCount?.isNone || previous.lastDocument? != document?)
  let (changedIds, blockCount?) :=
    if !highlightChanges then (#[], none)
    else if analyze then
      document?.map (fun document =>
        let (ids, count) := Renderer.changedBlockIdsAndCount previous.lastDocument? document
        (ids, some count)) |>.getD (#[], none)
    else (previous.changedIds, previous.blockCount?)
  let next := {
    input? := some preview
    lastDocument? := document?.or previous.lastDocument?
    changedIds
    blockCount?
    revision := previous.revision + 1
    highlightChanges
    diagnostics
    inputChanged
    : ChangeState
  }
  -- Guarded adjustment of this component's own state: React retries before
  -- rendering children. Unlike refs, this state participates in render replay.
  let value ← LeanRef.toJSL next
  State.set state value
  return next

private def renderSession (contentComponent : Js (Component Session.ContentProps))
    (preview : Preview) : ReactM (Js Node) := do
  let optionsState ← StateTuple.toState
    (← Hooks.useState (← LeanRef.toJSL Session.Options.initial))
  let options ← LeanRef.fromJSL optionsState.value
  let document? := preview.document?
  let changes ← useChangedBlockInfo preview options.highlightChanges options.debug
  let changedIds := if document?.isSome then changes.changedIds else #[]

  let debugSampleState ← StateTuple.toState
    (← Hooks.useState (← LeanRef.toJSL Session.DebugSample.initial))

  let label ← Node.pTextWith #[Props.id "vir-verso-label", ComponentStyle.label]
    "Verso React preview"
  let config ← Session.renderConfigPanel options optionsState
  -- Server durations already belong to the accepted response. Display them
  -- directly, without enabling diagnostic effects or taking another measurement.
  let timing ← Session.renderServerTiming (document?.bind (·.serverTiming?))
  let debugPanel ←
    if options.debug then
      some <$> Session.renderDebugPanel
        (← LeanRef.fromJSL debugSampleState.value)
    else
      pure none
  -- The optional debug panel changes the sibling position, not document identity.
  let contentProps ← LeanRef.toJSL ({
    preview
    dependency := toString changes.revision
    changedIds
    blockCount := changes.blockCount?.getD 0
    followCursor := options.followCursor
    highlightChanges := options.highlightChanges
    diagnostics := options.debug
    inputChanged := changes.inputChanged
    onCommit := Session.recordDebugSample debugSampleState
  } : Session.ContentProps)
  let content ← Node.keyedComponent contentComponent contentProps (← JsValue.ofString "document")
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
  Node.sectionWith #[
    Props.id "vir-verso-preview",
    Props.string "data-verso-render-mode" (if options.debug then "debug" else "document"),
    Props.string "data-verso-preview-status" status,
    Props.string "data-verso-version" (toString version),
    Props.string "data-verso-correlation-id" correlationId,
    Props.string "data-verso-changed-block-count" (toString changedIds.size),
    Props.string "data-verso-focus-block" (focus.getD ""),
    Props.role "region",
    Props.ariaLabel "Incremental Verso document preview",
    ComponentStyle.shell
  ] (#[label, config, timing] ++ debugPanel.toArray ++ #[content])

/--
Create once per runtime and reuse this native React component type. Prop updates
retain options and diagnostics; only unmounting resets them. Both component types
are created outside render, so parent rerenders never remount the content.
-/
def createComponent : RuntimeM (Js (Component Preview)) := do
  let content ← Session.createContentComponent
  Component.ofLean fun props => do renderSession content (← LeanRef.fromJSL props)

end VersoBlueprint.Experimental.VirPreview
