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

/-- Client-only React input; timing metadata never crosses the document codec. -/
structure Input where
  preview : Preview
  timing? : Option ResponseTiming := none

structure BrowserTiming where
  response : ResponseTiming
  preparationMs : Float
  renderMs : Float
  observedMs : Float

/-- One coherent post-commit diagnostic observation. -/
structure DebugSample where
  sequence : Nat := 0
  status : String := "waiting"
  version : Nat := 0
  correlationId : String := ""
  blockCount : Nat := 0
  changedCount : Nat := 0
  highlightChanges : Bool := Options.initial.highlightChanges
  inputChanged : Bool := false
  browserTiming? : Option BrowserTiming := none

namespace DebugSample

def initial : DebugSample := {}

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
    LeanRef.toJSL {
      sample with sequence := previousSample.sequence + 1
    }

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
      {...choices}
    </select>
  </label>

private def renderServerTiming (timingTickMs : Nat) (timing? : Option ServerTiming)
    (browser? : Option BrowserTiming) : ReactM (Js Node) := do
  let some timing := timing? |
    return ← <p id="vir-verso-server-timings" style={(← ComponentStyle.debugNote)}>Server timing unavailable</p>
  let milliseconds := fun nanos : Nat => formatMs (nanos.toFloat / 1000000.0) ++ " ms"
  let serverPhases := #[
    ("snapshot-wait", "Snapshot", "#4c9be8", timing.snapshotWaitNanos),
    ("checked-wait", "Checked", "#d99a32", timing.checkedWaitNanos),
    ("evaluation", "Document", "#42b89a", timing.evaluationNanos)
  ]
  let nanos := fun ms : Float => (max 0 ms * 1000000).toUInt64.toNat
  let browser? := browser?.filter fun sample =>
    sample.response.requestedMs <= sample.response.receivedMs &&
    sample.response.receivedMs <= sample.response.decodedMs &&
    sample.response.decodedMs <= sample.observedMs &&
    timing.preparationNanos <= nanos (sample.response.receivedMs - sample.response.requestedMs)
  let phases := match browser? with
    | none => serverPhases
    | some sample =>
      let rpc := nanos (sample.response.receivedMs - sample.response.requestedMs)
      let decode := nanos (sample.response.decodedMs - sample.response.receivedMs)
      let prepare := nanos sample.preparationMs
      let render := nanos sample.renderMs
      let browser := nanos (sample.observedMs - sample.response.decodedMs)
      serverPhases ++ #[
        ("rpc-remainder", "Encode / transport / scheduling", "#8995a6", rpc - timing.preparationNanos),
        ("decode", "Decode", "#a678cf", decode),
        ("prepare", "Identity / change preparation", "#df7861", prepare),
        ("render", "Build React elements", "#30a6b0", render),
        ("commit", "React / effects / scheduling", "#c79351", browser - prepare - render)
      ]
  let total := phases.foldl (fun n (_, _, _, duration) => n + duration) 0
  let timingTickMs := if timingTickMs != 0 then timingTickMs
    else if total <= 10000000 then 1
    else if total <= 100000000 then 10
    else if total <= 1000000000 then 100 else 1000
  let summary := (if browser?.isSome then "Request → preview " else "Server ") ++ milliseconds total
  let segments := phases.map fun (key, label, color, nanos) => do
    let style ← js%{
      "width" := (← JsValue.ofString s!"{timingPixels timingTickMs nanos}px"),
      "flexShrink" := (← js#"0"), "minWidth" := (← js#"0"), "backgroundColor" := (← JsValue.ofString color)
    }
    return ← <span key={(← JsValue.ofString key)} data-verso-phase={(← JsValue.ofString key)}
      data-verso-nanos={(← JsValue.ofString (toString nanos))} title={(← JsValue.ofString (label ++ ": " ++ milliseconds nanos))}
      style={style}/>
  let legends := phases.map fun (key, label, color, nanos) => do
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
    "display" := (← js#"flex"), "width" := (← JsValue.ofString s!"{timingPixels timingTickMs total}px"), "height" := (← js#"12px")
  }
  let trackStyle ← js%{
    "width" := (← js#"max-content"), "minWidth" := (← js#"100%"), "paddingBottom" := (← js#"5px"),
    "backgroundImage" := (← JsValue.ofString s!"repeating-linear-gradient(to right, var(--vscode-descriptionForeground,#888) 0px, var(--vscode-descriptionForeground,#888) 1px, transparent 1px, transparent {timingTickPixels}px)")
  }
  let scrollStyle ← js%{ "overflowX" := (← js#"auto"), "minWidth" := (← js#"0") }
  let legendStyle ← js%{
    "display" := (← js#"flex"), "flexWrap" := (← js#"wrap"), "gap" := (← js#"4px 12px"),
    "marginTop" := (← js#"5px"), "fontSize" := (← js#"0.85em")
  }
  return ← <div id="vir-verso-server-timings" style={(← js%{ "minWidth" := (← js#"0") })}>
    <p style={(← ComponentStyle.debugNote)}
      title="Server waits include remaining elaboration and scheduling, not pure CPU time. Full-chain endpoint is the content passive effect, not paint. RPC remainder is encoding, transport and scheduling together; its displayed position is schematic. Editor work before RPC dispatch is outside this bar.">
      {Node.text (← JsValue.ofString summary)}
    </p>
    <div id="vir-verso-server-scale" style={scrollStyle}><div style={trackStyle}>
      <div id="vir-verso-server-bar" role="img" aria-label={(← JsValue.ofString ariaLabel)}
        data-verso-total-nanos={(← JsValue.ofString (toString total))} data-verso-tick-ms={(← JsValue.ofString (toString timingTickMs))}
        style={barStyle}>{...segments}</div>
    </div></div>
    <div style={legendStyle}>{...legends}</div>
  </div>

def renderConfigPanel (options : Options) (state : State (JSL Options)) : ReactM (Js Node) := do
  return ← <fieldset id="vir-verso-config" style={(← ComponentStyle.configPanel)}
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
    (timing? : Option ServerTiming) (sample : DebugSample) : ReactM (Js Node) := do
  let analysis := if sample.highlightChanges then
    s!"{sample.blockCount} analyzed nodes · {sample.changedCount} changed"
    else "change analysis skipped"
  return ← <aside id="vir-verso-debug-panel" data-verso-debug="true"
    data-verso-debug-browser-timing={(← JsValue.ofString (if sample.browserTiming?.isSome then "demo-clock" else "unavailable"))}
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
