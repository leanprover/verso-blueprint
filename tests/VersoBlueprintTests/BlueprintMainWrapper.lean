/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.PreviewManifest
import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintMainWrapper

open Verso Genre Manual
open Verso.VersoBlueprintTests.Blueprint.Support

#docs (Manual) pdfSmokeDoc "PDF Smoke" :=
:::::::
This tiny document exercises PDF engine invocation.
:::::::

#docs (Manual) highlightedStartupPatchDoc "Highlighted Startup Patch" :=
:::::::
This tiny document exercises highlighted-code startup asset normalization.
:::::::

/-- info: true -/
#guard_msgs in
#eval
  let cfg : RenderConfig := {}
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  let jsFiles := cfg.toHtmlConfig.toHtmlAssets.extraJsFiles.toArray.map (·.filename)
  let cssFiles := cfg.toHtmlConfig.toHtmlAssets.extraCssFiles.toArray.map (·.filename)
  jsFiles.contains "popper.min.js" &&
    jsFiles.contains "tippy-bundle.umd.min.js" &&
    cssFiles.contains "tippy-border.css"

/-- info: true -/
#guard_msgs in
#eval
  let customJs : JS := "console.log('custom');"
  let cfg : RenderConfig := {
    toHtmlConfig := {
      extraJs := [customJs]
    }
  }
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  cfg.toHtmlConfig.extraJs.toArray.any (·.js.contains "custom")

/-- info: true -/
#guard_msgs in
#eval
  let cfg : RenderConfig := {}
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  cfg.toHtmlConfig.extraHead.any fun html =>
    let source := html.asString
    hasSubstr source "type=\"module\"" &&
      hasSubstr source "-verso-data/blueprint-page-runtime.mjs"

/-- info: true -/
#guard_msgs in
#eval
  let cfg : RenderConfig := {}
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  (cfg.toHtmlConfig.extraHead.filter fun html =>
    hasSubstr html.asString "-verso-data/blueprint-page-runtime.mjs").size == 1

/-- info: true -/
#guard_msgs in
#eval
  let cfg : RenderConfig := {}
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  cfg.toHtmlConfig.toHtmlAssets.extraCss.toArray.any fun css =>
    hasSubstr css.css ".bp_build_metadata"

/-- info: true -/
#guard_msgs in
#eval
  let metadata : Informal.PreviewManifest.BuildMetadata := {
    compiledAt := "2026-05-05T00:00:00Z"
    commit := "abc123"
    subject := "escape <tag> & message"
    projectRepositoryUrl := some "https://github.com/example/project"
    projectCommitUrl := some "https://github.com/example/project/commit/abc123full"
    leanToolchain := "leanprover/lean4:v4.30.0"
    blueprintVersion := "def456"
    blueprintRepositoryUrl := some "https://github.com/leanprover/verso-blueprint"
    blueprintCommitUrl := some "https://github.com/leanprover/verso-blueprint/commit/def456full"
    mathlibVersion := some "v4.30.0@789abc"
    mathlibRepositoryUrl := some "https://github.com/leanprover-community/mathlib4"
    mathlibCommitUrl := some "https://github.com/leanprover-community/mathlib4/commit/789abcfull"
    upstreamBlueprint := some {
      commit := "up987"
      subject := "upstream <msg> & more"
      repositoryUrl := some "https://github.com/example/upstream"
      commitUrl := some "https://github.com/example/upstream/commit/up987full"
    }
  }
  let input := "<html><body><div class=\"titlepage\"><h1>Example</h1><div class=\"authors\"></div></div></body></html>"
  let metadataHtml := Informal.PreviewManifest.buildMetadataHtmlString metadata
  match Informal.PreviewManifest.insertBuildMetadataHtml? input metadataHtml with
  | some out =>
      hasSubstr out "class=\"bp_build_metadata\"" &&
        hasSubstr out "2026-05-05T00:00:00Z" &&
        hasSubstr out "abc123" &&
        hasSubstr out "https://github.com/example/project" &&
        hasSubstr out "https://github.com/example/project/commit/abc123full" &&
        hasSubstr out "escape &lt;tag&gt; &amp; message" &&
        hasSubstr out "leanprover/lean4:v4.30.0" &&
        hasSubstr out "def456" &&
        hasSubstr out "https://github.com/leanprover/verso-blueprint/commit/def456full" &&
        hasSubstr out "up987" &&
        hasSubstr out "https://github.com/example/upstream" &&
        hasSubstr out "https://github.com/example/upstream/commit/up987full" &&
        hasSubstr out "upstream &lt;msg&gt; &amp; more" &&
        hasSubstr out "v4.30.0@789abc" &&
        hasSubstr out "https://github.com/leanprover-community/mathlib4/commit/789abcfull" &&
        appearsBefore out "<h1>Example</h1>" "class=\"bp_build_metadata\"" &&
        appearsBefore out "class=\"bp_build_metadata\"" "class=\"authors\""
  | none => false

private partial def freshBlueprintMainWrapperRoot (testName : String) : IO System.FilePath := do
  let suffix ← IO.rand 0 1000000000000
  let cwd ← IO.currentDir
  let root :=
    cwd / ".lake" / "build" / "tmp" /
      testName / toString suffix
  if ← root.pathExists then
    freshBlueprintMainWrapperRoot testName
  else
    pure root

private def freshPdfSmokeRoot : IO System.FilePath :=
  freshBlueprintMainWrapperRoot "verso-blueprint-pdf-smoke-test"

private def highlightedStartupWithoutTacticsJs : JS := r#"/* Render docstrings */
for (const d of document.querySelectorAll("code.docstring, pre.docstring")) {
  const str = d.innerText;
}
const defaultTippyProps = {
  allowHTML: true
};
"#

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let root ← freshBlueprintMainWrapperRoot "verso-blueprint-highlighted-startup-patch-test"
    let outDir := root / "site"
    let config : RenderConfig := Informal.PreviewManifest.withBlueprintAssets {
      toHtmlConfig := {
        extraJs := [highlightedStartupWithoutTacticsJs]
      }
    }
    let code ←
      Informal.PreviewManifest.blueprintMain
        highlightedStartupPatchDoc.toPart
        (extensionImpls := by exact extension_impls%)
        (options := [
          "--output", outDir.toString,
          "--without-html-single"
        ])
        (config := config)
    let html ← IO.FS.readFile (outDir / "html-multi" / "index.html")
    pure <|
      code == 0 &&
        hasSubstr html "const str = d.textContent || \"\";" &&
        !hasSubstr html "const str = d.innerText;"

private def fakePdfEngineScript : String := r#"#!/bin/sh
set -eu
outdir=""
for arg in "$@"; do
  case "$arg" in
    -output-directory=*) outdir="${arg#-output-directory=}" ;;
  esac
done
if [ -z "$outdir" ]; then
  echo "missing output directory" >&2
  exit 2
fi
printf '%s\n' "$@" > "$outdir/fake-engine-args.txt"
{
  printf '%s\n' "${TEXMFVAR:-}"
  printf '%s\n' "${TEXMFCACHE:-}"
  printf '%s\n' "${TEXMFCONFIG:-}"
} > "$outdir/fake-engine-env.txt"
{
  for name in main.pdf main.aux main.toc main.out main.log; do
    if [ -e "$outdir/$name" ]; then
      printf '%s\n' "$name"
    fi
  done
} > "$outdir/fake-stale-before.txt"
printf 'fake pdf\n' > "$outdir/main.pdf"
"#

private def writeFakePdfEngine (root : System.FilePath) : IO System.FilePath := do
  IO.FS.createDirAll root
  let engine := root / "fake-pdf-engine.sh"
  IO.FS.writeFile engine fakePdfEngineScript
  let chmod ← IO.Process.output { cmd := "chmod", args := #["+x", engine.toString] }
  unless chmod.exitCode == 0 do
    throw <| IO.userError s!"chmod failed: {chmod.stderr}"
  pure engine

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let root ← freshPdfSmokeRoot
    let engine ← writeFakePdfEngine root
    let outDir := root / "site"
    let runPdfBuild : IO UInt32 :=
      Informal.PreviewManifest.blueprintMain
        pdfSmokeDoc.toPart
        (extensionImpls := by exact extension_impls%)
        (options := [
          "--output", outDir.toString,
          "--without-html-single",
          "--without-html-multi"
        ])
        (pdfOptions := {
          enabled := true
          engine := engine.toString
          runs := 1
        })
    let code1 ← runPdfBuild
    let pdfDir := outDir / "pdf"
    IO.FS.writeFile (pdfDir / "main.aux") "stale aux"
    IO.FS.writeFile (pdfDir / "main.toc") "stale toc"
    IO.FS.writeFile (pdfDir / "main.out") "stale out"
    IO.FS.writeFile (pdfDir / "main.log") "stale log"
    let code2 ← runPdfBuild
    let argsLog ← IO.FS.readFile (pdfDir / "fake-engine-args.txt")
    let envLog ← IO.FS.readFile (pdfDir / "fake-engine-env.txt")
    let staleBeforeLog ← IO.FS.readFile (pdfDir / "fake-stale-before.txt")
    pure <|
      code1 == 0 &&
        code2 == 0 &&
        (← (pdfDir / "main.pdf").pathExists) &&
        !(← (pdfDir / "main.aux").pathExists) &&
        !(← (pdfDir / "main.toc").pathExists) &&
        !(← (pdfDir / "main.out").pathExists) &&
        !(← (pdfDir / "main.log").pathExists) &&
        (← (outDir / "tex" / "main.tex").pathExists) &&
        hasSubstr argsLog "-shell-escape" &&
        hasSubstr argsLog "-halt-on-error" &&
        hasSubstr argsLog s!"-output-directory={pdfDir}" &&
        hasSubstr argsLog "main.tex" &&
        hasSubstr envLog (outDir / "tex-cache" / "var").toString &&
        hasSubstr envLog (outDir / "tex-cache" / "cache").toString &&
        hasSubstr envLog (outDir / "tex-cache" / "config").toString &&
        staleBeforeLog.trimAscii.isEmpty

private def runHtmlCheck (action : EmitM (Option Informal.HtmlDocument))
    (impls : ExtensionImpls := ({} : Informal.RenderModel).withExtensions extension_impls%) :
    IO (Option Informal.HtmlDocument × Array String) := do
  let errors ← IO.mkRef (#[] : Array String)
  let logger : Verso.Logger IO := { (default : Verso.Logger IO) with
    log := fun severity message _ =>
      if severity == .error then errors.modify (·.push message) else pure () }
  let result ← action.run impls |>.run logger
  return (result, ← errors.get)

-- Completion means a stable document/state pair, not simply reaching the pass
-- limit. Logged errors also prevent admission even when the state is stable.
#eval show IO Unit from do
  let (missing, errors) ← runHtmlCheck
    (Informal.HtmlDocument.traverse .multi {} pdfSmokeDoc.toPart) extension_impls%
  unless missing.isNone && errors.any (hasSubstr · "Missing captured Blueprint") do
    throw <| IO.userError "HTML admission accepted a missing project capture"
  let (incomplete, errors) ← runHtmlCheck
    (Informal.HtmlDocument.traverse .multi { maxTraversals := 0 } pdfSmokeDoc.toPart)
  unless incomplete.isNone && errors.any (hasSubstr · "has not converged") do
    throw <| IO.userError "HTML admission accepted an incomplete traversal"
  let text := { pdfSmokeDoc.toPart with
    content := #[.other { name := `testUnstableHtml } #[]] }
  let impls := ({} : Informal.RenderModel).withExtensions extension_impls%
  let unstable := impls.insertBlock `testUnstableHtml {
    traverse := fun _ _ _ => do
      let _ ← freshId
      return none
    toHtml := none, toTeX := none }
  let (rejected, errors) ← runHtmlCheck
    (Informal.HtmlDocument.traverse .multi { maxTraversals := 3 } text) unstable
  unless rejected.isNone && errors.any (hasSubstr · "has not converged") do
    throw <| IO.userError "HTML admission accepted an unstable extension"
  let logging := impls.insertBlock `testUnstableHtml {
    traverse := fun _ _ _ => do
      Verso.reportError "synthetic traversal error"
      return none
    toHtml := none, toTeX := none }
  let (rejected, errors) ← runHtmlCheck (Informal.HtmlDocument.traverse .multi {} text) logging
  unless rejected.isNone && errors.any (· == "synthetic traversal error") do
    throw <| IO.userError "Stable traversal diagnostics did not prevent HTML admission"

-- The saved document and captured model remain authoritative. Resume can move
-- output and change logging, but cannot reinterpret an existing layout.
#eval show IO Unit from do
  let root ← freshBlueprintMainWrapperRoot "checked-html-checkpoint"
  IO.FS.createDirAll root
  let path := root / "checkpoint.json"
  let cfg : RenderConfig := { features := {}, htmlDepth := 2 }
  let model : Informal.RenderModel := {
    nodes := #[Informal.RenderNode.ofBlockData { label := `savedSnapshot, count := 0, owner := some `alice }] }
  let (some document, errors) ← runHtmlCheck
    (Informal.HtmlDocument.traverse .multi cfg pdfSmokeDoc.toPart)
    (model.withExtensions extension_impls%)
    | throw <| IO.userError "Could not create a completed HTML document"
  unless errors.isEmpty do throw <| IO.userError s!"Unexpected traversal errors: {errors}"
  document.save path
  let (some restored, errors) ← runHtmlCheck
    (Informal.HtmlDocument.load .multi { cfg with destination := root / "moved", verbose := true } path)
    extension_impls%
    | throw <| IO.userError "Could not resume with the saved project capture"
  unless errors.isEmpty && restored.text == document.text && restored.state == document.state do
    throw <| IO.userError "Checkpoint round trip changed the completed document/state"
  for maxTraversals in #[0, 1, cfg.maxTraversals + 1] do
    let (some resumed, errors) ← runHtmlCheck
      (Informal.HtmlDocument.load .multi { cfg with maxTraversals } path)
      extension_impls%
      | throw <| IO.userError "Resume rejected a changed traversal limit"
    unless errors.isEmpty && resumed.text == document.text && resumed.state == document.state do
      throw <| IO.userError "Changing the resume traversal limit changed the saved pair"
  for (mode, changed) in #[(Mode.single, cfg), (.multi, { cfg with htmlDepth := 1 }),
      (.multi, { cfg with draft := true }), (.multi, { cfg with features := {.KaTeX} })] do
    let (result, errors) ← runHtmlCheck (Informal.HtmlDocument.load mode changed path)
    unless result.isNone && errors.any (hasSubstr · "layout/configuration") do
      throw <| IO.userError "Resume accepted an incompatible layout/configuration"
  let checkpoint ← IO.FS.readFile path
  let .ok json := Lean.Json.parse checkpoint | throw <| IO.userError "Malformed test checkpoint"
  for (contents, diagnostic) in #[
      ("{", "Invalid Blueprint HTML checkpoint"),
      ((json.setObjVal! "version" (Lean.toJson (2 : Nat))).compress,
        "Unsupported Blueprint HTML checkpoint version 2")] do
    IO.FS.writeFile path contents
    let (result, errors) ← runHtmlCheck (Informal.HtmlDocument.load .multi cfg path)
    unless result.isNone && errors.any (hasSubstr · diagnostic) &&
        errors.any (hasSubstr · "regenerate") do
      throw <| IO.userError "Invalid checkpoint was accepted or lost its recovery diagnostic"
  let .ok saved := json.getObjVal? "saved" | throw <| IO.userError "Missing saved traversal"
  let corrupt := saved.setObjVal! "text" (Lean.toJson pdfSmokeDoc.toPart)
  IO.FS.writeFile path (json.setObjVal! "saved" corrupt).compress
  let (result, errors) ← runHtmlCheck (Informal.HtmlDocument.load .multi cfg path)
  unless result.isNone && errors.any (hasSubstr · "has not converged") do
    throw <| IO.userError "Resume accepted untraversed text paired with a completed state"
  (SavedState.mk document.text document.state).save path
  let (result, errors) ← runHtmlCheck (Informal.HtmlDocument.load .multi cfg path)
  unless result.isNone && errors.any (hasSubstr · "regenerate") do
    throw <| IO.userError "Resume accepted a legacy unbound checkpoint"

-- Resume must reject diagnostics even when the saved text/state remain a fixed
-- point under the current extension implementations.
#eval show IO Unit from do
  let text := { pdfSmokeDoc.toPart with content := #[.other { name := `resumeLogging } #[]] }
  let impls := (({} : Informal.RenderModel).withExtensions extension_impls%).insertBlock `resumeLogging {
    traverse := fun _ _ _ => pure none
    toHtml := none, toTeX := none }
  let (some document, errors) ← runHtmlCheck (Informal.HtmlDocument.traverse .multi {} text) impls
    | throw <| IO.userError "Could not prepare the resume diagnostic fixture"
  unless errors.isEmpty do throw <| IO.userError s!"Unexpected fixture errors: {errors}"
  IO.FS.withTempFile fun _ path => do
    document.save path
    let logging := impls.insertBlock `resumeLogging {
      traverse := fun _ _ _ => do
        Verso.reportError "synthetic resume error"
        return none
      toHtml := none, toTeX := none }
    let (result, errors) ← runHtmlCheck (Informal.HtmlDocument.load .multi {} path) logging
    unless result.isNone && errors == #["synthetic resume error"] do
      throw <| IO.userError "Stable resumed traversal errors did not prevent admission"

-- Exercise the public dispatcher: failed checks write no HTML/xrefs, and delayed
-- generation writes only a checkpoint. Resume uses the saved text and output
-- destination while post-render steps receive that same checked pair.
#eval show IO Unit from do
  let root ← freshBlueprintMainWrapperRoot "checked-html-dispatch"
  IO.FS.createDirAll root
  let path := root / "checkpoint.json"
  let cfg : RenderConfig := {
    features := {}
    destination := root / "delayed"
    emitHtmlSingle := .no
    emitHtmlMulti := .delay path }
  let (_, code) ← IO.FS.withIsolatedStreams <|
    Informal.PreviewManifest.blueprintMain pdfSmokeDoc.toPart (options := []) (config := cfg)
  unless code == 0 && (← path.pathExists) && !(← cfg.destination.pathExists) do
    throw <| IO.userError "Delayed HTML emitted output or failed to save a checkpoint"
  let output := root / "resumed"
  let seen ← IO.mkRef false
  let step : Informal.PreviewManifest.BlueprintExtraStep := fun prepared => do
    seen.set (prepared.text.titleString == "PDF Smoke" && prepared.config.destination == output)
  let (_, code) ← IO.FS.withIsolatedStreams <|
    Informal.PreviewManifest.blueprintMain highlightedStartupPatchDoc.toPart (options := [])
      (config := { cfg with destination := output, emitHtmlMulti := .resumeFrom path })
      (extraSteps := [step])
  unless code == 0 && (← seen.get) && (← (output / "html-multi" / "index.html").pathExists) &&
      (← (output / "html-multi" / "xref.json").pathExists) do
    throw <| IO.userError "Resume did not emit the checked document and xrefs"
  for (name, config) in #[
      ("incomplete", { cfg with emitHtmlMulti := .immediately, maxTraversals := 0 }),
      ("wrong-layout", { cfg with emitHtmlMulti := .resumeFrom path, htmlDepth := cfg.htmlDepth + 1 })] do
    let destination := root / name
    let (_, code) ← IO.FS.withIsolatedStreams <|
      Informal.PreviewManifest.blueprintMain pdfSmokeDoc.toPart (options := [])
        (config := { config with destination })
    unless code != 0 && !(← destination.pathExists) do
      throw <| IO.userError "Rejected HTML inputs still emitted files"

-- CLI dumps must cross the same completion boundary, rather than exporting a
-- plausible partial manifest after traversal exhaustion.
#eval show IO Unit from do
  for flag in ["--dump-manifest", "--dump-html-cache"] do
    let (messages, code) ← IO.FS.withIsolatedStreams <|
      Informal.PreviewManifest.blueprintMainWithPreviewData pdfSmokeDoc.toPart
        [flag] extension_impls% (config := { maxTraversals := 0 })
    unless code != 0 && hasSubstr messages "has not converged" &&
        !hasSubstr messages "\"previews\"" && !hasSubstr messages "\"entries\"" do
      throw <| IO.userError "CLI dump exported an incomplete traversal"

end Verso.VersoBlueprintTests.BlueprintMainWrapper
