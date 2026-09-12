/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Lib.PreviewSource

namespace Informal.RenderingResolution

open Lean Verso.Genre.Manual

/-- Resolve this occurrence, retaining its source and folding settings. Only numbering
comes from the shared document occurrence. The caller still owns the body being rendered. -/
def occurrence (state : TraverseState) (requested : BlockOccurrence)
    (context? : Option TraverseContext := none) : Except String BlockData := do
  let data ← TraversalIndex.Nodes.resolve state requested
  return match context? with
    | some context => data.withResolvedNumberingInContext state context
    | none => data.withResolvedNumbering state

/-- Resolve canonical node metadata and selected source provenance. This does not select
a body: callers needing a preview must retain its complete `PreviewCache.Entry`.
Missing captures, unknown labels, and malformed records remain distinct errors. -/
def canonical (state : TraverseState) (label : Data.Label) : Except String BlockData := do
  let node ← TraversalIndex.Nodes.required state label
  return (TraversalIndex.Nodes.resolveCanonical state node).withResolvedNumbering state

/-- Presentation of a node reference. A preview key is a candidate until artifact
finalization establishes that its manifest entry and rendered body both exist. -/
structure Reference where
  title : String
  href : Option String
  previewKey : Option PreviewKey

/-- Deliberate unresolved presentation for an optional relation target. -/
def Reference.labelOnly (label : Data.Label) : Reference := {
  title := label.toString (escape := false), href := none, previewKey := none
}

private def referenceWithTitle (state : TraverseState) (label : Data.Label)
    (facet? : Option PreviewCache.Facet) (title : String) : Reference := {
  title
  href := match facet? with
    | some facet => TraversalIndex.TraversalPreviews.hrefFor? state label facet
    | none => TraversalIndex.Nodes.href? state label
  previewKey := PreviewSource.traversalPreviewCandidateKey? state label facet?
}

/-- Present semantic metadata resolved from the same rendering state, without decoding
that semantic record again. Data from either `occurrence` or `canonical` is accepted:
reference numbering and the ordinary-reference facet come from the stored node occurrence,
never the supplied record's presentation. Source and folding settings are irrelevant here.
An explicit facet selects only its own title, target and preview; missing facets do not
borrow another facet's content. Proof-only nodes retain their ordinary proof title. -/
def referenceOfData (state : TraverseState) (data : BlockData)
    (facet? : Option PreviewCache.Facet := none) : Reference :=
  let title := match TraversalIndex.Nodes.occurrence? state data.label with
    | none => data.label.toString (escape := false)
    | some stored =>
      let display := ({ data with toBlockPresentation := stored.toBlockPresentation }).display state
      let isProof := (facet?.map (· == .proof)).getD stored.isProof
      if isProof then display.proofTitle else display.title
  referenceWithTitle state data.label facet? title

/-- Checked reference presentation, including for captured but unrendered nodes.
Use this at authored-reference rendering boundaries so malformed or missing semantic
records cannot become plausible plain text. -/
def reference (state : TraverseState) (label : Data.Label)
    (facet? : Option PreviewCache.Facet := none) : Except String Reference :=
  (canonical state label).map (referenceOfData state · facet?)

/-- Optional relation presentation. Unrendered labels need no semantic payload
decoding. This fallback does not validate authored references or required registry data. -/
def referenceOrLabel (state : TraverseState) (label : Data.Label) : Reference :=
  if !TraversalIndex.Nodes.hasRenderedOccurrence state label then
    if (TraversalIndex.Nodes.object? state label).isSome then
      referenceWithTitle state label none (label.toString (escape := false))
    else Reference.labelOnly label
  else
    match reference state label with
    | .ok result => result
    | .error _ => Reference.labelOnly label

end Informal.RenderingResolution
