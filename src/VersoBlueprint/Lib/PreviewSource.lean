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

/-- A renderable facet from the elaborated source inventory. -/
structure Selection where
  facet : PreviewCache.Facet
  key : String
  blocks : Array ManualBlock
deriving Inhabited, Repr

def Selection.ofBlocks (label : Name) (facet : PreviewCache.Facet) (blocks : Array ManualBlock) :
    Selection :=
  { facet, key := PreviewCache.key label facet, blocks }

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
Preview candidates for a Blueprint label in finished traversal state.

Prefer statement/proof prose, then a code-backed facet, then a source-backed
external-markup preview. Prose-only lookup helpers retain their body semantics. Final
generated data still checks whether the candidate has both a manifest entry and
rendered-fragment cache body before serializing it as a `previewKey`.

An explicit facet never borrows another facet's prose or code. Only statements
may fall back to source-backed external markup.

-/
def traversalPreviewCandidateKeys
    (s : Verso.Genre.Manual.TraverseState) (label : Name)
    (facet? : Option PreviewCache.Facet := none) : Array PreviewKey :=
  let facets := match facet? with
    | none => TraversalIndex.TraversalPreviews.previewFacets s label
    | some facet => #[facet].filter (TraversalIndex.TraversalPreviews.hasRenderablePreview s label)
  let markup := if facet? == some .proof then #[] else (traversalExternalMarkupLookupKey? s label).toArray
  (facets.map (PreviewCache.key label) ++ markup).filterMap PreviewKey.ofString?

def traversalPreviewCandidateKey?
    (s : Verso.Genre.Manual.TraverseState) (label : Name)
    (facet? : Option PreviewCache.Facet := none) : Option PreviewKey :=
  (traversalPreviewCandidateKeys s label facet?)[0]?

private def nonEmptyOrNone {α} (xs : Array α) : Option (Array α) :=
  if xs.isEmpty then none else some xs

private def nodeFacetPreview? (node : Data.NodeInventory) (facet : PreviewCache.Facet) :
    Option (Array ManualBlock) := do
  let facetName := match facet with
    | .statement => `statement
    | .proof => `proof
  let body ← node.defaultProseView facetName
  nonEmptyOrNone body.blocks

def environmentSelection? (env : Environment) (label : Name) : Option Selection := do
  let state := informalExt.getState env
  let node ← state.inventory.get? label
  let (facet, preview) ←
    PreviewCache.Facet.select? fun facet =>
      if facet == .statement && node.sources.any (·.adoption.isSome) then none
      else nodeFacetPreview? node facet
  pure <| Selection.ofBlocks label facet preview

def renderWidgetHtml (blocks? : Option (Array ManualBlock))
    (snapshot? : Option Realizations.Capture.Snapshot := none) :
    Lean.Elab.Term.TermElabM Verso.Output.Html := do
  let some blocks := blocks? | return .empty
  if blocks.isEmpty then return .empty
  match snapshot? with
  | none => Informal.renderPreviewBlocksHtml blocks
  | some snapshot => Informal.renderPreviewBlocksHtmlWithSnapshot blocks snapshot

end Informal.PreviewSource
