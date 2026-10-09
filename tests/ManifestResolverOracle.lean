/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprintRuntime.ManifestResolver
import Lean.Data.Json.Parser

public section

private def checkPrepared (source output : String) : IO Unit := do
  let .ok input := Lean.Json.parse source >>= Lean.fromJson? (α :=
      VersoBlueprint.Runtime.ManifestResolver.BatchInput) | return
  let .ok prepared := VersoBlueprint.Runtime.ManifestResolver.prepareManifest {
    abiVersion := input.abiVersion, manifest := input.manifest } | return
  let requests : VersoBlueprint.Runtime.ManifestResolver.RequestBatchInput := {
    abiVersion := input.abiVersion, requests := input.requests }
  let requestJson := (Lean.toJson requests).compress
  let resolve := VersoBlueprint.Runtime.ManifestResolver.resolvePreparedJson prepared
  unless resolve requestJson == output do
    throw <| IO.userError "Prepared lookup differs from batch lookup"
  for rejected in #["not json", (Lean.toJson { requests with abiVersion := requests.abiVersion + 1 }).compress] do
    let .ok result := Lean.Json.parse (resolve rejected) >>= Lean.fromJson? (α :=
        VersoBlueprint.Runtime.ManifestResolver.BatchOutput)
      | throw <| IO.userError "Malformed failure envelope"
    unless !result.ok && !result.error.isEmpty && result.results.isEmpty do
      throw <| IO.userError "Prepared lookup did not reject malformed request"
  unless resolve requestJson == output do
    throw <| IO.userError "Rejected requests damaged retained prepared index"

/-- Native correctness oracle for the shared browser conformance cases. -/
def main : IO Unit := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  repeat
    let source ← input.getLine
    if source.isEmpty then break
    let result := VersoBlueprint.Runtime.ManifestResolver.resolveBatchJson source
    checkPrepared source result
    output.putStrLn result
