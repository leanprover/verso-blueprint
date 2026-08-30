/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import Verso
public import VersoManual
public import VersoBlueprint.Data
public import VersoBlueprint.Environment
public import VersoBlueprint.PreviewCache
public import VersoBlueprint.PreviewRender
public import VersoBlueprint.Lib.PreviewKey
public import VersoBlueprint.Resolve
public import VersoBlueprint.TraversalIndex

public section

namespace Informal.PreviewSource

open Lean
open Informal Data Environment

/-!
`PreviewSource` is the shared read-side namespace for preview consumers.

Its job is to keep preview lookup details localized so callers do not decode
traversal caches or environment-side preview payloads directly.

The current split is intentionally phase-specific:

- traversal-time callers use the traversal helpers in this module when they
  need cached preview blocks or manifest lookup keys
- environment-time callers use the environment helpers when they need semantic
  preview content from `Informal.Environment.State`
- callers that need preview data for one label should use the selection helpers
  here so statement/proof fallback semantics stay consistent
- manifest construction uses the traversal enumeration helpers here when it
  needs every stored statement/proof preview entry

Known exception:

- manifest construction still enumerates the whole stored preview domain because
  it emits every renderable entry, not one selected label at a time
-/

abbrev ManualBlock := Verso.Doc.Block Verso.Genre.Manual

structure Preview where
  blocks : Array ManualBlock := #[]
  stxs : Array Syntax := #[]
deriving Inhabited, Repr

/--
A decoded traversal-preview object as stored after Manual traversal.

This is for whole-domain consumers such as manifest construction. Callers that
need one best preview for a label should use `Selection` instead.
-/
structure StoredTraversalEntry where
  /-- Manifest/cache key for this statement or proof preview facet. -/
  key : String
  /-- Canonical name of the underlying traversal object, for diagnostics. -/
  canonicalName : String
  entry : PreviewCache.Entry
deriving Inhabited, Repr

/-- A selected preview for one Blueprint label.

The `facet` and `key` fields identify the preview that should be used by
callers, while `preview` contains the phase-local renderable payload. -/
structure Selection where
  label : Name
  facet : PreviewCache.Facet
  key : String
  preview : Preview
deriving Inhabited, Repr

def Selection.ofPreview (label : Name) (facet : PreviewCache.Facet) (preview : Preview) :
    Selection :=
  {
    label
    facet
    key := PreviewCache.key label facet
    preview
  }

def traversalEntryByKey?
    (s : Verso.Genre.Manual.TraverseState) (key : String) : Option PreviewCache.Entry :=
  Informal.TraversalIndex.TraversalPreviews.entry? s key

/--
Decode every stored statement/proof traversal preview entry.

This intentionally does not apply statement/proof selection: manifest
construction needs every renderable facet, while one-label consumers should use
`traversalEntry?` for content or `traversalLookupKey?` for its identity.
-/
def traversalStoredEntries
    (s : Verso.Genre.Manual.TraverseState) :
    Array (Except Informal.TraversalIndex.DecodeError StoredTraversalEntry) :=
  Informal.TraversalIndex.TraversalPreviews.entries s |>.map fun
    | .error err => .error err
    | .ok stored =>
        let entry := stored.data
        .ok {
          key := PreviewCache.key entry.label entry.facet
          canonicalName := stored.canonicalName
          entry
        }

def traversalFacetEntry?
    (s : Verso.Genre.Manual.TraverseState)
    (label : Name)
    (facet : PreviewCache.Facet) : Option PreviewCache.Entry :=
  let key := Informal.TraversalIndex.TraversalPreviews.key label facet
  traversalEntryByKey? s key

def traversalEntry?
    (s : Verso.Genre.Manual.TraverseState) (label : Name) : Option PreviewCache.Entry :=
  Informal.TraversalIndex.TraversalPreviews.selectedEntry? s label

def traversalLookupKey?
    (s : Verso.Genre.Manual.TraverseState) (label : Name) : Option String := do
  let facet ← Informal.TraversalIndex.TraversalPreviews.selectedFacet? s label
  pure (PreviewCache.key label facet)

def externalMarkupKey (label : Name) : String :=
  s!"externalMarkup:{label}"

def traversalExternalMarkupLookupKey?
    (s : Verso.Genre.Manual.TraverseState) (label : Name) : Option String := do
  let data ← Informal.TraversalIndex.ExternalMarkup.data? s label
  if data.markup.isEmpty then
    none
  else
    some (externalMarkupKey label)

/--
Best preview candidate key for a Blueprint label in finished traversal state.

Prefer statement/proof prose, then a code-backed facet, then a source-backed
external-markup preview. Prose-only lookup helpers retain their body semantics. Final
generated data still checks whether the candidate has both a manifest entry and
rendered-fragment cache body before serializing it as a `previewKey`.
-/
def traversalPreviewCandidateKey?
    (s : Verso.Genre.Manual.TraverseState) (label : Name) : Option PreviewKey := do
  let key ← (PreviewCache.key label <$>
    Informal.TraversalIndex.TraversalPreviews.selectedPreviewFacet? s label) <|>
    traversalExternalMarkupLookupKey? s label
  PreviewKey.ofString? key

/-- Best preview candidate key for relation entries. -/
def traversalRelationPreviewKey?
    (s : Verso.Genre.Manual.TraverseState) (label : Name) : Option PreviewKey :=
  traversalPreviewCandidateKey? s label

private def nonEmptyOrNone {α} (xs : Array α) : Option (Array α) :=
  if xs.isEmpty then none else some xs

private def nodeFacetPreview? (node : Data.Node) (facet : PreviewCache.Facet) : Option Preview := do
  let informalData ←
    match facet with
    | .statement => node.statement
    | .proof => node.proof
  match nonEmptyOrNone informalData.previewBlocks with
  | some blocks => some { blocks }
  | none =>
    match nonEmptyOrNone informalData.elabStx with
    | some stxs => some { stxs }
    | none => none

def environmentSelection? (env : Environment) (label : Name) : Option Selection := do
  let state := informalExt.getState env
  let node ← state.data.get? label
  let (facet, preview) ←
    PreviewCache.Facet.select? (nodeFacetPreview? node)
  pure <| Selection.ofPreview label facet preview

def renderWidgetHtml (preview? : Option Preview) : Lean.Elab.Term.TermElabM Verso.Output.Html := do
  match preview? with
  | none => pure .empty
  | some preview =>
    if !preview.blocks.isEmpty then
      Informal.renderPreviewBlocksHtml preview.blocks
    else if !preview.stxs.isEmpty then
      Informal.renderStatementElabHtml preview.stxs
    else
      pure .empty

end Informal.PreviewSource
