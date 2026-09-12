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
  timingTickMs : Nat := 1

namespace Options

def initial : Options := {}

end Options

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

/-- Explicit scales keep successive responses comparable at the chosen zoom. -/
private def timingScales : Array Nat := #[1, 10, 100, 1000]
private def timingTickPixels : Nat := 40

private def timingPixels (timingTickMs nanos : Nat) : Float :=
  nanos.toFloat / (timingTickMs * 1000000).toFloat * timingTickPixels.toFloat

private def renderTimingScale (options : Options) (state : State (JSL Options)) : ReactM (Js Node) := do
  let choices ← timingScales.mapM fun tick => do
    Node.elementWith "option" #[Props.key (toString tick), Props.string "value" (toString tick)]
      #[← Node.text (← JsValue.ofString s!"{tick} ms / tick")]
  let select ← Node.elementWith "select" #[
    Props.id "vir-verso-timing-scale", Props.string "value" (toString options.timingTickMs),
    Props.onChange fun event => do
      let some value ← Js.Nullable.toOption (← Browser.Event.formValueNullable event) | return ()
      let value ← JsValue.toString value
      let some tick := timingScales.find? (fun tick => toString tick == value) | return ()
      updateOptions state fun current => { current with timingTickMs := tick }
  ] choices
  Node.elementWith "label" #[Props.htmlFor "vir-verso-timing-scale", ComponentStyle.debugNote]
    #[← Node.text (← JsValue.ofString "Scale "), select]

private def renderServerTiming (timingTickMs : Nat) (timing? : Option ServerTiming) : ReactM (Js Node) := do
  let some timing := timing? |
    Node.pTextWith #[Props.id "vir-verso-server-timings", ComponentStyle.debugNote]
      "Server timing unavailable"
  let milliseconds := fun nanos : Nat => formatMs (nanos.toFloat / 1000000.0) ++ " ms"
  let phases := #[
    ("snapshot-wait", "Snapshot", "#4c9be8", timing.snapshotWaitNanos),
    ("checked-wait", "Checked", "#d99a32", timing.checkedWaitNanos),
    ("evaluation", "Document", "#42b89a", timing.evaluationNanos)
  ]
  let total := timing.preparationNanos
  let summary := "Server " ++ milliseconds total
  let segments ← phases.mapM fun (key, label, color, nanos) =>
    Node.spanWith #[Props.key key, Props.string "data-verso-phase" key,
      Props.string "data-verso-nanos" (toString nanos),
      Props.string "title" (label ++ ": " ++ milliseconds nanos),
      Props.stylePairs #[
        ("width", s!"{timingPixels timingTickMs nanos}px"), ("flexShrink", "0"),
        ("minWidth", "0"), ("backgroundColor", color)
      ]] #[]
  let legend ← phases.mapM fun (key, label, color, nanos) => do
    let swatch ← Node.spanWith #[Props.ariaHidden true, Props.stylePairs #[
      ("display", "inline-block"), ("width", "8px"), ("height", "8px"),
      ("borderRadius", "2px"), ("backgroundColor", color)
    ]] #[]
    Node.spanWith #[Props.key key, Props.title (label ++ ": " ++ milliseconds nanos), Props.stylePairs #[
      ("display", "inline-flex"), ("alignItems", "center"), ("gap", "4px")
    ]] #[swatch, ← Node.text (← JsValue.ofString label)]
  let label ← Node.pTextWith #[ComponentStyle.debugNote,
    Props.title "Server preparation: snapshot wait, checked-environment wait, and document evaluation/cursor lookup. Includes scheduling; excludes encoding, transport and browser rendering."]
    summary
  let bar ← Node.divWith #[Props.id "vir-verso-server-bar", Props.role "img",
    Props.string "aria-label" (summary ++ "; " ++ String.intercalate ", "
      (phases.toList.map fun (_, label, _, nanos) => label ++ " " ++ milliseconds nanos)),
    Props.string "data-verso-total-nanos" (toString total),
    Props.string "data-verso-tick-ms" (toString timingTickMs),
    Props.stylePairs #[
      ("display", "flex"), ("width", s!"{timingPixels timingTickMs total}px"), ("height", "12px")
    ]] segments
  let track ← Node.divWith #[Props.stylePairs #[
    ("width", "max-content"), ("minWidth", "100%"), ("paddingBottom", "5px"),
    ("backgroundImage", s!"repeating-linear-gradient(to right, var(--vscode-descriptionForeground,#888) 0px, var(--vscode-descriptionForeground,#888) 1px, transparent 1px, transparent {timingTickPixels}px)")
  ]] #[bar]
  let track ← Node.divWith #[Props.id "vir-verso-server-scale", Props.stylePairs #[
    ("overflowX", "auto"), ("minWidth", "0")
  ]] #[track]
  let legend ← Node.divWith #[Props.stylePairs #[
    ("display", "flex"), ("flexWrap", "wrap"), ("gap", "4px 12px"),
    ("marginTop", "5px"), ("fontSize", "0.85em")
  ]] legend
  Node.divWith #[Props.id "vir-verso-server-timings", Props.stylePairs #[("minWidth", "0")]]
    #[label, track, legend]

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

def renderDebugPanel (options : Options) (state : State (JSL Options))
    (timing? : Option ServerTiming) (sample : DebugSample) : ReactM (Js Node) := do
  let scale ← renderTimingScale options state
  let timing ← renderServerTiming options.timingTickMs timing?
  let analysis := if sample.highlightChanges then
    s!"{sample.blockCount} analyzed nodes · {sample.changedCount} changed"
    else "change analysis skipped"
  let details ← Node.pTextWith #[ComponentStyle.debugDetails]
    s!"{sample.status} · editor v{sample.version} · {analysis}"
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
    Props.string "data-verso-debug-block-count" (if sample.highlightChanges then toString sample.blockCount else "skipped"),
    Props.string "data-verso-debug-changed-block-count" (toString sample.changedCount),
    ComponentStyle.debugPanel
  ] #[scale, timing, details]

end VersoBlueprint.Experimental.VirPreview.Session
