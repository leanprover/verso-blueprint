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

private def renderServerTiming (timing : ServerTiming) : ReactM (Js Node) := do
  let milliseconds := fun nanos : Nat => formatMs (nanos.toFloat / 1000000.0) ++ " ms"
  let phases := #[
    ("snapshot-wait", "Snapshot", "#4c9be8", timing.snapshotWaitNanos),
    ("checked-wait", "Checked", "#d99a32", timing.checkedWaitNanos),
    ("evaluation", "Document", "#42b89a", timing.evaluationNanos)
  ]
  let total := timing.preparationNanos
  let summary := "Server preparation · " ++ milliseconds total
  let segments ← phases.mapM fun (key, label, color, nanos) =>
    Node.spanWith #[Props.key key, Props.string "data-verso-phase" key,
      Props.string "data-verso-nanos" (toString nanos),
      Props.string "title" (label ++ ": " ++ milliseconds nanos),
      Props.stylePairs #[
        ("flexGrow", toString nanos), ("flexShrink", "0"), ("flexBasis", "0px"),
        ("minWidth", "0"), ("backgroundColor", color)
      ]] #[]
  let legend ← phases.mapM fun (key, label, color, nanos) => do
    let swatch ← Node.spanWith #[Props.ariaHidden true, Props.stylePairs #[
      ("display", "inline-block"), ("width", "8px"), ("height", "8px"),
      ("borderRadius", "2px"), ("backgroundColor", color)
    ]] #[]
    Node.spanWith #[Props.key key, Props.stylePairs #[
      ("display", "inline-flex"), ("alignItems", "center"), ("gap", "4px")
    ]] #[swatch, ← Node.text (← JsValue.ofString (label ++ " " ++ milliseconds nanos))]
  let label ← Node.pTextWith #[ComponentStyle.debugNote] summary
  let bar ← Node.divWith #[Props.id "vir-verso-server-bar", Props.role "img",
    Props.string "aria-label" (summary ++ "; " ++ String.intercalate ", "
      (phases.toList.map fun (_, label, _, nanos) => label ++ " " ++ milliseconds nanos)),
    Props.string "data-verso-total-nanos" (toString total),
    Props.stylePairs #[
      ("display", "flex"), ("width", "100%"), ("height", "12px"),
      ("overflow", "hidden"), ("borderRadius", "3px"),
      ("backgroundColor", "var(--vscode-editorWidget-background, #88888822)")
    ]] segments
  let legend ← Node.divWith #[Props.stylePairs #[
    ("display", "flex"), ("flexWrap", "wrap"), ("gap", "4px 12px"),
    ("marginTop", "5px"), ("fontSize", "0.85em")
  ]] legend
  Node.divWith #[Props.id "vir-verso-server-timings"] #[label, bar, legend]

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
        "Server timing was not supplied with this response."
    | some timing => renderServerTiming timing
  let note ← Node.pTextWith #[ComponentStyle.debugNote]
    "Server only: waits include scheduling; encoding and transport are excluded. Browser timing awaits VIR."
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
