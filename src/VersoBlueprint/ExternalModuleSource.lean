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

/-- Read a module-table entry without allocating the projected names array. -/
def moduleNameAt? (env : Environment) (idx : ModuleIdx) : Option Name :=
  env.header.modules[idx.toNat]?.map (·.module)

/-- Resolve the owner of a checked declaration. An invalid imported index
must not turn an imported declaration into a current-module declaration. -/
def moduleNameForDecl? (env : Environment) (name : Name) : Option Name :=
  match env.getModuleIdxFor? name with
  | some idx => moduleNameAt? env idx
  | none => if env.mainModule.isAnonymous then none else some env.mainModule

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
  let some mod := moduleNameAt? env idx | return none
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

/-- Read the selected artifact's source input and compare its Lake text hash.
Callers that replay an already admitted selection separately check exact bytes. -/
def verifiedSource (env : Environment) (idx : ModuleIdx) : IO (Except String (Owner × String)) := do
  let some owner ← find? env idx
    | return .error "The imported module has no matching Lake source input and output artifact"
  try
    let text ← IO.FS.readFile owner.path
    unless Lake.Hash.ofText text == owner.textHash do
      return .error "Owning source differs from the text input of the compiled module"
    return .ok (owner, text)
  catch _ =>
    return .error "Cannot read the compiled module's owning source"

end Informal.ExternalModuleSource
