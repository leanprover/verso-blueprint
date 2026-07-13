/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.GroupData
import VersoBlueprint.Informal.LeanCodePreviewKey
import VersoBlueprint.Graph
import VersoBlueprint.PreviewCache
import VersoBlueprint.Resolve
import VersoBlueprint.Rust
import VersoBlueprint.Source.Data

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

namespace Nodes

def spec : StoreSpec := {
  name := Resolve.informalDomainName
  kind := .semanticDomain
  key := "informal label"
  value := "StoredBlockData plus node anchor ids"
  summary := "Canonical traversal index for Blueprint node anchors and lightweight node metadata."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def storedData? (state : TraverseState) (label : Name) : Option Informal.StoredBlockData :=
  objectData? state domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.BlockData :=
  (storedData? state label).map (·.toBlockData)

def href? (state : TraverseState) (label : Name) : Option String :=
  Resolve.resolveDomainHref? state domainName label.toString

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveData (state : TraverseState) (label : Name) (data : Json) : TraverseState :=
  saveObjectData state domainName label.toString data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Decode every informal-node store entry, preserving per-entry decode errors. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.StoredBlockData)) :=
  decodeStoreEntries state domainName

end Nodes

namespace InlineCode

def spec : StoreSpec := {
  name := Resolve.informalCodeDomainName
  kind := .internalIndex
  key := "informal label"
  value := "InlineCodeData plus code-panel anchor ids and folding settings"
  summary := "Traversal-local index for Blueprint code-panel sources keyed by informal label."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.InlineCodeData :=
  objectData? state domainName label.toString

def href? (state : TraverseState) (label : Name) : Option String :=
  Resolve.resolveDomainHref? state domainName label.toString

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveData (state : TraverseState) (label : Name) (data : Json) : TraverseState :=
  saveObjectData state domainName label.toString data

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

namespace SourceRefs

def spec : StoreSpec := {
  name := Resolve.sourceRefDomainName
  kind := .semanticDomain
  key := "informal label"
  value := "Source.Ref provenance metadata"
  summary := "Semantic index for original-source spans attached to Blueprint nodes."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.Source.Ref :=
  objectData? state domainName label.toString

def saveData (state : TraverseState) (label : Name) (data : Informal.Source.Ref) :
    TraverseState :=
  saveObjectData state domainName label.toString (toJson data)

def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.Source.Ref)) :=
  decodeStoreEntries state domainName

end SourceRefs

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
  value := "semantic GraphData, render options, and graph block anchor ids"
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

namespace TraversalPreviews

def spec : StoreSpec := {
  name := Resolve.informalPreviewDomainName
  kind := .runtimeCache
  key := "(informal label, preview facet)"
  value := "PreviewCache.Entry plus preview anchor ids"
  summary := "Traversal-cached statement/proof preview payloads keyed by `(label, facet)`."
}

def domainName : Name := spec.name

def key (label : Name) (facet : PreviewCache.Facet) : String :=
  PreviewCache.key label facet

def object? (state : TraverseState) (previewKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName previewKey

def entry? (state : TraverseState) (previewKey : String) : Option PreviewCache.Entry :=
  objectData? state domainName previewKey

def href? (state : TraverseState) (previewKey : String) : Option String :=
  Resolve.resolveDomainHref? state domainName previewKey

def hrefFor? (state : TraverseState) (label : Name) (facet : PreviewCache.Facet) :
    Option String :=
  href? state (key label facet)

def saveId
    (state : TraverseState) (previewKey : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName previewKey id

def saveData (state : TraverseState) (previewKey : String) (data : Json) : TraverseState :=
  saveObjectData state domainName previewKey data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Decode every statement/proof traversal-preview entry, preserving per-entry decode errors. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry PreviewCache.Entry)) :=
  decodeStoreEntries state domainName

end TraversalPreviews

namespace LeanCodePreviews

def spec : StoreSpec := {
  name := Informal.LeanCodePreviewKey.domainName
  kind := .runtimeCache
  key := "external Lean declaration name or inline-code label"
  value := "LeanCodePreview.Entry plus code-preview anchor ids"
  summary := "Traversal-cached Lean code preview payloads keyed by external declaration name or shared inline-code label."
}

def domainName : Name := spec.name

def lookupKey (decl : Name) : String :=
  Informal.LeanCodePreviewKey.lookupKey decl

def lookupInlineKey (label : Name) : String :=
  Informal.LeanCodePreviewKey.inlineLookupKey label

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
  key := "(informal label, canonical external declaration)"
  value := "rendered declaration row anchor ids"
  summary := "Traversal-local anchor index for rendered external declaration rows."
}

def domainName : Name := spec.name

def key (label decl : Name) : String :=
  Resolve.externalRenderedDeclTargetKey label decl

def object? (state : TraverseState) (targetKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName targetKey

def href? (state : TraverseState) (label decl : Name) : Option String :=
  Resolve.resolveRenderedExternalDeclHref? state label decl

/-- HTML `id` attributes for a registered rendered external-declaration row. -/
def htmlIdAttrs (state : TraverseState) (label decl : Name) : Array (String × String) :=
  match object? state (key label decl) with
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

/--
Code-side inventory of the traversal indexes owned by Blueprint.

This is documentation-oriented metadata: callers should still use the typed
namespaces above. The list exists so reviews of the design-rationale schema can
compare against one source location instead of rediscovering each domain name.
-/
def allSpecs : Array StoreSpec := #[
  Nodes.spec,
  InlineCode.spec,
  RustInlineCode.spec,
  SourceDocuments.spec,
  SourceRefs.spec,
  ExternalMarkup.spec,
  Groups.spec,
  Graphs.spec,
  TraversalPreviews.spec,
  LeanCodePreviews.spec,
  ExternalDeclAnchors.spec,
  CitationPreviews.spec,
  Bibliography.spec,
  CitationUsages.spec
]

end Informal.TraversalIndex
