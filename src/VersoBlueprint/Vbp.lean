/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.PreviewManifest

namespace VersoBlueprint.Vbp

open Lean
open System

abbrev ManifestFile := Informal.PreviewManifest.File
abbrev HtmlCacheFile := Informal.PreviewManifest.HtmlCache.File
abbrev Entry := Informal.PreviewManifest.Entry
abbrev RelatedEntry := Informal.PreviewManifest.RelatedEntry
abbrev GroupRelation := Informal.PreviewManifest.GroupRelation
abbrev RelationAxis := Informal.PreviewManifest.RelationAxis
abbrev PreviewArtifactIndex := Informal.PreviewManifest.PreviewArtifactIndex
abbrev PersistedGeneratedData := Informal.PreviewManifest.PersistedFiles
abbrev WorkQueueItem := Informal.PreviewManifest.WorkQueueItem

def defaultSite : FilePath := "_out" / "site"

def defaultOutput : FilePath := defaultSite

def apiStability : String := "unstable"

def responseJson (fields : List (String × Json)) : Json :=
  Json.mkObj (("apiStability", Json.str apiStability) :: fields)

def htmlDirForSite (site : FilePath) : IO FilePath := do
  if ← (site / "-verso-data" / Informal.PreviewManifest.manifestFilename).pathExists then
    pure site
  else
    pure (site / "html-multi")

def dataDirForSite (site : FilePath) : IO FilePath := do
  pure ((← htmlDirForSite site) / "-verso-data")

def manifestPathForSite (site : FilePath) : IO FilePath := do
  pure ((← dataDirForSite site) / Informal.PreviewManifest.manifestFilename)

def htmlCachePathForSite (site : FilePath) : IO FilePath := do
  pure ((← dataDirForSite site) / Informal.PreviewManifest.htmlCacheFilename)

private def nameJson (name : Name) : Json :=
  Json.str (Informal.PreviewManifest.labelString name)

private def optionStringJson : Option String → Json
  | none => Json.null
  | some value => Json.str value

private def optionNameJson : Option Name → Json
  | none => Json.null
  | some value => nameJson value

private def stringArrayJson (values : Array String) : Json :=
  Json.arr (values.map Json.str)

private def kindString : Option Informal.Data.NodeKind → String
  | none => "unknown"
  | some kind => (toString kind).toLower

private def useRefJson (useRef : Informal.Data.UseRef) : Json :=
  Json.mkObj [
    ("label", nameJson useRef.label),
    ("origin", Json.str (toString useRef.origin)),
    ("intent", Json.str (toString useRef.intent))
  ]

private def relationAxisJson (axis : RelationAxis) : Json :=
  Json.str axis.display

private def relatedEntryJson (entry : RelatedEntry) : Json :=
  Json.mkObj [
    ("label", nameJson entry.label),
    ("title", Json.str entry.title),
    ("href", optionStringJson entry.href),
    ("previewKey", toJson entry.previewKey),
    ("axes", Json.arr (entry.axes.map relationAxisJson))
  ]

private def groupRelationJson (group : GroupRelation) : Json :=
  Json.mkObj [
    ("label", nameJson group.label),
    ("title", Json.str group.title),
    ("declared", Json.bool group.declared),
    ("entries", Json.arr (group.entries.map relatedEntryJson))
  ]

private def entrySummaryFields (entry : Entry) : List (String × Json) := [
    ("key", Json.str entry.key),
    ("label", nameJson entry.label),
    ("authoredLabel", Json.str entry.authoredLabel),
    ("title", Json.str entry.title),
    ("kind", toJson entry.kind),
    ("facet", toJson entry.facet),
    ("href", optionStringJson entry.href),
    ("parent", optionNameJson entry.parent),
    ("parentTitle", optionStringJson entry.parentTitle),
    ("ownerDisplayName", optionStringJson entry.ownerDisplayName),
    ("tags", stringArrayJson entry.tags),
    ("priority", optionStringJson entry.priority),
    ("effort", optionStringJson entry.effort),
    ("leanCodePreviewKeys", stringArrayJson entry.leanCodePreviewKeys)
  ]

private def entrySummaryJson (entry : Entry) : Json :=
  Json.mkObj (entrySummaryFields entry)

private def workQueueItemJson (item : WorkQueueItem) : Json :=
  Json.mkObj <| entrySummaryFields item.entry ++ [
    ("nextStep", Json.str item.nextStep),
    ("statementStatus", Json.str item.graphNode.statementStatus.toText),
    ("proofStatus", Json.str item.graphNode.proofStatus.toText)
  ]

private def entryGroupJson (manifest : ManifestFile) (entry : Entry) : Json :=
  match manifest.groupForEntry? entry with
  | none => Json.null
  | some group => groupRelationJson group

private def entryDetailFields
    (entry : Entry)
    (group? : Option GroupRelation := none) : List (String × Json) := [
    ("key", Json.str entry.key),
    ("targetKind", toJson entry.targetKind),
    ("label", nameJson entry.label),
    ("authoredLabel", Json.str entry.authoredLabel),
    ("facet", toJson entry.facet),
    ("kind", toJson entry.kind),
    ("title", Json.str entry.title),
    ("displayCaption", optionStringJson entry.displayCaption),
    ("displayLabel", optionStringJson entry.displayLabel),
    ("href", optionStringJson entry.href),
    ("parent", optionNameJson entry.parent),
    ("parentTitle", optionStringJson entry.parentTitle),
    ("statementUses", Json.arr (entry.statementUses.map useRefJson)),
    ("proofUses", Json.arr (entry.proofUses.map useRefJson)),
    ("leanCodePreviewKeys", stringArrayJson entry.leanCodePreviewKeys),
    ("codeData", toJson entry.codeData),
    ("uses", Json.arr (entry.uses.map relatedEntryJson)),
    ("usedBy", Json.arr (entry.usedBy.map relatedEntryJson)),
    ("group", group?.map groupRelationJson |>.getD Json.null),
    ("ownerDisplayName", optionStringJson entry.ownerDisplayName),
    ("tags", stringArrayJson entry.tags),
    ("priority", optionStringJson entry.priority),
    ("effort", optionStringJson entry.effort)
  ]

private def entryResponseJson (manifest : ManifestFile) (entry : Entry) : Json :=
  responseJson (entryDetailFields entry (manifest.groupForEntry? entry))

private def incrementCount (counts : Array (String × Nat)) (key : String) : Array (String × Nat) :=
  let rec go (seen : Bool) (acc : Array (String × Nat)) : List (String × Nat) → Array (String × Nat)
    | [] =>
        if seen then acc else acc.push (key, 1)
    | (name, count) :: rest =>
        if name == key then
          go true (acc.push (name, count + 1)) rest
        else
          go seen (acc.push (name, count)) rest
  go false #[] counts.toList

private def countsJson (counts : Array (String × Nat)) : Json :=
  let counts := counts.qsort (fun a b => a.1 < b.1)
  Json.mkObj (counts.toList.map fun (key, count) => (key, Json.num count))

private def statsJson (manifest : ManifestFile) : Json :=
  let entries := manifest.queryableStatementEntries
  let byKind := entries.foldl (fun counts entry => incrementCount counts (kindString entry.kind)) #[]
  let byOwner := entries.foldl
    (fun counts entry => entry.ownerDisplayName.map (incrementCount counts ·) |>.getD counts)
    #[]
  let byTag := entries.foldl
    (fun counts entry => entry.tags.foldl incrementCount counts)
    #[]
  responseJson [
    ("statements", Json.num entries.size),
    ("byKind", countsJson byKind),
    ("byOwner", countsJson byOwner),
    ("byTag", countsJson byTag)
  ]

private def missingLabelJson (label : String) : Json :=
  responseJson [
    ("error", Json.str "unknown-label"),
    ("label", Json.str label)
  ]

private def withPrimaryEntry
    (manifest : ManifestFile) (label : String) (mkJson : Entry → Json) : Json :=
  match manifest.findPrimaryQueryableEntry? label with
  | some entry => mkJson entry
  | none => missingLabelJson label

/-- A validated query and the manifest projection needed to execute it. -/
structure QueryPlan where
  /-- Whether execution requires reconstructing strict graph projections. -/
  needsGraphData : Bool
  /-- Execute the validated query against the selected manifest projection. -/
  run : ManifestFile → Json

private structure QuerySelector where
  name : String
  argumentName : String
  needsGraphData : Bool
  run : Sum (ManifestFile → Json) (String → ManifestFile → Json)

private def QuerySelector.noArg
    (name : String) (needsGraphData : Bool) (run : ManifestFile → Json) : QuerySelector :=
  { name, argumentName := "", needsGraphData, run := .inl run }

private def QuerySelector.oneArg
    (name argumentName : String) (needsGraphData : Bool)
    (run : String → ManifestFile → Json) : QuerySelector :=
  { name, argumentName, needsGraphData, run := .inr run }

private def QuerySelector.line (selector : QuerySelector) : String :=
  match selector.run with
  | .inl _ => selector.name
  | .inr _ => s!"{selector.name} <{selector.argumentName}>"

private def QuerySelector.plan? (selector : QuerySelector) (args : List String) : Option QueryPlan :=
  match selector.run, args with
  | .inl run, [name] =>
      if name == selector.name then
        some { needsGraphData := selector.needsGraphData, run }
      else
        none
  | .inr run, [name, argument] =>
      if name == selector.name then
        some {
          needsGraphData := selector.needsGraphData
          run := run argument
        }
      else
        none
  | _, _ => none

private def querySelectors : List QuerySelector := [
  QuerySelector.noArg "labels" false fun manifest =>
    responseJson [
      ("labels", Json.arr (manifest.queryableStatementEntries.map entrySummaryJson))
    ],
  QuerySelector.oneArg "node" "label" false fun label manifest =>
    withPrimaryEntry manifest label (entryResponseJson manifest),
  QuerySelector.oneArg "uses" "label" false fun label manifest =>
    withPrimaryEntry manifest label fun entry =>
      responseJson [
        ("label", Json.str label),
        ("statementUses", Json.arr (entry.statementUses.map useRefJson)),
        ("proofUses", Json.arr (entry.proofUses.map useRefJson)),
        ("uses", Json.arr (entry.uses.map relatedEntryJson))
      ],
  QuerySelector.oneArg "used-by" "label" false fun label manifest =>
    withPrimaryEntry manifest label fun entry =>
      responseJson [
        ("label", Json.str label),
        ("usedBy", Json.arr (entry.usedBy.map relatedEntryJson))
      ],
  QuerySelector.oneArg "group" "label" false fun label manifest =>
    withPrimaryEntry manifest label fun entry =>
      responseJson [
        ("label", Json.str label),
        ("group", entryGroupJson manifest entry)
      ],
  QuerySelector.noArg "owners" false fun manifest =>
    responseJson [("owners", stringArrayJson manifest.ownerValues)],
  QuerySelector.noArg "tags" false fun manifest =>
    responseJson [("tags", stringArrayJson manifest.tagValues)],
  QuerySelector.noArg "work-queue" true fun manifest =>
    responseJson [
      ("entries", Json.arr (manifest.workQueueItems.map workQueueItemJson))
    ],
  QuerySelector.noArg "metadata" false fun manifest =>
    responseJson [
      ("entries", Json.arr (manifest.metadataEntries.map entrySummaryJson))
    ],
  QuerySelector.oneArg "search" "text" false fun text manifest =>
    responseJson [
      ("query", Json.str text),
      ("labels", Json.arr (manifest.queryableStatementEntries |>.filter
        (fun entry => entry.matchesText text) |>.map entrySummaryJson))
    ],
  QuerySelector.oneArg "code" "decl" false fun decl manifest =>
    responseJson [
      ("query", Json.str decl),
      ("labels", Json.arr (manifest.queryableStatementEntries |>.filter
        (fun entry => entry.matchesCode decl) |>.map entrySummaryJson))
    ],
  QuerySelector.noArg "stats" false statsJson
]

def querySelectorLines : List String :=
  "selectors" :: querySelectors.map QuerySelector.line

def querySelectorsJson : Json :=
  responseJson [
    ("selectors", Json.arr (querySelectorLines.toArray.map Json.str))
  ]

private def findQueryPlan? (args : List String) : List QuerySelector → Option QueryPlan
  | [] => none
  | selector :: selectors =>
      selector.plan? args |>.orElse (fun _ => findQueryPlan? args selectors)

private def findQuerySelector? (name : String) : List QuerySelector → Option QuerySelector
  | [] => none
  | selector :: selectors =>
      if selector.name == name then some selector else findQuerySelector? name selectors

/-- Parse and validate a query before reading any generated data. -/
def parseQueryPlan (args : List String) : Except String (Option QueryPlan) :=
  match args with
  | ["selectors"] => .ok none
  | [] => .error "missing query selector"
  | name :: _ =>
      match findQueryPlan? args querySelectors with
      | some plan => .ok (some plan)
      | none =>
          if name == "selectors" then
            .error "invalid arguments for query selector 'selectors'; expected 'selectors'"
          else
            match findQuerySelector? name querySelectors with
            | some selector =>
                .error s!"invalid arguments for query selector '{name}'; expected '{selector.line}'"
            | none => .error s!"unknown query selector '{name}'"

def queryJson (manifest : ManifestFile) (args : List String) : Except String Json :=
  match parseQueryPlan args with
  | .ok none => .ok querySelectorsJson
  | .ok (some plan) => .ok (plan.run manifest)
  | .error err => .error err

private def readManifestWith
    (read : FilePath → IO ManifestFile) (site : FilePath) : IO ManifestFile := do
  let manifestPath ← manifestPathForSite site
  unless ← manifestPath.pathExists do
    throw <| IO.userError s!"missing Blueprint manifest at {manifestPath}; run `lake exe vbp build` first"
  read manifestPath

def readManifestForSite (site : FilePath) : IO ManifestFile :=
  readManifestWith Informal.PreviewManifest.readFile site

/-- Read exactly the manifest projection required by a validated query. -/
def readManifestForQuery (site : FilePath) (plan : QueryPlan) : IO ManifestFile := do
  if plan.needsGraphData then
    readManifestForSite site
  else
    readManifestWith Informal.PreviewManifest.readFileWithoutGraphs site

def readHtmlCacheForSite (site : FilePath) : IO HtmlCacheFile := do
  let htmlCachePath ← htmlCachePathForSite site
  unless ← htmlCachePath.pathExists do
    throw <| IO.userError s!"missing Blueprint HTML cache at {htmlCachePath}; run `lake exe vbp build` first"
  Informal.PreviewManifest.HtmlCache.readFile htmlCachePath

def readPersistedGeneratedData (site : FilePath) : IO PersistedGeneratedData := do
  let manifest ← readManifestForSite site
  let htmlCache ← readHtmlCacheForSite site
  pure { manifest, htmlCache }

private def pushMissingCacheKey
    (index : PreviewArtifactIndex) (errors : Array String) (context key : String) :
    Array String :=
  if index.hasCacheKey key then
    errors
  else
    errors.push s!"missing HTML cache entry for {context}: {key}"

private def pushMissingManifestKey
    (index : PreviewArtifactIndex) (errors : Array String) (context key : String) :
    Array String :=
  if index.hasManifestKey key then
    errors
  else
    errors.push s!"missing manifest entry for {context}: {key}"

private def checkPreviewReference
    (index : PreviewArtifactIndex) (context key : String) (errors : Array String) :
    Array String :=
  let errors := pushMissingManifestKey index errors context key
  pushMissingCacheKey index errors context key

private def checkRelatedEntries
    (index : PreviewArtifactIndex) (context : String) (entries : Array RelatedEntry)
    (errors : Array String) : Array String :=
  entries.foldl
    (fun errors entry =>
      match entry.previewKey with
      | none => errors
      | some key =>
        let context := s!"{context} relation {Informal.PreviewManifest.labelString entry.label}"
        checkPreviewReference index context key.value errors)
    errors

private def checkGraphNodePreviewKey
    (index : PreviewArtifactIndex) (graphKey : String) (node : Informal.Graph.NodeData)
    (errors : Array String) : Array String :=
  match node.previewKey with
  | none => errors
  | some key =>
      checkPreviewReference index
        s!"graph {graphKey} node {Informal.PreviewManifest.labelString node.label}"
        key.value errors

private def checkGraphPreviewKeys
    (index : PreviewArtifactIndex) (graph : Informal.Graph.GraphData)
    (errors : Array String) : Array String :=
  graph.nodes.foldl (fun errors node => checkGraphNodePreviewKey index graph.key node errors) errors

private def checkManifestGroupIntegrity
    (manifest : ManifestFile) (errors : Array String) : Array String := Id.run do
  let mut errors := errors
  let mut groupsByLabel : NameMap GroupRelation := {}
  let mut memberGroups : NameMap Name := {}
  for group in manifest.groups do
    if group.label == .anonymous then
      errors := errors.push "manifest group has empty label"
    if group.title.trimAscii.toString.isEmpty then
      errors := errors.push <|
        s!"manifest group {Informal.PreviewManifest.labelString group.label} has empty title"
    if groupsByLabel.contains group.label then
      errors := errors.push
        s!"duplicate manifest group label: {Informal.PreviewManifest.labelString group.label}"
    else
      groupsByLabel := groupsByLabel.insert group.label group
    let mut memberLabels : NameSet := {}
    for member in group.entries do
      if member.label == .anonymous then
        errors := errors.push <|
          s!"manifest group {Informal.PreviewManifest.labelString group.label} " ++
            "has member with empty label"
        continue
      if memberLabels.contains member.label then
        errors := errors.push <|
          s!"duplicate member {Informal.PreviewManifest.labelString member.label} " ++
            s!"in manifest group {Informal.PreviewManifest.labelString group.label}"
      else
        memberLabels := memberLabels.insert member.label
      match memberGroups.get? member.label with
      | some previousGroup =>
          if previousGroup != group.label then
            errors := errors.push <|
              s!"manifest member {Informal.PreviewManifest.labelString member.label} " ++
                s!"belongs to multiple groups: " ++
                s!"{Informal.PreviewManifest.labelString previousGroup} and " ++
                Informal.PreviewManifest.labelString group.label
      | none =>
          memberGroups := memberGroups.insert member.label group.label
  let mut matchedMembers : NameSet := {}
  for entry in manifest.previews do
    if entry.targetKind != .block && entry.targetKind != .externalMarkup then
      continue
    if entry.label == .anonymous then
      errors := errors.push s!"entry {entry.key} is missing label"
      continue
    match entry.parent with
    | none =>
        if entry.parentTitle.isSome then
          errors := errors.push s!"entry {entry.key} has parentTitle without parent"
        if let some group := memberGroups.get? entry.label then
          errors := errors.push <|
            s!"entry {entry.key} has no parent but is listed in manifest group: " ++
              Informal.PreviewManifest.labelString group
    | some parent =>
        if parent == .anonymous then
          errors := errors.push s!"entry {entry.key} has invalid parent"
          continue
        match groupsByLabel.get? parent with
        | none =>
          errors := errors.push <|
            s!"entry {entry.key} references missing manifest group: " ++
              Informal.PreviewManifest.labelString parent
        | some group =>
            if entry.parentTitle != some group.title then
              errors := errors.push <|
                s!"entry {entry.key} has inconsistent parentTitle for manifest group: " ++
                  Informal.PreviewManifest.labelString parent
        match memberGroups.get? entry.label with
        | none =>
            errors := errors.push <|
              s!"entry {entry.key} is missing from manifest group: " ++
                Informal.PreviewManifest.labelString parent
        | some memberGroup =>
            if memberGroup == parent then
              matchedMembers := matchedMembers.insert entry.label
            else
              errors := errors.push <|
                s!"entry {entry.key} belongs to manifest group " ++
                  s!"{Informal.PreviewManifest.labelString memberGroup} but references " ++
                  Informal.PreviewManifest.labelString parent
  for (member, group) in memberGroups.toArray do
    unless matchedMembers.contains member do
      errors := errors.push <|
        s!"manifest group {Informal.PreviewManifest.labelString group} member " ++
          s!"{Informal.PreviewManifest.labelString member} has no matching manifest entry"
  return errors

def checkGeneratedData (data : PersistedGeneratedData) : Array String :=
  let manifest := data.manifest
  let index := Informal.PreviewManifest.PreviewArtifactIndex.ofPersistedFiles data
  let errors := manifest.previews.foldl
    (fun errors entry =>
      let errors :=
        if entry.requiresRenderedBody then
          pushMissingCacheKey index errors s!"entry {entry.key}" entry.key
        else
          errors
      let errors := entry.leanCodePreviewKeys.foldl
        (fun errors key =>
          let errors :=
            if index.hasManifestKey key then
              errors
            else
              errors.push s!"missing manifest entry for Lean preview key {key}"
          pushMissingCacheKey index errors s!"Lean preview key on {entry.key}" key)
        errors
      let errors := checkRelatedEntries index s!"uses of {entry.key}" entry.uses errors
      checkRelatedEntries index s!"used-by of {entry.key}" entry.usedBy errors)
    #[]
  let errors := manifest.groups.foldl
    (fun errors group =>
      checkRelatedEntries index
        s!"group {Informal.PreviewManifest.labelString group.label}"
        group.entries errors)
    errors
  let errors := checkManifestGroupIntegrity manifest errors
  manifest.graphs.foldl (fun errors graph => checkGraphPreviewKeys index graph errors) errors

def checkJsonFromErrors (data : PersistedGeneratedData) (errors : Array String) : Json :=
  responseJson [
    ("ok", Json.bool errors.isEmpty),
    ("manifestEntries", Json.num data.manifest.previews.size),
    ("htmlCacheEntries", Json.num data.htmlCache.entries.size),
    ("errors", Json.arr (errors.map Json.str))
  ]

def checkJson (data : PersistedGeneratedData) : Json :=
  checkJsonFromErrors data (checkGeneratedData data)

end VersoBlueprint.Vbp
