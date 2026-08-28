/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Vbp
import Lake.CLI.Actions
import Lake.Load.Workspace

open Lean
open System

namespace VersoBlueprint.Vbp.Main

private def buildUsageLine : String :=
  "lake exe vbp build [--output <dir>] [--pdf] [--verbose] [--serve] [--port <n>]"

private def mainCommandLines : List String := [
  "lake exe vbp discover",
  buildUsageLine,
  "lake exe vbp query [--site <dir>] <selector>",
  "lake exe vbp check [--site <dir>]"
]

private def defaultHelpLines : List String := [
  "build writes _out/site",
  "--pdf builds _out/site/pdf/main.pdf from the generated TeX",
  "--verbose shows Blueprint generation phase progress during build",
  "query and check read _out/site",
  "--serve serves the generated html-multi directory after a successful build",
  "--serve --port <n> serves on a fixed port"
]

private def buildOptionLines : List String := [
  "--output <dir>      Write generated output under <dir> instead of _out/site",
  "--pdf               Build _out/site/pdf/main.pdf from the generated TeX",
  "--pdf-engine <cmd>  Use <cmd> for PDF compilation",
  "--pdf-runs <n>      Run the PDF engine <n> times",
  "--verbose           Show Blueprint generation phase progress",
  "--serve             Serve the generated html-multi directory after build",
  "--port <n>          Serve on a fixed TCP port; requires --serve"
]

private def indentHelpLine (line : String) : String :=
  "  " ++ line

def helpText : String := String.intercalate "\n" <|
  [
  "vbp - Verso Blueprint project helper",
  "",
  "Usage:"
  ] ++ mainCommandLines.map indentHelpLine ++ [
    "",
    "Query selectors:"
  ] ++ VersoBlueprint.Vbp.querySelectorLines.map indentHelpLine ++ [
    "",
    "Defaults:"
  ] ++ defaultHelpLines.map indentHelpLine

def buildHelpText : String := String.intercalate "\n" <|
  [
  "vbp build - build a Verso Blueprint site",
  "",
  "Usage:",
  indentHelpLine buildUsageLine,
  "",
  "Options:"
  ] ++ buildOptionLines.map indentHelpLine

private def printJson (json : Json) : IO Unit :=
  IO.println json.compress

private def firstToken? (text : String) : Option String :=
  text.trimAscii.toString.splitOn " " |>.filter (!·.isEmpty) |>.head?

def conventionalGeneratorFiles (packageName : String) : Array FilePath :=
  #[FilePath.mk s!"{packageName}Main.lean", FilePath.mk "Main.lean", FilePath.mk "BlueprintMain.lean"]

def generatorModuleFromFile (path : FilePath) : String :=
  let text := path.toString
  let text :=
    if text.endsWith ".lean" then
      (text.dropEnd ".lean".length).toString
    else
      text
  text.replace "/" "."

private structure GeneratorContext where
  workspace : Lake.Workspace
  generatorFile : FilePath

/--
Resolve Lake relative to the Lean installation selected for the project.

Unlike the `lake` executable, `vbp` is built inside the project, so Lake cannot
discover a co-located Lean installation from `IO.appPath`. In an Elan toolchain,
`LAKE_HOME` can also name Lean's sysroot, whose Lake layout is represented by
`LakeInstall.ofLean` rather than the standalone Lake build layout.
-/
private def findLakeInstallForLean
    (leanInstall : Lake.LeanInstall) : BaseIO (Option Lake.LakeInstall) := do
  if let some home ← IO.getEnv "LAKE_HOME" then
    let home := FilePath.mk home
    if home == leanInstall.sysroot then
      return some <| Lake.LakeInstall.ofLean leanInstall
    else
      return some { home }
  let colocatedLake := leanInstall.binDir / Lake.lakeExe
  if ← colocatedLake.pathExists then
    return some <| Lake.LakeInstall.ofLean leanInstall
  Lake.findLakeInstall?

private def loadWorkspace : IO (Except String Lake.Workspace) := do
  let cwd ← IO.currentDir
  let elanInstall? ← Lake.findElanInstall?
  let leanInstall? ← Lake.findLeanInstall?
  let some leanInstall := leanInstall?
    | pure (.error "could not detect a Lean installation")
  let lakeInstall? ← findLakeInstallForLean leanInstall
  let some lakeInstall := lakeInstall?
    | pure (.error "could not detect the configuration of the Lake installation")
  match ← (Lake.Env.compute lakeInstall leanInstall elanInstall?).toBaseIO with
  | .error err => pure (.error err)
  | .ok lakeEnv =>
      let config : Lake.LoadConfig := {
        lakeEnv,
        wsDir := cwd,
        updateToolchain := false
      }
      match ← (Lake.loadWorkspace config).toBaseIO with
      | some workspace => pure (.ok workspace)
      | none => pure (.error "could not load Lake workspace")

private def lineImportModule? (line : String) : Option String :=
  let line := line.trimAscii.toString
  if line.startsWith "import " then
    firstToken? ((line.drop "import ".length).toString)
  else
    none

private def docModule? (text : String) : Option String :=
  text.splitOn "\n" |>.findSome? fun line =>
    match line.splitOn "%doc " with
    | _ :: after :: _ =>
      firstToken? (after.replace ")" " ")
    | _ => none

private def topLevelBlueprintModule? (cwd generator : FilePath) : IO (Option String) := do
  if !(← (cwd / generator).pathExists) then
    pure none
  else
    let text ← IO.FS.readFile (cwd / generator)
    pure <|
      docModule? text <|>
        (text.splitOn "\n" |>.filterMap lineImportModule? |>.find? (·.endsWith ".Blueprint"))

private def pathString (path : FilePath) : String :=
  path.toString

private def rootLeanFiles (cwd : FilePath) : IO (Array FilePath) := do
  let mut files := #[]
  for entry in ← cwd.readDir do
    let name := entry.path.fileName.getD ""
    if name != "lakefile.lean" && name.endsWith ".lean" then
      files := files.push (FilePath.mk name)
  pure <| files.qsort (fun left right => pathString left < pathString right)

private def looksLikeBlueprintGenerator (cwd file : FilePath) : IO Bool := do
  try
    let text ← IO.FS.readFile (cwd / file)
    pure <|
      text.contains "def main" &&
        (text.contains "blueprintMain" || text.contains "PreviewManifest")
  catch _ =>
    pure false

private partial def firstGeneratorLikeFile? (cwd : FilePath) : List FilePath → IO (Option FilePath)
  | [] => pure none
  | file :: rest => do
      if ← looksLikeBlueprintGenerator cwd file then
        pure (some file)
      else
        firstGeneratorLikeFile? cwd rest

private def findGeneratorFile? (cwd : FilePath) (packageName : String) : IO (Option FilePath) := do
  match ← firstGeneratorLikeFile? cwd (conventionalGeneratorFiles packageName).toList with
  | some file => pure (some file)
  | none =>
      let rootFiles ← rootLeanFiles cwd
      firstGeneratorLikeFile? cwd rootFiles.toList

private def generatorContext : IO (Except String GeneratorContext) := do
  let cwd ← IO.currentDir
  match ← loadWorkspace with
  | .error err => pure (.error err)
  | .ok workspace =>
      let packageName := workspace.root.prettyName
      match ← findGeneratorFile? cwd packageName with
      | none =>
          let candidates :=
            String.intercalate ", " ((conventionalGeneratorFiles packageName).toList.map pathString)
          pure (.error s!"could not find a Blueprint generator entry point; expected one of {candidates} or a root-level Lean file with `def main` using VersoBlueprint.PreviewManifest")
      | some generatorFile =>
          pure (.ok {
            workspace,
            generatorFile
          })

private def chapterCandidates (cwd : FilePath) (packageName? : Option String) : IO (Array String) := do
  match packageName? with
  | none => pure #[]
  | some packageName =>
      let dir := cwd / packageName / "Chapters"
      if !(← dir.pathExists) then
        pure #[]
      else
        try
          let mut chapters := #[]
          for entry in ← dir.readDir do
            let pathText := entry.path.toString
            if pathText.endsWith ".lean" then
              chapters := chapters.push (pathString (FilePath.mk packageName / "Chapters" / entry.path.fileName.getD ""))
          pure <| chapters.qsort (· < ·)
        catch _ =>
          pure #[]

def discover : IO UInt32 := do
  let cwd ← IO.currentDir
  let context? ← generatorContext
  let (packageName?, generator?, discoveryErrors) :=
    match context? with
    | .ok context =>
        (some context.workspace.root.prettyName, some context.generatorFile, #[])
    | .error err => (none, none, #[err])
  let generatorModule? := generator?.map generatorModuleFromFile
  let topLevel? ←
    match generator? with
    | none => pure none
    | some generator => topLevelBlueprintModule? cwd generator
  let chapters ← chapterCandidates cwd packageName?
  let manifestPath ← VersoBlueprint.Vbp.manifestPathForSite VersoBlueprint.Vbp.defaultSite
  let cachePath ← VersoBlueprint.Vbp.htmlCachePathForSite VersoBlueprint.Vbp.defaultSite
  printJson <| VersoBlueprint.Vbp.responseJson [
    ("projectRoot", Json.str cwd.toString),
    ("packageName", packageName?.map Json.str |>.getD Json.null),
    ("generatorModule", generatorModule?.map Json.str |>.getD Json.null),
    ("generator", generator?.map (Json.str ∘ pathString) |>.getD Json.null),
    ("topLevelBlueprintModuleGuess", topLevel?.map Json.str |>.getD Json.null),
    ("defaultOutput", Json.str VersoBlueprint.Vbp.defaultOutput.toString),
    ("manifest", Json.str manifestPath.toString),
    ("htmlCache", Json.str cachePath.toString),
    ("chapterCandidateGuesses", Json.arr (chapters.map Json.str)),
    ("discoveryErrors", Json.arr (discoveryErrors.map Json.str))
  ]
  pure 0

structure BuildOptions where
  output : FilePath := VersoBlueprint.Vbp.defaultOutput
  pdf : Bool := false
  pdfEngine? : Option String := none
  pdfRuns? : Option Nat := none
  verbose : Bool := false
  serve : Bool := false
  port? : Option Nat := none

private def maxTcpPort : Nat := 65535

private def parseTcpPort (raw : String) : Except String Nat :=
  match raw.toNat? with
  | some port =>
      if port <= maxTcpPort then
        .ok port
      else
        .error s!"invalid --port value '{raw}'; expected a TCP port between 0 and {maxTcpPort}"
  | none => .error s!"invalid --port value '{raw}'"

private def parsePositiveNatOption (option raw : String) : Except String Nat :=
  match raw.toNat? with
  | some n =>
      if n == 0 then
        .error s!"invalid {option} value '{raw}'; expected a positive integer"
      else
        .ok n
  | none => .error s!"invalid {option} value '{raw}'"

private partial def parseBuildOptionsCore : List String → BuildOptions → Except String BuildOptions
  | [], opts => .ok opts
  | "--output" :: dir :: args, opts => parseBuildOptionsCore args { opts with output := FilePath.mk dir }
  | "--output" :: [], _ => .error "missing value after --output"
  | arg :: args, opts =>
      if arg == Informal.PreviewManifest.pdfFlag then
        parseBuildOptionsCore args { opts with pdf := true }
      else if arg == Informal.PreviewManifest.pdfEngineFlag then
        match args with
        | engine :: more =>
            let engine := engine.trimAscii.toString
            if engine.isEmpty then
              .error s!"empty value after {Informal.PreviewManifest.pdfEngineFlag}"
            else
              parseBuildOptionsCore more { opts with pdf := true, pdfEngine? := some engine }
        | [] => .error s!"missing value after {Informal.PreviewManifest.pdfEngineFlag}"
      else if arg == Informal.PreviewManifest.pdfRunsFlag then
        match args with
        | raw :: more =>
            match parsePositiveNatOption Informal.PreviewManifest.pdfRunsFlag raw with
            | .ok runs => parseBuildOptionsCore more { opts with pdf := true, pdfRuns? := some runs }
            | .error err => .error err
        | [] => .error s!"missing value after {Informal.PreviewManifest.pdfRunsFlag}"
      else
        match arg, args with
        | "--verbose", args => parseBuildOptionsCore args { opts with verbose := true }
        | "--serve", args => parseBuildOptionsCore args { opts with serve := true }
        | "--port", raw :: args =>
            match parseTcpPort raw with
            | .ok port => parseBuildOptionsCore args { opts with port? := some port }
            | .error err => .error err
        | "--port", [] => .error "missing value after --port"
        | arg, _ => .error s!"unknown build option '{arg}'"

private def validateBuildOptions (opts : BuildOptions) : Except String BuildOptions :=
  if opts.port?.isSome && !opts.serve then
    .error "--port requires --serve"
  else
    .ok opts

def parseBuildOptions (args : List String) (opts : BuildOptions) : Except String BuildOptions :=
  match parseBuildOptionsCore args opts with
  | .ok opts => validateBuildOptions opts
  | .error err => .error err

structure SiteOptions where
  site : FilePath := VersoBlueprint.Vbp.defaultSite
  rest : List String := []

partial def parseSiteOptions : List String → SiteOptions → Except String SiteOptions
  | [], opts => .ok { opts with rest := opts.rest.reverse }
  | "--site" :: dir :: args, opts => parseSiteOptions args { opts with site := FilePath.mk dir }
  | "--site" :: [], _ => .error "missing value after --site"
  | arg :: args, opts => parseSiteOptions args { opts with rest := arg :: opts.rest }

private def runAttached (cmd : String) (args : Array String) : IO UInt32 := do
  let child ← IO.Process.spawn { cmd, args }
  child.wait

private def runGenerator
    (context : GeneratorContext) (args : Array String) : IO UInt32 := do
  try
    let code ← context.workspace.evalLeanFile context.generatorFile args
    unless code == 0 do
      IO.eprintln s!"vbp build: generator run failed with exit code {code}: {context.generatorFile}"
    pure code
  catch err =>
    IO.eprintln s!"vbp build: generator run failed: {err}"
    pure 1

/--
Run a generator through Lake's Lean setup.

The raw environment-wrapped Lean interpreter form does not load package native
libraries such as MD4Lean. `Lake.Workspace.evalLeanFile` is the implementation
behind `lake lean`; it builds the generator's imports, constructs the required
module setup, and loads package native libraries while reusing the workspace
that VBP already loaded for project discovery.
-/
def generatorLeanArgs (generatorFile output : FilePath) (verbose : Bool) : Array String :=
  let args := #["--run", generatorFile.toString, "--output", output.toString]
  if verbose then
    args ++ #["--verbose"]
  else
    args

private def pdfGeneratorArgs (opts : BuildOptions) : Array String :=
  let args := if opts.pdf then #[Informal.PreviewManifest.pdfFlag] else #[]
  let args :=
    match opts.pdfEngine? with
    | some engine => args ++ #[Informal.PreviewManifest.pdfEngineFlag, engine]
    | none => args
  match opts.pdfRuns? with
  | some runs => args ++ #[Informal.PreviewManifest.pdfRunsFlag, toString runs]
  | none => args

private def generateSite (opts : BuildOptions) : IO UInt32 := do
  match ← generatorContext with
  | .error err =>
      IO.eprintln err
      pure 1
  | .ok context =>
      let args := generatorLeanArgs context.generatorFile opts.output opts.verbose ++ pdfGeneratorArgs opts
      runGenerator context args

private def serveScript : String := String.intercalate "\n" [
  "import functools, http.server, socketserver, sys",
  "mode = sys.argv[1]",
  "requested = int(sys.argv[2])",
  "directory = sys.argv[3]",
  "host = '127.0.0.1'",
  "ports = [requested] if mode == 'fixed' else [requested, 0]",
  "last_error = None",
  "for port in ports:",
  "    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)",
  "    try:",
  "        with socketserver.TCPServer((host, port), handler) as httpd:",
  "            actual = httpd.server_address[1]",
  "            print(f'Preview URL: http://{host}:{actual}/', flush=True)",
  "            httpd.serve_forever()",
  "    except OSError as exc:",
  "        last_error = exc",
  "        continue",
  "print(f'could not start preview server: {last_error}', file=sys.stderr)",
  "sys.exit(1)"
]

private def serve (output : FilePath) (port? : Option Nat) : IO UInt32 := do
  let htmlDir := output / "html-multi"
  if !(← htmlDir.pathExists) then
    IO.eprintln s!"missing generated HTML directory {htmlDir}; build did not produce html-multi output"
    pure 1
  else
    let mode := if port?.isSome then "fixed" else "auto"
    let port := port?.getD 8000
    runAttached "python3" #["-c", serveScript, mode, toString port, htmlDir.toString]

def build (args : List String) : IO UInt32 := do
  match args with
  | ["--help"] | ["-h"] | ["help"] =>
      IO.println buildHelpText
      pure 0
  | _ =>
      match parseBuildOptions args {} with
      | .error err =>
          IO.eprintln err
          pure 2
      | .ok opts =>
          let code ← generateSite opts
          if code != 0 then
            pure code
          else if opts.serve then
            serve opts.output opts.port?
          else
            pure 0

def query (args : List String) : IO UInt32 := do
  match parseSiteOptions args {} with
  | .error err =>
      IO.eprintln err
      pure 2
  | .ok opts =>
      match VersoBlueprint.Vbp.parseQueryPlan opts.rest with
      | .error err =>
          IO.eprintln err
          pure 2
      | .ok none =>
          printJson VersoBlueprint.Vbp.querySelectorsJson
          pure 0
      | .ok (some plan) =>
          try
            let manifest ← VersoBlueprint.Vbp.readManifestForQuery opts.site plan
            printJson (plan.run manifest)
            pure 0
          catch err =>
            IO.eprintln err.toString
            pure 1

def check (args : List String) : IO UInt32 := do
  match parseSiteOptions args {} with
  | .error err =>
      IO.eprintln err
      pure 2
  | .ok opts =>
      try
        let data ← VersoBlueprint.Vbp.readPersistedGeneratedData opts.site
        let errors := VersoBlueprint.Vbp.checkGeneratedData data
        printJson (VersoBlueprint.Vbp.checkJsonFromErrors data errors)
        if errors.isEmpty then pure 0 else pure 1
      catch err =>
        IO.eprintln err.toString
        pure 1

def main (args : List String) : IO UInt32 := do
  match args with
  | [] =>
      IO.println helpText
      pure 0
  | ["--help"] | ["-h"] | ["help"] =>
      IO.println helpText
      pure 0
  | "discover" :: rest =>
      match rest with
      | [] => discover
      | _ =>
          IO.eprintln "discover does not accept arguments"
          pure 2
  | "build" :: rest => build rest
  | "query" :: rest => query rest
  | "check" :: rest => check rest
  | cmd :: _ =>
      IO.eprintln s!"unknown command '{cmd}'"
      IO.eprintln helpText
      pure 2

end VersoBlueprint.Vbp.Main

def main (args : List String) : IO UInt32 :=
  VersoBlueprint.Vbp.Main.main args
