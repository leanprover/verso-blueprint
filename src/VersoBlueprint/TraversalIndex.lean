/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoManual
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.GroupData
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
roles clarify whether the stored data is meant to be semantic document state or
just local render-time indexing/caching.
-/
inductive StoreKind where
  | semanticDomain
  | internalIndex
  | runtimeCache
  | accumulator
deriving Inhabited, Repr, BEq

structure StoreSpec where
  name : Name
  kind : StoreKind
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
  summary := "Canonical traversal index for Blueprint node anchors and lightweight node metadata."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.BlockData :=
  match object? state label with
  | some obj =>
      match fromJson? (α := Informal.StoredBlockData) obj.data with
      | .ok data => some data.toBlockData
      | .error _ =>
          match fromJson? (α := Informal.BlockData) obj.data with
          | .ok data => some data
          | .error _ => none
  | none => none

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
  kind := .internalIndex
  summary := "Traversal-local metadata lookup for declared Blueprint groups."
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
  name := Name.mkSimple "Informal.LeanCodePreview"
  kind := .runtimeCache
  summary := "Traversal-cached Lean declaration preview payloads keyed by declaration name."
}

def domainName : Name := spec.name

private def namespaceRoot : Name :=
  Name.str (Name.str .anonymous "Informal") "LeanCodePreview"

private partial def appendName (rootName : Name) (suffixName : Name) : Name :=
  match suffixName with
  | .anonymous => rootName
  | .str parent component => .str (appendName rootName parent) component
  | .num parent component => .num (appendName rootName parent) component

def lookupKey (decl : Name) : String :=
  (appendName namespaceRoot decl.eraseMacroScopes).toString

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

namespace InlinePreviewOwners

def spec : StoreSpec := {
  name := Name.mkSimple "Informal.inlinePreview.store"
  kind := .internalIndex
  summary := "Traversal-local ownership index used to deduplicate inline preview template emission."
}

def domainName : Name := spec.name

def key (path : Array String) (previewId : String) : String :=
  s!"{String.intercalate "/" path.toList}::{previewId}"

def registerOwner
    (state : TraverseState) (path : Array String) (previewId : String)
    (id : Verso.Multi.InternalId) : TraverseState :=
  let ownerKey := key path previewId
  if (state.getDomainObject? domainName ownerKey).isSome then
    state
  else
    saveObjectId state domainName ownerKey id

def ownerId?
    (state : TraverseState) (path : Array String) (previewId : String) :
    Option Verso.Multi.InternalId :=
  let ownerKey := key path previewId
  match state.getDomainObject? domainName ownerKey with
  | some obj => obj.ids.toArray[0]?
  | none => none

def isOwner
    (state : TraverseState) (path : Array String) (previewId : String)
    (id : Verso.Multi.InternalId) : Bool :=
  match ownerId? state path previewId with
  | some owner => owner == id
  | none => true

end InlinePreviewOwners

namespace Bibliography

def spec : StoreSpec := {
  name := Resolve.bibliographyDomainName
  kind := .semanticDomain
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

end Informal.TraversalIndex
