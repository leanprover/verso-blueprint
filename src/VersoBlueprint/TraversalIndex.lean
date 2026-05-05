/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.GroupData
import VersoBlueprint.Informal.LeanDeclPreviewKey
import VersoBlueprint.PreviewCache
import VersoBlueprint.Resolve

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

def storedObjectData? (obj : Verso.Multi.Object) : Option Informal.StoredBlockData :=
  (fromJson? (α := Informal.StoredBlockData) obj.data).toOption

def storedData? (state : TraverseState) (label : Name) : Option Informal.StoredBlockData := do
  let obj ← object? state label
  storedObjectData? obj

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

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveData (state : TraverseState) (label : Name) (data : Json) : TraverseState :=
  saveObjectData state domainName label.toString data

end InlineCode

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

def saveId
    (state : TraverseState) (previewKey : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName previewKey id

def saveData (state : TraverseState) (previewKey : String) (data : Json) : TraverseState :=
  saveObjectData state domainName previewKey data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

end TraversalPreviews

namespace LeanCodePreviews

def spec : StoreSpec := {
  name := Informal.LeanDeclPreviewKey.domainName
  kind := .runtimeCache
  key := "Lean declaration name"
  value := "LeanCodePreview.Entry plus declaration-preview anchor ids"
  summary := "Traversal-cached Lean declaration preview payloads keyed by declaration name."
}

def domainName : Name := spec.name

def lookupKey (decl : Name) : String :=
  Informal.LeanDeclPreviewKey.lookupKey decl

def object? (state : TraverseState) (previewKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName previewKey

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
  Groups.spec,
  TraversalPreviews.spec,
  LeanCodePreviews.spec,
  ExternalDeclAnchors.spec,
  CitationPreviews.spec,
  Bibliography.spec,
  CitationUsages.spec
]

end Informal.TraversalIndex
