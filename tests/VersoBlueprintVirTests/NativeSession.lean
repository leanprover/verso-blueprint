/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Component
meta import Vir.Attributes

public section

namespace VersoBlueprintVirTests.NativeSession

open Verso Verso.Doc Lean.Vir Lean.Vir.React
open VersoBlueprint.Experimental.VirPreview
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx

private def document (version : Nat) (text : String) : Document := {
  version
  correlationId := s!"native-session-{version}"
  focus := some "part-root-block-0"
  serverTiming? := some {
    snapshotWaitNanos := 1000000
    checkedWaitNanos := 2000000
    evaluationNanos := 3000000
  }
  document := .mk #[.text "Native preview session"] "Native preview session" none
    #[.para #[.text text], .other {
      name := `Informal.Block.informal
      data := Lean.toJson ({ label := `test, isProof := true, count := 0 } : Informal.BlockOccurrence)
    } #[.para #[.text "Retained informal proof"]]] #[]
}

/-- Test input is constructed in Lean, not a new JSON transport adapter. -/
private def preview (scenario : Nat) : Preview := match scenario with
  | 0 => .ready (document 1 "Before edit")
  | 1 => .ready (document 2 "After edit")
  | 2 => .loading "Document is being checked"
  | 3 => .unavailable "No document at cursor"
  | 4 => .error "Document RPC failed"
  | 6 => .ready { document 4 "Without timing" with serverTiming? := none }
  | 7 => .ready { document 5 "Zero timing" with serverTiming? := some {
      snapshotWaitNanos := 0, checkedWaitNanos := 0, evaluationNanos := 0 } }
  | 8 => .ready { document 6 "600 ms" with serverTiming? := some {
      snapshotWaitNanos := 100000000, checkedWaitNanos := 200000000, evaluationNanos := 300000000 } }
  | 9 => .ready { document 7 "1200 ms" with serverTiming? := some {
      snapshotWaitNanos := 200000000, checkedWaitNanos := 400000000, evaluationNanos := 600000000 } }
  | _ => .ready (document 3 "Recovered preview")

@[vir_export]
def createComponent : RuntimeM (FunctionComponent (Props.WithData Preview)) :=
  VersoBlueprint.Experimental.VirPreview.createComponent

@[vir_export]
def createEncodedDocumentComponent : RuntimeM (FunctionComponent EncodedDocumentProps) :=
  VersoBlueprint.Experimental.VirPreview.createEncodedDocumentComponent

@[vir_export]
def createTimedEncodedDocumentComponent : RuntimeM (FunctionComponent EncodedDocumentProps) :=
  VersoBlueprint.Experimental.VirPreview.createEncodedDocumentComponent none (some (pure 100))

/-- Demo-only binding until the matched upstream SDK supplies a browser clock. -/
@[vir_js "previewDemo.now"]
private opaque browserNow : RuntimeM (Js Float)

/-- The same factory for both backends, with explicit native math and clock.
Native components are passed unchanged; neither host reconstructs a document. -/
@[vir_export]
def createBrowserEncodedDocumentComponent (math : FunctionComponent Props) :
    RuntimeM (FunctionComponent EncodedDocumentProps) :=
  VersoBlueprint.Experimental.VirPreview.createEncodedDocumentComponent (some math)
    (some (do JsValue.toFloat (← browserNow)))

@[vir_export]
def encodedDocument (scenario : Nat) : String :=
  if scenario == 2 then "not JSON"
  else Document.encode (document (scenario + 1) (if scenario == 0 then "Before edit" else "After edit"))

/-- Exercise timing arithmetic through the browser runtime, without a mock codec. -/
@[vir_export]
def timingChecks (scenario : Nat) : Bool := Id.run do
  let server : ServerTiming := ⟨1000000, 2000000, 3000000⟩
  let sample : Session.BrowserTiming := {
    response := ⟨10, 20, 25, none⟩, preparationMs := 2, renderMs := 3, observedMs := 35
  }
  match scenario with
  | 0 => return sample.partition? server == some (25000000,
      #[1000000, 2000000, 3000000, 4000000, 5000000, 2000000, 3000000, 5000000, 0])
  | 1 => return ({ sample with preparationMs := 8 }.partition? server).isNone
  | 2 => return ({ sample with renderMs := 20 }.partition? server).isNone
  | 3 => return ({ sample with response := ⟨20, 10, 25, none⟩ }.partition? server).isNone
  | 4 => return (sample.partition? ⟨11000000, 0, 0⟩).isNone
  | 5 => return ({ sample with preparationMs := -1 }.partition? server).isNone
  | 6 => return ({ sample with observedMs := 0 / 0 }.partition? server).isNone
  | 7 => return ({ sample with observedMs := 1 / 0 }.partition? server).isNone
  | 8 =>
    let some (total, phases) := { sample with observedMs := 35.1234567 }.partition? server
      | return false
    return phases.foldl (· + ·) 0 == total && total == 25123456
  | 9 =>
    let zero : Session.BrowserTiming := ⟨⟨0, 0, 0, none⟩, 0, 0, 0⟩
    return zero.partition? ⟨0, 0, 0⟩ == some (0, Array.replicate 9 0)
  | 11 =>
    let some (total, phases) := { sample with response := ⟨10, 20, 25, some 7⟩ }.partition? server
      | return false
    return total == 28000000 && phases[8]! == 3000000 && phases.foldl (· + ·) 0 == total
  | 12 => return ({ sample with response := ⟨10, 20, 25, some 11⟩ }.partition? server).isNone
  | 13 => return Session.autoRangeNanos 6000000 == 10000000 &&
      Session.autoRangeNanos 11000000 == 20000000 &&
      Session.autoRangeNanos 21000000 == 50000000 &&
      Session.autoRangeNanos 1200000000 == 2000000000
  | 15 =>
    let initial := Session.DebugSample.initial.record {
      status := "ready", version := 1, correlationId := "initial", serverTiming? := some server }
    let edited := initial.record {
      status := "ready", version := 2, correlationId := "edit", serverTiming? := some server }
    let cursor := edited.record {
      status := "ready", version := 2, correlationId := "cursor", serverTiming? := some ⟨1, 0, 0⟩ }
    let loading := cursor.record { status := "loading", version := 3 }
    return initial.completedTiming?.any (!·.fromEdit) &&
      edited.completedTiming?.any (·.fromEdit) &&
      cursor.completedTiming?.any (fun c => c.version == 2 && c.correlationId == "edit" &&
        c.server == server) &&
      loading.completedTiming?.any (·.correlationId == "edit") && cursor.correlationId == "cursor"
  | _ =>
    let debug : Session.DebugSample := {
      correlationId := "same-position", serverTiming? := some server, browserTiming? := some sample }
    let control : Session.DebugSample := {
      correlationId := "same-position", serverTiming? := some server }
    return (debug.record control).browserTiming?.isSome &&
      (debug.record { control with inputChanged := true }).browserTiming?.isNone &&
      (debug.record { control with correlationId := "different-position" }).browserTiming?.isNone &&
      (debug.record { control with serverTiming? := none }).browserTiming?.isNone

@[vir_export]
def render (component : FunctionComponent (Props.WithData Preview)) (scenario : Nat) : ReactM (Js Node) := do
  let props ← Props.WithData.make (← LeanRef.toJSL (preview scenario))
  Node.functionComponent component props (← js#[])

/-- Deterministic browser-clock endpoint for coherent-sample acceptance. -/
@[vir_export]
def createTimedComponent : RuntimeM (FunctionComponent (Props.WithData Session.Input)) :=
  VersoBlueprint.Experimental.VirPreview.createTimedComponent (pure 100)

@[vir_export]
def renderTimed (component : FunctionComponent (Props.WithData Session.Input))
    (refresh : Nat) : ReactM (Js Node) := do
  let offset := refresh.toFloat * 10
  let props ← Props.WithData.make (← LeanRef.toJSL ({
    preview := preview 0
    timing? := some ⟨10 + offset, 20 + offset, 25 + offset, none⟩
  } : Session.Input))
  Node.functionComponent component props (← js#[])

end VersoBlueprintVirTests.NativeSession
