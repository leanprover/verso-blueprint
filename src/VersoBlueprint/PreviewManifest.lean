/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Elab.Command
import Std.Data.HashSet
import VersoManual
import VersoManual.HighlightedCode
import VersoBlueprint.Cite
import VersoBlueprint.Informal.Block
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Group
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.PreviewCache
import VersoBlueprint.PreviewRender
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

namespace Informal.PreviewManifest

open Lean Elab Command Term Meta
open Verso Doc
open Verso.Genre Manual

def blueprintHtmlAssets : HtmlAssets :=
  Verso.Genre.Manual.highlightAssets

def withBlueprintAssets (config : RenderConfig := {}) : RenderConfig :=
  let htmlConfig := config.toHtmlConfig
  let htmlAssets := htmlConfig.toHtmlAssets.combine blueprintHtmlAssets
  { config with
    toHtmlConfig := { htmlConfig with toHtmlAssets := htmlAssets }
  }

def manifestFilename : String := "blueprint-preview-manifest.json"

inductive EntryKind where
  | block
  | leanDecl
  | citation
deriving Inhabited, Repr, ToJson, FromJson

structure Entry where
  /-- Composite preview lookup key for this target family. -/
  key : String
  /-- Preview target family. -/
  targetKind : EntryKind
  /-- Canonical target label: informal label, Lean declaration name, or citation label. -/
  label : Name
  /-- Which preview variant this entry contains; non-block previews use `statement`. -/
  facet : PreviewCache.Facet
  /-- Kind (definition, lemma, theorem, corollary). -/
  kind : Option Informal.Data.NodeKind := none
  /-- Resolved display title for this preview entry. -/
  title : String
  /-- Canonical link target for the rendered informal node. -/
  href : Option String := none
  /-- Parent/group label for this informal node, if any. -/
  parent : Option Name := none
  /-- Resolved display title for the parent/group, if any. -/
  parentTitle : Option String := none
  /-- Informal nodes used by the statement. -/
  statementDeps : Array Name := #[]
  /-- Informal nodes used by the proof. -/
  proofDeps : Array Name := #[]
  /-- Resolved display name of the assigned owner, if available. -/
  ownerDisplayName : Option String := none
  /-- Normalized tags attached to this informal node. -/
  tags : Array String := #[]
  /-- Declared triage priority for this informal node, if any. -/
  priority : Option String := none
  /-- Declared effort estimate for this informal node, if any. -/
  effort : Option String := none
  /-- Rendered HTML body for this preview. -/
  html : String
deriving Inhabited, Repr, ToJson, FromJson

structure File where
  previews : Array Entry := #[]
deriving Inhabited, Repr, ToJson, FromJson

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
                throwError "Schema generation currently supports only nullary inductives, but '{name}' has constructor '{ctorName}' with fields"
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
  | .error err => panic! s!"Invalid generated preview manifest schema: {err}"

private def jsonPretty (json : Json) : String :=
  json.render.pretty 80

private def outDirForMode (cfg : Verso.Genre.Manual.Config) (mode : Mode) : System.FilePath :=
  cfg.destination / (match mode with | .single => "html-single" | .multi => "html-multi")

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

private def highlightedDocstringInnerTextRead : String :=
  "const str = d.innerText;"

private def highlightedDocstringTextContentRead : String :=
  "const str = d.textContent || \"\";"

private def patchHighlightedDocstringStartupHtml (html : String) : Option String :=
  let patched := html.replace highlightedDocstringInnerTextRead highlightedDocstringTextContentRead
  if patched == html then none else some patched

private partial def patchHighlightedDocstringStartup (outDir : System.FilePath) : IO Unit := do
  if !(← outDir.pathExists) then
    return
  if ← outDir.isDir then
    for entry in ← outDir.readDir do
      patchHighlightedDocstringStartup entry.path
  else if outDir.extension == "html" then
    let html ← IO.FS.readFile outDir
    if let some patched := patchHighlightedDocstringStartupHtml html then
      IO.FS.writeFile outDir patched

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

private def blockTitle (state : TraverseState) (label : Name) (blockData? : Option Informal.BlockData := none) : String :=
  match blockData? <|> blockInfo? state label with
  | some blockData => blockData.displayTitle state
  | none => label.toString

private def blockHref (state : TraverseState) (label : Name) : Option String :=
  Informal.TraversalIndex.Nodes.href? state label

private def blockKind? (blockData? : Option Informal.BlockData) : Option Informal.Data.NodeKind :=
  match blockData? with
  | some blockData =>
      match blockData.kind with
      | Informal.Data.InProgressKind.statement kind => some kind
      | Informal.Data.InProgressKind.proof => none
  | none => none

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

private def buildTraversalEntries
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState) : IO (Array Entry) := do
  let some domain := Informal.TraversalIndex.TraversalPreviews.domain? state
    | return #[]
  let mut entries := #[]
  for (_key, obj) in domain.objects.toArray do
    match fromJson? (α := PreviewCache.Entry) obj.data with
    | .error err =>
      logError s!"Preview manifest: malformed preview entry {obj.canonicalName}: {err}"
    | .ok entry =>
      if entry.blocks.isEmpty then
        continue
      let html ← Output.Html.asString <$> Informal.renderManualBlocksHtmlWithState entry.blocks impls state
        (logError := logError)
      if html.trimAscii.isEmpty then
        continue
      let blockData? := blockInfo? state entry.label
      let key := PreviewCache.key entry.label entry.facet
      let manifestEntry : Entry := {
        key
        targetKind := .block
        label := entry.label
        facet := entry.facet
        kind := blockKind? blockData?
        title := blockTitle state entry.label blockData?
        href := blockHref state entry.label
        parent := blockData?.bind (·.parent)
        parentTitle := blockParentTitle? state blockData?
        statementDeps := blockData?.map (·.statementDeps) |>.getD #[]
        proofDeps := blockData?.map (·.proofDeps) |>.getD #[]
        ownerDisplayName := blockData?.bind (·.ownerDisplayName)
        tags := blockData?.map (·.tags) |>.getD #[]
        priority := blockData?.bind (·.priority)
        effort := blockData?.bind (·.effort)
        html
      }
      entries := entries.push manifestEntry
  pure entries

private def buildLeanCodeEntries
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState) : IO (Array Entry) := do
  let some domain := Informal.TraversalIndex.LeanCodePreviews.domain? state
    | return #[]
  let mut entries := #[]
  for (_key, obj) in domain.objects.toArray do
    match fromJson? (α := Informal.LeanCodePreview.Entry) obj.data with
    | .error err =>
      logError s!"Preview manifest: malformed Lean-code preview entry {obj.canonicalName}: {err}"
    | .ok entry =>
      let html ← Output.Html.asString <$> Informal.LeanCodePreview.renderHtmlWithState entry impls state
        (logError := logError)
      if html.trimAscii.isEmpty then
        continue
      let manifestEntry : Entry := {
        key := Informal.TraversalIndex.LeanCodePreviews.lookupKey entry.target
        targetKind := .leanDecl
        label := entry.target
        facet := .statement
        title := Informal.LeanCodePreview.title entry.target
        html
      }
      entries := entries.push manifestEntry
  pure entries

private def renderCitationEntryHtml
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (entry : Informal.Cite.CitationPreviewData) : IO String := do
  let citationHtml ← Informal.renderManualHtmlWithState
    (entry.item.citation.bibHtml (Verso.Doc.Html.ToHtml.toHtml (genre := Verso.Genre.Manual)))
    impls state (logError := logError)
  let body := Informal.Cite.citationPreviewBody citationHtml entry.kind entry.index
  pure <| Output.Html.asString body

private def buildCitationEntries
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState) : IO (Array Entry) := do
  let some domain := Informal.TraversalIndex.CitationPreviews.domain? state
    | return #[]
  let mut entries := #[]
  for (_key, obj) in domain.objects.toArray do
    match fromJson? (α := Informal.Cite.CitationPreviewData) obj.data with
    | .error err =>
      logError s!"Preview manifest: malformed citation preview entry {obj.canonicalName}: {err}"
    | .ok citation =>
      let html ← renderCitationEntryHtml impls logError state citation
      if html.trimAscii.isEmpty then
        continue
      let manifestEntry : Entry := {
        key := citation.key
        targetKind := .citation
        label := citation.item.label.toName
        facet := .statement
        title := Informal.Cite.citationPreviewTitle citation.item
        href := Informal.TraversalIndex.Bibliography.href? state citation.item.label
        html
      }
      entries := entries.push manifestEntry
  pure entries

private def buildManifestFile
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState) : IO File := do
  let traversalPreviews ← buildTraversalEntries impls logError state
  let leanCodePreviews ← buildLeanCodeEntries impls logError state
  let citationPreviews ← buildCitationEntries impls logError state
  let previews := (traversalPreviews ++ leanCodePreviews ++ citationPreviews).qsort (fun a b => a.key < b.key)
  pure { previews }

private def parseRenderConfigOptions (config : RenderConfig := {}) :
    List String → ReaderT ExtensionImpls IO RenderConfig
  | ("--output"::dir::more) => parseRenderConfigOptions { config with destination := dir } more
  | ("--depth"::n::more) => parseRenderConfigOptions { config with htmlDepth := n.toNat! } more

  | ("--with-tex"::more) => parseRenderConfigOptions { config with emitTeX := true } more
  | ("--without-tex"::more) => parseRenderConfigOptions { config with emitTeX := false } more

  | ("--with-html-single"::more) => parseRenderConfigOptions { config with emitHtmlSingle := .immediately } more
  | ("--delay-html-single"::more) =>
    match Verso.CLI.requireFilename "--delay-html-single" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlSingle := .delay f } more'
    | .error e => throw (↑ e)
  | ("--resume-html-single"::more) =>
    match Verso.CLI.requireFilename "--resume-html-single" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlSingle := .resumeFrom f } more'
    | .error e => throw (↑ e)
  | ("--without-html-single"::more) => parseRenderConfigOptions { config with emitHtmlSingle := .no } more

  | ("--with-html-multi"::more) => parseRenderConfigOptions { config with emitHtmlMulti := .immediately } more
  | ("--delay-html-multi"::more) =>
    match Verso.CLI.requireFilename "--delay-html-multi" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlMulti := .delay f } more'
    | .error e => throw (↑ e)
  | ("--resume-html-multi"::more) =>
    match Verso.CLI.requireFilename "--resume-html-multi" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlMulti := .resumeFrom f } more'
    | .error e => throw (↑ e)
  | ("--without-html-multi"::more) => parseRenderConfigOptions { config with emitHtmlMulti := .no } more

  | ("--with-word-count"::more) =>
    match Verso.CLI.requireFilename "--with-word-count" more with
    | .ok file more' _ => parseRenderConfigOptions { config with wordCount := some file } more'
    | .error e => throw (↑ e)
  | ("--without-word-count"::more) => parseRenderConfigOptions { config with wordCount := none } more
  | ("--draft"::more) => parseRenderConfigOptions { config with draft := true } more
  | ("--verbose"::more) => parseRenderConfigOptions { config with verbose := true } more
  | ("--remote-config"::more) =>
    match Verso.CLI.requireFilename "--remote-config" more with
    | .ok file more' _ => parseRenderConfigOptions { config with remoteConfigFile := some file } more'
    | .error e => throw (↑ e)
  | (other :: _) => throw (↑ s!"Unknown option {other}")
  | [] => pure config

private def dumpManifest
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {}) : IO UInt32 := do
  let errorCount : IO.Ref Nat ← IO.mkRef 0
  let logError msg := do
    errorCount.modify (· + 1)
    IO.eprintln msg
  let cfg ← ReaderT.run (parseRenderConfigOptions config options) extensionImpls
  let (_text, traverseState) ← ReaderT.run (Verso.Genre.Manual.traverseHtmlMulti logError cfg text) extensionImpls
  let file ← buildManifestFile extensionImpls logError traverseState
  IO.println <| jsonPretty <| toJson file
  if (← errorCount.get) == 0 then pure 0 else pure 1

/--
Emit the canonical shared blueprint preview manifest file.

The shared manifest contains:
- traversal-cached statement/proof previews keyed by `PreviewCache`,
- dedicated Lean-code previews keyed by `Informal.LeanCodePreview`.
- citation previews keyed by citation label, style, and locator.
-/
def emitSharedPreviewManifest (extensionImpls : ExtensionImpls) : ExtraStep := fun mode logError cfg state _text => do
  let file ← buildManifestFile extensionImpls logError state
  let outDir := outDirForMode cfg mode
  let dataDir := outDir / "-verso-data"
  IO.FS.createDirAll dataDir
  let json := (toJson file).compress
  IO.FS.writeFile (dataDir / manifestFilename) json
  emitPublicXref mode logError cfg state
  patchHighlightedDocstringStartup outDir

def dumpSchemaFlag : String := "--dump-schema"
def dumpManifestFlag : String := "--dump-manifest"
def helpFlag : String := "--help"

def helpText : String := String.intercalate "\n" [
  "Blueprint preview manifest options:",
  s!"  {dumpSchemaFlag}    Print the preview manifest JSON Schema and exit.",
  s!"  {dumpManifestFlag}  Print the generated preview manifest JSON and exit.",
  s!"  {helpFlag}           Show this help text and exit.",
  "",
  "Standard manual rendering options:",
  "  --output <dir>",
  "  --depth <n>",
  "  --with-tex | --without-tex",
  "  --with-html-single | --delay-html-single <file> | --resume-html-single <file> | --without-html-single",
  "  --with-html-multi | --delay-html-multi <file> | --resume-html-multi <file> | --without-html-multi",
  "  --with-word-count <file> | --without-word-count",
  "  --draft",
  "  --verbose",
  "  --remote-config <file>"
]

private def stripFlag (flag : String) (args : List String) : List String :=
  args.filter (· != flag)

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
    (config : RenderConfig := {}) : IO (Option UInt32 × List String) := do
  if options.contains helpFlag then
    IO.println helpText
    pure (some 0, stripFlag helpFlag options)
  else if options.contains dumpManifestFlag then
    let options := stripFlag dumpManifestFlag options
    let code ← dumpManifest text options extensionImpls config
    pure (some code, options)
  else
    handleDumpSchemaFlag options

def blueprintMainWithSharedPreviewManifest
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 := do
  let config := withBlueprintAssets config
  let (dumped?, options) ← handleCliFlags text options extensionImpls config
  if let some code := dumped? then
    return code
  manualMain text (extensionImpls := extensionImpls) (options := options) (config := config)
    (extraSteps := emitSharedPreviewManifest extensionImpls :: extraSteps)

def manualMainWithSharedPreviewManifest
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 :=
  blueprintMainWithSharedPreviewManifest text options extensionImpls config extraSteps

end Informal.PreviewManifest
