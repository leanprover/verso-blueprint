/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.PreviewCache
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

namespace Informal

open Lean
open Verso
open Verso.Genre Manual

/--
Whether traversal should refresh preview payload data for an existing object id set.

The first writer initializes the preview payload. Later writers may refresh it
only when they correspond to the same object id, which keeps duplicate labels
from clobbering the canonical preview.
-/
def shouldWritePreviewDataByIds [BEq α] (existingIds : Array α) (currentId : α) : Bool :=
  existingIds.isEmpty || existingIds.contains currentId

private def shouldWritePreviewData (existing? : Option Verso.Multi.Object) (id : Verso.Multi.InternalId) : Bool :=
  shouldWritePreviewDataByIds ((existing?.map (·.ids.toArray)).getD #[]) id

private def externalDeclsOfBlock (blockData : BlockData) : Array Data.ExternalRef :=
  match blockData.kind, blockData.codeData with
  | .statement _, some codeData => codeData.externalDecls
  | _, _ => #[]

/-- Store the rendered block body used by hover previews and Blueprint preview data. -/
def registerBlockPreviewData
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (blockData : BlockData)
    (contents : Array (Verso.Doc.Block Verso.Genre.Manual)) :
    m Unit := do
  let previewFacet := PreviewCache.Facet.ofInProgressKind blockData.kind
  let previewKey := PreviewCache.key blockData.label previewFacet
  let leanCodePreviewKeys :=
    (externalDeclsOfBlock blockData).map fun decl =>
      Informal.TraversalIndex.LeanCodePreviews.lookupKey decl.canonical
  let previewData := toJson <|
    PreviewCache.Entry.ofBlocks blockData.label previewFacet contents
      (sourceLocation := blockData.sourceLocation)
      (leanCodePreviewKeys := leanCodePreviewKeys)
  let existingPreview? := Informal.TraversalIndex.TraversalPreviews.object? (← get) previewKey
  if shouldWritePreviewData existingPreview? id then
    modify λ s => Informal.TraversalIndex.TraversalPreviews.saveData s previewKey previewData
  if existingPreview?.isNone then
    let path := (← read).path
    let _ ← Verso.Genre.Manual.externalTag id path s!"--informal-preview-{previewKey}"
    modify λ s => Informal.TraversalIndex.TraversalPreviews.saveId s previewKey id

private def registerExternalCodePreview
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (decl : Data.ExternalRef) :
    m Unit := do
  let codePreviewKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey decl.canonical
  let codePreviewData := toJson (LeanCodePreview.Entry.ofExternalDecl decl.canonical decl)
  let existingCodePreview? := Informal.TraversalIndex.LeanCodePreviews.object? (← get) codePreviewKey
  if shouldWritePreviewData existingCodePreview? id then
    modify λ s => Informal.TraversalIndex.LeanCodePreviews.saveData s codePreviewKey codePreviewData
  if existingCodePreview?.isNone then
    let path := (← read).path
    let _ ← Verso.Genre.Manual.externalTag id path s!"--lean-code-preview-{codePreviewKey}"
    modify λ s => Informal.TraversalIndex.LeanCodePreviews.saveId s codePreviewKey id

private def registerExternalCodePreviews
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (decls : Array Data.ExternalRef) :
    m Unit := do
  for decl in decls do
    registerExternalCodePreview id decl

private def registerExternalDeclAnchor
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (label : Data.Label)
    (decl : Data.ExternalRef) :
    m Unit := do
  let key := Resolve.externalRenderedDeclTargetKey label decl.canonical
  if (Informal.TraversalIndex.ExternalDeclAnchors.object? (← get) key).isNone then
    let declId ← Verso.Genre.Manual.freshId
    let path := (← read).path
    let _ ← Verso.Genre.Manual.externalTag declId path
      s!"--informal-external-decl-{label}-{decl.canonical}"
    modify λ s => Informal.TraversalIndex.ExternalDeclAnchors.saveId s key declId

private def registerExternalDeclAnchors
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (label : Data.Label)
    (decls : Array Data.ExternalRef) :
    m Unit := do
  for decl in decls do
    registerExternalDeclAnchor label decl

/--
Register all traversal-time preview and anchor data owned by an informal block.

This keeps the block extension focused on orchestration while the traversal
store owns hover-preview payloads, external Lean previews, and rendered
declaration anchors.
-/
def registerTraversedBlockAssets
    {m}
    [Monad m]
    [MonadReaderOf TraverseContext m]
    [MonadStateOf TraverseState m]
    [MonadLiftT IO m]
    (id : Verso.Multi.InternalId)
    (blockData : BlockData)
    (contents : Array (Verso.Doc.Block Verso.Genre.Manual)) :
    m Unit := do
  let externalDecls := externalDeclsOfBlock blockData
  registerBlockPreviewData id blockData contents
  registerExternalCodePreviews id externalDecls
  registerExternalDeclAnchors blockData.label externalDecls

end Informal
