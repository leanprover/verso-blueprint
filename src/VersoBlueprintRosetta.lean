/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.PreviewManifest
import VersoRosetta

namespace Informal
open Lean
open Verso.Genre.Manual
open PreviewManifest (parseRosettaBundleFilename rosettaBundleFlag)

private def parseBundleArg (options : List String) :
    Except String (Option System.FilePath × List String) := do
  match options.span (· != rosettaBundleFlag) with
  | (_, []) => return (none, options)
  | (before, _ :: rest) =>
    let (file, after) ← parseRosettaBundleFilename rest
    if after.contains rosettaBundleFlag then throw s!"{rosettaBundleFlag} may only be given once"
    return (some file, before ++ after)

/--
Render a Blueprint with optional saved Rosetta analysis. The generator supplies
the document and its captured model. The bundle enriches the document before
traversal, while the renderer uses the original model for Blueprint semantics.
-/
def blueprintMainWithRosetta (document : BlueprintDocument) (options : List String)
    (extensionImpls : ExtensionImpls := by exact extension_impls%)
    (config : RenderConfig := {}) (extraSteps : List PreviewManifest.BlueprintExtraStep := []) : IO UInt32 := do
  let (bundle?, options) ← match parseBundleArg options with
    | .ok parsed => pure parsed
    | .error message => IO.eprintln message; return 2
  let text ← match bundle? with
    | none => pure document.text
    | some path => do
      -- A resumed traversal already contains the document selected at save time.
      let resumes : EmitHtml → Bool
        | .resumeFrom _ => true
        | _ => false
      if resumes config.emitHtmlSingle || resumes config.emitHtmlMulti ||
          options.contains "--resume-html-single" || options.contains "--resume-html-multi" then
        IO.eprintln s!"{rosettaBundleFlag} requires a fresh HTML traversal"
        return 2
      try
        let raw ← IO.FS.readFile path
        let enriched := do
          let bundle ← Json.parse raw >>= fromJson? (α := Rosetta.Bundle)
          VersoRosetta.enrich bundle document.text
        IO.ofExcept enriched
      catch error =>
        IO.eprintln s!"Rosetta bundle {path}: {error}"
        return 1
  PreviewManifest.blueprintMainWithPreviewData text options extensionImpls config extraSteps
    (model := document.model)

end Informal
