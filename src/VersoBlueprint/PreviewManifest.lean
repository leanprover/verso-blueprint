/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Elab.Command
import Std.Data.HashMap
import Std.Data.HashSet
import VersoManual
import VersoManual.HighlightedCode
import VersoBlueprint.Cite
import VersoBlueprint.Informal.Block
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Group
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.PreviewCache
import VersoBlueprint.PreviewManifest.Cli
import VersoBlueprint.PreviewManifest.ExternalMarkupRender
import VersoBlueprint.PreviewRender
import VersoBlueprint.GraphApi
import VersoBlueprint.Git
import VersoBlueprint.Html
import VersoBlueprint.Process
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

namespace Informal.PreviewManifest

open Lean Elab Command Term Meta
open Verso Doc
open Verso.Genre Manual

private def readJsonFileAs [FromJson α] (path : System.FilePath) (description : String) :
    IO α := do
  let json ←
    match Json.parse (← IO.FS.readFile path) with
    | .ok json => pure json
    | .error err => throw <| IO.userError s!"could not parse {description} {path}: {err}"
  match fromJson? (α := α) json with
  | .ok value => pure value
  | .error err => throw <| IO.userError s!"could not decode {description} {path}: {err}"

private def buildMetadataCss : String := r##"
.bp_build_metadata {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 0.3rem 0.75rem;
  margin: 0.45rem 0 1.1rem;
  color: var(--bp-color-text-muted, #475569);
  font-size: 0.82rem;
  line-height: 1.4;
}

.bp_build_metadata_item {
  display: inline-flex;
  align-items: baseline;
  gap: 0.28rem;
  min-width: 0;
  flex-wrap: wrap;
}

.bp_build_metadata_label {
  color: var(--bp-color-text-subtle, #475569);
  font-weight: 600;
}

.bp_build_metadata_link {
  color: inherit;
  text-decoration: underline;
  text-decoration-style: dotted;
  text-underline-offset: 0.12em;
}

.bp_build_metadata_link:hover {
  text-decoration-style: solid;
}

.bp_build_metadata_commit {
  padding: 0.02rem 0.22rem;
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: 0.25rem;
  background: var(--bp-color-surface-muted, #f8fafc);
  color: var(--bp-color-text-strong, #0f172a);
  font-size: 0.86em;
}

.bp_build_metadata_commit_link {
  text-decoration: none;
}

.bp_build_metadata_commit_link:hover .bp_build_metadata_commit {
  border-color: var(--bp-color-link, #2563eb);
}

.bp_build_metadata_subject {
  overflow-wrap: anywhere;
}

@media (max-width: 640px) {
  .bp_build_metadata {
    justify-content: flex-start;
  }
}
"##

def buildMetadataHtmlAssets : HtmlAssets :=
  { extraCss := [buildMetadataCss] }

def blueprintBlockHtmlAssets : HtmlAssets :=
  { extraCss := Informal.Block.Assets.blockCssAssets }

def blueprintHtmlAssets : HtmlAssets :=
  Verso.Genre.Manual.highlightAssets
    |>.combine blueprintBlockHtmlAssets
    |>.combine buildMetadataHtmlAssets
    |>.combine externalMarkupRenderHtmlAssets

def pageRuntimeModuleFilename : String := "blueprint-page-runtime.mjs"

private def blueprintPageRuntimeHead : Verso.Output.Html :=
  open Verso.Output.Html in
  {{<script type="module" src={{"-verso-data/" ++ pageRuntimeModuleFilename}}></script>}}

private def pushHtmlIfMissing (values : Array Verso.Output.Html) (value : Verso.Output.Html) :
    Array Verso.Output.Html :=
  let valueString := Verso.Output.Html.asString value
  if values.any (fun item => Verso.Output.Html.asString item == valueString) then
    values
  else
    values.push value

def withBuildMetadataAssets (config : RenderConfig := {}) : RenderConfig :=
  let htmlConfig := config.toHtmlConfig
  let htmlAssets := htmlConfig.toHtmlAssets.combine buildMetadataHtmlAssets
  { config with
    toHtmlConfig := { htmlConfig with toHtmlAssets := htmlAssets }
  }

def withBlueprintAssets (config : RenderConfig := {}) : RenderConfig :=
  let htmlConfig := config.toHtmlConfig
  let htmlAssets := htmlConfig.toHtmlAssets.combine blueprintHtmlAssets
  { config with
    toHtmlConfig := {
      htmlConfig with
      toHtmlAssets := htmlAssets
      extraHead := pushHtmlIfMissing htmlConfig.extraHead blueprintPageRuntimeHead
    }
  }

structure GitCommitMetadata where
  commit : String
  subject : String
  repositoryUrl : Option String := none
  commitUrl : Option String := none
deriving Inhabited, Repr

structure PackageMetadata where
  version : String
  repositoryUrl : Option String := none
  commitUrl : Option String := none
deriving Inhabited, Repr

structure BuildMetadata where
  compiledAt : String
  commit : String
  subject : String
  projectRepositoryUrl : Option String := none
  projectCommitUrl : Option String := none
  leanToolchain : String
  blueprintVersion : String
  blueprintRepositoryUrl : Option String := none
  blueprintCommitUrl : Option String := none
  mathlibVersion : Option String := none
  mathlibRepositoryUrl : Option String := none
  mathlibCommitUrl : Option String := none
  upstreamBlueprint : Option GitCommitMetadata := none
deriving Inhabited, Repr

private def unknownMetadataValue : String := "unknown"

private def outputDirNameForMode : Mode → String
  | .single => "html-single"
  | .multi => "html-multi"

private def outDirForMode (cfg : Verso.Genre.Manual.Config) (mode : Mode) : System.FilePath :=
  cfg.destination / outputDirNameForMode mode

private def readTrimmedFile? (path : System.FilePath) : IO (Option String) := do
  try
    unless ← path.pathExists do
      return none
    let text := (← IO.FS.readFile path).trimAscii.toString
    if text.isEmpty then
      pure none
    else
      pure (some text)
  catch _ =>
    pure none

private def gitCommitMetadataAt? (dir : System.FilePath) : IO (Option GitCommitMetadata) := do
  let some commit ← Git.shortCommitAt? dir
    | return none
  let subject ← Git.subjectAt? dir
  let repositoryUrl ← Git.repositoryUrlAt? dir
  let commitUrl := Git.commitUrl? repositoryUrl (← Git.fullCommitAt? dir)
  pure <| some {
    commit
    subject := subject.getD unknownMetadataValue
    repositoryUrl
    commitUrl
  }

private def readLeanToolchain : IO String := do
  let cwd ← IO.currentDir
  match ← readTrimmedFile? (cwd / "lean-toolchain") with
  | some toolchain => pure toolchain
  | none =>
      pure <| (← Process.runTrimmedCommand? "lean" #["--version"]).getD unknownMetadataValue

private def readLakeManifestJson? : IO (Option Json) := do
  let cwd ← IO.currentDir
  try
    unless ← (cwd / "lake-manifest.json").pathExists do
      return none
    match Json.parse (← IO.FS.readFile (cwd / "lake-manifest.json")) with
    | .ok json => pure (some json)
    | .error _ => pure none
  catch _ =>
    pure none

private def jsonStringField? (json : Json) (field : String) : Option String :=
  match json.getObjValAs? String field with
  | .ok value => some value
  | .error _ => none

private def manifestPackages? (json : Json) : Option (Array Json) :=
  match json.getObjVal? "packages" with
  | .ok (.arr packages) => some packages
  | _ => none

private def manifestPackageByName? (manifest : Json) (names : Array String) : Option Json := do
  let packages ← manifestPackages? manifest
  packages.find? fun pkg =>
    match jsonStringField? pkg "name" with
    | some name => names.any (· == name)
    | none => false

private def shortRev (rev : String) : String :=
  if rev.length <= 12 then rev else (rev.take 12).copy

private def versionFromManifestPackage? (pkg : Json) : Option String :=
  match jsonStringField? pkg "rev" with
  | some rev =>
      let rev := shortRev rev
      match jsonStringField? pkg "inputRev" with
      | some inputRev =>
          if inputRev == rev then
            some rev
          else
            some s!"{inputRev}@{rev}"
      | none => some rev
  | none => none

private def packageMetadataFromPathPackage? (pkg : Json) : IO (Option PackageMetadata) := do
  let some dir := jsonStringField? pkg "dir"
    | return none
  let cwd ← IO.currentDir
  let packageDir := (cwd / dir).normalize
  let some version ← Git.shortCommitAt? packageDir
    | return none
  let repositoryUrl ← Git.repositoryUrlAt? packageDir
  let commitUrl := Git.commitUrl? repositoryUrl (← Git.fullCommitAt? packageDir)
  pure <| some { version, repositoryUrl, commitUrl }

private def packageMetadataFromGitPackage? (pkg : Json) : Option PackageMetadata := do
  let version ← versionFromManifestPackage? pkg
  let repositoryUrl :=
    match jsonStringField? pkg "url" with
    | some url => Git.githubRepositoryUrl? url
    | none => none
  let commitUrl := Git.commitUrl? repositoryUrl (jsonStringField? pkg "rev")
  some { version, repositoryUrl, commitUrl }

private def packageMetadata? (manifest : Json) (names : Array String) : IO (Option PackageMetadata) := do
  let some pkg := manifestPackageByName? manifest names
    | return none
  match packageMetadataFromGitPackage? pkg with
  | some metadata => pure (some metadata)
  | none => packageMetadataFromPathPackage? pkg

private def gitPackageMetadataAt (dir : System.FilePath) : IO PackageMetadata := do
  let version ← Git.shortCommitAt? dir
  let repositoryUrl ← Git.repositoryUrlAt? dir
  let commitUrl := Git.commitUrl? repositoryUrl (← Git.fullCommitAt? dir)
  pure {
    version := version.getD unknownMetadataValue
    repositoryUrl
    commitUrl
  }

private def readBlueprintPackage (manifest? : Option Json) : IO PackageMetadata := do
  match manifest? with
  | some manifest =>
      match ← packageMetadata? manifest #["VersoBlueprint", "verso-blueprint"] with
      | some metadata => pure metadata
      | none => gitPackageMetadataAt (← IO.currentDir)
  | none => gitPackageMetadataAt (← IO.currentDir)

private def readMathlibPackage? (manifest? : Option Json) : IO (Option PackageMetadata) := do
  match manifest? with
  | some manifest => packageMetadata? manifest #["mathlib", "Mathlib"]
  | none => pure none

private def tomlQuotedValue? (line key : String) : Option String :=
  let line := line.trimAscii.toString
  match line.splitOn "=" with
  | lhs :: rhsParts =>
      if lhs.trimAscii.toString != key then
        none
      else
        let rhs := (String.intercalate "=" rhsParts).trimAscii.toString
        match rhs.splitOn "\"" with
        | "" :: value :: _ => some value
        | _ => none
  | _ => none

private def firstTomlQuotedValue? (lines : List String) (key : String) : Option String :=
  match lines with
  | [] => none
  | line :: lines =>
      match tomlQuotedValue? line key with
      | some value => some value
      | none => firstTomlQuotedValue? lines key

private def readHarnessFormalizationPath? : IO (Option String) := do
  let cwd ← IO.currentDir
  match ← readTrimmedFile? (cwd / "verso-harness.toml") with
  | some text => pure <| firstTomlQuotedValue? (text.splitOn "\n") "formalization_path"
  | none => pure none

private def readUpstreamBlueprint? : IO (Option GitCommitMetadata) := do
  let cwd ← IO.currentDir
  let some upstreamPath ← readHarnessFormalizationPath?
    | return none
  let upstreamDir := (cwd / upstreamPath).normalize
  unless ← upstreamDir.pathExists do
    return none
  match (← Git.toplevelAt? cwd), (← Git.toplevelAt? upstreamDir) with
  | some projectRoot, some upstreamRoot =>
      if projectRoot == upstreamRoot then
        return none
  | _, _ => pure ()
  gitCommitMetadataAt? upstreamDir

def readBuildMetadata : IO BuildMetadata := do
  let cwd ← IO.currentDir
  let manifest? ← readLakeManifestJson?
  let compiledAt ← Process.runTrimmedCommand? "date" #["-u", "+%Y-%m-%dT%H:%M:%SZ"]
  let commit ← Git.shortCommitAt? cwd
  let subject ← Git.subjectAt? cwd
  let projectRepositoryUrl ← Git.repositoryUrlAt? cwd
  let projectCommitUrl := Git.commitUrl? projectRepositoryUrl (← Git.fullCommitAt? cwd)
  let leanToolchain ← readLeanToolchain
  let blueprintPackage ← readBlueprintPackage manifest?
  let mathlibPackage? ← readMathlibPackage? manifest?
  let upstreamBlueprint ← readUpstreamBlueprint?
  pure {
    compiledAt := compiledAt.getD unknownMetadataValue
    commit := commit.getD unknownMetadataValue
    subject := subject.getD unknownMetadataValue
    projectRepositoryUrl
    projectCommitUrl
    leanToolchain
    blueprintVersion := blueprintPackage.version
    blueprintRepositoryUrl := blueprintPackage.repositoryUrl
    blueprintCommitUrl := blueprintPackage.commitUrl
    mathlibVersion := mathlibPackage?.map (·.version)
    mathlibRepositoryUrl := mathlibPackage?.bind (·.repositoryUrl)
    mathlibCommitUrl := mathlibPackage?.bind (·.commitUrl)
    upstreamBlueprint
  }

private def buildMetadataLabelHtml (label : String) (href? : Option String) : Output.Html :=
  match href? with
  | some href =>
      Output.Html.tag "a"
        #[("class", "bp_build_metadata_label bp_build_metadata_link"), ("href", href)]
        (VersoBlueprint.Html.text label)
  | none =>
      Output.Html.tag "span" #[("class", "bp_build_metadata_label")] (VersoBlueprint.Html.text label)

private def buildMetadataCodeHtml (value : String) (href? : Option String) : Output.Html :=
  let code := Output.Html.tag "code" #[("class", "bp_build_metadata_commit")] (VersoBlueprint.Html.text value)
  match href? with
  | some href =>
      Output.Html.tag "a" #[("class", "bp_build_metadata_commit_link"), ("href", href)] code
  | none => code

def buildMetadataHtml (metadata : BuildMetadata) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_build_metadata" aria-label="Build metadata">
      <span class="bp_build_metadata_item">
        <span class="bp_build_metadata_label">"Compiled"</span>
        <span class="bp_build_metadata_value">{{VersoBlueprint.Html.text metadata.compiledAt}}</span>
      </span>
      <span class="bp_build_metadata_item">
        {{buildMetadataLabelHtml "Project" metadata.projectRepositoryUrl}}
        {{buildMetadataCodeHtml metadata.commit metadata.projectCommitUrl}}
        <span class="bp_build_metadata_subject">{{VersoBlueprint.Html.text metadata.subject}}</span>
      </span>
      <span class="bp_build_metadata_item">
        <span class="bp_build_metadata_label">"Lean"</span>
        <span class="bp_build_metadata_value">{{VersoBlueprint.Html.text metadata.leanToolchain}}</span>
      </span>
      <span class="bp_build_metadata_item">
        {{buildMetadataLabelHtml "VersoBlueprint" metadata.blueprintRepositoryUrl}}
        {{buildMetadataCodeHtml metadata.blueprintVersion metadata.blueprintCommitUrl}}
      </span>
      {{if let some upstream := metadata.upstreamBlueprint then
        {{<span class="bp_build_metadata_item">
            {{buildMetadataLabelHtml "Upstream" upstream.repositoryUrl}}
            {{buildMetadataCodeHtml upstream.commit upstream.commitUrl}}
            <span class="bp_build_metadata_subject">{{VersoBlueprint.Html.text upstream.subject}}</span>
          </span>}}
        else .empty}}
      {{if let some mathlibVersion := metadata.mathlibVersion then
        {{<span class="bp_build_metadata_item">
            {{buildMetadataLabelHtml "Mathlib" metadata.mathlibRepositoryUrl}}
            {{buildMetadataCodeHtml mathlibVersion metadata.mathlibCommitUrl}}
          </span>}}
        else .empty}}
    </div>
  }}

def buildMetadataHtmlString (metadata : BuildMetadata) : String :=
  Output.Html.asString <| buildMetadataHtml metadata

def insertBuildMetadataHtml? (html metadataHtml : String) : Option String :=
  if html.contains "class=\"bp_build_metadata\"" then
    some html
  else
    let titlePageMarker := "<div class=\"titlepage\">"
    let h1CloseMarker := "</h1>"
    match html.splitOn titlePageMarker with
    | before :: titlePagePart :: titlePageRest =>
        let afterTitlePage := String.intercalate titlePageMarker (titlePagePart :: titlePageRest)
        match afterTitlePage.splitOn h1CloseMarker with
        | titleHtml :: afterTitle :: afterTitleRest =>
            some <|
              before ++ titlePageMarker ++ titleHtml ++ h1CloseMarker ++ "\n" ++ metadataHtml ++
                String.intercalate h1CloseMarker (afterTitle :: afterTitleRest)
        | _ => none
    | _ => none

private def writeBuildMetadataHtml
    (metadata : BuildMetadata)
    (logError : String → IO Unit)
    (path : System.FilePath) : IO Unit := do
  unless ← path.pathExists do
    logError s!"Blueprint build metadata: missing root page {path}"
    return
  let html ← IO.FS.readFile path
  match insertBuildMetadataHtml? html (buildMetadataHtmlString metadata) with
  | some html => IO.FS.writeFile path html
  | none => logError s!"Blueprint build metadata: could not find title page heading in {path}"

def emitBuildMetadata (metadata : BuildMetadata) : ExtraStep := fun mode logError cfg _state _text => do
  writeBuildMetadataHtml metadata logError (outDirForMode cfg mode / "index.html")

private def highlightedDocstringInnerTextRead : String :=
  "const str = d.innerText;"

private def highlightedDocstringTextContentRead : String :=
  "const str = d.textContent || \"\";"

private def highlightedTacticShowGuardBefore : String :=
  "if (inst.reference.className == 'tactic') {
            const toggle = inst.reference.querySelector(\":scope > input.tactic-toggle\");"

private def highlightedTacticShowGuardBeforeNoScope : String :=
  "if (inst.reference.className == 'tactic') {
            const toggle = inst.reference.querySelector(\"input.tactic-toggle\");"

private def highlightedTacticShowGuardAfter : String :=
  "if (inst.reference.className == 'tactic') {
            if (!inst.reference.querySelector(\".tactic-state\")) {
              return false;
            }
            const toggle = inst.reference.querySelector(\"input.tactic-toggle\");"

private def highlightedTacticContentBefore : String :=
  "if (tgt.className == 'tactic') {
            const state = tgt.querySelector(\":scope > .tactic-state\").cloneNode(true);"

private def highlightedTacticContentBeforeNoScope : String :=
  "if (tgt.className == 'tactic') {
            const state = tgt.querySelector(\".tactic-state\").cloneNode(true);"

private def highlightedTacticContentAfter : String :=
  "if (tgt.className == 'tactic') {
            const stateSource = tgt.querySelector(\".tactic-state\");
            if (!stateSource) {
              return content;
            }
            const state = stateSource.cloneNode(true);"

private def isHighlightedStartupJs (source : String) : Bool :=
  source.contains "let docsJson = \"-verso-docs.json\";" &&
    source.contains "const defaultTippyProps = {"

private def replaceFirstHighlightedJs?
    (beforeOptions : List String)
    (after source : String) : Option String :=
  match beforeOptions with
  | [] => none
  | before :: rest =>
      if source.contains before then
        some (source.replace before after)
      else
        replaceFirstHighlightedJs? rest after source

private def replaceRequiredHighlightedJs
    (label : String) (beforeOptions : List String) (after source : String) : String :=
  match replaceFirstHighlightedJs? beforeOptions after source with
  | some source => source
  | none =>
    panic! s!"Blueprint highlighted-code JS patch `{label}` did not apply; upstream Verso highlight startup JS likely changed"

private def patchHighlightedStartupJs (js : JS) : JS :=
  if !isHighlightedStartupJs js.js then
    js
  else
  let patched :=
    js.js
      |> replaceRequiredHighlightedJs
          "docstring textContent read"
          [highlightedDocstringInnerTextRead]
          highlightedDocstringTextContentRead
      |> replaceRequiredHighlightedJs
          "tactic show guard"
          [highlightedTacticShowGuardBefore, highlightedTacticShowGuardBeforeNoScope]
          highlightedTacticShowGuardAfter
      |> replaceRequiredHighlightedJs
          "tactic content guard"
          [highlightedTacticContentBefore, highlightedTacticContentBeforeNoScope]
          highlightedTacticContentAfter
  { js with js := patched }

private def patchBlueprintHtmlAssets (assets : HtmlAssets) : HtmlAssets :=
  { assets with
    extraJs :=
      Std.HashSet.ofArray <|
        assets.extraJs.toArray.map patchHighlightedStartupJs
  }

private def patchBlueprintTraverseState (state : TraverseState) : TraverseState :=
  state.modifyHtmlAssets patchBlueprintHtmlAssets

def manifestFilename : String := "blueprint-manifest.json"

def htmlCacheFilename : String := "blueprint-html-cache.json"

def graphApiModuleFilename : String := "blueprint-graph-api.mjs"

def graphCoreModuleFilename : String := "blueprint-graph-core.mjs"

def previewCoreModuleFilename : String := "blueprint-preview-core.mjs"

def apiCommonModuleFilename : String := "blueprint-api-common.mjs"

def dataApiModuleFilename : String := "blueprint-data-api.mjs"

def previewApiModuleFilename : String := "blueprint-preview-api.mjs"

def apiModuleDirname : String := "api"

def previewRuntimeModuleDirname : String := "Commands"

def graphApiModuleAliasFilename : String := "graph.mjs"

def dataApiModuleAliasFilename : String := "data.mjs"

def previewApiModuleAliasFilename : String := "preview.mjs"

def graphApiModulePath : String := apiModuleDirname ++ "/" ++ graphApiModuleAliasFilename

def dataApiModulePath : String := apiModuleDirname ++ "/" ++ dataApiModuleAliasFilename

def previewApiModulePath : String := apiModuleDirname ++ "/" ++ previewApiModuleAliasFilename

-- Keep this module rebuilt when the standalone browser ESM APIs change.
private def graphCoreModuleMjs : String := include_str "blueprint-graph-core.mjs"

private def previewCoreModuleMjs : String := include_str "blueprint-preview-core.mjs"

private def apiCommonModuleMjs : String := include_str "blueprint-api-common.mjs"

private def graphApiModuleMjs : String := include_str "blueprint-graph-api.mjs"

private def dataApiModuleMjs : String := include_str "blueprint-data-api.mjs"

private def previewApiModuleMjs : String := include_str "blueprint-preview-api.mjs"

private def pageRuntimeModuleMjs : String := include_str "blueprint-page-runtime.mjs"

private def openTargetDetailsModuleMjs : String := include_str "Commands/open-target-details.mjs"

private def inlinePreviewModuleMjs : String := include_str "Commands/inline-preview.mjs"

private def graphRuntimeCoreModuleMjs : String := include_str "Commands/graph-runtime-core.mjs"

private def graphRuntimeModuleMjs : String := include_str "Commands/graph.mjs"

private def relationPanelModuleMjs : String := include_str "Informal/Block/relation-panel.mjs"

private def previewRuntimeBaseModuleFilename : String := "preview-runtime-base.mjs"

private def previewRuntimeDataModuleFilename : String := "preview-runtime-data.mjs"

private def previewRuntimeRenderModuleFilename : String := "preview-runtime-render.mjs"

private def previewRuntimeHydrationModuleFilename : String := "preview-runtime-hydration.mjs"

private def previewRuntimeLifecycleModuleFilename : String := "preview-runtime-lifecycle.mjs"

private def previewRuntimeSurfaceModuleFilename : String := "preview-runtime-surface.mjs"

private def previewRuntimeTemplateModuleFilename : String := "preview-runtime-template.mjs"

private def previewRuntimeApiModuleFilename : String := "preview-runtime-api.mjs"

private def previewRuntimeBaseModuleMjs : String := include_str "Commands/preview-runtime-base.mjs"

private def previewRuntimeDataModuleMjs : String := include_str "Commands/preview-runtime-data.mjs"

private def previewRuntimeRenderModuleMjs : String := include_str "Commands/preview-runtime-render.mjs"

private def previewRuntimeHydrationModuleMjs : String := include_str "Commands/preview-runtime-hydration.mjs"

private def previewRuntimeLifecycleModuleMjs : String := include_str "Commands/preview-runtime-lifecycle.mjs"

private def previewRuntimeSurfaceModuleMjs : String := include_str "Commands/preview-runtime-surface.mjs"

private def previewRuntimeTemplateModuleMjs : String := include_str "Commands/preview-runtime-template.mjs"

private def previewRuntimeApiModuleMjs : String := include_str "Commands/preview-runtime-api.mjs"

private def previewRuntimeModules : Array (String × String) := #[
  (previewRuntimeBaseModuleFilename, previewRuntimeBaseModuleMjs),
  (previewRuntimeDataModuleFilename, previewRuntimeDataModuleMjs),
  (previewRuntimeRenderModuleFilename, previewRuntimeRenderModuleMjs),
  (previewRuntimeHydrationModuleFilename, previewRuntimeHydrationModuleMjs),
  (previewRuntimeLifecycleModuleFilename, previewRuntimeLifecycleModuleMjs),
  (previewRuntimeSurfaceModuleFilename, previewRuntimeSurfaceModuleMjs),
  (previewRuntimeTemplateModuleFilename, previewRuntimeTemplateModuleMjs),
  (previewRuntimeApiModuleFilename, previewRuntimeApiModuleMjs)
]

private def pageRuntimeModules : Array (String × String) := #[
  (pageRuntimeModuleFilename, pageRuntimeModuleMjs),
  ("Commands/open-target-details.mjs", openTargetDetailsModuleMjs),
  ("Commands/inline-preview.mjs", inlinePreviewModuleMjs),
  ("Commands/graph-runtime-core.mjs", graphRuntimeCoreModuleMjs),
  ("Commands/graph.mjs", graphRuntimeModuleMjs),
  ("Informal/Block/relation-panel.mjs", relationPanelModuleMjs)
]

private def writeDataFile (dataDir : System.FilePath) (relativePath contents : String) : IO Unit := do
  let path := dataDir / relativePath
  IO.FS.createDirAll (path.parent.getD ".")
  IO.FS.writeFile path contents

private def writePageRuntimeModules (dataDir : System.FilePath) : IO Unit := do
  for module in pageRuntimeModules do
    writeDataFile dataDir module.fst module.snd

private def writePreviewRuntimeModules (dataDir : System.FilePath) : IO Unit := do
  let runtimeDir := dataDir / previewRuntimeModuleDirname
  IO.FS.createDirAll runtimeDir
  for module in previewRuntimeModules do
    IO.FS.writeFile (runtimeDir / module.fst) module.snd

private def graphApiModuleAliasMjs : String :=
  "export * from \"../" ++ graphApiModuleFilename ++ "\";\n" ++
  "export { default } from \"../" ++ graphApiModuleFilename ++ "\";\n"

private def dataApiModuleAliasMjs : String :=
  "export * from \"../" ++ dataApiModuleFilename ++ "\";\n" ++
  "export { default } from \"../" ++ dataApiModuleFilename ++ "\";\n"

private def previewApiModuleAliasMjs : String :=
  "export * from \"../" ++ previewApiModuleFilename ++ "\";\n" ++
  "export { default } from \"../" ++ previewApiModuleFilename ++ "\";\n"

inductive EntryKind where
  | block
  | leanDecl
  | citation
  | externalMarkup
deriving Inhabited, Repr, BEq, ToJson, FromJson

/-- Dependency axis for a related informal node. -/
inductive RelationAxis where
  | statement
  | proof
deriving Inhabited, Repr, BEq, ToJson, FromJson

def RelationAxis.display : RelationAxis → String
  | .statement => "statement"
  | .proof => "proof"

/-- Manifest-owned related informal node metadata for slide and tooling consumers. -/
structure RelatedEntry where
  /-- Informal label for the related node. -/
  label : Name
  /-- Resolved display title for the related node. -/
  title : String
  /-- Canonical link target for the related informal node, if available. -/
  href : Option String := none
  /-- Rendered-fragment cache key for this related node's statement preview. -/
  previewKey : String
  /-- Statement/proof dependency axes through which this related node is connected. -/
  axes : Array RelationAxis := #[]
deriving Inhabited, Repr, ToJson, FromJson

/-- Manifest-owned group metadata for an informal node. -/
structure GroupRelation where
  /-- Parent/group label. -/
  label : Name
  /-- Resolved group title, or the parent label when no group declaration exists. -/
  title : String
  /-- Whether a matching `:::group` declaration was present. -/
  declared : Bool := false
  /-- Traversal-ordered statement siblings in this group, excluding the current node. -/
  entries : Array RelatedEntry := #[]
deriving Inhabited, Repr, ToJson, FromJson

/--
Semantic preview entry consumed by generated renderers and custom tools.

This is the authoritative home for portable Blueprint facts: labels, facets,
titles, hrefs, relations, code associations, ownership, tags, and other
metadata. Do not add rendered HTML bodies here; put reusable presentation in
`HtmlCache.Entry` and join it to this semantic entry by `key` at render time.
-/
structure Entry where
  /-- Composite manifest lookup key for this target family. -/
  key : String
  /-- Manifest target family. -/
  targetKind : EntryKind
  /-- Canonical target label: informal label, Lean declaration name, citation label, or external-markup witness label. -/
  label : Name
  /-- Which preview variant this entry contains; non-block entries use `statement`. -/
  facet : PreviewCache.Facet
  /-- Kind (definition, proposition, lemma, theorem, corollary). -/
  kind : Option Informal.Data.NodeKind := none
  /-- Resolved display title for this manifest entry. -/
  title : String
  /-- Structured heading caption for renderers that need to lay out the title. -/
  displayCaption : Option String := none
  /-- Structured heading label or number for renderers that need to lay out the title. -/
  displayLabel : Option String := none
  /-- Canonical link target for the rendered informal node. -/
  href : Option String := none
  /-- Parent/group label for this informal node, if any. -/
  parent : Option Name := none
  /-- Resolved display title for the parent/group, if any. -/
  parentTitle : Option String := none
  /-- Structured statement use metadata, preserving origin and intent tags. -/
  statementUses : Array Informal.Data.UseRef := #[]
  /-- Structured proof use metadata, preserving origin and intent tags. -/
  proofUses : Array Informal.Data.UseRef := #[]
  /-- Rendered-fragment cache keys for Lean declaration previews associated with this entry. -/
  leanCodePreviewKeys : Array String := #[]
  /-- Canonical Lean code data associated with this informal node, if any. -/
  codeData : Option Informal.BlockCodeData := none
  /-- Raw external markup attachments keyed by language and slot. -/
  externalMarkup : Array Informal.Data.ExternalMarkup := #[]
  /-- Informal nodes used by this entry, with statement/proof axes and preview keys. -/
  uses : Array RelatedEntry := #[]
  /-- Informal statement nodes that depend on this entry, with dependency axes and preview keys. -/
  usedBy : Array RelatedEntry := #[]
  /-- Group declaration status and traversal-ordered sibling statement entries. -/
  group : Option GroupRelation := none
  /-- Resolved display name of the assigned owner, if available. -/
  ownerDisplayName : Option String := none
  /-- Normalized tags attached to this informal node. -/
  tags : Array String := #[]
  /-- Declared triage priority for this informal node, if any. -/
  priority : Option String := none
  /-- Declared effort estimate for this informal node, if any. -/
  effort : Option String := none
deriving Inhabited, Repr, ToJson, FromJson

/-- Structured heading text for renderers that rebuild an informal block shell. -/
structure EntryHeading where
  /-- Heading caption, such as "Definition" or "Theorem". -/
  caption : String
  /-- Heading label/number text. -/
  label : String
deriving Inhabited, Repr

/-- Informal block kind represented by this manifest entry. -/
def Entry.blockKind (entry : Entry) : Informal.Data.InProgressKind :=
  match entry.facet with
  | .proof => .proof
  | .statement => .statement (entry.kind.getD .theorem)

/-- Convert manifest entry metadata to the shared informal block model. -/
def Entry.blockData (entry : Entry) : Informal.BlockData := {
  kind := entry.blockKind
  codeData := entry.codeData
  label := entry.label
  parent := entry.parent
  count := 0
  statementUses := entry.statementUses
  proofUses := entry.proofUses
  ownerDisplayName := entry.ownerDisplayName
  tags := entry.tags
  effort := entry.effort
  priority := entry.priority
}

/--
Heading text for manifest-backed block rendering.

The optional override is used by embedding surfaces such as slides that want a
local display label without mutating the manifest entry.
-/
def Entry.heading (entry : Entry) (displayLabelOverride? : Option String := none) :
    EntryHeading :=
  let kindText :=
    match entry.kind with
    | some kind => toString kind
    | none => "Blueprint"
  let caption := (entry.displayCaption.getD kindText).trimAscii.toString
  let fallbackLabel := entry.label.toString
  let label := ((displayLabelOverride? <|> entry.displayLabel).getD fallbackLabel).trimAscii.toString
  { caption, label }

structure File where
  /--
  Semantic manifest entries keyed by `PreviewCache`, `externalMarkupEntryKey`,
  Lean preview key, or citation key.
  -/
  previews : Array Entry := #[]
  /--
  Public graph data captured from rendered `{blueprint_graph}` blocks.

  These entries share the same schema as the page-embedded graph data used by
  the browser runtime.
  -/
  graphs : Array Informal.Graph.GraphData := #[]
deriving Inhabited, Repr, ToJson, FromJson

/-
Rendered-fragment cache paired with the semantic preview manifest.

This namespace owns presentation artifacts only: opaque rendered fragments
and the Verso hover payloads referenced by those fragments. Semantic facts that
custom consumers may need to query belong in `PreviewManifest.Entry`, not in
HTML attributes or text that consumers would need to scrape from cached markup.
-/
namespace HtmlCache

/--
First hover id reserved for cache-rendered fragments.

Verso writes page-local hover tables after rendering the main document. Cache
fragments are rendered separately and then merged into that table, so their ids
must live outside the normal small page-local range unless the HTML fragments are
structurally remapped. Keeping a reserved range preserves normal
`data-verso-hover` markup without duplicating hover payloads into each fragment.
-/
def hoverIdStart : Nat := 1000000

structure HoverDoc where
  /-- Numeric `data-verso-hover` id reserved for a cached rendered fragment. -/
  id : Nat
  /-- Rendered hover payload HTML for this id. -/
  html : String
deriving Inhabited, Repr, ToJson, FromJson

structure Entry where
  /-- Composite preview lookup key for this rendered fragment. -/
  key : String
  /--
  Opaque already-rendered HTML fragment for this preview/cache entry.

  Consumers may insert and hydrate this fragment, but should not parse it to
  recover labels, relationships, code metadata, or status facts. Those belong
  to the semantic manifest entry with the same key.
  -/
  html : String
deriving Inhabited, Repr, ToJson, FromJson

structure File where
  /-- Opaque rendered fragments keyed by preview/cache entry key. -/
  entries : Array Entry := #[]
  /-- Verso hover payloads referenced by the rendered fragments. -/
  hoverDocs : Array HoverDoc := #[]
deriving Inhabited, Repr, ToJson, FromJson

structure Index where
  entriesByKey : Std.HashMap String Entry := {}
deriving Inhabited

def Index.ofFile (file : File) : Index := {
  entriesByKey := file.entries.foldl (fun entries entry => entries.insert entry.key entry) {}
}

def File.index (file : File) : Index :=
  Index.ofFile file

def Index.findEntry? (index : Index) (key : String) : Option Entry :=
  index.entriesByKey.get? key

def Index.findHtml? (index : Index) (key : String) : Option String :=
  (index.findEntry? key).map (·.html)

def File.findEntry? (file : File) (key : String) : Option Entry :=
  file.index.findEntry? key

def File.findHtml? (file : File) (key : String) : Option String :=
  file.index.findHtml? key

def initialHoverState : Verso.Code.Hover.State Output.Html :=
  { dedup := { ({} : Verso.Code.Hover.Dedup Output.Html) with nextId := hoverIdStart }
    idSupply := {} }

def HoverDoc.ofDedup (dedup : Verso.Code.Hover.Dedup Output.Html) : Array HoverDoc :=
  dedup.contentId.toArray.map (fun (id, html) => {
    id
    html := html.asString
  }) |>.qsort (fun a b => a.id < b.id)

def HoverDoc.toHtml (doc : HoverDoc) : Output.Html :=
  Output.Html.text false doc.html

def File.hoverDocsJson (file : File) : Json :=
  file.hoverDocs.foldl (init := Json.mkObj []) fun out doc =>
    out.setObjVal! (toString doc.id) (Json.str doc.html)

def File.hoverDedup (file : File) : Verso.Code.Hover.Dedup Output.Html :=
  let nextId :=
    file.hoverDocs.foldl (init := 0) fun next doc =>
      Nat.max next (doc.id + 1)
  let contentId :=
    file.hoverDocs.foldl (init := {}) fun content doc =>
      content.insert doc.id doc.toHtml
  let idContent :=
    file.hoverDocs.foldl (init := {}) fun ids doc =>
      ids.insert doc.toHtml doc.id
  { nextId, contentId, idContent }

def File.hoverState (file : File) : Verso.Code.Hover.State Output.Html :=
  { dedup := file.hoverDedup
    idSupply := {} }

private def pushDistinctHtml (values : Array String) (html : String) : Array String :=
  if values.contains html then values else values.push html

/--
Rendered Lean-code preview bodies for an informal entry, deduplicated by the
actual rendered fragment.
-/
def Index.codeHtmlBodies (index : Index) (entry : _root_.Informal.PreviewManifest.Entry) :
    Array String :=
  entry.leanCodePreviewKeys.foldl (init := #[]) fun bodies key =>
    match index.findHtml? key with
    | some html => pushDistinctHtml bodies html
    | none => bodies

def File.codeHtmlBodies (file : File) (entry : _root_.Informal.PreviewManifest.Entry) :
    Array String :=
  file.index.codeHtmlBodies entry

def readFile (path : System.FilePath) : IO File := do
  readJsonFileAs path "Blueprint HTML cache"

end HtmlCache

/-- Paired preview-data outputs emitted for a generated Blueprint site. -/
structure Files where
  /--
  Semantic preview data. This is the public source of truth for labels, hrefs,
  relationship topology, Lean-code associations, external-source metadata, and
  other facts that generated consumers need.
  -/
  manifest : File := {}
  /--
  Opaque rendered fragments and their hover payload side table. Consumers join
  this cache with `manifest` by preview key when they need presentation data.
  -/
  htmlCache : HtmlCache.File := {}
deriving Inhabited, Repr

structure Index where
  entriesByKey : Std.HashMap String Entry := {}
deriving Inhabited

def Index.ofFile (file : File) : Index := {
  entriesByKey := file.previews.foldl (fun entries entry => entries.insert entry.key entry) {}
}

def File.index (file : File) : Index :=
  Index.ofFile file

def Index.findEntry? (index : Index) (key : String) : Option Entry :=
  index.entriesByKey.get? key

def File.findEntry? (file : File) (key : String) : Option Entry :=
  file.index.findEntry? key

/-- Manifest metadata that was present during traversal but is absent from export. -/
structure PreviewMetadataLoss where
  /-- Traversal-preview cache key whose metadata was not fully represented. -/
  previewKey : String
  /-- Blueprint label recorded by traversal. -/
  label : Name
  /-- Preview facet recorded by traversal. -/
  facet : PreviewCache.Facet
  /-- Matching manifest entry key, if the manifest contains one. -/
  manifestEntryKey? : Option String := none
  /-- Lean declaration preview keys present during traversal but missing from the manifest entry. -/
  missingLeanCodePreviewKeys : Array String := #[]
deriving Inhabited, Repr, ToJson, FromJson

/--
Find the manifest entry that should carry metadata for a traversal preview.

Bodyless source-backed nodes may export as `targetKind: "externalMarkup"` rather
than as ordinary block entries, but the label/facet provenance is still the same.
-/
def File.findPreviewMetadataEntry? (file : File) (metadata : PreviewCache.Metadata) :
    Option Entry :=
  file.previews.find? fun entry =>
    entry.label == metadata.label && entry.facet == metadata.facet

private def missingPreviewLeanCodeKeys (entry? : Option Entry)
    (metadata : PreviewCache.Metadata) : Array String :=
  metadata.leanCodePreviewKeys.filter fun key =>
    match entry? with
    | some entry => !entry.leanCodePreviewKeys.contains key
    | none => true

/--
Return traversal-preview metadata that was lost while constructing the manifest.

This is intentionally a queryable invariant rather than an unconditional build
error so tests and downstream tooling can opt into stricter checks without
changing existing generation behavior.
-/
def previewMetadataLosses (state : TraverseState) (file : File) : Array PreviewMetadataLoss :=
  Id.run do
    let mut losses := #[]
    for decoded in Informal.TraversalIndex.TraversalPreviews.entries state do
      match decoded with
      | .error _ => pure ()
      | .ok stored =>
          let metadata := stored.data.metadata
          if !metadata.leanCodePreviewKeys.isEmpty then
            let manifestEntry? := file.findPreviewMetadataEntry? metadata
            let missing := missingPreviewLeanCodeKeys manifestEntry? metadata
            if !missing.isEmpty then
              losses := losses.push {
                previewKey := stored.canonicalName
                label := metadata.label
                facet := metadata.facet
                manifestEntryKey? := manifestEntry?.map (·.key)
                missingLeanCodePreviewKeys := missing
              }
    losses

/-- Human-facing warning text for one manifest metadata-loss audit result. -/
def PreviewMetadataLoss.warningMessage (loss : PreviewMetadataLoss) : String :=
  let manifestEntry :=
    match loss.manifestEntryKey? with
    | some key => s!"manifest entry {key}"
    | none => "no matching manifest entry"
  let missing := String.intercalate ", " loss.missingLeanCodePreviewKeys.toList
  s!"Blueprint manifest: traversal preview {loss.previewKey} for {loss.label} ({loss.facet.suffix}) lost Lean preview keys [{missing}] while exporting {manifestEntry}"

/-- Report non-fatal generator warnings for traversal metadata lost during manifest export. -/
def reportPreviewMetadataLossWarnings
    (reportWarning : String → IO Unit) (state : TraverseState) (file : File) : IO Unit := do
  for loss in previewMetadataLosses state file do
    reportWarning loss.warningMessage

/-- Stable string form used by manifest query APIs for Blueprint labels. -/
def labelString : Name → String
  | .str .anonymous s => s
  | name => name.toString

/-- Whether this manifest entry represents an informal Blueprint block. -/
def Entry.isBlock (entry : Entry) : Bool :=
  match entry.targetKind with
  | .block => true
  | _ => false

/-- Whether this manifest entry represents the statement facet. -/
def Entry.isStatement (entry : Entry) : Bool :=
  match entry.facet with
  | .statement => true
  | _ => false

/-- Statement-facet block entries, the primary row set for client label queries. -/
def File.blockStatementEntries (file : File) : Array Entry :=
  file.previews.filter (fun entry => entry.isBlock && entry.isStatement)

/-- All block entries matching the public label string, including non-statement facets. -/
def File.findBlockEntriesByLabel (file : File) (label : String) : Array Entry :=
  file.previews.filter fun entry =>
    entry.isBlock && labelString entry.label == label

/--
Best public block entry for a label.

Statement entries are primary because most clients ask for node metadata rather
than a proof-only rendered facet. If a label only has another facet, return it.
-/
def File.findPrimaryBlockEntry? (file : File) (label : String) : Option Entry :=
  let entries := file.findBlockEntriesByLabel label
  entries.find? (·.isStatement) <|> entries[0]?

private def pushUniqueString (values : Array String) (value : String) : Array String :=
  if values.contains value then values else values.push value

/-- Sorted owner names present on statement-facet block entries. -/
def File.ownerValues (file : File) : Array String :=
  let owners := file.blockStatementEntries.foldl (init := #[]) fun owners entry =>
      match entry.ownerDisplayName with
      | none => owners
      | some owner => pushUniqueString owners owner
  owners.qsort (· < ·)

/-- Sorted tag values present on statement-facet block entries. -/
def File.tagValues (file : File) : Array String :=
  let tags := file.blockStatementEntries.foldl (init := #[]) fun tags entry =>
      entry.tags.foldl pushUniqueString tags
  tags.qsort (· < ·)

/-- Statement-facet block entries carrying work-queue metadata. -/
def File.workQueueEntries (file : File) : Array Entry :=
  file.blockStatementEntries.filter fun entry =>
    entry.ownerDisplayName.isSome || entry.priority.isSome ||
      entry.effort.isSome || !entry.tags.isEmpty

private def containsSearchText (text value : String) : Bool :=
  value.toLower.contains text

/-- Case-insensitive text search over user-facing block manifest fields. -/
def Entry.matchesText (entry : Entry) (query : String) : Bool :=
  let text := query.toLower
  containsSearchText text (labelString entry.label) ||
    containsSearchText text entry.title ||
    entry.parentTitle.any (containsSearchText text) ||
    entry.tags.any (containsSearchText text) ||
    entry.ownerDisplayName.any (containsSearchText text)

/-- Search whether the entry references a Lean-code preview key containing `decl`. -/
def Entry.matchesCode (entry : Entry) (decl : String) : Bool :=
  entry.leanCodePreviewKeys.any (fun key => key.contains decl)

def externalMarkupEntryKey (label : Name) : String :=
  s!"externalMarkup:{label}"

/-- Count available Lean-code preview entries before display-level deduplication. -/
def Index.codeEntryCount (index : Index) (entry : Entry) : Nat :=
  (entry.leanCodePreviewKeys.filterMap index.findEntry?).size

/--
Lean-code preview keys are declaration-granular. Return the semantic entries in
key order while keeping display-level rendered-HTML deduplication in
`HtmlCache.Index.codeHtmlBodies`.
-/
def Index.codeEntries (index : Index) (entry : Entry) : Array Entry :=
  entry.leanCodePreviewKeys.filterMap index.findEntry?

def readFile (path : System.FilePath) : IO File := do
  readJsonFileAs path "Blueprint manifest"

private structure SchemaState where
  seen : Std.HashSet Name := {}
  defs : Array (String × Json) := #[]

private def jsonSchemaRef (name : Name) : Json :=
  Json.mkObj [("$ref", Json.str s!"#/$defs/{name}")]

private def fieldKey (name : Name) : String :=
  name.getString!

private def fieldType (fieldName : Name) : MetaM Expr := do
  let info ← getConstInfo fieldName
  Meta.forallTelescopeReducing info.type fun _ body => pure body

private def docSummary (docs : String) : String :=
  match docs.trimAscii.toString.splitOn "\n\n" with
  | [] => ""
  | first :: _ => first.trimAscii.toString

private def schemaWithDescription (schema : Json) (docs : String) : Json :=
  let docs := docSummary docs
  if docs.isEmpty then
    schema
  else
    let combined :=
      match schema.getObjValAs? String "description" with
      | .ok existing =>
          let existing := existing.trimAscii.toString
          if existing.isEmpty then docs else s!"{docs} {existing}"
      | .error _ => docs
    schema.setObjVal! "description" (Json.str combined)

private partial def schemaForType (ty : Expr) : StateT SchemaState MetaM Json := do
  let ty ← Meta.whnf ty
  let args := Expr.getAppArgs ty
  match Expr.getAppFn ty with
  | .const ``String _ =>
      pure <| Json.mkObj [("type", Json.str "string")]
  | .const ``Name _ =>
      pure <| Json.mkObj [("type", Json.str "string")]
  | .const ``Bool _ =>
      pure <| Json.mkObj [("type", Json.str "boolean")]
  | .const ``Nat _ =>
      pure <| Json.mkObj [("type", Json.str "integer")]
  | .const ``Int _ =>
      pure <| Json.mkObj [("type", Json.str "integer")]
  | .const ``Float _ =>
      pure <| Json.mkObj [("type", Json.str "number")]
  | .const ``Array _ =>
      let itemSchema ← schemaForType args[0]!
      pure <| Json.mkObj [("type", Json.str "array"), ("items", itemSchema)]
  | .const ``List _ =>
      let itemSchema ← schemaForType args[0]!
      pure <| Json.mkObj [("type", Json.str "array"), ("items", itemSchema)]
  | .const ``Option _ =>
      let itemSchema ← schemaForType args[0]!
      pure <| Json.mkObj [
        ("anyOf", Json.arr #[
          itemSchema,
          Json.mkObj [("type", Json.str "null")]
        ])
      ]
  | .const name _ =>
      let st ← get
      if st.seen.contains name then
        return jsonSchemaRef name
      modify fun st => { st with seen := st.seen.insert name }
      let env ← getEnv
      if let some info := getStructureInfo? env name then
        let mut properties : List (String × Json) := []
        let mut required : Array Json := #[]
        for fieldInfo in info.fieldInfo do
          let schema ← schemaForType (← fieldType fieldInfo.projFn)
          let docs? ← findDocString? env fieldInfo.projFn
          let schema :=
            match docs? with
            | some docs => schemaWithDescription schema docs
            | none => schema
          let key := fieldKey fieldInfo.fieldName
          properties := properties.concat (key, schema)
          required := required.push (Json.str key)
        let schema := Json.mkObj [
          ("type", Json.str "object"),
          ("properties", Json.mkObj properties),
          ("required", Json.arr required),
          ("additionalProperties", Json.bool false)
        ]
        modify fun st => { st with defs := st.defs.push (name.toString, schema) }
        pure <| jsonSchemaRef name
      else
        match env.find? name with
        | some (.inductInfo info) =>
            let mut enumVals : Array Json := #[]
            for ctorName in info.ctors do
              let ctorInfo ← getConstInfoCtor ctorName
              unless ctorInfo.numFields == 0 do
                let schema := Json.mkObj [
                  ("type", Json.str "object"),
                  ("description", Json.str s!"Derived JSON representation for '{name}'.")
                ]
                modify fun st => { st with defs := st.defs.push (name.toString, schema) }
                return jsonSchemaRef name
              enumVals := enumVals.push (Json.str ctorName.getString!)
            let schema := Json.mkObj [
              ("type", Json.str "string"),
              ("enum", Json.arr enumVals)
            ]
            modify fun st => { st with defs := st.defs.push (name.toString, schema) }
            pure <| jsonSchemaRef name
        | _ =>
            throwError "Unsupported schema type: {ty}"
  | _ =>
      throwError "Unsupported schema type: {ty}"

syntax (name := previewManifestSchema) "previewManifestSchema%" : term

@[term_elab previewManifestSchema]
def elabPreviewManifestSchema : TermElab := fun _ _ => do
  let rootTy := Lean.mkConst ``Informal.PreviewManifest.File
  let (_rootRef, st) ← Meta.liftMetaM <| (schemaForType rootTy).run {}
  let defs := st.defs.qsort (fun a b => a.1 < b.1)
  let schema : Json := Json.mkObj [
    ("$schema", Json.str "https://json-schema.org/draft/2020-12/schema"),
    ("$ref", Json.str s!"#/$defs/{``Informal.PreviewManifest.File}"),
    ("$defs", Json.mkObj defs.toList)
  ]
  let schemaText := schema.render.pretty 80
  return mkStrLit schemaText

def schemaString : String :=
  previewManifestSchema%

def schemaJson : Json :=
  match Json.parse schemaString with
  | .ok json => json
  | .error err => panic! s!"Invalid generated Blueprint manifest schema: {err}"

private def jsonPretty (json : Json) : String :=
  json.render.pretty 80

private def xrefExcludedDomainNames : Array Name :=
  Informal.TraversalIndex.allSpecs.filterMap fun spec =>
    match spec.kind with
    | .semanticDomain => none
    | .internalIndex | .runtimeCache | .accumulator => some spec.name

private def isPublicXrefDomain (name : Name) : Bool :=
  !xrefExcludedDomainNames.any (· == name)

private def publicXrefDomains (domains : Verso.NameMap Verso.Multi.Domain) :
    Verso.NameMap Verso.Multi.Domain := Id.run do
  let mut publicDomains : Verso.NameMap Verso.Multi.Domain := {}
  for (name, domain) in domains do
    if isPublicXrefDomain name then
      publicDomains := publicDomains.insert! name domain
  publicDomains

def buildPublicXrefJson (state : TraverseState) : Json :=
  Verso.Multi.xrefJson (publicXrefDomains state.domains) state.externalTags

private def replaceFindPageXref (html xrefJson : String) : Option String :=
  let marker := "window.xref = "
  match html.splitOn marker with
  | before :: afterMarkerPart :: afterMarkerParts =>
      let afterMarker := String.intercalate marker (afterMarkerPart :: afterMarkerParts)
      match afterMarker.splitOn Verso.Genre.Manual.find.js with
      | _oldJson :: afterFindJsPart :: afterFindJsParts =>
          some <|
            before ++ marker ++ xrefJson ++ ";\n" ++
            Verso.Genre.Manual.find.js ++
            String.intercalate Verso.Genre.Manual.find.js (afterFindJsPart :: afterFindJsParts)
      | _ => none
  | _ => none

def emitPublicXref (mode : Mode) (logError : String → IO Unit) (cfg : Verso.Genre.Manual.Config)
    (state : TraverseState) : IO Unit := do
  let outDir := outDirForMode cfg mode
  let json := (buildPublicXrefJson state).compress
  IO.FS.writeFile (outDir / "xref.json") json
  let findIndex := outDir / "find" / "index.html"
  if ← findIndex.pathExists then
    let html ← IO.FS.readFile findIndex
    match replaceFindPageXref html json with
    | some html => IO.FS.writeFile findIndex html
    | none => logError s!"Blueprint xref filter: could not find embedded xref payload in {findIndex}"

private def blockInfo? (state : TraverseState) (label : Name) : Option Informal.BlockData :=
  match Informal.TraversalIndex.Nodes.data? state label with
  | some blockData => some (blockData.withResolvedNumbering state)
  | none => none

private def blockTitle (state : TraverseState) (label : Name)
    (facet : PreviewCache.Facet := .statement) (blockData? : Option Informal.BlockData := none) : String :=
  match blockData? <|> blockInfo? state label with
  | some blockData =>
      match facet with
      | .proof => blockData.displayProofTitle state
      | .statement => blockData.displayTitle state
  | none => label.toString

private structure BlockHeadingParts where
  caption : String
  label : String

private def blockHeadingParts? (state : TraverseState) (label : Name)
    (facet : PreviewCache.Facet := .statement) (blockData? : Option Informal.BlockData := none) :
    Option BlockHeadingParts := do
  let blockData ← blockData? <|> blockInfo? state label
  let numberText := blockData.displayNumber state
  match facet with
  | .statement =>
      let kind ← blockData.statementKind? state
      some { caption := toString kind, label := numberText }
  | .proof =>
      let label :=
        match blockData.statementKind? state with
        | some kind => s!"for {kind} {numberText}"
        | none => numberText
      some { caption := "Proof", label }

private def blockHref (state : TraverseState) (label : Name)
    (facet : PreviewCache.Facet := .statement) : Option String :=
  Informal.TraversalIndex.TraversalPreviews.hrefFor? state label facet <|>
    Informal.TraversalIndex.Nodes.href? state label

private def blockKind? (blockData? : Option Informal.BlockData) : Option Informal.Data.NodeKind :=
  match blockData? with
  | some blockData =>
      match blockData.kind with
      | Informal.Data.InProgressKind.statement kind => some kind
      | Informal.Data.InProgressKind.proof => none
  | none => none

private def externalMarkupArray (state : TraverseState) (label : Name) :
    Array Informal.Data.ExternalMarkup :=
  (Informal.TraversalIndex.ExternalMarkup.data? state label).map (·.markup.toArray) |>.getD #[]

private def groupTitle? (state : TraverseState) (parent : Name) : Option String :=
  match Informal.TraversalIndex.Groups.data? state parent with
  | some groupData =>
      let header := groupData.header.trimAscii.toString
      if header.isEmpty then none else some header
  | none => none

private def blockParentTitle? (state : TraverseState) (blockData? : Option Informal.BlockData) : Option String :=
  blockData?.bind fun blockData =>
    blockData.parent.map fun parent =>
      (groupTitle? state parent).getD parent.toString

private def pushUnique [BEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

private def inlineCodePreviewKeys (state : TraverseState) (label : Name) : Array String :=
  match Informal.TraversalIndex.InlineCode.data? state label with
  | none => #[]
  | some codeData =>
    let decls := (codeData.definedDefs.map (·.name)) ++ (codeData.definedTheorems.map (·.name))
    decls.map Informal.TraversalIndex.LeanCodePreviews.lookupKey

private def blockLeanCodePreviewKeys
    (state : TraverseState)
    (label : Name)
    (entry : PreviewCache.Entry) : Array String :=
  (inlineCodePreviewKeys state label).foldl
    (init := entry.leanCodePreviewKeys)
    (fun keys key => pushUnique keys key)

private def externalDeclsFromLeanPreviewKeys
    (state : TraverseState)
    (keys : Array String) : Array Informal.Data.ExternalRef :=
  keys.filterMap fun key =>
    match Informal.TraversalIndex.LeanCodePreviews.entry? state key with
    | some { source := .externalDecl decl, .. } => some decl
    | _ => none

private def blockCodeData?
    (state : TraverseState)
    (label : Name)
    (entry : PreviewCache.Entry)
    (blockData? : Option Informal.BlockData) : Option Informal.BlockCodeData :=
  let inline? := Informal.TraversalIndex.InlineCode.data? state label
  let externalDecls := externalDeclsFromLeanPreviewKeys state entry.leanCodePreviewKeys
  let external? :=
    if externalDecls.isEmpty then
      blockData?.bind (·.codeData)
    else
      some (Informal.BlockCodeData.external externalDecls)
  Informal.BlockCodeData.ofHintAndInline external? inline?

private def relatedAxes (source : Informal.BlockData) (target : Name) : Array RelationAxis :=
  let axes : Array RelationAxis :=
    if source.statementDeps.contains target then #[.statement] else #[]
  if source.proofDeps.contains target then axes.push .proof else axes

private def relatedEntryForLabel
    (state : TraverseState)
    (label : Name)
    (axes : Array RelationAxis := #[]) : RelatedEntry :=
  let blockData? := blockInfo? state label
  {
    label
    title := blockTitle state label .statement blockData?
    href := blockHref state label
    previewKey := Informal.PreviewSource.traversalLookupKeyOrStatement state label
    axes
  }

private def relatedEntryForBlock
    (state : TraverseState)
    (blockData : Informal.BlockData)
    (axes : Array RelationAxis := #[]) : RelatedEntry :=
  {
    label := blockData.label
    title := blockTitle state blockData.label .statement (some blockData)
    href := blockHref state blockData.label
    previewKey := Informal.PreviewSource.traversalLookupKeyOrStatement state blockData.label
    axes
  }

private def buildUsesRelations
    (state : TraverseState)
    (blockData : Informal.BlockData) : Array RelatedEntry :=
  let labels := (blockData.statementDeps ++ blockData.proofDeps).foldl
    (fun acc label => if acc.contains label then acc else acc.push label)
    #[]
  labels.map fun label =>
    relatedEntryForLabel state label (relatedAxes blockData label)

private def buildUsedByRelations
    (state : TraverseState)
    (storedBlocks : Array Informal.BlockData)
    (blockData : Informal.BlockData) : Array RelatedEntry :=
  storedBlocks.filterMap fun source =>
    if source.label == blockData.label then
      none
    else
      let axes := relatedAxes source blockData.label
      if axes.isEmpty then
        none
      else
        some <| relatedEntryForBlock state source axes

private def buildGroupRelation?
    (state : TraverseState)
    (storedBlocks : Array Informal.BlockData)
    (blockData : Informal.BlockData) : Option GroupRelation := do
  let parent ← blockData.parent
  let groupData? := Informal.TraversalIndex.Groups.data? state parent
  let title :=
    match groupData? with
    | some groupData =>
      let header := groupData.header.trimAscii.toString
      if header.isEmpty then parent.toString else header
    | none => parent.toString
  let entries := storedBlocks.filterMap fun source =>
    if source.label == blockData.label then
      none
    else if source.parent == some parent then
      match source.kind with
      | .statement _ => some <| relatedEntryForBlock state source
      | .proof => none
    else
      none
  some {
    label := parent
    title
    declared := groupData?.isSome
    entries
  }

private def fallbackTraversalPreview (label : Name) (facet : PreviewCache.Facet) :
    PreviewCache.Entry :=
  PreviewCache.Entry.ofBlocks label facet #[]

private def traversalPreviewOrFallback
    (state : TraverseState) (label : Name) (facet : PreviewCache.Facet) :
    PreviewCache.Entry :=
  (Informal.TraversalIndex.TraversalPreviews.entry? state (PreviewCache.key label facet)).getD
    (fallbackTraversalPreview label facet)

private def blockSemanticManifestEntry
    (state : TraverseState)
    (preview : PreviewCache.Entry)
    (key : String := PreviewCache.key preview.label preview.facet)
    (targetKind : EntryKind := .block)
    (externalMarkup? : Option (Array Informal.Data.ExternalMarkup) := none) : Entry :=
  let blockData? := blockInfo? state preview.label
  let headingParts? := blockHeadingParts? state preview.label preview.facet blockData?
  let codeData := blockCodeData? state preview.label preview blockData?
  let storedBlocks := Informal.collectStoredBlocks state
  {
    key
    targetKind
    label := preview.label
    facet := preview.facet
    kind := blockKind? blockData?
    title := blockTitle state preview.label preview.facet blockData?
    displayCaption := headingParts?.map (·.caption)
    displayLabel := headingParts?.map (·.label)
    href := blockHref state preview.label preview.facet
    parent := blockData?.bind (·.parent)
    parentTitle := blockParentTitle? state blockData?
    statementUses := blockData?.map (·.statementUses) |>.getD #[]
    proofUses := blockData?.map (·.proofUses) |>.getD #[]
    leanCodePreviewKeys := blockLeanCodePreviewKeys state preview.label preview
    codeData
    externalMarkup := externalMarkup?.getD (externalMarkupArray state preview.label)
    uses := blockData?.map (buildUsesRelations state ·) |>.getD #[]
    usedBy := blockData?.map (buildUsedByRelations state storedBlocks ·) |>.getD #[]
    group := blockData?.bind (buildGroupRelation? state storedBlocks)
    ownerDisplayName := blockData?.bind (·.ownerDisplayName)
    tags := blockData?.map (·.tags) |>.getD #[]
    priority := blockData?.bind (·.priority)
    effort := blockData?.bind (·.effort)
  }

def blockEntryOfTraversalPreview
    (state : TraverseState)
    (preview : PreviewCache.Entry) : Entry :=
  blockSemanticManifestEntry state preview

def findTraversalBlockEntry? (state : TraverseState) (key : String) :
    Option (PreviewCache.Entry × Entry) := do
  let preview ← Informal.PreviewSource.traversalEntryByKey? state key
  some (preview, blockEntryOfTraversalPreview state preview)

private def buildTraversalEntries
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (hoverState : Verso.Code.Hover.State Output.Html) :
    IO (Array Entry × Array HtmlCache.Entry × Verso.Code.Hover.State Output.Html) := do
  let mut entries := #[]
  let mut htmlEntries := #[]
  let mut hoverState := hoverState
  for decoded in Informal.PreviewSource.traversalStoredEntries state do
    match decoded with
    | .error err =>
      logError s!"Blueprint manifest: malformed preview entry {err.canonicalName}: {err.message}"
    | .ok stored =>
      let entry := stored.entry
      if !entry.hasRenderedBody then
        continue
      let rendered ← Informal.renderManualBlocksHtmlWithStateAndHovers entry.renderedBody.blocks impls state
        (logError := logError) (hoverState := hoverState)
      hoverState := rendered.hoverState
      let html := rendered.html.asString
      if html.trimAscii.isEmpty then
        continue
      let manifestEntry := blockEntryOfTraversalPreview state entry
      entries := entries.push manifestEntry
      htmlEntries := htmlEntries.push { key := stored.key, html }
  pure (entries, htmlEntries, hoverState)

private def hasPreviewBackedBlockEntry (entries : Array Entry) (label : Name) : Bool :=
  entries.any fun entry =>
    entry.targetKind == .block && entry.label == label

private def buildExternalMarkupEntries
    (logError : String → IO Unit)
    (state : TraverseState)
    (previewBackedEntries : Array Entry)
    (renderConfig : ExternalMarkupRenderConfig := {}) :
    IO (Array Entry × Array HtmlCache.Entry) := do
  let mut entries := #[]
  let mut htmlEntries := #[]
  for decoded in Informal.TraversalIndex.ExternalMarkup.entries state do
    match decoded with
    | .error err =>
      logError s!"Blueprint manifest: malformed external-markup entry {err.canonicalName}: {err.message}"
    | .ok stored =>
      let data := stored.data
      if data.markup.isEmpty then
        continue
      if hasPreviewBackedBlockEntry previewBackedEntries data.label then
        continue
      let statementPreview := traversalPreviewOrFallback state data.label .statement
      let manifestEntry := blockSemanticManifestEntry state statementPreview
        (key := externalMarkupEntryKey data.label)
        (targetKind := .externalMarkup)
        (externalMarkup? := some data.markup.toArray)
      entries := entries.push manifestEntry
      if let some markup := selectedExternalMarkup? renderConfig manifestEntry.externalMarkup then
        let heading := manifestEntry.heading
        if let some html := renderExternalMarkupEntryHtml renderConfig manifestEntry.blockData
            heading.caption heading.label markup then
          htmlEntries := htmlEntries.push { key := manifestEntry.key, html }
  pure (entries, htmlEntries)

private def buildLeanCodeEntries
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (hoverState : Verso.Code.Hover.State Output.Html) :
    IO (Array Entry × Array HtmlCache.Entry × Verso.Code.Hover.State Output.Html) := do
  let mut entries := #[]
  let mut htmlEntries := #[]
  let mut hoverState := hoverState
  for decoded in Informal.TraversalIndex.LeanCodePreviews.entries state do
    match decoded with
    | .error err =>
      logError s!"Blueprint manifest: malformed Lean-code preview entry {err.canonicalName}: {err.message}"
    | .ok stored =>
      let entry := stored.data
      let rendered ← Informal.LeanCodePreview.renderWithState entry impls state
        (logError := logError) (hoverState := hoverState)
      hoverState := rendered.hoverState
      let html := rendered.html.asString
      if html.trimAscii.isEmpty then
        continue
      let manifestEntry : Entry := {
        key := Informal.TraversalIndex.LeanCodePreviews.lookupKey entry.target
        targetKind := .leanDecl
        label := entry.target
        facet := .statement
        title := Informal.LeanCodePreview.title entry.target
      }
      entries := entries.push manifestEntry
      htmlEntries := htmlEntries.push { key := manifestEntry.key, html }
  pure (entries, htmlEntries, hoverState)

private def renderCitationEntryHtml
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (entry : Informal.Cite.CitationPreviewData)
    (hoverState : Verso.Code.Hover.State Output.Html) :
    IO (String × Verso.Code.Hover.State Output.Html) := do
  let rendered ← Informal.renderManualHtmlWithStateAndHovers
    (entry.item.citation.bibHtml (Verso.Doc.Html.ToHtml.toHtml (genre := Verso.Genre.Manual)))
    impls state (logError := logError) (hoverState := hoverState)
  let body := Informal.Cite.citationPreviewBody rendered.html entry.kind entry.index
  pure (Output.Html.asString body, rendered.hoverState)

private def buildCitationEntries
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (hoverState : Verso.Code.Hover.State Output.Html) :
    IO (Array Entry × Array HtmlCache.Entry × Verso.Code.Hover.State Output.Html) := do
  let mut entries := #[]
  let mut htmlEntries := #[]
  let mut hoverState := hoverState
  for decoded in Informal.TraversalIndex.CitationPreviews.entries state do
    match decoded with
    | .error err =>
      logError s!"Blueprint manifest: malformed citation preview entry {err.canonicalName}: {err.message}"
    | .ok stored =>
      let citation := stored.data
      let (html, hoverState') ← renderCitationEntryHtml impls logError state citation hoverState
      hoverState := hoverState'
      if html.trimAscii.isEmpty then
        continue
      let manifestEntry : Entry := {
        key := citation.key
        targetKind := .citation
        label := citation.item.label.toName
        facet := .statement
        title := Informal.Cite.citationPreviewTitle citation.item
        href := Informal.TraversalIndex.Bibliography.href? state citation.item.label
      }
      entries := entries.push manifestEntry
      htmlEntries := htmlEntries.push { key := manifestEntry.key, html }
  pure (entries, htmlEntries, hoverState)

/--
Build the semantic Blueprint manifest and rendered-fragment cache from a
completed Manual traversal state.

This is the traversal-to-public-data boundary: traversal domains may contain
semantic payloads that are not visible as rendered page bodies, such as bodyless
external-source directives carrying Lean preview keys. Preserve those facts in
the manifest, and keep rendered fragments in the HTML cache.
-/
def buildPreviewDataFiles
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (externalMarkupConfig : ExternalMarkupRenderConfig := {}) : IO Files := do
  let hoverState := HtmlCache.initialHoverState
  let (traversalPreviews, traversalHtml, hoverState) ← buildTraversalEntries impls logError state hoverState
  let (externalMarkupPreviews, externalMarkupHtml) ←
    buildExternalMarkupEntries logError state traversalPreviews externalMarkupConfig
  let (leanCodePreviews, leanCodeHtml, hoverState) ← buildLeanCodeEntries impls logError state hoverState
  let (citationPreviews, citationHtml, hoverState) ← buildCitationEntries impls logError state hoverState
  let previews := (traversalPreviews ++ externalMarkupPreviews ++ leanCodePreviews ++ citationPreviews).qsort (fun a b => a.key < b.key)
  let htmlEntries := (traversalHtml ++ externalMarkupHtml ++ leanCodeHtml ++ citationHtml).qsort (fun a b => a.key < b.key)
  let graphs := Informal.GraphApi.cachedData state
  pure {
    manifest := { previews, graphs }
    htmlCache := {
      entries := htmlEntries
      hoverDocs := HtmlCache.HoverDoc.ofDedup hoverState.dedup
    }
  }

private def dumpManifest
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (externalMarkupConfig : ExternalMarkupRenderConfig := {}) : IO UInt32 := do
  let errorCount : IO.Ref Nat ← IO.mkRef 0
  let logError msg := do
    errorCount.modify (· + 1)
    IO.eprintln msg
  let cfg ← ReaderT.run (parseRenderConfigOptions config options) extensionImpls
  let (_text, traverseState) ← ReaderT.run (Verso.Genre.Manual.traverseHtmlMulti logError cfg text) extensionImpls
  let files ← buildPreviewDataFiles extensionImpls logError traverseState externalMarkupConfig
  reportPreviewMetadataLossWarnings IO.eprintln traverseState files.manifest
  IO.println <| jsonPretty <| toJson files.manifest
  if (← errorCount.get) == 0 then pure 0 else pure 1

private def dumpHtmlCache
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (externalMarkupConfig : ExternalMarkupRenderConfig := {}) : IO UInt32 := do
  let errorCount : IO.Ref Nat ← IO.mkRef 0
  let logError msg := do
    errorCount.modify (· + 1)
    IO.eprintln msg
  let cfg ← ReaderT.run (parseRenderConfigOptions config options) extensionImpls
  let (_text, traverseState) ← ReaderT.run (Verso.Genre.Manual.traverseHtmlMulti logError cfg text) extensionImpls
  let files ← buildPreviewDataFiles extensionImpls logError traverseState externalMarkupConfig
  reportPreviewMetadataLossWarnings IO.eprintln traverseState files.manifest
  IO.println <| jsonPretty <| toJson files.htmlCache
  if (← errorCount.get) == 0 then pure 0 else pure 1

private def readJsonFileOrEmptyObject (path : System.FilePath) : IO Json := do
  if !(← path.pathExists) then
    pure <| Json.mkObj []
  else
    match Json.parse (← IO.FS.readFile path) with
    | .ok json => pure json
    | .error err => throw <| IO.userError s!"could not parse JSON file {path}: {err}"

private def mergeHtmlCacheHoverDocsIntoVersoDocs
    (docsPath : System.FilePath) (htmlCache : HtmlCache.File) : IO Unit := do
  if htmlCache.hoverDocs.isEmpty then
    return
  let docs ← readJsonFileOrEmptyObject docsPath
  IO.FS.writeFile docsPath (toString <| docs.mergeObj htmlCache.hoverDocsJson)

/--
Emit the canonical Blueprint manifest and rendered-fragment cache files.

The manifest contains semantic data keyed by `PreviewCache`, Lean preview key,
or citation key. The rendered-fragment cache contains the corresponding opaque
rendered fragments for browser hover previews and file-mode consumers such as
slides. Emission also writes the generated ESM APIs under `-verso-data/`, merges
hover payloads into the Verso docs side table, and reports non-fatal warnings
when traversal-preview metadata was lost before export.
-/
def emitBlueprintPreviewData
    (extensionImpls : ExtensionImpls)
    (externalMarkupConfig : ExternalMarkupRenderConfig := {}) :
    ExtraStep := fun mode logError cfg state _text => do
  let files ← buildPreviewDataFiles extensionImpls logError state externalMarkupConfig
  reportPreviewMetadataLossWarnings IO.eprintln state files.manifest
  let outDir := outDirForMode cfg mode
  let dataDir := outDir / "-verso-data"
  let apiDir := dataDir / apiModuleDirname
  IO.FS.createDirAll dataDir
  IO.FS.createDirAll apiDir
  IO.FS.writeFile (dataDir / manifestFilename) (toJson files.manifest).compress
  IO.FS.writeFile (dataDir / htmlCacheFilename) (toJson files.htmlCache).compress
  IO.FS.writeFile (dataDir / graphCoreModuleFilename) graphCoreModuleMjs
  IO.FS.writeFile (dataDir / previewCoreModuleFilename) previewCoreModuleMjs
  IO.FS.writeFile (dataDir / apiCommonModuleFilename) apiCommonModuleMjs
  IO.FS.writeFile (dataDir / graphApiModuleFilename) graphApiModuleMjs
  IO.FS.writeFile (dataDir / dataApiModuleFilename) dataApiModuleMjs
  IO.FS.writeFile (dataDir / previewApiModuleFilename) previewApiModuleMjs
  writePageRuntimeModules dataDir
  writePreviewRuntimeModules dataDir
  IO.FS.writeFile (apiDir / graphApiModuleAliasFilename) graphApiModuleAliasMjs
  IO.FS.writeFile (apiDir / dataApiModuleAliasFilename) dataApiModuleAliasMjs
  IO.FS.writeFile (apiDir / previewApiModuleAliasFilename) previewApiModuleAliasMjs
  mergeHtmlCacheHoverDocsIntoVersoDocs (outDir / "-verso-docs.json") files.htmlCache
  emitPublicXref mode logError cfg state

def handleDumpSchemaFlag (args : List String) : IO (Option UInt32 × List String) := do
  if args.contains dumpSchemaFlag then
    IO.println schemaString
    pure (some 0, stripFlag dumpSchemaFlag args)
  else
    pure (none, args)

def handleCliFlags
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (externalMarkupConfig : ExternalMarkupRenderConfig := {}) :
    IO (Option UInt32 × List String × ExternalMarkupRenderConfig) := do
  if options.contains helpFlag then
    IO.println helpText
    pure (some 0, stripFlag helpFlag options, externalMarkupConfig)
  else if options.contains dumpSchemaFlag then
    let (dumped?, options) ← handleDumpSchemaFlag options
    pure (dumped?, options, externalMarkupConfig)
  else
    let (externalMarkupConfig, options) ←
      parseExternalMarkupRenderOptionsIO externalMarkupConfig options
    if options.contains dumpManifestFlag then
      let options := stripFlag dumpManifestFlag options
      let code ← dumpManifest text options extensionImpls config externalMarkupConfig
      pure (some code, options, externalMarkupConfig)
    else if options.contains dumpHtmlCacheFlag then
      let options := stripFlag dumpHtmlCacheFlag options
      let code ← dumpHtmlCache text options extensionImpls config externalMarkupConfig
      pure (some code, options, externalMarkupConfig)
    else
      pure (none, options, externalMarkupConfig)

private abbrev HtmlTraverse :=
  (String → IO Unit) → RenderConfig → Part Manual → ReaderT ExtensionImpls IO (Part Manual × TraverseState)

private abbrev HtmlEmitter :=
  (String → IO Unit) → RenderConfig → Part Manual → TraverseState → ReaderT ExtensionImpls IO Unit

private def emitBlueprintHtml
    (extraSteps : List ExtraStep)
    (how : EmitHtml)
    (mode : Mode)
    (logError : String → IO Unit)
    (cfg : RenderConfig)
    (text : Part Manual)
    (traverse : HtmlTraverse)
    (emit : HtmlEmitter) :
    ReaderT ExtensionImpls IO Unit := do
  let outDir := outputDirNameForMode mode
  match how with
  | .no => pure ()
  | .immediately =>
      if cfg.verbose then
        IO.println s!"Saving {match mode with | .single => "single" | .multi => "multi"}-page HTML"
      let (text', traverseState) ← traverse logError cfg text
      let traverseState := patchBlueprintTraverseState traverseState
      emitXrefsJson (cfg.destination / outDir) traverseState
      emit logError cfg text' traverseState
      for step in extraSteps do
        step mode logError cfg.toConfig traverseState text'
  | .delay f =>
      let (text', traverseState) ← traverse logError cfg text
      let traverseState := patchBlueprintTraverseState traverseState
      emitXrefsJson (cfg.destination / outDir) traverseState
      SavedState.mk text' traverseState |>.save f
  | .resumeFrom f =>
      let { text, traverseState } ← SavedState.load f
      let traverseState := patchBlueprintTraverseState traverseState
      emit logError cfg text traverseState
      for step in extraSteps do
        step mode logError cfg.toConfig traverseState text

def blueprintMain (text : Part Manual)
    (extensionImpls : ExtensionImpls := by exact extension_impls%)
    (options : List String)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 :=
  ReaderT.run go extensionImpls
where
  go : ReaderT ExtensionImpls IO UInt32 := do
    let errorCount : IO.Ref Nat ← IO.mkRef 0
    let logError msg := do
      errorCount.modify (· + 1)
      IO.eprintln msg
    let cfg ← parseRenderConfigOptions (withBuildMetadataAssets config) options
    let buildMetadata ← readBuildMetadata
    let extraSteps := emitBuildMetadata buildMetadata :: extraSteps

    if cfg.emitTeX then
      if cfg.verbose then
        IO.println "Saving TeX"
      emitTeX logError cfg.toConfig text

    emitBlueprintHtml extraSteps cfg.emitHtmlSingle .single logError cfg text
      traverseHtmlSingle emitHtmlSingle
    emitBlueprintHtml extraSteps cfg.emitHtmlMulti .multi logError cfg text
      traverseHtmlMulti emitHtmlMulti

    if let some wcFile := cfg.wordCount then
      if cfg.verbose then
        IO.println s!"Saving word counts to {wcFile}"
      wordCount wcFile logError cfg.toConfig text

    match ← errorCount.get with
    | 0 => return 0
    | 1 =>
        IO.eprintln "An error was encountered!"
        return 1
    | n =>
        IO.eprintln s!"{n} errors were encountered!"
        return 1

def blueprintMainWithPreviewData
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 := do
  let config := withBlueprintAssets config
  let (dumped?, options, externalMarkupConfig) ← handleCliFlags text options extensionImpls config
  if let some code := dumped? then
    return code
  blueprintMain text (extensionImpls := extensionImpls) (options := options) (config := config)
    (extraSteps := emitBlueprintPreviewData extensionImpls externalMarkupConfig :: extraSteps)

-- Compatibility for reference generators pinned before preview data was renamed.
@[deprecated blueprintMainWithPreviewData (since := "2026-06-08")]
def manualMainWithPreviewData
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 :=
  blueprintMainWithPreviewData text options extensionImpls config extraSteps

@[deprecated blueprintMainWithPreviewData (since := "2026-06-08")]
def manualMainWithSharedPreviewManifest
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 :=
  blueprintMainWithPreviewData text options extensionImpls config extraSteps

end Informal.PreviewManifest
