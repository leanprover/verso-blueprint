/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprint.Informal.Block.Store
public import VersoBlueprint.Informal.LeanCodePreview
public import VersoBlueprint.Lib.PreviewSource

public section

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

/-- A selected facet retains its complete content/occurrence record alongside the
node semantics from the same rendering state. This is a transient view, not a store. -/
structure Facet where
  preview : PreviewCache.Entry
  data : BlockData

/-- Resolve node semantics for an already decoded facet. Keep `preview` intact:
its source, target and folding defaults belong to the selected occurrence. -/
def facet (state : TraverseState) (key : String) (preview : PreviewCache.Entry) : Except String Facet := do
  unless PreviewCache.key preview.label preview.facet == key do
    throw s!"Mismatched Blueprint preview identity for '{key}'"
  return { preview, data := ← canonical state preview.label }

/-- Resolve an explicit stored facet. Absence is optional; malformed content,
mismatched identity, and missing node semantics are errors. No other facet is borrowed. -/
def facetByKey? (state : TraverseState) (key : String) : Except String (Option Facet) := do
  let some object := TraversalIndex.TraversalPreviews.object? state key | return none
  let preview ← (fromJson? (α := PreviewCache.Entry) object.data).mapError
    (fun error => s!"Malformed Blueprint preview '{key}': {error}")
  return some (← facet state key preview)

/-- Included code panels for this facet, retaining the selected entry's keys first.
Captured declaration facts do not make omitted inline panels available. -/
def codePreviewKeys (state : TraverseState) (resolved : Facet) : Array String := Id.run do
  let externalKeys := (resolved.data.codeData.toArray.flatMap (·.externalDecls)).filterMap fun decl =>
    let key := TraversalIndex.LeanCodePreviews.lookupKey decl.canonical
    if (TraversalIndex.LeanCodePreviews.object? state key).isSome then some key else none
  let inlineKeys := (TraversalIndex.InlineCode.blockIds state resolved.preview.label).filterMap fun blockId =>
    let key := TraversalIndex.LeanCodePreviews.lookupInlineKey blockId
    -- Keep broken required panels discoverable for checked resolution. Only a
    -- known declaration-free block without a preview has no panel to resolve.
    if (TraversalIndex.LeanCodePreviews.object? state key).isSome then some key else
      match TraversalIndex.InlineCode.data? state blockId with
      | some block => if block.declarations.isEmpty then none else some key
      | none => some key
  let mut keys := #[]
  for key in resolved.preview.leanCodePreviewKeys ++ externalKeys ++ inlineKeys do
    if !keys.contains key then keys := keys.push key
  return keys

/-- One included code panel with its checked declaration facts. Like `Facet`, this
is a transient view tied to the rendering state used to resolve it. -/
structure CodePanel where
  preview : LeanCodePreview.Entry
  facts : BlockCodeData

/-- Resolve an already decoded code preview. Its storage key, payload identity and
required inline metadata must agree before either content or facts are consumed. -/
def codePanel (state : TraverseState) (key : String) (preview : LeanCodePreview.Entry) :
    Except String CodePanel := do
  let facts ← match preview.source with
    | .externalDecl decl =>
      unless preview.target == decl.canonical &&
          key == TraversalIndex.LeanCodePreviews.lookupKey preview.target do
        throw s!"Mismatched Blueprint Lean-code preview identity for '{key}'"
      pure { externalDecls := #[decl] }
    | .inlineBlocks label .. =>
      unless key == TraversalIndex.LeanCodePreviews.lookupInlineKey preview.target do
        throw s!"Mismatched Blueprint Lean-code preview identity for '{key}'"
      let block ← TraversalIndex.InlineCode.required state preview.target
      unless block.label == label do
        throw s!"Mismatched Blueprint inline-code owner for '{key}'"
      pure (BlockCodeData.ofInlineBlocks #[block])
  return { preview, facts }

/-- Required included code content and facts. Missing or malformed records remain
errors; availability does not establish successful rendering or a final artifact. -/
def codePanelByKey (state : TraverseState) (key : String) : Except String CodePanel := do
  let preview ← match TraversalIndex.LeanCodePreviews.decodedEntry? state key with
    | none => .error s!"Missing Blueprint Lean-code preview '{key}'"
    | some (.error error) => .error s!"Malformed Blueprint Lean-code preview '{key}': {error.message}"
    | some (.ok entry) => .ok entry.data
  codePanel state key preview

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
