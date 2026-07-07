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

def defaultSite : FilePath := "_out" / "site"

def defaultOutput : FilePath := defaultSite

def apiStability : String := "unstable"

def querySelectorLines : List String := [
  "selectors",
  "labels",
  "node <label>",
  "all <label>",
  "uses <label>",
  "used-by <label>",
  "group <label>",
  "owners",
  "tags",
  "work-queue",
  "search <text>",
  "code <decl>",
  "stats"
]

def responseJson (fields : List (String × Json)) : Json :=
  Json.mkObj (("apiStability", Json.str apiStability) :: fields)

def querySelectorsJson : Json :=
  responseJson [
    ("selectors", Json.arr (querySelectorLines.toArray.map Json.str))
  ]

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

private def entryGroupJson (entry : Entry) : Json :=
  match entry.group with
  | none => Json.null
  | some group => groupRelationJson group

private def entryDetailFields (entry : Entry) : List (String × Json) := [
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
    ("group", entryGroupJson entry),
    ("ownerDisplayName", optionStringJson entry.ownerDisplayName),
    ("tags", stringArrayJson entry.tags),
    ("priority", optionStringJson entry.priority),
    ("effort", optionStringJson entry.effort)
  ]

def entryJson (entry : Entry) : Json :=
  Json.mkObj (entryDetailFields entry)

private def entryResponseJson (entry : Entry) : Json :=
  responseJson (entryDetailFields entry)

private def entryAllJson (label : String) (entry : Entry) : Json :=
  responseJson [
    ("label", Json.str label),
    ("node", entryJson entry),
    ("statementUses", Json.arr (entry.statementUses.map useRefJson)),
    ("proofUses", Json.arr (entry.proofUses.map useRefJson)),
    ("uses", Json.arr (entry.uses.map relatedEntryJson)),
    ("usedBy", Json.arr (entry.usedBy.map relatedEntryJson)),
    ("group", entryGroupJson entry)
  ]

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
    (manifest : ManifestFile) (label : String) (mkJson : Entry → Json) : Except String Json :=
  match manifest.findPrimaryQueryableEntry? label with
  | some entry => .ok (mkJson entry)
  | none => .ok (missingLabelJson label)

def queryJson (manifest : ManifestFile) (args : List String) : Except String Json :=
  match args with
  | ["selectors"] =>
      .ok querySelectorsJson
  | ["labels"] =>
      .ok <| responseJson [
        ("labels", Json.arr (manifest.queryableStatementEntries.map entrySummaryJson))
      ]
  | ["node", label] =>
      withPrimaryEntry manifest label entryResponseJson
  | ["all", label] =>
      withPrimaryEntry manifest label (entryAllJson label)
  | ["uses", label] =>
      withPrimaryEntry manifest label fun entry =>
        responseJson [
          ("label", Json.str label),
          ("statementUses", Json.arr (entry.statementUses.map useRefJson)),
          ("proofUses", Json.arr (entry.proofUses.map useRefJson)),
          ("uses", Json.arr (entry.uses.map relatedEntryJson))
        ]
  | ["used-by", label] =>
      withPrimaryEntry manifest label fun entry =>
        responseJson [
          ("label", Json.str label),
          ("usedBy", Json.arr (entry.usedBy.map relatedEntryJson))
        ]
  | ["group", label] =>
      withPrimaryEntry manifest label fun entry =>
        responseJson [
          ("label", Json.str label),
          ("group", entryGroupJson entry)
        ]
  | ["owners"] =>
      .ok <| responseJson [("owners", stringArrayJson manifest.ownerValues)]
  | ["tags"] =>
      .ok <| responseJson [("tags", stringArrayJson manifest.tagValues)]
  | ["work-queue"] =>
      .ok <| responseJson [
        ("entries", Json.arr (manifest.workQueueEntries.map entrySummaryJson))
      ]
  | ["search", text] =>
      .ok <| responseJson [
        ("query", Json.str text),
        ("labels", Json.arr (manifest.queryableStatementEntries |>.filter (fun entry => entry.matchesText text) |>.map entrySummaryJson))
      ]
  | ["code", decl] =>
      .ok <| responseJson [
        ("query", Json.str decl),
        ("labels", Json.arr (manifest.queryableStatementEntries |>.filter (fun entry => entry.matchesCode decl) |>.map entrySummaryJson))
      ]
  | ["stats"] =>
      .ok (statsJson manifest)
  | [] => .error "missing query selector"
  | selector :: _ => .error s!"unknown query selector '{selector}'"

structure GeneratedData where
  manifest : ManifestFile
  htmlCache : HtmlCacheFile

def readManifestForSite (site : FilePath) : IO ManifestFile := do
  let manifestPath ← manifestPathForSite site
  unless ← manifestPath.pathExists do
    throw <| IO.userError s!"missing Blueprint manifest at {manifestPath}; run `lake exe vbp build` first"
  Informal.PreviewManifest.readFile manifestPath

def readHtmlCacheForSite (site : FilePath) : IO HtmlCacheFile := do
  let htmlCachePath ← htmlCachePathForSite site
  unless ← htmlCachePath.pathExists do
    throw <| IO.userError s!"missing Blueprint HTML cache at {htmlCachePath}; run `lake exe vbp build` first"
  Informal.PreviewManifest.HtmlCache.readFile htmlCachePath

def readGeneratedData (site : FilePath) : IO GeneratedData := do
  let manifest ← readManifestForSite site
  let htmlCache ← readHtmlCacheForSite site
  pure { manifest, htmlCache }

def cacheKeySet (cache : HtmlCacheFile) : Std.HashSet String :=
  cache.entries.foldl (fun keys entry => keys.insert entry.key) {}

def manifestKeySet (manifest : ManifestFile) : Std.HashSet String :=
  manifest.previews.foldl (fun keys entry => keys.insert entry.key) {}

private def pushMissingCacheKey
    (keys : Std.HashSet String) (errors : Array String) (context key : String) : Array String :=
  if keys.contains key then
    errors
  else
    errors.push s!"missing HTML cache entry for {context}: {key}"

private def checkRelatedEntries
    (cacheKeys : Std.HashSet String) (context : String) (entries : Array RelatedEntry)
    (errors : Array String) : Array String :=
  entries.foldl
    (fun errors entry =>
      match entry.previewKey with
      | none => errors
      | some key =>
        pushMissingCacheKey cacheKeys errors
          s!"{context} relation {Informal.PreviewManifest.labelString entry.label}"
          key.value)
    errors

def checkGeneratedData (manifest : ManifestFile) (htmlCache : HtmlCacheFile) : Array String :=
  let manifestKeys := manifestKeySet manifest
  let cacheKeys := cacheKeySet htmlCache
  manifest.previews.foldl
    (fun errors entry =>
      let errors := pushMissingCacheKey cacheKeys errors s!"entry {entry.key}" entry.key
      let errors := entry.leanCodePreviewKeys.foldl
        (fun errors key =>
          let errors :=
            if manifestKeys.contains key then errors else errors.push s!"missing manifest entry for Lean preview key {key}"
          pushMissingCacheKey cacheKeys errors s!"Lean preview key on {entry.key}" key)
        errors
      let errors := checkRelatedEntries cacheKeys s!"uses of {entry.key}" entry.uses errors
      let errors := checkRelatedEntries cacheKeys s!"used-by of {entry.key}" entry.usedBy errors
      match entry.group with
      | none => errors
      | some group =>
          checkRelatedEntries cacheKeys
            s!"group {Informal.PreviewManifest.labelString group.label} on {entry.key}"
            group.entries errors)
    #[]

def checkJsonFromErrors
    (manifest : ManifestFile) (htmlCache : HtmlCacheFile) (errors : Array String) : Json :=
  responseJson [
    ("ok", Json.bool errors.isEmpty),
    ("manifestEntries", Json.num manifest.previews.size),
    ("htmlCacheEntries", Json.num htmlCache.entries.size),
    ("errors", Json.arr (errors.map Json.str))
  ]

def checkJson (manifest : ManifestFile) (htmlCache : HtmlCacheFile) : Json :=
  checkJsonFromErrors manifest htmlCache (checkGeneratedData manifest htmlCache)

end VersoBlueprint.Vbp
