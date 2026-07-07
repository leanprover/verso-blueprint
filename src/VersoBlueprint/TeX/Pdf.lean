/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.PreviewManifest.Cli

namespace Informal.TeX.Pdf

open Verso (BuildLogT)

abbrev PdfOptions := Informal.PreviewManifest.PdfOptions

private def absolutePath (path : System.FilePath) : IO System.FilePath := do
  let path := path.normalize
  if path.isAbsolute then
    pure path
  else
    pure <| ((← IO.currentDir) / path).normalize

private def processOutputTail (text : String) (lineCount : Nat := 30) : String :=
  let text := text.trimAscii.toString
  if text.isEmpty then
    ""
  else
    let lines := text.splitOn "\n"
    String.intercalate "\n" <| lines.drop (lines.length - lineCount)

private def processFailureText (out : IO.Process.Output) : String :=
  let stdout := processOutputTail out.stdout
  let stderr := processOutputTail out.stderr
  match stdout.isEmpty, stderr.isEmpty with
  | true, true => ""
  | false, true => s!"stdout:\n{stdout}"
  | true, false => s!"stderr:\n{stderr}"
  | false, false => s!"stdout:\n{stdout}\nstderr:\n{stderr}"

private def compileArgs (pdfDir : System.FilePath) : Array String :=
  #[
    "-shell-escape",
    "-halt-on-error",
    "-interaction=nonstopmode",
    s!"-output-directory={pdfDir}",
    "main.tex"
  ]

private def texCacheEnv (cacheRoot : System.FilePath) : Array (String × Option String) :=
  #[
    ("TEXMFVAR", some s!"{cacheRoot / "var"}"),
    ("TEXMFCACHE", some s!"{cacheRoot / "cache"}"),
    ("TEXMFCONFIG", some s!"{cacheRoot / "config"}")
  ]

private def prepareTexCache (cacheRoot : System.FilePath) : IO Unit := do
  IO.FS.createDirAll (cacheRoot / "var")
  IO.FS.createDirAll (cacheRoot / "cache")
  IO.FS.createDirAll (cacheRoot / "config")

private def generatedFilenames : Array String :=
  #["main.pdf", "main.aux", "main.toc", "main.out", "main.log"]

private def removeGeneratedFileIfExists (path : System.FilePath) : BuildLogT IO Unit := do
  if ← path.pathExists then
    if ← path.isDir then
      Verso.reportError s!"Refusing to remove directory at generated PDF output path {path}"
    else
      IO.FS.removeFile path

private def clearGeneratedFiles (pdfDir : System.FilePath) : BuildLogT IO Unit := do
  for filename in generatedFilenames do
    removeGeneratedFileIfExists (pdfDir / filename)

private def compilePass
    (opts : PdfOptions)
    (texDir pdfDir cacheRoot : System.FilePath)
    (pass : Nat)
    (verbose : Bool) : BuildLogT IO Bool := do
  let args := compileArgs pdfDir
  prepareTexCache cacheRoot
  if verbose then
    IO.println s!"Building PDF pass {pass}: {opts.engine} {String.intercalate " " args.toList}"
  try
    let out ← IO.Process.output { cmd := opts.engine, args, cwd := texDir, env := texCacheEnv cacheRoot }
    if out.exitCode == 0 then
      if verbose then
        let stdout := out.stdout.trimAscii.toString
        unless stdout.isEmpty do
          IO.println stdout
      pure true
    else
      let details := processFailureText out
      let suffix := if details.isEmpty then "" else s!"\n{details}"
      Verso.reportError s!"PDF build failed on pass {pass} with exit code {out.exitCode}.{suffix}"
      pure false
  catch err =>
    Verso.reportError s!"PDF build failed to start `{opts.engine}`: {err}"
    pure false

def compile (opts : PdfOptions) (cfg : Verso.Genre.Manual.Config) : BuildLogT IO Unit := do
  let destination ← absolutePath cfg.destination
  let texDir := destination / "tex"
  let texPath := texDir / "main.tex"
  unless ← texPath.pathExists do
    Verso.reportError s!"PDF build requested, but TeX output is missing at {texPath}"
    return
  let pdfDir := destination / "pdf"
  IO.FS.createDirAll pdfDir
  clearGeneratedFiles pdfDir
  let cacheRoot := destination / "tex-cache"
  for pass in [1:opts.runs + 1] do
    unless ← compilePass opts texDir pdfDir cacheRoot pass cfg.verbose do
      return
  let pdfPath := pdfDir / "main.pdf"
  if ← pdfPath.pathExists then
    if cfg.verbose then
      IO.println s!"Saved PDF to {pdfPath}"
  else
    Verso.reportError s!"PDF build completed, but expected output is missing at {pdfPath}"

end Informal.TeX.Pdf
