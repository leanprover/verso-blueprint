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
abbrev PreviewArtifactIndex := Informal.PreviewManifest.PreviewArtifactIndex
abbrev PersistedGeneratedData := Informal.PreviewManifest.PersistedFiles
abbrev WorkQueueItem := Informal.PreviewManifest.WorkQueueItem
abbrev NodeRow := Informal.PreviewManifest.NodeRow
abbrev NodeOccurrenceMetadata := Informal.PreviewManifest.NodeOccurrenceMetadata
abbrev ManifestIndex := Informal.PreviewManifest.Index

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

private def relatedEntryJson (entry : RelatedEntry) : Json :=
  Json.mkObj [
    ("label", nameJson entry.label),
    ("title", Json.str entry.title),
    ("href", optionStringJson entry.href),
    ("previewKey", toJson entry.previewKey),
    ("dependencies", toJson entry.dependencies)
  ]

private def groupRelationJson (group : GroupRelation) : Json :=
  Json.mkObj [
    ("label", nameJson group.label),
    ("title", Json.str group.title),
    ("declared", Json.bool group.declared),
    ("entries", Json.arr (group.entries.map relatedEntryJson))
  ]

private def nodeSummaryFields (node : NodeOccurrenceMetadata) (entry : Option Entry) :
    List (String × Json) := [
    ("key", optionStringJson (entry.map (·.key))),
    ("label", nameJson node.label),
    ("authoredLabel", Json.str node.authoredLabel),
    ("title", Json.str node.title),
    ("kind", toJson node.kind),
    ("facet", toJson (entry.map (·.facet))),
    ("href", optionStringJson node.href),
    ("parent", optionNameJson node.parent),
    ("parentTitle", optionStringJson node.parentTitle),
    ("ownerDisplayName", optionStringJson node.ownerDisplayName),
    ("tags", stringArrayJson node.tags),
    ("priority", optionStringJson node.priority),
    ("effort", optionStringJson node.effort),
    ("leanCodePreviewKeys", stringArrayJson ((entry.map (·.leanCodePreviewKeys)).getD #[]))
  ]

private def nodeSummaries (manifest : ManifestFile)
    (includeNode : NodeOccurrenceMetadata → Option Entry → Bool := fun _ _ => true) : Array Json :=
  let index := manifest.index
  manifest.nodes.filterMap fun row => do
    let node ← index.nodeMetadata? row
    let entry := index.primaryEntry? row
    guard (includeNode node entry)
    return Json.mkObj (nodeSummaryFields node entry)

private def workQueueItemJson (index : ManifestIndex) (item : WorkQueueItem) : Option Json := do
  let node ← index.nodeMetadata? item.node
  return Json.mkObj <| nodeSummaryFields node (index.primaryEntry? item.node) ++ [
    ("nextStep", Json.str item.nextStep),
    ("statementStatus", Json.str item.statementStatus.toText),
    ("proofStatus", Json.str item.proofStatus.toText)
  ]

private def nodeGroupJson (manifest : ManifestFile) (node : NodeOccurrenceMetadata) : Json :=
  ((manifest.index.groupForNode? node).map groupRelationJson).getD Json.null

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
  let proof? := (manifest.findBlockEntriesByLabel entry.authoredLabel).find?
    (·.facet == .proof)
  responseJson <| entryDetailFields entry (manifest.groupForEntry? entry) ++ [
    ("proof", proof?.map (fun proof => Json.mkObj (entryDetailFields proof)) |>.getD Json.null)
  ]

private def bodylessResponseJson (manifest : ManifestFile) (node : NodeOccurrenceMetadata) : Json :=
  responseJson <| nodeSummaryFields node none ++ [
    ("targetKind", Json.null),
    ("displayCaption", Json.null),
    ("displayLabel", Json.null),
    ("statementUses", Json.arr (node.statementUses.map useRefJson)),
    ("proofUses", Json.arr (node.proofUses.map useRefJson)),
    ("codeData", Json.null),
    ("uses", Json.arr (node.uses.map relatedEntryJson)),
    ("usedBy", Json.arr (node.usedBy.map relatedEntryJson)),
    ("group", nodeGroupJson manifest node),
    ("proof", Json.null)
  ]

/-- Read captured checks and node assessment alongside the per-facet declaration
inventory observed at registration. -/
private def nodeStatusJson (manifest : ManifestFile) (row : NodeRow) : Json := Id.run do
  let facets := manifest.findQueryableEntriesByLabel (Informal.PreviewManifest.labelString row.label)
  let assessment? := row.assessment
  let mut declarations : Array Json := #[]
  let mut nativeDeclarations : Array Json := #[]
  for facet in facets do
    let code := facet.codeData.getD {}
    for decl in code.externalDecls do
      let status := decl.observedStatus.map Informal.Data.ProvedStatus.reportJson |>.getD
        (Json.mkObj [("verdict", Json.str "awaiting-capture")])
      declarations := declarations.push <| Json.mkObj [
        ("name", nameJson decl.canonical), ("facet", toJson facet.facet),
        ("association", Json.str "external"), ("kind", toJson decl.kind),
        ("sourceSnapshotStatus", status)]
    for (name, status) in code.externalChecks do
      nativeDeclarations := nativeDeclarations.push <| Json.mkObj [
        ("name", nameJson name), ("facet", toJson facet.facet),
        ("status", status.map Informal.Data.ProvedStatus.reportJson |>.getD
          (Json.mkObj [("verdict", Json.str "unavailable")]))]
    for decl in code.literateDeclarations.declarations do
      declarations := declarations.push <| Json.mkObj [
        ("name", nameJson decl.name), ("facet", toJson facet.facet),
        ("association", Json.str "inline"),
        ("sourceSnapshotStatus", decl.provedStatus.reportJson)]
  let validation := match assessment? with
    | none => Json.mkObj [("captured", toJson false)]
    | some assessment => Json.mkObj [
        ("captured", toJson true),
        ("hasNativeDeclarations", toJson assessment.hasNativeDeclarations),
        ("hasAxiomLike", toJson assessment.hasAxiomLike),
        ("nativeStatementComplete", toJson assessment.nativeStatementComplete),
        ("hasNativeBodyRequirement", toJson assessment.hasNativeBodyRequirement),
        ("proofRoleComplete", toJson assessment.proofRoleComplete),
        ("nativeBodyComplete", toJson assessment.nativeBodyComplete),
        ("requiredComplete", toJson assessment.requiredComplete),
        ("statementDependenciesComplete", toJson assessment.statementDependenciesComplete),
        ("proofDependenciesComplete", toJson assessment.proofDependenciesComplete),
        ("selectedLeanUseCount", toJson assessment.selectedLeanUseCount),
        ("externalDeclarationChecks", Json.arr nativeDeclarations),
        ("details", assessment.details)]
  return responseJson [
    ("label", nameJson row.label),
    ("asOf", Json.str (if assessment?.isSome then "captured-build" else "uncaptured")),
    ("validation", validation),
    ("sourceDeclarationSnapshots", Json.arr declarations)]

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
  let index := manifest.index
  let entries := manifest.nodes.filterMap index.nodeMetadata?
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

private def withNode (manifest : ManifestFile) (label : String)
    (mkJson : NodeRow → NodeOccurrenceMetadata → Option Entry → Json) : Json :=
  let index := manifest.index
  (do
    let row ← manifest.findNodeRow? label
    let node ← index.nodeMetadata? row
    return mkJson row node (index.primaryEntry? row)).getD (missingLabelJson label)

/-- A validated query of the semantic manifest. -/
structure QueryPlan where
  run : ManifestFile → Json

private structure QuerySelector where
  name : String
  argumentName : String
  run : Sum (ManifestFile → Json) (String → ManifestFile → Json)

private def QuerySelector.noArg
    (name : String) (run : ManifestFile → Json) : QuerySelector :=
  { name, argumentName := "", run := .inl run }

private def QuerySelector.oneArg
    (name argumentName : String) (run : String → ManifestFile → Json) : QuerySelector :=
  { name, argumentName, run := .inr run }

private def QuerySelector.line (selector : QuerySelector) : String :=
  match selector.run with
  | .inl _ => selector.name
  | .inr _ => s!"{selector.name} <{selector.argumentName}>"

private def QuerySelector.plan? (selector : QuerySelector) (args : List String) : Option QueryPlan :=
  match selector.run, args with
  | .inl run, [name] =>
      if name == selector.name then
        some { run }
      else
        none
  | .inr run, [name, argument] =>
      if name == selector.name then
        some { run := run argument }
      else
        none
  | _, _ => none

private def querySelectors : List QuerySelector := [
  QuerySelector.noArg "labels" fun manifest =>
    responseJson [
      ("labels", Json.arr (nodeSummaries manifest))
    ],
  QuerySelector.oneArg "node" "label" fun label manifest =>
    withNode manifest label fun _ node entry =>
      match entry with
      | some resource => entryResponseJson manifest resource
      | none => bodylessResponseJson manifest node,
  QuerySelector.oneArg "status" "label" fun label manifest =>
    withNode manifest label fun row _ _ => nodeStatusJson manifest row,
  QuerySelector.oneArg "uses" "label" fun label manifest =>
    withNode manifest label fun _ node _ =>
      responseJson [
        ("label", Json.str label),
        ("statementUses", Json.arr (node.statementUses.map useRefJson)),
        ("proofUses", Json.arr (node.proofUses.map useRefJson)),
        ("uses", Json.arr (node.uses.map relatedEntryJson))
      ],
  QuerySelector.oneArg "used-by" "label" fun label manifest =>
    withNode manifest label fun _ node _ =>
      responseJson [
        ("label", Json.str label),
        ("usedBy", Json.arr (node.usedBy.map relatedEntryJson))
      ],
  QuerySelector.oneArg "group" "label" fun label manifest =>
    withNode manifest label fun _ node _ =>
      responseJson [
        ("label", Json.str label),
        ("group", nodeGroupJson manifest node)
      ],
  QuerySelector.noArg "owners" fun manifest =>
    responseJson [("owners", stringArrayJson manifest.ownerValues)],
  QuerySelector.noArg "tags" fun manifest =>
    responseJson [("tags", stringArrayJson manifest.tagValues)],
  QuerySelector.noArg "work-queue" fun manifest =>
    responseJson [
      ("entries", Json.arr (manifest.workQueueItems.filterMap (workQueueItemJson manifest.index)))
    ],
  QuerySelector.noArg "metadata" fun manifest =>
    responseJson [
      ("entries", Json.arr (nodeSummaries manifest fun node _ => node.hasTriageMetadata))
    ],
  QuerySelector.oneArg "search" "text" fun text manifest =>
    responseJson [
      ("query", Json.str text),
      ("labels", Json.arr (nodeSummaries manifest fun node _ => node.matchesText text))
    ],
  QuerySelector.oneArg "code" "decl" fun decl manifest =>
    responseJson [
      ("query", Json.str decl),
      ("labels", Json.arr (nodeSummaries manifest fun node entry =>
        entry.any (·.matchesCode decl) || (manifest.findBlockEntriesByLabel node.authoredLabel).any
          (·.matchesCode decl)))
    ],
  QuerySelector.noArg "stats" statsJson
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

private def readManifestWith
    (read : FilePath → IO ManifestFile) (site : FilePath) : IO ManifestFile := do
  let manifestPath ← manifestPathForSite site
  unless ← manifestPath.pathExists do
    throw <| IO.userError s!"missing Blueprint manifest at {manifestPath}; run `lake exe vbp build` first"
  read manifestPath

def readManifestForSite (site : FilePath) : IO ManifestFile :=
  readManifestWith Informal.PreviewManifest.readFile site

/-- Read query metadata without reconstructing graph projections. -/
def readManifestForQuery (site : FilePath) : IO ManifestFile :=
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
  let errors := pushMissingCacheKey index errors context key
  if index.hasManifestKey key && index.hasCacheKey key && !index.resolves key then
    errors.push s!"preview for {context} has no usable Lean fragments: {key}"
  else errors

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
  let checkJoin (state : Array String × NameSet) (context : String)
      (label : Name) (parent : Option Name) (parentTitle : Option String) := Id.run do
    let mut errors := state.1
    let matchedMembers := state.2
    if label == .anonymous then
      return (errors.push s!"{context} is missing label", matchedMembers)
    match parent with
    | none =>
        if parentTitle.isSome then
          errors := errors.push s!"{context} has parentTitle without parent"
        if let some group := memberGroups.get? label then
          errors := errors.push <|
            s!"{context} has no parent but is listed in manifest group: " ++
              Informal.PreviewManifest.labelString group
    | some parent =>
        if parent == .anonymous then
          return (errors.push s!"{context} has invalid parent", matchedMembers)
        match groupsByLabel.get? parent with
        | none =>
          errors := errors.push <|
            s!"{context} references missing manifest group: " ++
              Informal.PreviewManifest.labelString parent
        | some group =>
            if parentTitle != some group.title then
              errors := errors.push <|
                s!"{context} has inconsistent parentTitle for manifest group: " ++
                  Informal.PreviewManifest.labelString parent
        match memberGroups.get? label with
        | none =>
            errors := errors.push <|
              s!"{context} is missing from manifest group: " ++
                Informal.PreviewManifest.labelString parent
        | some memberGroup =>
            if memberGroup == parent then
              return (errors, matchedMembers.insert label)
            else
              errors := errors.push <|
                s!"{context} belongs to manifest group " ++
                  s!"{Informal.PreviewManifest.labelString memberGroup} but references " ++
                  Informal.PreviewManifest.labelString parent
    return (errors, matchedMembers)
  let mut joins : Array String × NameSet := (errors, {})
  for entry in manifest.previews do
    if entry.targetKind == .block || entry.targetKind == .externalMarkup then
      joins := checkJoin joins s!"entry {entry.key}" entry.label entry.parent entry.parentTitle
  for row in manifest.nodes do
    if let some node := row.bodyless then
      let label := Informal.PreviewManifest.labelString row.label
      joins := checkJoin joins s!"bodyless node {label}" row.label node.parent node.parentTitle
  errors := joins.1
  let matchedMembers := joins.2
  -- Semantic group members survive blank resource omission. A member only
  -- requires a preview entry when it advertises a preview key.
  for group in manifest.groups do
    for member in group.entries do
      if member.previewKey.isSome && !matchedMembers.contains member.label then
        errors := errors.push <|
          s!"manifest group {Informal.PreviewManifest.labelString group.label} member " ++
            s!"{Informal.PreviewManifest.labelString member.label} has no matching manifest entry"
  return errors

private def duplicateKeyErrors (kind : String) (keys : Array String) : Array String := Id.run do
  let mut seen : Std.HashSet String := {}
  let mut errors := #[]
  for key in keys do
    if seen.contains key then
      errors := errors.push s!"duplicate {kind} key: {key}"
    else
      seen := seen.insert key
  return errors

private def checkDefaultPreviews (index : PreviewArtifactIndex) (entries : Array Entry)
    (errors : Array String) : Array String := Id.run do
  let mut seen : NameSet := {}
  let mut errors := errors
  for entry in entries do
    if !entry.defaultPreview then continue
    let label := Informal.PreviewManifest.labelString entry.label
    if seen.contains entry.label then
      errors := errors.push s!"duplicate default preview for {label}"
    else seen := seen.insert entry.label
    if entry.targetKind != .block && entry.targetKind != .externalMarkup then
      errors := errors.push s!"default preview for {label} is not a node preview"
    errors := checkPreviewReference index s!"default preview of {label}" entry.key errors
  return errors

def checkGeneratedData (data : PersistedGeneratedData) : Array String :=
  let manifest := data.manifest
  let index := Informal.PreviewManifest.PreviewArtifactIndex.ofPersistedFiles data
  -- Membership indexes collapse duplicates; audit the original arrays as well.
  let keyErrors := duplicateKeyErrors "manifest preview" (manifest.previews.map (·.key)) ++
    duplicateKeyErrors "HTML cache" (data.htmlCache.entries.map (·.key))
  let cacheErrors := data.htmlCache.entries.foldl (init := keyErrors) fun errors entry =>
    if entry.hasBody then errors else errors.push s!"empty HTML cache body for key {entry.key}"
  let errors := manifest.previews.foldl
    (fun errors entry =>
      let errors :=
        if entry.requiresRenderedBody then
          pushMissingCacheKey index errors s!"entry {entry.key}" entry.key
        else
          errors
      let errors := entry.leanCodePreviewKeys.foldl
        (fun errors key =>
          if key == entry.key then
            errors.push s!"self-referential Lean preview key on {entry.key}"
          else
            let errors :=
              if index.hasManifestKey key then
                errors
              else
                errors.push s!"missing manifest entry for Lean preview key {key}"
            pushMissingCacheKey index errors s!"Lean preview key on {entry.key}" key)
        errors
      let errors := checkRelatedEntries index s!"uses of {entry.key}" entry.uses errors
      checkRelatedEntries index s!"used-by of {entry.key}" entry.usedBy errors)
    cacheErrors
  let errors := manifest.groups.foldl
    (fun errors group =>
      checkRelatedEntries index
        s!"group {Informal.PreviewManifest.labelString group.label}"
        group.entries errors)
    errors
  let errors := manifest.nodes.foldl (init := errors) fun errors row =>
    match row.bodyless with
    | none => errors
    | some node =>
      let label := Informal.PreviewManifest.labelString row.label
      let errors := checkRelatedEntries index s!"uses of {label}" node.uses errors
      checkRelatedEntries index s!"used-by of {label}" node.usedBy errors
  let errors := checkManifestGroupIntegrity manifest errors
  let errors := checkDefaultPreviews index manifest.previews errors
  manifest.graphs.foldl (fun errors graph => checkGraphPreviewKeys index graph errors) errors

/-- Current Verso section routes also cover pages with no Blueprint previews. -/
private def currentSectionRoutes (xref : Json) : Except String (Std.HashSet String) := do
  let domain ← xref.getObjVal? Verso.Genre.Manual.sectionDomain.toString
  let contents ← (← domain.getObjVal? "contents").getObj?
  let mut routes : Std.HashSet String := {}
  for (_, targets) in contents.toList do
    for target in ← targets.getArr? do
      routes := routes.insert (← target.getObjValAs? String "address")
  return routes

/-- Identify a stock Verso manual page from its head and the relative base it
uses to address this site. The read is bounded, including for user HTML. -/
private def hasVersoPageHeader (path : FilePath) (depth : Nat) : IO Bool := do
  let header ← IO.FS.withFile path .read (·.read 4096)
  let signature := ("<!DOCTYPE html>\n<html>\n  <head>\n    <script>\n      (function(){\n" ++
    "  const {protocol:proto, host:hostName, pathname:path, search:srch, hash:hsh} = window.location;").toUTF8
  unless (header.extract 0 signature.size).data == signature.data do return false
  let relativeRoot := "./" ++ String.join (List.replicate depth "../")
  let base := s!"<base href=\"{relativeRoot}\">".toUTF8
  for offset in [signature.size:header.size - base.size + 1] do
    if header[offset]? == some '<'.toUInt8 && (header.extract offset (offset + base.size)).data == base.data then
      return true
  return false

/-- Report known Verso manual pages outside the current section routes. This
audit reads regular index files in the selected HTML tree and leaves the tree
untouched. Artifact-only directories have no Verso cross-reference table. -/
def checkHtmlRoutes (site : FilePath) : IO (Array String) := do
  let html ← htmlDirForSite site
  let xrefPath := html / "xref.json"
  let .ok metadata ← xrefPath.symlinkMetadata.toBaseIO | return #[]
  unless metadata.type == .file do return #[]
  let .ok routes := Json.parse (← IO.FS.readFile xrefPath) >>= currentSectionRoutes
    | throw <| IO.userError s!"cannot read Verso section routes from {xrefPath}"
  -- A current root entry distinguishes a manual from an unrelated xref table.
  unless routes.contains "/" do return #[]
  let mut pending := #[(html, "/", 0)]
  let mut stale := #[]
  repeat
    let some (directory, route, depth) := pending.back? | break
    pending := pending.pop
    for entry in ← directory.readDir do
      if depth == 0 && #["-verso-data", "-verso-search"].contains entry.fileName then continue
      let fileType := (← entry.path.symlinkMetadata).type
      if fileType == .dir then
        pending := pending.push (entry.path, route ++ entry.fileName ++ "/", depth + 1)
      else if fileType == .file && entry.fileName == "index.html" &&
          !routes.contains route && route != "/find/" && route != "/search/" then
        if ← hasVersoPageHeader entry.path depth then
          stale := stale.push (s!"stale generated HTML route: {route}")
  return stale.qsort (· < ·)

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
