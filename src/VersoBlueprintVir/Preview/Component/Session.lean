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

/-- Persistent options owned by one mounted preview session. -/
structure Options where
  followCursor : Bool := true
  debug : Bool := false
  highlightChanges : Bool := false
  debugExpanded : Bool := false

namespace Options

def initial : Options := {}

end Options

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
  let input ← Node.elementWith "input" #[Props.id id, Props.type "checkbox",
    Props.checked checked, Props.onChangeUnit onChange] #[]
  Node.elementWith "label" #[Props.htmlFor id] #[input, ← Node.text (← JsValue.ofString (" " ++ label))]

private def renderMetrics (id : String) (metrics : Array (String × String × String)) :
    ReactM (Js Node) := do
  let entries ← metrics.mapM fun (key, label, value) => do
    Node.spanWith #[Props.key key] #[← Node.text (← JsValue.ofString (label ++ ": " ++ value))]
  Node.divWith #[Props.id id, Props.stylePairs #[
    ("display", "flex"), ("flexWrap", "wrap"), ("gap", "4px 12px")]] entries

def renderConfigPanel
    (options : Options)
    (state : State (JSL Options)) : ReactM (Js Node) := do
  let legend ← Node.legendWith #[ComponentStyle.configLegend]
    #[← Node.text (← JsValue.ofString "Preview options")]
  let follow ← renderToggle "vir-verso-follow-cursor" "Follow cursor" options.followCursor
    (updateOptions state fun current => { current with followCursor := !current.followCursor })
  let debug ← renderToggle "vir-verso-debug" "Debug details" options.debug
    (updateOptions state fun current => { current with debug := !current.debug })
  let changes ← renderToggle "vir-verso-highlight-changes" "Highlight changes (debug)"
    options.highlightChanges (updateOptions state fun current => {
      current with highlightChanges := !current.highlightChanges })
  Node.fieldsetWith #[
    Props.id "vir-verso-config",
    Props.string "data-verso-follow-cursor" (toString options.followCursor),
    Props.string "data-verso-debug-enabled" (toString options.debug),
    Props.string "data-verso-highlight-changes" (toString options.highlightChanges),
    ComponentStyle.configPanel
  ] #[legend, follow, debug, changes]

private def renderDebugBody (sample : DebugSample) : ReactM (Js Node) := do
  let server ← match sample.serverTiming? with
    | none =>
      Node.pTextWith #[Props.id "vir-verso-server-timings", ComponentStyle.debugNote]
        "Server timing not recorded for this response. Enable it in the demo's RPC registration."
    | some timing => do
        let milliseconds := fun nanos : Nat => formatMs (nanos.toFloat / 1000000.0) ++ " ms"
        let timingBar ← renderMetrics "vir-verso-server-timings" #[
          ("preparation", "server preparation", milliseconds timing.preparationNanos),
          ("snapshot-wait", "terminal snapshot wait", milliseconds timing.snapshotWaitNanos),
          ("checked-wait", "checked environment wait", milliseconds timing.checkedWaitNanos),
          ("evaluation", "document evaluation", milliseconds timing.evaluationNanos)
        ]
        let note ← Node.pTextWith #[ComponentStyle.debugNote]
          "Server preparation ends before response encoding and transport. Waits include scheduling and remaining document work, not just finalization. Server tracing is configured by the demo, independently of this Debug checkbox."
        Node.divWith #[] #[timingBar, note]
  let note ← Node.pTextWith #[ComponentStyle.debugNote]
    "Browser timings and heap samples are pending VIR's native Performance API. Server timings above belong to the response, not to option toggles; they are not end-to-end latency."
  let analysis := if sample.highlightChanges then
    s!"{sample.blockCount} analyzed nodes · {sample.changedCount} changed"
    else "change analysis skipped"
  let details ← Node.pTextWith #[ComponentStyle.debugDetails]
    s!"{sample.status} · editor v{sample.version} · {analysis} · sample {sample.sequence}"
  Node.divWith #[ComponentStyle.debugBody] #[server, note, details]

def renderDebugPanel
    (options : Options)
    (state : State (JSL Options))
    (sample : DebugSample) : ReactM (Js Node) := do
  let summary :=
    if sample.sequence == 0 then
      "waiting for first commit"
    else
      s!"{sample.status} · editor v{sample.version} · sample {sample.sequence}"
  let disclosure ← Node.elementWith "button" #[
    Props.id "vir-verso-debug-disclosure", Props.type "button",
    Props.ariaExpanded options.debugExpanded,
    Props.string "aria-controls" "vir-verso-debug-details",
    Props.onClick (updateOptions state fun current => {
      current with debugExpanded := !current.debugExpanded })
  ] #[← Node.text (← JsValue.ofString ("Last render · " ++ summary))]
  let body ← if options.debugExpanded then do pure #[← renderDebugBody sample] else pure #[]
  let details ← Node.divWith #[Props.id "vir-verso-debug-details",
    Props.bool "hidden" (!options.debugExpanded)]
    body
  Node.asideWith #[
    Props.id "vir-verso-debug-panel",
    Props.string "data-verso-debug" "true",
    Props.string "data-verso-debug-status" sample.status,
    Props.string "data-verso-debug-browser-timing" "pending-upstream",
    Props.string "data-verso-debug-new-input" (toString sample.inputChanged),
    Props.string "data-verso-debug-highlight-changes" (toString sample.highlightChanges),
    Props.string "data-verso-debug-snapshot-effects" (toString sample.sequence),
    Props.string "data-verso-debug-version" (toString sample.version),
    Props.string "data-verso-debug-correlation-id" sample.correlationId,
    Props.string "data-verso-debug-server-preparation-nanos"
      (sample.serverTiming?.map (toString ∘ ServerTiming.preparationNanos) |>.getD "unavailable"),
    Props.string "data-verso-debug-block-count" (if sample.highlightChanges then toString sample.blockCount else "skipped"),
    Props.string "data-verso-debug-changed-block-count" (toString sample.changedCount),
    ComponentStyle.debugPanel
  ] #[disclosure, details]

end VersoBlueprint.Experimental.VirPreview.Session
