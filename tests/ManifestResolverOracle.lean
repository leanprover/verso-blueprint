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
  let expected := VersoBlueprint.Runtime.ManifestResolver.resolvePrepared prepared input.requests
  for request in input.requests, result in expected.results do
    if request.kind != .sourceMetadata then continue
    let source := (Lean.toJson request.value).compress
    let inspect := VersoBlueprint.Runtime.ManifestResolver.inspectSourceMetadataJson source
    let .ok initial := Lean.Json.parse (inspect "null") >>= Lean.fromJson? (α :=
        VersoBlueprint.Runtime.ManifestResolver.BatchOutput)
      | throw <| IO.userError "Malformed source inspection envelope"
    let entryJson := if initial.results[0]!.reason == "manifest-entry-missing" then
      (Lean.toJson result.manifestEntry).compress else "null"
    let .ok inspected := Lean.Json.parse (inspect entryJson) >>= Lean.fromJson? (α :=
        VersoBlueprint.Runtime.ManifestResolver.BatchOutput)
      | throw <| IO.userError "Malformed resolved-source envelope"
    unless inspected.ok && inspected.results.size == 1 do
      throw <| IO.userError s!"Source inspection failed: {inspected.error}"
    let actual := inspected.results[0]!
    unless (actual.ok, actual.key, actual.reason, actual.manifestEntry, actual.inputEntryIsNested) ==
        (result.ok, result.key, result.reason, result.manifestEntry, result.inputEntryIsNested) do
      throw <| IO.userError "Source inspection differs from indexed selection"
    let refs := fun (sources : Array VersoBlueprint.Runtime.ManifestResolver.ResolvedSource) =>
      sources.map fun source => (source.sourceRef, source.documentId, source.spans)
    unless refs actual.sources == refs result.sources do
      throw <| IO.userError "Source inspection differs from indexed reference normalization"

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
