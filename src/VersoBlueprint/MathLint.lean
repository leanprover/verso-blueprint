/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

open Lean

register_option verso.blueprint.math.lint : Bool := {
  defValue := true
  descr := "if true, run best-effort KaTeX validation for blueprint math via local node during elaboration; silently skip when node is unavailable"
}

namespace Informal.MathLint

inductive Mode
  | inline
  | display
deriving BEq, Repr

instance : ToJson Mode where
  toJson
    | .inline => "inline"
    | .display => "display"

structure Payload where
  mode : Mode
  source : String
  texPrelude : String := ""
deriving ToJson, Repr

/--
Decoded-character span reported by KaTeX or derived from one of its UTF-16 spans.
-/
structure Span where
  start : Nat
  length : Nat
deriving Repr, BEq

/--
Location of a KaTeX failure after normalizing the loose JSON transport shape.

`katexInput` means "we know where the failure occurred in the exact string passed to KaTeX, but do
not have a source-relative span". Today this is mainly a defensive fallback, but keeping it explicit
preserves useful information if future mappings fail or if the transport becomes less structured.
-/
inductive Site where
  /-- The error was found while validating `texPrelude` in isolation. -/
  | prelude (span : Span)
  /-- The error can be attributed to the original math source, with the KaTeX-input span retained too. -/
  | source (source : Span) (katexInput : Span)
  /-- The error has only been located in the exact string passed to KaTeX. -/
  | katexInput (span : Span)
  /-- KaTeX rejected the input but did not give us a usable span. -/
  | unknown
deriving Repr, BEq

/-- Normalized failure returned by the Lean-side linter API. -/
structure Failure where
  /-- KaTeX's raw reason text, normalized for display in Lean warnings. -/
  reason : String
  /-- The most precise site information we could recover from KaTeX's offsets. -/
  site : Site
deriving Repr, BEq

/--
Loose JSON transport result returned by the Node checker.

This mirrors the script output rather than the public Lean API, so it may admit combinations that
are normalized away by `RawResult.toFailure`.
-/
private structure RawResult where
  ok : Bool
  message : String := ""
  position : Option Nat := none
  length : Option Nat := none
  sourcePosition : Option Nat := none
  sourceLength : Option Nat := none
  inPrelude : Bool := false
deriving FromJson, ToJson, Repr

/--
Package-relative location of the vendored KaTeX lint entrypoint.

The package root is either the repository checkout itself or the Lake dependency root under
`.lake/packages/VersoBlueprint`, so the script path must stay relative to that root rather than to
an external repository slug.
-/
private def katexLintScriptPath : System.FilePath :=
  "static-web" / "katex-lint.mjs"

private def versoKatexModulePath : System.FilePath :=
  "vendored-js" / "katex" / "katex.mjs"

private structure RuntimePaths where
  script : System.FilePath
  katexModule : System.FilePath

initialize runtimePathsRef : IO.Ref (Option (Option RuntimePaths)) ← IO.mkRef none

private abbrev WorkerChild := IO.Process.Child {
  stdin := .piped
  stdout := .piped
  stderr := .null
}

private structure Worker where
  child : WorkerChild

private inductive WorkerStatus where
  | notStarted
  | running (worker : Worker)
  | unavailable
deriving Inhabited

initialize workerStatusRef : IO.Ref WorkerStatus ← IO.mkRef .notStarted
initialize lintCacheRef : IO.Ref (Std.HashMap String (Option Failure)) ← IO.mkRef {}
initialize lintRequestMutexRef : IO.Ref (Option Std.BaseMutex) ← IO.mkRef none

/--
Create the request mutex lazily: this module runs in Lean's interpreter during elaboration, where
a platform mutex cannot safely be allocated by the module initializer. `modifyGet` also ensures
that concurrent first requests converge on one mutex.
-/
private def lintRequestMutex : IO Std.BaseMutex := do
  if let some mutex ← lintRequestMutexRef.get then
    return mutex
  let fresh ← Std.BaseMutex.new
  lintRequestMutexRef.modifyGet fun
    | some mutex => (mutex, some mutex)
    | none => (fresh, some fresh)

private def withLintRequestMutex (action : IO α) : IO α := do
  let mutex ← lintRequestMutex
  mutex.lock
  try
    action
  finally
    mutex.unlock

private partial def findPackageAssetFrom
    (dir : System.FilePath) (assetPath : System.FilePath) : IO (Option System.FilePath) := do
  let candidate := dir / assetPath
  if ← candidate.pathExists then
    pure (some (← IO.FS.realPath candidate))
  else
    match dir.parent with
    | some parent =>
      if parent == dir then
        pure none
      else
        findPackageAssetFrom parent assetPath
    | none => pure none

/--
Locate a package-owned asset by starting from the module source or build output.

We first try the source tree from `LEAN_SRC_PATH`, then fall back to the compiled `.olean` path from
`LEAN_PATH`. Walking upward from either location lets us recover the package root in root checkouts,
linked worktrees, and dependency checkouts without assuming a specific Lake `packagesDir`.
-/
private def findPackageAsset (moduleName : Name) (assetPath : System.FilePath) : IO (Option System.FilePath) := do
  let srcSearchPath ← Lean.getSrcSearchPath
  let srcPath? ← srcSearchPath.findModuleWithExt "lean" moduleName
  if let some srcPath := srcPath? then
    let srcPath ← IO.FS.realPath srcPath
    if let some dir := srcPath.parent then
      if let some asset := ← findPackageAssetFrom dir assetPath then
        return some asset
  try
    let oleanPath ← Lean.findOLean moduleName
    let oleanPath ← IO.FS.realPath oleanPath
    let some dir := oleanPath.parent
      | return none
    findPackageAssetFrom dir assetPath
  catch _ =>
    pure none

/--
Resolve the external files needed by the KaTeX math linter.

These paths are resolved once per Lean process because they are stable for a given checkout.
-/
private def runtimePaths : IO (Option RuntimePaths) := do
  match ← runtimePathsRef.get with
  | some cached => pure cached
  | none =>
    let resolved ← do
      let some script ← findPackageAsset `VersoBlueprint.MathLint katexLintScriptPath
        | return none
      let some katexModule ← findPackageAsset `Verso.Output.Html.KaTeX versoKatexModulePath
        | return none
      pure (some { script, katexModule })
    runtimePathsRef.set (some resolved)
    pure resolved

def enabled (opts : Options) : Bool :=
  opts.get verso.blueprint.math.lint.name verso.blueprint.math.lint.defValue

private def mkSpan? (start? length? : Option Nat) : Option Span := do
  let start ← start?
  let length ← length?
  pure { start, length }

private def Site.sourceSpan? (site : Site) : Option Span :=
  match site with
  | .source src _katexInput => some src
  | _ => none

/--
Map a decoded span back onto the raw inline-code contents parsed by Verso.

We cannot recover the raw source slice with `offsetBy` alone because KaTeX reports positions in the
decoded string, while the original inline-code text may contain width-changing escapes. In Verso
inline code, only `\``, `\\`, and `\n` collapse to a single decoded character; ordinary TeX
backslashes like `\alpha` still occupy source text one-for-one.
-/
def inlineCodeRawRangeOfDecodedSpan? (rawSource : String) (span : Span) :
    Option (String.Pos.Raw × String.Pos.Raw) := Id.run do
  let stop := span.start + span.length
  let mut pos : String.Pos.Raw := 0
  let mut decodedIndex := 0
  let mut startPos? : Option String.Pos.Raw := if span.start == 0 then some pos else none
  let mut stopPos? : Option String.Pos.Raw := if stop == 0 then some pos else none
  while !pos.atEnd rawSource do
    if startPos?.isNone && decodedIndex == span.start then
      startPos? := some pos
    if stopPos?.isNone && decodedIndex == stop then
      stopPos? := some pos
    let c := pos.get rawSource
    let nextPos := pos.next rawSource
    if c == '\\' then
      if nextPos.atEnd rawSource then
        pos := nextPos
        decodedIndex := decodedIndex + 1
      else
        let escaped := nextPos.get rawSource
        if escaped == '`' || escaped == '\\' || escaped == 'n' then
          pos := nextPos.next rawSource
          decodedIndex := decodedIndex + 1
        else
          pos := nextPos
          decodedIndex := decodedIndex + 1
    else
      pos := nextPos
      decodedIndex := decodedIndex + 1
  if startPos?.isNone && decodedIndex == span.start then
    startPos? := some pos
  if stopPos?.isNone && decodedIndex == stop then
    stopPos? := some pos
  match startPos?, stopPos? with
  | some startPos, some stopPos => some (startPos, stopPos)
  | _, _ => none

private def RawResult.toFailure : RawResult → Failure
  | { message, position, length, inPrelude := true, .. } =>
    let katexInput? := mkSpan? position length
    {
      reason := message
      site := match katexInput? with
        | some span => .prelude span
        | none => .unknown
    }
  | { message, position, length, sourcePosition, sourceLength, inPrelude := false, .. } =>
    let katexInput? := mkSpan? position length
    let source? := mkSpan? sourcePosition sourceLength
    {
      reason := message
      site := match source?, katexInput? with
        | some source, some katexInput => .source source katexInput
        | some source, none => .source source source
        | none, some katexInput => .katexInput katexInput
        | none, none => .unknown
    }

private def startWorker (paths : RuntimePaths) : IO (Option Worker) := do
  try
    let child ← IO.Process.spawn {
      cmd := "node"
      args := #[paths.script.toString, "--worker", paths.katexModule.toString]
      stdin := .piped
      stdout := .piped
      stderr := .null
    }
    pure <| some { child }
  catch _ =>
    pure none

private def stopWorker (worker : Worker) : IO Unit := do
  try
    worker.child.kill
  catch _ =>
    pure ()
  try
    discard worker.child.wait
  catch _ =>
    pure ()

private def requestWorker (worker : Worker) (payloadJson : String) : IO (Option RawResult) := do
  if (← worker.child.tryWait).isSome then
    return none
  worker.child.stdin.putStr payloadJson
  worker.child.stdin.putStr "\n"
  worker.child.stdin.flush
  let line ← worker.child.stdout.getLine
  if line.isEmpty then
    return none
  let json ←
    match Json.parse line with
    | .ok json => pure json
    | .error _ => return none
  match fromJson? (α := RawResult) json with
  | .ok report => pure (some report)
  | .error _ => pure none

private def requestWithState
    (status : WorkerStatus) (payloadJson : String) : IO (WorkerStatus × Option RawResult) := do
  if let .unavailable := status then
    return (.unavailable, none)
  let some paths ← runtimePaths
    | return (.unavailable, none)
  let worker? ←
    match status with
    | .notStarted => startWorker paths
    | .running worker => pure (some worker)
    | .unavailable => pure none
  let some worker := worker?
    | return (status, none)
  let report? ←
    try
      requestWorker worker payloadJson
    catch _ =>
      pure none
  match report? with
  | some report =>
    pure (.running worker, some report)
  | none =>
    stopWorker worker
    pure (.unavailable, none)

/--
Runs the persistent Node+KaTeX checker synchronously and memoizes by payload.
Returning `none` means either "no error" or "linting unavailable"; callers treat both as non-fatal.
-/
def lint? (payload : Payload) : IO (Option Failure) := do
  let key := Json.compress (toJson payload)
  withLintRequestMutex do
    if let some cached := (← lintCacheRef.get)[key]? then
      return cached
    let (status, report?) ← requestWithState (← workerStatusRef.get) key
    workerStatusRef.set status
    let some report := report?
      | return none
    let result := if report.ok then none else some report.toFailure
    lintCacheRef.modify fun cache => cache.insert key result
    pure result

/-- Render the most precise span wording we have, preferring source-relative spans over KaTeX-input ones. -/
private def spanText? (label : String) (span? : Option Span) : Option MessageData :=
  match span? with
  | none => none
  | some { start, length := 0 } => some m!"{label} position {start + 1}"
  | some { start, length } => some m!"{label} span {start + 1}-{start + length}"

/-- Format the lint result as a short headline plus KaTeX's raw reason text. -/
def Failure.toMessageData (failure : Failure) : MessageData :=
  let (scope, whereText?) :=
    match failure.site with
    | .prelude span =>
      (" while processing `tex_prelude`", spanText? "prelude" (some span))
    | .source source _katexInput =>
      ("", spanText? "source" (some source))
    | .katexInput span =>
      ("", spanText? "KaTeX input" (some span))
    | .unknown =>
      ("", none)
  let header := match whereText? with
    | some whereText => m!"KaTeX rejected blueprint math{scope} at {whereText}."
    | none => m!"KaTeX rejected blueprint math{scope}."
  header ++ m!"\nReason: {failure.reason}"

end Informal.MathLint
