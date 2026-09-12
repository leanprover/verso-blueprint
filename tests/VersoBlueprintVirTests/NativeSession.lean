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
  | _ => .ready (document 3 "Recovered preview")

@[vir_export]
def createComponent : RuntimeM (Js (Component Preview)) :=
  VersoBlueprint.Experimental.VirPreview.createComponent

@[vir_export]
def render (component : Js (Component Preview)) (scenario : Nat) : ReactM (Js Node) := do
  Node.component component (← LeanRef.toJSL (preview scenario))

end VersoBlueprintVirTests.NativeSession
