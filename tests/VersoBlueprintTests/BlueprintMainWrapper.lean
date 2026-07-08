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

end Verso.VersoBlueprintTests.BlueprintMainWrapper
