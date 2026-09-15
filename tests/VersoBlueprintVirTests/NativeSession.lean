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
def render (component : FunctionComponent (Props.WithData Preview)) (scenario : Nat) : ReactM (Js Node) := do
  let props ← Props.WithData.make (← LeanRef.toJSL (preview scenario))
  Node.functionComponent component props (← js#[])

end VersoBlueprintVirTests.NativeSession
