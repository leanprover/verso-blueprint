/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintRosetta
import ReplayFixture.Blueprint

open Lean Rosetta
open Verso.Genre.Manual

private def fixtureBundle : IO Bundle := do
  let requests ← IO.ofExcept <| VersoRosetta.collect ReplayFixture.blueprintDocument.text
  let mut bundle : Bundle := { contexts := #[], requests := #[] }
  for request in requests do
    let diagnostic : Lsp.Diagnostic := {
      range := { start := ⟨0, 0⟩, «end» := ⟨0, 1⟩ }
      message := "Saved Rosetta fixture diagnostic"
    }
    let diagnostics := if request.kind == .code then #[diagnostic] else #[]
    bundle := { bundle with requests := bundle.requests.push {
      request, languageId := "fixture", tokens := .ok #[], diagnostics, queries := #[] } }
    unless bundle.contexts.any (·.key == request.context) do
      bundle := { bundle with contexts := bundle.contexts.push {
        key := request.context, languageId := "fixture", diagnosticCoverage := "Synthetic fixture"
        completion := .null, generatedDiagnostics := #[] } }
  return bundle

def main (args : List String) : IO UInt32 := do
  match args with
  | ["fixture-bundle", path] =>
    IO.FS.writeFile path (toJson (← fixtureBundle)).compress
    return 0
  | _ =>
    Informal.blueprintMainWithRosetta ReplayFixture.blueprintDocument args
      (config := { emitTeX := true })
