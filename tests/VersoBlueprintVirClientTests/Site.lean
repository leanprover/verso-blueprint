/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import Lean.Data.Json
public import Vir.Resources.Site

public section

/-- Publish one test program using upstream-owned runtime and resource URLs. -/
def VersoBlueprintVirClientTests.publishSite (resources : Vir.Resources.ResourceSet) (entry : String)
    (directory : System.FilePath) (fields : List (String × Lean.Json) := []) : IO Unit := do
  let site ← IO.ofExcept <| (resources.forSite "lib/vir").mapError reprStr
  unless site.programManifests.size == 1 do
    throw <| IO.userError "the client test requires exactly one program"
  for file in site.files do
    let path := directory / file.path
    IO.FS.createDirAll (path.parent.getD directory)
    IO.FS.writeBinFile path file.bytes
  let client := Lean.Json.mkObj <| [
    ("runtimeModule", Lean.toJson site.runtimeModule),
    ("runtimeManifest", Lean.toJson site.runtimeManifest),
    ("programManifest", Lean.toJson site.programManifests[0]!),
    ("entry", Lean.toJson entry)] ++ fields
  IO.FS.writeFile (directory / "client.json") client.compress
