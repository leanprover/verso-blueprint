/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.Data.Json.FromToJson
import VersoBlueprint.Lib.BrowserString
import Lean.Data.Json.Parser
import Lean.Data.Json.Printer
import Std.Data.HashMap
import Std.Data.HashSet

public section

/-!
A portable, pure resolver for generated Blueprint manifests.

This module intentionally does not import Blueprint's elaboration, traversal,
rendering, filesystem, or process layers. It consumes the existing generated
manifest JSON, validates the subset used by browser data clients, and answers a
batch of lookup requests. Browser hosts remain responsible for fetching and
caching the JSON.

`resolveBatchJson` is the coarse string-to-string root intended for VIR/FIR
conformance experiments. `prepareManifestJson` and `resolvePreparedJson` split
manifest preparation from request batches so a runtime adapter can retain the
immutable prepared value explicitly. `resolveBatch` is the typed native entry
point used by tests and other Lean callers.
-/

namespace VersoBlueprint.Runtime.ManifestResolver

open Lean

def abiVersion : Nat := 1

inductive RequestKind where
  | preview
  | label
  | declaration
  | group
  | sourceDocument
  | sourceMetadata
deriving Inhabited, Repr, BEq, ToJson, FromJson

structure Request where
  id : String
  kind : RequestKind
  value : String
  facet : Option String := none
deriving Inhabited, ToJson, FromJson

structure BatchInput where
  abiVersion : Nat
  manifest : Json
  requests : Array Request := #[]
deriving Inhabited, ToJson, FromJson

/-- The manifest-bearing half of the runtime protocol, decoded once per artifact revision. -/
structure ManifestInput where
  abiVersion : Nat
  manifest : Json
deriving Inhabited, ToJson, FromJson

/-- A request batch resolved against an already prepared manifest. -/
structure RequestBatchInput where
  abiVersion : Nat
  requests : Array Request := #[]
deriving Inhabited, ToJson, FromJson

structure ResolvedSource where
  sourceRef : Json
  documentId : String
  document : Option Json := none
  spans : Array Json := #[]
deriving Inhabited, ToJson, FromJson

structure Result where
  requestId : String
  kind : RequestKind
  ok : Bool := false
  key : String := ""
  reason : String := ""
  label : Option String := none
  facet : Option String := none
  declaration : Option String := none
  manifestEntry : Option Json := none
  value : Option Json := none
  href : String := ""
  sourceLocation : Json
  sources : Array ResolvedSource := #[]
deriving Inhabited, ToJson, FromJson

structure BatchOutput where
  abiVersion : Nat := ManifestResolver.abiVersion
  ok : Bool := true
  error : String := ""
  results : Array Result := #[]
deriving Inhabited, ToJson, FromJson

private def trim (value : String) : String :=
  Informal.BrowserString.trim value

private def isObject : Json → Bool
  | .obj _ => true
  | _ => false

private def field? (json : Json) (name : String) : Option Json :=
  json.getObjVal? name |>.toOption

private def stringField (json : Json) (name : String) : String :=
  match field? json name with
  | some (.str value) => value
  | _ => ""

private def arrayField (json : Json) (name : String) : Array Json :=
  match field? json name with
  | some (.arr values) => values
  | _ => #[]

private def requiredArrayField
    (json : Json) (name objectMessage missingMessage : String) : Except String (Array Json) := do
  if !isObject json then
    throw objectMessage
  match field? json name with
  | some (.arr values) => pure values
  | _ => throw missingMessage

private def unavailableSourceLocation (message : String) : Json :=
  Json.mkObj [
    ("ok", .bool false),
    ("location", .null),
    ("error", .str message)
  ]

private structure Entry where
  raw : Json
  key : String
  targetKind : String
  label : String
  facet : String
  href : String
  sourceLocation : Json
  sources : Array Json := #[]
deriving Inhabited

private structure Group where
  raw : Json
  title : String
deriving Inhabited

private structure SourceDocument where
  raw : Json
deriving Inhabited

private structure Index where
  entries : Array Entry := #[]
  entriesByKey : Std.HashMap String Entry := {}
  groupsByLabel : Std.HashMap String Group := {}
  memberGroupsByLabel : Std.HashMap String String := {}
  requiredPreviewMembers : Array (String × String) := #[]
  sourceDocumentsById : Std.HashMap String SourceDocument := {}
deriving Inhabited

/--
An immutable, validated Blueprint manifest index.

Runtime adapters may retain this value behind their own explicit handle. The
representation remains private so VIR, FIR, and native hosts share the same
preparation and lookup semantics without making the index layout part of the
wire protocol.
-/
structure PreparedManifest where
  private index : Index

private def decodeEntry (raw : Json) (index : Nat) : Except String Entry := do
  if !isObject raw then
    throw s!"Blueprint manifest entry {index} must be an object"
  let key := trim (stringField raw "key")
  if key.isEmpty then
    throw s!"Blueprint manifest entry {index} is missing key"
  let sourceLocation ←
    match field? raw "sourceLocation" with
    | some value => pure value
    | none => throw s!"Blueprint manifest entry {index} is missing sourceLocation"
  if !isObject sourceLocation then
    throw s!"Blueprint manifest entry {index} is missing sourceLocation"
  match field? sourceLocation "ok" with
  | some (.bool _) => pure ()
  | _ => throw s!"Blueprint manifest entry {index} sourceLocation.ok must be boolean"
  pure {
    raw
    key
    targetKind := stringField raw "targetKind"
    label := stringField raw "label"
    facet := stringField raw "facet"
    href := stringField raw "href"
    sourceLocation
    sources := arrayField raw "sources"
  }

private def decodeEntries (manifest : Json) : Except String (Array Entry × Std.HashMap String Entry) := do
  let rawEntries ← requiredArrayField manifest "previews"
    "Blueprint manifest must be an object with a previews array"
    "Blueprint manifest is missing previews array"
  let mut entries := #[]
  let mut entriesByKey : Std.HashMap String Entry := {}
  for index in [:rawEntries.size] do
    let entry ← decodeEntry rawEntries[index]! index
    if entriesByKey.contains entry.key then
      throw s!"Blueprint manifest contains duplicate key {entry.key}"
    entries := entries.push entry
    entriesByKey := entriesByKey.insert entry.key entry
  pure (entries, entriesByKey)

private def decodeGroups (manifest : Json) :
    Except String
      (Std.HashMap String Group × Std.HashMap String String × Array (String × String)) := do
  let rawGroups ← requiredArrayField manifest "groups"
    "Blueprint manifest must be an object with a groups array"
    "Blueprint manifest is missing groups array"
  let mut groupsByLabel : Std.HashMap String Group := {}
  let mut memberGroupsByLabel : Std.HashMap String String := {}
  let mut requiredPreviewMembers := #[]
  for index in [:rawGroups.size] do
    let raw := rawGroups[index]!
    if !isObject raw then
      throw s!"Blueprint manifest group {index} must be an object"
    let label := trim (stringField raw "label")
    if label.isEmpty then
      throw s!"Blueprint manifest group {index} is missing label"
    let rawMembers ←
      match field? raw "entries" with
      | some (.arr values) => pure values
      | _ => throw s!"Blueprint manifest group {label} is missing entries array"
    if groupsByLabel.contains label then
      throw s!"Blueprint manifest contains duplicate group {label}"
    let title := trim (stringField raw "title")
    if title.isEmpty then
      throw s!"Blueprint manifest group {label} is missing title"
    let mut members : Std.HashSet String := {}
    for memberIndex in [:rawMembers.size] do
      let member := rawMembers[memberIndex]!
      if !isObject member then
        throw s!"Blueprint manifest group {label} member {memberIndex} must be an object"
      let memberLabel := trim (stringField member "label")
      if memberLabel.isEmpty then
        throw s!"Blueprint manifest group {label} member {memberIndex} is missing label"
      if members.contains memberLabel then
        throw s!"Blueprint manifest contains duplicate member {memberLabel} in group {label}"
      if let some previousGroup := memberGroupsByLabel.get? memberLabel then
        throw s!"Blueprint manifest member {memberLabel} belongs to multiple groups: {previousGroup} and {label}"
      members := members.insert memberLabel
      memberGroupsByLabel := memberGroupsByLabel.insert memberLabel label
      -- A blank resource still contributes semantic group membership. Only
      -- members advertising a preview key require a corresponding preview.
      if (field? member "previewKey").any (· != .null) then
        requiredPreviewMembers := requiredPreviewMembers.push (memberLabel, label)
    groupsByLabel := groupsByLabel.insert label { raw, title := stringField raw "title" }
  pure (groupsByLabel, memberGroupsByLabel, requiredPreviewMembers)

private def decodeSourceDocuments (manifest : Json) :
    Except String (Std.HashMap String SourceDocument) := do
  let rawDocuments ←
    match field? manifest "sourceDocuments" with
    | none | some .null => pure #[]
    | some (.arr values) => pure values
    | _ => throw "Blueprint manifest sourceDocuments must be an array"
  let mut sourceDocumentsById : Std.HashMap String SourceDocument := {}
  for index in [:rawDocuments.size] do
    let raw := rawDocuments[index]!
    if !isObject raw then
      throw s!"Blueprint source document {index} must be an object"
    let id := trim (stringField raw "id")
    if id.isEmpty then
      throw s!"Blueprint source document {index} is missing id"
    if sourceDocumentsById.contains id then
      throw s!"Blueprint manifest contains duplicate source document {id}"
    sourceDocumentsById := sourceDocumentsById.insert id { raw }
  pure sourceDocumentsById

private def validateGroupJoins (index : Index) : Except String Unit := do
  let mut matchedMembers : Std.HashSet String := {}
  for entry in index.entries do
    if entry.targetKind == "block" || entry.targetKind == "externalMarkup" then
      let label := trim entry.label
      if label.isEmpty then
        throw s!"Blueprint manifest entry {entry.key} is missing label"
      match field? entry.raw "parent" with
      | none | some .null =>
          match field? entry.raw "parentTitle" with
          | some value =>
              if value != .null then
                throw s!"Blueprint manifest entry {entry.key} has parentTitle without parent"
          | none => pure ()
          if let some group := index.memberGroupsByLabel.get? label then
            throw s!"Blueprint manifest entry {entry.key} has no parent but is listed in group {group}"
      | some _ =>
          let parent := trim (stringField entry.raw "parent")
          if parent.isEmpty then
            throw s!"Blueprint manifest entry {entry.key} has invalid parent"
          let some group := index.groupsByLabel.get? parent
            | throw s!"Blueprint manifest entry {entry.key} references missing group {parent}"
          if stringField entry.raw "parentTitle" != group.title then
            throw s!"Blueprint manifest entry {entry.key} has inconsistent parentTitle for group {parent}"
          let some memberGroup := index.memberGroupsByLabel.get? label
            | throw s!"Blueprint manifest entry {entry.key} is missing from group {parent}"
          if memberGroup != parent then
            throw s!"Blueprint manifest entry {entry.key} belongs to group {memberGroup} but references {parent}"
          matchedMembers := matchedMembers.insert label
  for (member, group) in index.requiredPreviewMembers do
    if !matchedMembers.contains member then
      throw s!"Blueprint manifest group {group} member {member} has no matching manifest entry"

private def Index.decode (manifest : Json) : Except String Index := do
  let (entries, entriesByKey) ← decodeEntries manifest
  let (groupsByLabel, memberGroupsByLabel, requiredPreviewMembers) ← decodeGroups manifest
  let sourceDocumentsById ← decodeSourceDocuments manifest
  let index := {
    entries, entriesByKey, groupsByLabel, memberGroupsByLabel, requiredPreviewMembers, sourceDocumentsById
  }
  validateGroupJoins index
  pure index

private def previewKey (label facet : String) : String :=
  let label := trim label
  let facet := trim facet
  let facet := if facet.isEmpty then "statement" else facet
  if label.isEmpty then "" else s!"{label}--{facet}"

private def declarationPreviewKey (declaration : String) : String :=
  let declaration := trim declaration
  if declaration.isEmpty then
    ""
  else if declaration.startsWith "Informal.LeanCodePreview." then
    declaration
  else
    "Informal.LeanCodePreview." ++ declaration

private def entryForLabel? (index : Index) (label facet : String) (explicitFacet : Bool) : Option Entry :=
  let key := previewKey label facet
  let exact? := index.entriesByKey.get? key |>.filter fun entry =>
    entry.targetKind == "block" && entry.label == label
  exact? <|> Id.run do
    let mut first? := none
    let mut statement? := none
    for entry in index.entries do
      if entry.targetKind == "block" && entry.label == label then
        if first?.isNone then first? := some entry
        if entry.facet == facet then return some entry
        if entry.facet == "statement" && statement?.isNone then statement? := some entry
    if explicitFacet then none else statement? <|> first?

private def entryForDeclaration? (index : Index) (declaration : String) : Option Entry :=
  let key := declarationPreviewKey declaration
  let exact? := index.entriesByKey.get? key |>.filter (·.targetKind == "leanDecl")
  exact? <|> index.entries.find? fun entry =>
    entry.targetKind == "leanDecl" && (entry.label == declaration || entry.key == key)

private def missingResult
    (request : Request) (key reason message : String)
    (label facet declaration : Option String := none) : Result := {
  requestId := request.id
  kind := request.kind
  key
  reason
  label
  facet
  declaration
  sourceLocation := unavailableSourceLocation message
}

private def entryResult
    (request : Request) (entry : Entry)
    (label facet declaration : Option String := none) : Result := {
  requestId := request.id
  kind := request.kind
  ok := true
  key := stringField entry.raw "key"
  label
  facet
  declaration
  manifestEntry := some entry.raw
  href := entry.href
  sourceLocation := entry.sourceLocation
}

private def resolveLabel (index : Index) (request : Request) : Result :=
  let label := trim request.value
  let requestedFacet := request.facet.map trim |>.filter (!·.isEmpty)
  let facet := requestedFacet.getD "statement"
  let key := previewKey label facet
  if label.isEmpty then
    missingResult request "" "missing-label" "label missing"
      (label := some "") (facet := some facet)
  else
    match entryForLabel? index label facet requestedFacet.isSome with
    | none =>
        missingResult request key "label-entry-missing" "label entry missing"
          (label := some label) (facet := some facet)
    | some entry =>
        entryResult request entry
          (label := some label)
          (facet := some (match field? entry.raw "facet" with
            | some (.str value) => value
            | _ => facet))

private def resolveDeclaration (index : Index) (request : Request) : Result :=
  let declaration := trim request.value
  let key := declarationPreviewKey declaration
  if declaration.isEmpty then
    missingResult request "" "missing-declaration" "declaration missing"
      (declaration := some "")
  else
    match entryForDeclaration? index declaration with
    | none =>
        missingResult request key "declaration-entry-missing" "declaration entry missing"
          (declaration := some declaration)
    | some entry =>
        entryResult request entry
          (declaration := some (match field? entry.raw "label" with
            | some (.str value) => value
            | _ => declaration))

private def resolvePreview (index : Index) (request : Request) : Result :=
  let key := trim request.value
  if key.isEmpty then
    missingResult request "" "missing-key" "preview key missing"
  else
    match index.entriesByKey.get? key with
    | none => missingResult request key "manifest-entry-missing" "manifest entry missing"
    | some entry => { entryResult request entry with key }

private def resolveGroup (index : Index) (request : Request) : Result :=
  let label := trim request.value
  if label.isEmpty then
    missingResult request "" "missing-group" "group label missing" (label := some "")
  else
    match index.groupsByLabel.get? label with
    | none =>
        missingResult request label "group-entry-missing" "group entry missing"
          (label := some label)
    | some group => {
        requestId := request.id
        kind := request.kind
        ok := true
        key := label
        label := some label
        value := some group.raw
        sourceLocation := unavailableSourceLocation "source location unavailable"
      }

private def resolveSourceDocument (index : Index) (request : Request) : Result :=
  let id := trim request.value
  if id.isEmpty then
    missingResult request "" "missing-source-document" "source document id missing"
  else
    match index.sourceDocumentsById.get? id with
    | none =>
        missingResult request id "source-document-missing" "source document missing"
    | some document => {
        requestId := request.id
        kind := request.kind
        ok := true
        key := id
        value := some document.raw
        sourceLocation := unavailableSourceLocation "source location unavailable"
      }

private def resolvedSource (index : Index) (rawRef : Json) : ResolvedSource :=
  let sourceRef := if isObject rawRef then rawRef else Json.mkObj []
  let documentId := trim (stringField sourceRef "document")
  let document :=
    if documentId.isEmpty then none
    else index.sourceDocumentsById.get? documentId |>.map (·.raw)
  {
    sourceRef
    documentId
    document
    spans := arrayField sourceRef "spans"
  }

private def resolveSourceMetadata (index : Index) (request : Request) : Result :=
  let key := trim request.value
  if key.isEmpty then
    missingResult request "" "missing-key" "source metadata key missing"
  else
    match index.entriesByKey.get? key with
    | none => missingResult request key "manifest-entry-missing" "manifest entry missing"
    | some entry =>
        if entry.sources.isEmpty then
          { entryResult request entry with
            key
            ok := false
            reason := "source-missing"
            href := ""
          }
        else
          { entryResult request entry with
            key
            href := ""
            sources := entry.sources.map (resolvedSource index)
          }

private def Index.resolve (index : Index) (request : Request) : Result :=
  match request.kind with
  | .preview => resolvePreview index request
  | .label => resolveLabel index request
  | .declaration => resolveDeclaration index request
  | .group => resolveGroup index request
  | .sourceDocument => resolveSourceDocument index request
  | .sourceMetadata => resolveSourceMetadata index request

private def ensureAbiVersion (actual : Nat) : Except String Unit :=
  if actual == ManifestResolver.abiVersion then
    pure ()
  else
    throw s!"unsupported manifest resolver ABI version {actual}"

/-- Validate a manifest and construct its immutable lookup index. -/
def prepareManifest (input : ManifestInput) : Except String PreparedManifest := do
  ensureAbiVersion input.abiVersion
  pure { index := ← Index.decode input.manifest }

/-- Decode and prepare the manifest-bearing half of the JSON protocol. -/
def prepareManifestJson (inputJson : String) : Except String PreparedManifest := do
  let input ← Json.parse inputJson >>= fromJson? (α := ManifestInput)
  prepareManifest input

/-- Resolve a typed request batch without rebuilding the manifest index. -/
def resolvePrepared
    (prepared : PreparedManifest) (requests : Array Request) : BatchOutput :=
  { results := requests.map prepared.index.resolve }

private def batchOutputJson (output : Except String BatchOutput) : String :=
  let output : BatchOutput :=
    match output with
    | .error error => { ok := false, error }
    | .ok output => output
  toJson output |>.compress

/-- Decode and resolve a request-only JSON batch against a prepared manifest. -/
def resolvePreparedJson (prepared : PreparedManifest) (inputJson : String) : String :=
  batchOutputJson do
    let input ← Json.parse inputJson >>= fromJson? (α := RequestBatchInput)
    ensureAbiVersion input.abiVersion
    pure (resolvePrepared prepared input.requests)

def resolveBatch (input : BatchInput) : Except String BatchOutput := do
  let prepared ← prepareManifest { abiVersion := input.abiVersion, manifest := input.manifest }
  pure (resolvePrepared prepared input.requests)

def resolveBatchJson (inputJson : String) : String :=
  batchOutputJson do
    let input ← Json.parse inputJson >>= fromJson? (α := BatchInput)
    resolveBatch input

end VersoBlueprint.Runtime.ManifestResolver
