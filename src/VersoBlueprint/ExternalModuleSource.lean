/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import Lean.Compiler.ModPkgExt
import Lake.Build.Common

/-! Resolve an imported source against its owning Lake build. The source path
alone can select a different checkout exporting the same Lean module. -/

namespace Informal.ExternalModuleSource
open Lean System

structure Owner where
  «module» : Name
  package : String
  path : FilePath
  textHash : Lake.Hash

private def ownerFromTrace? (env : Environment) (mod : Name) (pkg : String)
    (trace : FilePath) : IO (Option Owner) := do
  try
    let .ok metadata := Lake.BuildMetadata.parse (← IO.FS.readFile trace) | return none
    let inputs := metadata.inputs
    unless inputs.any (·.1 == s!"Module.name: {mod}") &&
        inputs.any (·.1 == s!"Package.id?: (some {pkg})") do return none
    let some outputs := metadata.outputs? | return none
    let .ok artifacts := outputs.getObjValAs? (Array String) "o" | return none
    let some artifact := artifacts[0]? | return none
    let expectedPath ← IO.FS.realPath (trace.withExtension "olean") |>.catchExceptions
      fun _ => pure (trace.withExtension "olean")
    -- Cache-in-place regions carry their content-addressed filename. Restored
    -- regions carry the conventional module filename alongside the trace.
    let matched ← env.header.regions.anyM fun region => do
      if region.filePath.fileName == some artifact then return true
      if region.filePath.fileName != expectedPath.fileName then return false
      if (← IO.FS.realPath region.filePath) != expectedPath then return false
      return s!"{← Lake.computeBinFileHash expectedPath}.olean" == artifact
    unless matched do return none
    let #[(path, digest)] := inputs.filter (fun (k, _) => (FilePath.mk k).extension == some "lean")
      | return none
    let .ok textHash := fromJson? (α := Lake.Hash) digest | return none
    let path := FilePath.mk path
    unless path.isAbsolute do return none
    return some { module := mod, package := pkg, path, textHash }
  catch _ => return none

/-- Find the source input of the imported artifact. When the library search
path contains several copies of a module, only a trace that matches the loaded
package and artifact can identify its owner. -/
def find? (env : Environment) (idx : ModuleIdx) : IO (Option Owner) := do
  let some mod := env.header.modules[idx.toNat]?.map (·.module) | return none
  let some pkg := env.getModulePackageByIdx? idx | return none
  let mut selected : Option Owner := none
  for root in ← searchPathRef.get do
    let trace := modToFilePath root mod "trace"
    if ← trace.pathExists then
      if let some owner ← ownerFromTrace? env mod pkg trace then
        if let some prior := selected then
          if prior.path != owner.path || prior.textHash != owner.textHash then return none
        selected := some owner
  return selected

end Informal.ExternalModuleSource
