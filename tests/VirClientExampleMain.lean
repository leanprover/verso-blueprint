/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Data.Json
import VersoBlueprintVirClientTests.Program
import VersoBlueprintVirClientTests.Resources

/-- Publish the minimal client and native results for comparison in JavaScript. -/
def main (args : List String) : IO Unit := do
  let [output] := args
    | throw <| IO.userError "usage: vir-client-example OUTPUT"
  let directory := System.FilePath.mk output
  let site ← IO.ofExcept <|
    (VersoBlueprintVirClientTests.resources.forSite "lib/vir").mapError reprStr
  unless site.programManifests.size == 1 do
    throw <| IO.userError "the client example requires exactly one program"
  for file in site.files do
    let path := directory / file.path
    IO.FS.createDirAll (path.parent.getD directory)
    IO.FS.writeBinFile path file.bytes
  let inputs := #["", "FLT", "Fermat’s Last Theorem", "Προεπισκόπηση 🦀"]
  let cases := inputs.map fun input => Lean.Json.mkObj [
    ("input", Lean.toJson input),
    ("expected", Lean.toJson (VersoBlueprintVirClientTests.Program.title input))]
  let client := Lean.Json.mkObj [
    ("runtimeModule", Lean.toJson site.runtimeModule),
    ("runtimeManifest", Lean.toJson site.runtimeManifest),
    ("programManifest", Lean.toJson site.programManifests[0]!),
    ("entry", Lean.toJson (``VersoBlueprintVirClientTests.Program.title).toString),
    ("cases", Lean.Json.arr cases)]
  IO.FS.writeFile (directory / "client.json") client.compress
