/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Vir.Browser
public import VersoBlueprintVir.Preview.Model
public import VersoBlueprintVir.Preview.Component.Style

public section

namespace VersoBlueprint.Experimental.VirPreview.Session

open Lean.Vir
open Lean.Vir.React
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

/-- Persistent options owned by one mounted preview session. -/
structure Options where
  followCursor : Bool := true
  debug : Bool := false
  highlightChanges : Bool := false
  timingTickMs : Nat := 0

namespace Options

def initial : Options := {}

end Options

/-- Browser-clock boundaries for one accepted reply. -/
structure ResponseTiming where
  requestedMs : Float
  receivedMs : Float
  decodedMs : Float
  notifiedMs? : Option Float := none
  deriving BEq

/-- Client-only React input; timing metadata never crosses the document codec. -/
structure Input where
  preview : Preview
  timing? : Option ResponseTiming := none

structure BrowserTiming where
  response : ResponseTiming
  preparationMs : Float
  renderMs : Float
  observedMs : Float

/-- Partition one RPC-to-effect interval. Reject inconsistent samples instead of
turning an overlapping phase into an inflated total through saturating subtraction.
The total is measured independently of the phase estimates. -/
def BrowserTiming.partition? (sample : BrowserTiming) (server : ServerTiming) :
    Option (Nat × Array Nat) := do
  let r := sample.response
  let start := r.notifiedMs?.getD r.requestedMs
  let values := #[start, r.requestedMs, r.receivedMs, r.decodedMs, sample.observedMs,
    sample.preparationMs, sample.renderMs]
  -- Ordered bounds also reject NaN/infinity and keep nanoseconds within UInt64.
  guard (values.all fun value => value >= 0 && value < 18446744073709.0)
  guard (start <= r.requestedMs && r.requestedMs <= r.receivedMs && r.receivedMs <= r.decodedMs &&
    r.decodedMs <= sample.observedMs)
  let nanos := fun ms : Float => (ms * 1000000).toUInt64.toNat
  let total := nanos (sample.observedMs - start)
  let dispatch := nanos (r.requestedMs - start)
  let rpc := nanos (r.receivedMs - r.requestedMs)
  let decode := nanos (r.decodedMs - r.receivedMs)
  let browser := nanos (sample.observedMs - r.decodedMs)
  let prepare := nanos sample.preparationMs
  let render := nanos sample.renderMs
  guard (server.preparationNanos <= rpc && prepare + render <= browser &&
    dispatch + rpc + decode + prepare + render <= total)
  pure (total, #[server.snapshotWaitNanos, server.checkedWaitNanos, server.evaluationNanos,
    rpc - server.preparationNanos, decode, prepare, render,
    total - dispatch - rpc - decode - prepare - render, dispatch])

/-- One coherent post-commit diagnostic observation. -/
structure DebugSample where
  sequence : Nat := 0
  status : String := "waiting"
  version : Nat := 0
  correlationId : String := ""
  serverTiming? : Option ServerTiming := none
  blockCount : Nat := 0
  changedCount : Nat := 0
  highlightChanges : Bool := Options.initial.highlightChanges
  inputChanged : Bool := false
  browserTiming? : Option BrowserTiming := none

namespace DebugSample

def initial : DebugSample := {}

/-- Control-only observations do not replace a completed response measurement. -/
def record (previous sample : DebugSample) : DebugSample :=
  { sample with
    sequence := previous.sequence + 1
    browserTiming? := if !sample.inputChanged && sample.correlationId == previous.correlationId &&
        sample.serverTiming? == previous.serverTiming? then
      sample.browserTiming?.or previous.browserTiming?
    else sample.browserTiming? }

end DebugSample

def formatMs (value : Float) : String :=
  let tenths := (value * 10.0).round.toUInt64.toNat
  s!"{tenths / 10}.{tenths % 10}"

def updateOptions
    (state : State (JSL Options))
    (update : Options → Options) : Browser.DomM Unit :=
  State.modify state fun previous => do
    LeanRef.toJSL (update (← LeanRef.fromJSL previous))

def recordDebugSample
    (state : State (JSL DebugSample))
    (sample : DebugSample) : Browser.DomM Unit :=
  State.modify state fun previous => do
    let previousSample ← LeanRef.fromJSL previous
    LeanRef.toJSL (previousSample.record sample)

private def renderToggle (id label : String) (checked : Bool)
    (onChange : Browser.DomM Unit) : ReactM (Js Node) := do
  let handler ← Callback.ofUnary fun (_ : Js Browser.Event) => onChange
  return ← <label htmlFor={(← JsValue.ofString id)}>
    <input id={(← JsValue.ofString id)} type="checkbox" checked={(← JsValue.ofBool checked)} onChange={handler}/>
    {Node.text (← JsValue.ofString (" " ++ label))}
  </label>

/-- Explicit scales keep successive responses comparable at the chosen zoom. -/
private def timingScales : Array Nat := #[0, 1, 10, 100, 1000]
private def timingTickPixels : Nat := 40

private def timingPixels (timingTickMs nanos : Nat) : Float :=
  nanos.toFloat / (timingTickMs * 1000000).toFloat * timingTickPixels.toFloat

/-- A readable 1–2–5 upper bound. Auto bars occupy 40–100% of the available
width instead of jumping between coarse fixed-pixel decade scales. -/
def autoRangeNanos (total : Nat) : Nat := Id.run do
  let mut unit := 100000
  for _ in [:20] do
    for factor in #[1, 2, 5] do
      if total <= factor * unit then return factor * unit
    unit := unit * 10
  return max total unit

private def renderTimingScale (options : Options) (state : State (JSL Options)) : ReactM (Js Node) := do
  let choices := timingScales.map fun tick => do
    return ← <option key={(← JsValue.ofString (toString tick))} value={(← JsValue.ofString (toString tick))}>
      {Node.text (← JsValue.ofString (if tick == 0 then "Auto" else s!"{tick} ms / tick"))}
    </option>
  let handler ← Callback.ofUnary fun (event : Js Browser.Event) => do
    let some value ← Js.Nullable.toOption (← Browser.Event.formValueNullable event) | return ()
    let value ← JsValue.toString value
    let some tick := timingScales.find? (fun tick => toString tick == value) | return ()
    updateOptions state fun current => { current with timingTickMs := tick }
  return ← <label htmlFor="vir-verso-timing-scale" style={(← ComponentStyle.debugNote)}>
    Scale <select id="vir-verso-timing-scale" value={(← JsValue.ofString (toString options.timingTickMs))} onChange={handler}>
      {Js.Array.ofArray (α := Node) (← choices.mapM id)}
    </select>
  </label>

private def renderServerTiming (timingTickMs : Nat) (timing? : Option ServerTiming)
    (browser? : Option BrowserTiming) : ReactM (Js Node) := do
  let some timing := timing? |
    return ← <p id="vir-verso-server-timings" style={(← ComponentStyle.debugNote)}>Server timing unavailable</p>
  let milliseconds := fun nanos : Nat => formatMs (nanos.toFloat / 1000000.0) ++ " ms"
  let serverPhases := #[
    ("snapshot-wait", "Snapshot wait", "#4c9be8", timing.snapshotWaitNanos),
    ("checked-wait", "Checks wait", "#d99a32", timing.checkedWaitNanos),
    ("evaluation", "Evaluate / locate focus", "#42b89a", timing.evaluationNanos)
  ]
  let partition? := browser?.bind (·.partition? timing)
  let fromEdit := browser?.any fun (b : BrowserTiming) => b.response.notifiedMs?.isSome
  let phases : Array (String × String × String × Nat) := match partition? with
    | none => serverPhases
    | some (_, durations) =>
      (if fromEdit then
        #[("dispatch", "Notification / dispatch", "#63806b", durations[8]!)] else #[]) ++
      serverPhases ++ #[
        ("rpc-remainder", "Encode / transport / scheduling", "#8995a6", durations[3]!),
        ("decode", "Reply → decoded / scheduling", "#a678cf", durations[4]!),
        ("prepare", "Identity / change preparation", "#df7861", durations[5]!),
        ("render", "Build React elements", "#30a6b0", durations[6]!),
        ("commit", "React / effects / scheduling", "#c79351", durations[7]!)
      ]
  let total := partition?.map (·.1) |>.getD timing.preparationNanos
  let automatic := timingTickMs == 0
  let range := autoRangeNanos total
  let tickNanos := if automatic then range / 10 else timingTickMs * 1000000
  let summary := (if partition?.isSome then
      if fromEdit then "Edit notification → content effect "
      else "RPC → content effect "
    else "RPC server only ") ++ milliseconds total
  let boundary := if partition?.isSome then
      if fromEdit then
        "Includes notification-to-dispatch. Keystroke-to-notification, startup and paint are not measured."
      else "Cursor/initial/refresh RPC; excludes earlier edit processing, startup and paint."
    else if browser?.isSome then
      "Browser sample inconsistent; showing server phases only."
    else
      "Browser timing unavailable. RPC waits are not total elaboration time; encoding and rendering are excluded."
  let segments : Array (ReactM (Js Node)) := phases.map fun (key, label, color, nanos) => do
    let style ← js%{
      "width" := (← JsValue.ofString (if automatic then
        s!"{if total == 0 then 0 else nanos.toFloat / total.toFloat * 100}%"
        else s!"{timingPixels timingTickMs nanos}px")),
      "flexShrink" := (← js#"0"), "minWidth" := (← js#"0"), "backgroundColor" := (← JsValue.ofString color)
    }
    return ← <span key={(← JsValue.ofString key)} data-verso-phase={(← JsValue.ofString key)}
      data-verso-nanos={(← JsValue.ofString (toString nanos))} title={(← JsValue.ofString (label ++ ": " ++ milliseconds nanos))}
      style={style}/>
  let legends : Array (ReactM (Js Node)) := phases.map fun (key, label, color, nanos) => do
    let style ← js%{ "display" := (← js#"inline-flex"), "alignItems" := (← js#"center"), "gap" := (← js#"4px") }
    let swatchStyle ← js%{
      "display" := (← js#"inline-block"), "width" := (← js#"8px"), "height" := (← js#"8px"),
      "borderRadius" := (← js#"2px"), "backgroundColor" := (← JsValue.ofString color)
    }
    return ← <span key={(← JsValue.ofString key)} title={(← JsValue.ofString (label ++ ": " ++ milliseconds nanos))} style={style}>
      <span aria-hidden={(← JsValue.ofBool true)} style={swatchStyle}/>{Node.text (← JsValue.ofString (label ++ " " ++ milliseconds nanos))}
    </span>
  let ariaLabel := summary ++ "; " ++ String.intercalate ", "
    (phases.toList.map fun (_, label, _, nanos) => label ++ " " ++ milliseconds nanos)
  let barStyle ← js%{
    "display" := (← js#"flex"), "width" := (← JsValue.ofString (if automatic then
      s!"{total.toFloat / range.toFloat * 100}%" else s!"{timingPixels timingTickMs total}px")),
    "height" := (← js#"12px")
  }
  let trackStyle ← js%{
    "width" := (← JsValue.ofString (if automatic then "100%" else "max-content")),
    "minWidth" := (← js#"100%"), "paddingBottom" := (← js#"5px"),
    "backgroundImage" := (← JsValue.ofString s!"repeating-linear-gradient(to right, var(--vscode-descriptionForeground,#888) 0px, var(--vscode-descriptionForeground,#888) 1px, transparent 1px, transparent {if automatic then "10%" else s!"{timingTickPixels}px"})")
  }
  let scrollStyle ← js%{ "overflowX" := (← js#"auto"), "minWidth" := (← js#"0") }
  let legendStyle ← js%{
    "display" := (← js#"flex"), "flexWrap" := (← js#"wrap"), "gap" := (← js#"4px 12px"),
    "marginTop" := (← js#"5px"), "fontSize" := (← js#"0.85em")
  }
  return ← <div id="vir-verso-server-timings" style={(← js%{ "minWidth" := (← js#"0") })}>
    <p style={(← ComponentStyle.debugNote)}
      title="Server waits include remaining elaboration and scheduling, not pure CPU time. The endpoint is the content passive effect, not paint. RPC remainder is encoding, transport and scheduling together; its displayed position is schematic. Earlier editor work before the observed notification is not measured.">
      {Node.text (← JsValue.ofString summary)}
    </p>
    <p id="vir-verso-timing-boundary" style={(← ComponentStyle.debugNote)}>{Node.text (← JsValue.ofString boundary)}</p>
    <div id="vir-verso-server-scale" style={scrollStyle}
      title={(← JsValue.ofString s!"{milliseconds tickNanos} / tick") }><div style={trackStyle}>
      <div id="vir-verso-server-bar" role="img" aria-label={(← JsValue.ofString ariaLabel)}
        data-verso-start-ms={(← JsValue.ofString (browser?.map (fun b => toString (b.response.notifiedMs?.getD b.response.requestedMs)) |>.getD ""))}
        data-verso-effect-ms={(← JsValue.ofString (browser?.map (fun b => toString b.observedMs) |>.getD ""))}
        data-verso-total-nanos={(← JsValue.ofString (toString total))} data-verso-tick-ms={(← JsValue.ofString (toString timingTickMs))}
        data-verso-range-nanos={(← JsValue.ofString (if automatic then toString range else ""))}
        style={barStyle}>{Js.Array.ofArray (α := Node) (← segments.mapM id)}</div>
    </div></div>
    <p style={(← ComponentStyle.debugNote)}>{Node.text (← JsValue.ofString s!"{milliseconds tickNanos} / tick")}</p>
    <div style={legendStyle}>{Js.Array.ofArray (α := Node) (← legends.mapM id)}</div>
  </div>

def renderConfigPanel (options : Options) (state : State (JSL Options)) : ReactM (Js Node) := do
  return ← <fieldset key="config" id="vir-verso-config" style={(← ComponentStyle.configPanel)}
    data-verso-follow-cursor={(← JsValue.ofString (toString options.followCursor))}
    data-verso-debug-enabled={(← JsValue.ofString (toString options.debug))}
    data-verso-highlight-changes={(← JsValue.ofString (toString options.highlightChanges))}>
    <legend style={(← ComponentStyle.configLegend)}>Preview options</legend>
    {renderToggle "vir-verso-follow-cursor" "Follow cursor" options.followCursor
      (updateOptions state fun current => { current with followCursor := !current.followCursor })}
    {renderToggle "vir-verso-debug" "Debug details" options.debug
      (updateOptions state fun current => { current with debug := !current.debug })}
    {renderToggle "vir-verso-highlight-changes" "Highlight changes (debug)" options.highlightChanges
      (updateOptions state fun current => { current with highlightChanges := !current.highlightChanges })}
  </fieldset>

def renderDebugPanel (options : Options) (state : State (JSL Options))
    (sample : DebugSample) : ReactM (Js Node) := do
  let timing? := sample.serverTiming?
  let analysis := if sample.highlightChanges then
    s!"{sample.blockCount} analyzed nodes · {sample.changedCount} changed"
    else "change analysis skipped"
  return ← <aside key="debug" id="vir-verso-debug-panel" data-verso-debug="true"
    data-verso-debug-browser-timing={(← JsValue.ofString (match sample.browserTiming? with
      | none => "unavailable"
      | some browser => if (timing?.bind (browser.partition?)).isSome then "demo-clock" else "invalid"))}
    style={(← ComponentStyle.debugPanel)}
    data-verso-debug-status={(← JsValue.ofString sample.status)}
    data-verso-debug-new-input={(← JsValue.ofString (toString sample.inputChanged))}
    data-verso-debug-highlight-changes={(← JsValue.ofString (toString sample.highlightChanges))}
    data-verso-debug-snapshot-effects={(← JsValue.ofString (toString sample.sequence))}
    data-verso-debug-version={(← JsValue.ofString (toString sample.version))}
    data-verso-debug-correlation-id={(← JsValue.ofString sample.correlationId)}
    data-verso-debug-block-count={(← JsValue.ofString (if sample.highlightChanges then toString sample.blockCount else "skipped"))}
    data-verso-debug-changed-block-count={(← JsValue.ofString (toString sample.changedCount))}>
    {renderTimingScale options state}
    {renderServerTiming options.timingTickMs timing? sample.browserTiming?}
    <p style={(← ComponentStyle.debugDetails)}>{Node.text (← JsValue.ofString s!"{sample.status} · editor v{sample.version} · {analysis}")}</p>
  </aside>

end VersoBlueprint.Experimental.VirPreview.Session
