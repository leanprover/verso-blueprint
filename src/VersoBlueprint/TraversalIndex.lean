/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import VersoManual
public import VersoBlueprint.Informal.Block.Model
public import VersoBlueprint.Informal.GroupData
public import VersoBlueprint.Informal.LeanCodePreviewKey
public import VersoBlueprint.Graph
public import VersoBlueprint.PreviewCache
public import VersoBlueprint.Resolve
public import VersoBlueprint.Rust
public import VersoBlueprint.Source.Data

public section

/-!
Typed accessors for Blueprint's traversal-time stores.

Verso traversal domains are flexible, but raw domain names and JSON payloads are
easy to misuse. This module is the small typed facade used by renderers and
traversal hooks. Each namespace names one store and exposes only the operations
callers should need.
-/

namespace Informal.TraversalIndex

open Lean
open Verso
open Verso.Genre Manual

/--
Classification for traversal-time Blueprint stores.

This is intentionally architectural metadata rather than behavior: the current
storage backend still uses Verso traversal domains in several places, but these
roles clarify whether the stored data is meant to be semantic document state,
a render-time index, a cache, or an accumulator.
-/
inductive StoreKind where
  | semanticDomain
  | internalIndex
  | runtimeCache
  | accumulator
deriving Inhabited, Repr, BEq

structure StoreSpec where
  /-- Concrete Verso traversal-domain name used as the current backend key. -/
  name : Name
  /-- Architectural role of this store. -/
  kind : StoreKind
  /-- Functional key shape, written as documentation rather than encoded behavior. -/
  key : String
  /-- Functional value shape, including whether the value is object data or only anchor IDs. -/
  value : String
  /-- One-line purpose for human readers. -/
  summary : String
deriving Repr

/-- Failed traversal-domain object decode with caller-facing diagnostic context. -/
structure DecodeError where
  canonicalName : String
  message : String
deriving Inhabited, Repr

/-- Decoded traversal-domain object paired with its canonical storage key. -/
structure StoredEntry (α : Type) where
  canonicalName : String
  data : α
deriving Inhabited, Repr

/-- Decode one Verso traversal-domain object while preserving its canonical key for diagnostics. -/
def decodeObjectData [FromJson α] (obj : Verso.Multi.Object) :
    Except DecodeError (StoredEntry α) :=
  match fromJson? (α := α) obj.data with
  | .error err =>
      .error { canonicalName := obj.canonicalName, message := err }
  | .ok data =>
      .ok { canonicalName := obj.canonicalName, data }

/-- Decode every object in a traversal domain without discarding malformed entries. -/
def decodeDomainEntries [FromJson α] (domain : Verso.Multi.Domain) :
    Array (Except DecodeError (StoredEntry α)) :=
  domain.objects.toArray.map fun (_key, obj) => decodeObjectData obj

/-- Decode every object in a named traversal store, returning an empty array when absent. -/
def decodeStoreEntries [FromJson α] (state : TraverseState) (domainName : Name) :
    Array (Except DecodeError (StoredEntry α)) :=
  match state.domains.get? domainName with
  | none => #[]
  | some domain => decodeDomainEntries domain

private def objectData? [FromJson α]
    (state : TraverseState) (domain : Name) (canonicalName : String) : Option α := do
  let obj ← state.getDomainObject? domain canonicalName
  (fromJson? (α := α) obj.data).toOption

private def saveObjectData
    (state : TraverseState) (domain : Name) (canonicalName : String) (data : Json) : TraverseState :=
  state.saveDomainObjectData domain canonicalName data

private def saveObjectId
    (state : TraverseState) (domain : Name) (canonicalName : String)
    (id : Verso.Multi.InternalId) : TraverseState :=
  state.saveDomainObject domain canonicalName id

private def modifyObjectData
    (state : TraverseState) (domain : Name) (canonicalName : String)
    (f : Json → Json) : TraverseState :=
  state.modifyDomainObjectData domain canonicalName f

namespace TraversalPreviews

def spec : StoreSpec := {
  name := Resolve.informalPreviewDomainName
  kind := .runtimeCache
  key := "(informal label, preview facet)"
  value := "Selected facet body, source location, provenance, and canonical target"
  summary := "One selected occurrence per statement/proof facet, preferring a nonempty body."
}

def domainName : Name := spec.name

def key (label : Name) (facet : PreviewCache.Facet) : String :=
  PreviewCache.key label facet

def object? (state : TraverseState) (previewKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName previewKey

def entry? (state : TraverseState) (previewKey : String) : Option PreviewCache.Entry :=
  objectData? state domainName previewKey

private def select? (state : TraverseState) (label : Name)
    (accept : Verso.Multi.Object → Bool) : Option (PreviewCache.Facet × Verso.Multi.Object) :=
  PreviewCache.Facet.select? fun facet => (object? state (key label facet)).filter accept

private def objectHasBody (object : Verso.Multi.Object) : Bool :=
  -- Inspect body presence without decoding the document AST for links and keys.
  (object.data.getObjVal? "blocks" >>= Json.getArr?).toOption.any (fun blocks => !blocks.isEmpty)

private def selectBody? (state : TraverseState) (label : Name) :
    Option (PreviewCache.Facet × Verso.Multi.Object) :=
  select? state label objectHasBody

/-- The preferred nonempty facet, without decoding its document body. -/
def selectedFacet? (state : TraverseState) (label : Name) : Option PreviewCache.Facet :=
  (selectBody? state label).map (·.1)

/-- Prefer actual statement/proof prose, then a code-backed facet. Unlike
`selectedFacet?`, this selects a preview identity, not a nonempty Manual body. -/
def selectedPreviewFacet? (state : TraverseState) (label : Name) : Option PreviewCache.Facet :=
  selectedFacet? state label <|>
    (select? state label fun object =>
      (fromJson? (α := PreviewCache.Metadata) object.data).toOption.any fun metadata =>
        metadata.hasRenderablePreview (objectHasBody object)).map (·.1)

/-- Decode the selected nonempty body only when the caller needs its content. -/
def selectedEntry? (state : TraverseState) (label : Name) : Option PreviewCache.Entry := do
  let (_, object) ← selectBody? state label
  (fromJson? object.data).toOption

/-- Canonical links prefer a nonempty body but may target a bodyless occurrence. -/
def canonicalOccurrence? (state : TraverseState) (label : Name) : Option PreviewCache.Occurrence := do
  let (_, object) ← selectBody? state label <|> select? state label (fun _ => true)
  (fromJson? object.data).toOption

def href? (state : TraverseState) (previewKey : String) : Option String :=
  (objectData? (α := PreviewCache.Occurrence) state domainName previewKey).bind (·.target) |>.bind fun id =>
    (state.externalTags[id]?).map (·.relativeLink)

def hrefFor? (state : TraverseState) (label : Name) (facet : PreviewCache.Facet) :
    Option String :=
  href? state (key label facet)

def saveId
    (state : TraverseState) (previewKey : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName previewKey id

def saveData (state : TraverseState) (previewKey : String) (data : Json) : TraverseState :=
  saveObjectData state domainName previewKey data

/-- Commit a selected facet's body, source metadata, and target together. -/
def saveSelected (state : TraverseState) (id : Verso.Multi.InternalId)
    (entry : PreviewCache.Entry) : TraverseState :=
  let previewKey := key entry.label entry.facet
  saveId (saveData state previewKey (toJson { entry with target := some id })) previewKey id


def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Decode every statement/proof traversal-preview entry, preserving per-entry decode errors. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry PreviewCache.Entry)) :=
  decodeStoreEntries state domainName

end TraversalPreviews

/-- Supply a rendering context through Verso's normal initialization hook. -/
def withInitializer (impls : ExtensionImpls) (initializeState : TraverseState → TraverseState) : ExtensionImpls :=
  impls.insertBlock `Informal.renderModel {
    init := initializeState
    traverse := fun _ _ _ => pure none
    toHtml := none
    toTeX := none
  }

namespace Nodes

def spec : StoreSpec := {
  name := Resolve.informalDomainName
  kind := .semanticDomain
  key := "informal label"
  value := "RenderNode plus node anchor ids"
  summary := "Shared rendering nodes, initialized at capture and completed by traversal."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def node? (state : TraverseState) (label : Name) : Option Informal.RenderNode :=
  objectData? state domainName label.toString

/-- Required semantic lookups distinguish absent captures, unknown labels, and corrupt entries. -/
def required (state : TraverseState) (label : Name) : Except String Informal.RenderNode := do
  let some object := object? state label
    | if (state.getDomainObject? `Informal.renderOverviews "graph").isNone then
        throw s!"Missing rendering node '{label}'; initialize traversal with the document's RenderModel"
      else
        throw s!"Unknown Blueprint label '{label}' in the document's RenderModel"
  fromJson? object.data |>.mapError (fun error => s!"Malformed rendering node '{label}': {error}")

/-- Resolve canonical source metadata from the selected facet while preserving node numbering. -/
def resolveCanonical (state : TraverseState) (node : Informal.RenderNode) : Informal.BlockData :=
  let data := node.toBlockData
  match TraversalPreviews.canonicalOccurrence? state node.label with
  | none => data
  | some occurrence => { data with
      sourceLocation := occurrence.sourceLocation
      sourceRef := occurrence.sourceRef }

/-- Rendering metadata is available even before this node has a document occurrence. -/
def capturedData? (state : TraverseState) (label : Name) : Option Informal.BlockData :=
  (node? state label).map (resolveCanonical state)

/-- Canonical occurrence data is present only for traversed nodes. -/
def hasRenderedOccurrence (state : TraverseState) (label : Name) : Bool :=
  (object? state label).any fun object =>
    !object.ids.isEmpty && (object.data.getObjVal? "occurrence").toOption.any (· != .null)

/-- Read the occurrence without decoding semantic metadata or external code payloads. -/
def occurrence? (state : TraverseState) (label : Name) : Option Informal.BlockOccurrence := do
  let object ← object? state label
  guard (!object.ids.isEmpty)
  (object.data.getObjValAs? (Option Informal.BlockOccurrence) "occurrence").toOption.join

/-- Resolve a node only after traversal has allocated its occurrence and target. -/
def renderedData? (state : TraverseState) (label : Name) : Option Informal.BlockData := do
  guard (hasRenderedOccurrence state label)
  capturedData? state label

def resolve? (state : TraverseState) (occurrence : Informal.BlockOccurrence) : Option Informal.BlockData :=
  (node? state occurrence.label).map (·.resolve occurrence)

def resolve (state : TraverseState) (occurrence : Informal.BlockOccurrence) : Except String Informal.BlockData :=
  (required state occurrence.label).map (·.resolve occurrence)

def href? (state : TraverseState) (label : Name) : Option String :=
  ((TraversalPreviews.canonicalOccurrence? state label).bind (·.target)).bind (fun id => (state.externalTags[id]?).map (·.relativeLink)) <|>
    Resolve.resolveDomainHref? state domainName label.toString

/-- The selected body target when available, otherwise the first traversal target. -/
def target? (state : TraverseState) (label : Name) : Option Verso.Multi.InternalId :=
  (TraversalPreviews.canonicalOccurrence? state label).bind (·.target) <|> (object? state label).bind (·.ids.toArray[0]?)

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveNode (state : TraverseState) (node : Informal.RenderNode) : TraverseState :=
  saveObjectData state domainName node.label.toString (toJson node)

def saveOccurrence (state : TraverseState) (occurrence : Informal.BlockOccurrence) : TraverseState :=
  match object? state occurrence.label with
  | none => state
  | some object =>
    -- The occurrence is the only mutable part of the captured record. Preserve
    -- external declaration payloads without decoding or serializing them again.
    saveObjectData state domainName occurrence.label.toString
      (object.data.setObjVal! "occurrence" (toJson (some occurrence)))

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Capture the rendering projection without retaining elaboration or provenance state. -/
def capture (state : Informal.Environment.State) : Array Informal.RenderNode :=
  state.data.toArray.map fun (label, node) =>
    Informal.RenderNode.ofNode label node (node.owner.bind state.authors.get?)

def install (state : TraverseState) (nodes : Array Informal.RenderNode) : TraverseState :=
  nodes.foldl saveNode state

/-- Every captured node, including nodes without a rendered occurrence. -/
def allEntries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.RenderNode)) :=
  decodeStoreEntries state domainName

/-- Only traversed nodes participate in document numbering and relation indexes. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.BlockData)) :=
  (allEntries state).filterMap fun decoded =>
    match decoded with
    | .error err => some (.error err)
    | .ok stored =>
      if !hasRenderedOccurrence state stored.data.label then none else
        stored.data.occurrence.map fun occurrence =>
          .ok { canonicalName := stored.canonicalName, data := stored.data.resolve occurrence }

end Nodes

/- Project overviews captured alongside the shared rendering nodes. -/
namespace RenderOverviews

def spec : StoreSpec := {
  name := `Informal.renderOverviews
  kind := .internalIndex
  key := "overview name"
  value := "Typed captured graph or summary data"
  summary := "Project overviews selected by the generator and reused by traversal and rendering."
}

def required [FromJson α] (state : TraverseState) (name : Name) : Except String α := do
  let some object := state.getDomainObject? spec.name name.toString
    | throw s!"Missing captured Blueprint {name}; initialize traversal with the document's RenderModel"
  fromJson? object.data |>.mapError (fun error => s!"Malformed captured Blueprint {name}: {error}")

def saveData [ToJson α] (state : TraverseState) (name : Name) (data : α) : TraverseState :=
  saveObjectData state spec.name name.toString (toJson data)

end RenderOverviews

namespace InlineCode

def spec : StoreSpec := {
  name := Resolve.informalCodeDomainName
  kind := .internalIndex
  key := "source code-block identity"
  value := "InlineCodeData plus code-panel anchor ids and folding settings"
  summary := "Traversal-local code panels, each retaining its declarations and source identity."
}

def labelSpec : StoreSpec := {
  name := `Informal.Block.inlineCodeLabels
  kind := .internalIndex
  key := "informal label"
  value := "Ordered array of source code-block identities"
  summary := "Index from each informal label to all of its rendered literate code blocks."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (blockId : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName blockId.toString

def data? (state : TraverseState) (blockId : Name) : Option Informal.InlineCodeData :=
  objectData? state domainName blockId.toString

def href? (state : TraverseState) (blockId : Name) : Option String :=
  Resolve.resolveDomainHref? state domainName blockId.toString

private def blockIds (state : TraverseState) (label : Name) : Array Name :=
  (objectData? state labelSpec.name label.toString).getD #[]

/-- Distinct blocks in document order; the block store remains the single owner of their data. -/
def blocks (state : TraverseState) (label : Name) : Informal.InlineCodeBlocks :=
  (blockIds state label).filterMap (data? state)

def firstHref? (state : TraverseState) (label : Name) : Option String :=
  (blockIds state label).findSome? (href? state)

def forDecl? (state : TraverseState) (label decl : Name) : Option Informal.InlineCodeData :=
  (blocks state label).find? fun block =>
    block.declarations.any (fun candidate => candidate.name.eraseMacroScopes == decl.eraseMacroScopes)

def saveId (state : TraverseState) (blockId : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName blockId.toString id

def saveData (state : TraverseState) (data : Informal.InlineCodeData) : TraverseState :=
  let ids := blockIds state data.label
  let ids := if ids.contains data.blockId then ids else ids.push data.blockId
  saveObjectData (saveObjectData state domainName data.blockId.toString (toJson data))
    labelSpec.name data.label.toString (toJson ids)

end InlineCode

namespace RustInlineCode

def spec : StoreSpec := {
  name := Informal.Rust.informalRustCodeDomain
  kind := .internalIndex
  key := "informal label"
  value := "Rust.InlineCodeData plus code-panel anchor ids and folding settings"
  summary := "Traversal-local index for Blueprint Rust code-panel sources keyed by informal label."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.Rust.InlineCodeData :=
  objectData? state domainName label.toString

def href? (state : TraverseState) (label : Name) : Option String :=
  Resolve.resolveDomainHref? state domainName label.toString

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveData (state : TraverseState) (label : Name) (data : Informal.Rust.InlineCodeData) :
    TraverseState :=
  saveObjectData state domainName label.toString (toJson data)

end RustInlineCode

namespace SourceDocuments

def spec : StoreSpec := {
  name := Resolve.sourceDocumentDomainName
  kind := .semanticDomain
  key := "source document id"
  value := "Source.Document declaration metadata"
  summary := "Semantic index for original source documents referenced by Blueprint nodes."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (id : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName id

def data? (state : TraverseState) (id : String) : Option Informal.Source.Document :=
  objectData? state domainName id

def saveData (state : TraverseState) (id : String) (data : Informal.Source.Document) :
    TraverseState :=
  saveObjectData state domainName id (toJson data)

def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.Source.Document)) :=
  decodeStoreEntries state domainName

end SourceDocuments

namespace ExternalMarkup

def spec : StoreSpec := {
  name := Resolve.externalMarkupDomainName
  kind := .semanticDomain
  key := "informal label"
  value := "ExternalMarkupData plus markup block anchor ids"
  summary := "Semantic index for raw external markup attachments keyed by informal label."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.Data.ExternalMarkupData :=
  objectData? state domainName label.toString

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveData (state : TraverseState) (label : Name) (data : Json) : TraverseState :=
  saveObjectData state domainName label.toString data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Decode every external-markup store entry, preserving per-entry decode errors. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.Data.ExternalMarkupData)) :=
  decodeStoreEntries state domainName

end ExternalMarkup

namespace Groups

def spec : StoreSpec := {
  name := Resolve.informalGroupDomainName
  kind := .semanticDomain
  key := "group label"
  value := "GroupBlockData declaration metadata"
  summary := "Semantic declaration index for Blueprint parent/group labels."
}

def domainName : Name := spec.name

def data? (state : TraverseState) (label : Name) : Option Informal.GroupBlockData :=
  objectData? state domainName label.toString

def saveData (state : TraverseState) (label : Name) (data : Json) : TraverseState :=
  saveObjectData state domainName label.toString data

end Groups

namespace Graphs

def spec : StoreSpec := {
  name := Resolve.graphDomainName
  kind := .runtimeCache
  key := "graph block key"
  value := "semantic GraphModel, render options, and graph block anchor ids"
  summary := "Traversal-cached Blueprint graph data finalized by GraphApi for manifest and browser consumers."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (key : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName key

def data? (state : TraverseState) (key : String) : Option Informal.Graph.CachedGraphData :=
  objectData? state domainName key

def saveId
    (state : TraverseState) (key : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName key id

def saveData (state : TraverseState) (key : String) (data : Informal.Graph.CachedGraphData) :
    TraverseState :=
  saveObjectData state domainName key (toJson data)

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Decode every cached graph entry, preserving per-entry decode errors. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.Graph.CachedGraphData)) :=
  decodeStoreEntries state domainName

end Graphs



namespace LeanCodePreviews

def spec : StoreSpec := {
  name := Informal.LeanCodePreviewKey.domainName
  kind := .runtimeCache
  key := "external Lean declaration name or source code-block identity"
  value := "LeanCodePreview.Entry plus code-preview anchor ids"
  summary := "Traversal-cached Lean code preview payloads keyed by external declaration name or source code-block identity."
}

def domainName : Name := spec.name

def lookupKey (decl : Name) : String :=
  Informal.LeanCodePreviewKey.lookupKey decl

def lookupInlineKey (blockId : Name) : String :=
  Informal.LeanCodePreviewKey.inlineLookupKey blockId

def object? (state : TraverseState) (previewKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName previewKey

def href? (state : TraverseState) (previewKey : String) : Option String :=
  (Resolve.resolveDomainHrefs state domainName previewKey)[0]?

def hrefFor? (state : TraverseState) (decl : Name) : Option String :=
  href? state (lookupKey decl)

def saveId
    (state : TraverseState) (previewKey : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName previewKey id

def saveData (state : TraverseState) (previewKey : String) (data : Json) : TraverseState :=
  saveObjectData state domainName previewKey data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

end LeanCodePreviews

namespace ExternalDeclAnchors

def spec : StoreSpec := {
  name := Resolve.externalRenderedDeclDomainName
  kind := .internalIndex
  key := "(occurrence, canonical declaration), plus (label, declaration) fallback"
  value := "rendered declaration row anchor ids"
  summary := "Visible declaration rows and the first visible fallback when the selected prose occurrence has no code."
}

def domainName : Name := spec.name

def key (occurrence : Verso.Multi.InternalId) (decl : Name) : String :=
  Resolve.externalRenderedDeclTargetKey occurrence decl

def object? (state : TraverseState) (targetKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName targetKey

def href? (state : TraverseState) (label decl : Name) : Option String :=
  Resolve.resolveRenderedExternalDeclHref? state label decl

/-- HTML `id` attributes for a registered rendered external-declaration row. -/
def htmlIdAttrs (state : TraverseState) (occurrence : Verso.Multi.InternalId) (decl : Name) : Array (String × String) :=
  match object? state (key occurrence decl) with
  | none => #[]
  | some obj =>
    match obj.ids.toArray[0]? with
    | some targetId => state.htmlId targetId
    | none => #[]

def saveId
    (state : TraverseState) (targetKey : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName targetKey id

end ExternalDeclAnchors

namespace CitationPreviews

def spec : StoreSpec := {
  name := Resolve.citationPreviewDomainName
  kind := .runtimeCache
  key := "(citation label, citation style, locator kind, locator index)"
  value := "citation preview payload"
  summary := "Manifest-backed bibliography hover previews keyed by citation target and locator."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (previewKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName previewKey

def saveData (state : TraverseState) (previewKey : String) (data : Json) : TraverseState :=
  saveObjectData state domainName previewKey data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

end CitationPreviews

namespace Bibliography

def spec : StoreSpec := {
  name := Resolve.bibliographyDomainName
  kind := .semanticDomain
  key := "citation label"
  value := "bibliography entry anchor ids"
  summary := "Semantic index for bibliography entry anchors keyed by citation label."
}

def domainName : Name := spec.name

def href? (state : TraverseState) (label : String) : Option String :=
  Resolve.resolveDomainHref? state domainName label

def saveId (state : TraverseState) (label : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label id

end Bibliography

namespace CitationUsages

def spec : StoreSpec := {
  name := Resolve.citationUsageDomainName
  kind := .accumulator
  key := "citation label"
  value := "CitationUsageData plus citation use-site ids"
  summary := "Traversal-local backlink accumulator for bibliography usage details."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label

def saveId (state : TraverseState) (label : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label id

def modifyData (state : TraverseState) (label : String) (f : Json → Json) : TraverseState :=
  modifyObjectData state domainName label f

def hrefs (state : TraverseState) (label : String) : Array String :=
  Resolve.resolveDomainHrefs state domainName label

end CitationUsages

namespace RelatedPanelUsedByCache

/-- Compact reverse-dependency metadata; canonical source-node data remains in `Nodes`. -/
structure Entry where
  sourceLabel : Data.Label
  inStatement : Bool := false
  inProof : Bool := false
  origins : Array Data.UseOrigin := #[]
  intents : Array Data.UseIntent := #[]
deriving FromJson, ToJson

def spec : StoreSpec := {
  name := `_versoBlueprintRelationUsedByCache
  kind := .internalIndex
  key := "informal label"
  value := "precomputed reverse-dependency metadata keyed by source label"
  summary := "Traversal-local render cache for Blueprint relation-panel reverse dependencies."
}

def domainName : Name := spec.name

def data? (state : TraverseState) (label : Data.Label) : Option (Array Entry) :=
  objectData? state domainName label.toString

def saveData (state : TraverseState) (label : Data.Label) (entries : Array Entry) :
    TraverseState :=
  saveObjectData state domainName label.toString (toJson entries)

end RelatedPanelUsedByCache

namespace RelatedPanelGroupMembersCache

def spec : StoreSpec := {
  name := `_versoBlueprintRelationGroupMembersCache
  kind := .internalIndex
  key := "group label"
  value := "ordered statement-member labels"
  summary := "Traversal-local render cache for Blueprint relation-panel group membership."
}

def domainName : Name := spec.name

def data? (state : TraverseState) (label : Data.Label) : Option (Array Data.Label) :=
  objectData? state domainName label.toString

def saveData (state : TraverseState) (label : Data.Label) (members : Array Data.Label) :
    TraverseState :=
  saveObjectData state domainName label.toString (toJson members)

end RelatedPanelGroupMembersCache

/--
Code-side inventory of the traversal indexes owned by Blueprint.

This is documentation-oriented metadata: callers should still use the typed
namespaces above. The list exists so reviews of the design-rationale schema can
compare against one source location instead of rediscovering each domain name.
-/
def allSpecs : Array StoreSpec := #[
  Nodes.spec,
  RenderOverviews.spec,
  InlineCode.spec,
  InlineCode.labelSpec,
  RustInlineCode.spec,
  SourceDocuments.spec,
  ExternalMarkup.spec,
  Groups.spec,
  Graphs.spec,
  TraversalPreviews.spec,
  LeanCodePreviews.spec,
  ExternalDeclAnchors.spec,
  CitationPreviews.spec,
  Bibliography.spec,
  CitationUsages.spec,
  RelatedPanelUsedByCache.spec,
  RelatedPanelGroupMembersCache.spec
]

end Informal.TraversalIndex
