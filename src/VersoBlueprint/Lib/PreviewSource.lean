/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.PreviewCache
import VersoBlueprint.PreviewRender
import VersoBlueprint.Lib.PreviewKey
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

namespace Informal.PreviewSource

open Lean
open Informal Data Environment

/-!
`PreviewSource` owns phase-specific preview selection: environment previews for
widgets, traversal prose selection, and candidate keys for code/markup previews.
These low-level optional queries do not validate required rendering inputs.

`RenderingResolution` interprets traversal stores for rendering consumers. Use its
checked facet and code-panel queries when content and semantic metadata are both
required. It builds on this module's selection policy. Manifest enumeration reads
all stored facets, retaining their storage keys for checked resolution.
-/

abbrev ManualBlock := Verso.Doc.Block Verso.Genre.Manual

structure Preview where
  blocks : Array ManualBlock := #[]
  stxs : Array Syntax := #[]
deriving Inhabited, Repr

/--
A decoded traversal-preview object as stored after Manual traversal.

This is for whole-domain consumers such as manifest construction. One-label
consumers use `traversalEntry?` for selected prose and its provenance, or
`traversalPreviewCandidateKey?` for a preview candidate including code and markup.
-/
structure StoredTraversalEntry where
  /-- Manifest/cache key for this statement or proof preview facet. -/
  key : String
  /-- Canonical name of the underlying traversal object, for diagnostics. -/
  canonicalName : String
  entry : PreviewCache.Entry
deriving Inhabited, Repr

/-- An environment-time preview for one Blueprint label.

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

An explicit facet never borrows another facet's prose or code. Only statements
may fall back to source-backed external markup.

-/
def traversalPreviewCandidateKey?
    (s : Verso.Genre.Manual.TraverseState) (label : Name)
    (facet? : Option PreviewCache.Facet := none) : Option PreviewKey := do
  let key ← match facet? with
    | none => (PreviewCache.key label <$>
        Informal.TraversalIndex.TraversalPreviews.selectedPreviewFacet? s label) <|>
        traversalExternalMarkupLookupKey? s label
    | some facet =>
      if Informal.TraversalIndex.TraversalPreviews.hasRenderablePreview s label facet then
        some (PreviewCache.key label facet)
      else if facet == .statement then traversalExternalMarkupLookupKey? s label
      else none
  PreviewKey.ofString? key

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
