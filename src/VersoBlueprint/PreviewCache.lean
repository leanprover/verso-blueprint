/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoManual
import VersoBlueprint.Data

namespace Informal.PreviewCache

open Lean

inductive Facet where
  | statement
  | proof
deriving Inhabited, Repr, BEq, ToJson, FromJson

def Facet.suffix : Facet → String
  | .statement => "statement"
  | .proof => "proof"

def Facet.ofInProgressKind : Informal.Data.InProgressKind → Facet
  | .statement _ => .statement
  | .proof => .proof

def key (label : Name) (facet : Facet) : String :=
  s!"{label}--{facet.suffix}"

/-- Preview-cache key for the statement facet of a Blueprint label.

Use this when the caller intentionally needs the fixed statement preview
identity. Callers that want the best available preview for a rendered label
should use `PreviewSource` selection helpers instead. -/
def statementKey (label : Name) : String :=
  key label .statement

/-- Preview-cache key for the proof facet of a Blueprint label. -/
def proofKey (label : Name) : String :=
  key label .proof

/--
Semantic preview metadata stored during traversal.

This metadata is meaningful even when a node has no rendered body blocks. For
example, a bodyless imported theorem may still carry Lean code preview keys
from `(lean := ...)`.
-/
structure Metadata where
  label : Name
  facet : Facet
  /-- HTML-cache keys for associated Lean code previews. -/
  leanCodePreviewKeys : Array String := #[]
deriving Inhabited, Repr, ToJson, FromJson

/--
Rendered preview body stored during traversal.

`blocks` are already in the Manual genre and can be rendered by later HTML
consumers. Empty body blocks do not imply empty semantic metadata.
-/
structure RenderedBody where
  blocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
deriving Inhabited, Repr, ToJson, FromJson

def RenderedBody.hasRenderedBody (body : RenderedBody) : Bool :=
  !body.blocks.isEmpty

/--
Preview payload stored during traversal.

The derived JSON shape remains flat for compatibility with saved traversal
states, but callers should treat `metadata` and `renderedBody` as separate
concerns.
-/
structure Entry where
  label : Name
  facet : Facet
  blocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
  /-- Source location result for the source that produced this preview facet. -/
  sourceLocation : Informal.Data.SourceLocationResult :=
    Informal.Data.SourceLocationResult.unavailable "preview source location unavailable"
  /-- HTML-cache keys for associated Lean code previews. -/
  leanCodePreviewKeys : Array String := #[]
deriving Inhabited, Repr, ToJson, FromJson

def Entry.metadata (entry : Entry) : Metadata := {
  label := entry.label
  facet := entry.facet
  leanCodePreviewKeys := entry.leanCodePreviewKeys
}

def Entry.renderedBody (entry : Entry) : RenderedBody := {
  blocks := entry.blocks
}

def Entry.hasRenderedBody (entry : Entry) : Bool :=
  entry.renderedBody.hasRenderedBody

def Entry.ofMetadataAndBody (metadata : Metadata) (body : RenderedBody := {})
    (sourceLocation : Informal.Data.SourceLocationResult :=
      Informal.Data.SourceLocationResult.unavailable "preview source location unavailable") : Entry := {
  label := metadata.label
  facet := metadata.facet
  blocks := body.blocks
  sourceLocation
  leanCodePreviewKeys := metadata.leanCodePreviewKeys
}

def Entry.ofBlocks (label : Name) (facet : Facet)
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual))
    (sourceLocation : Informal.Data.SourceLocationResult :=
      Informal.Data.SourceLocationResult.unavailable "preview source location unavailable")
    (leanCodePreviewKeys : Array String := #[]) : Entry :=
  Entry.ofMetadataAndBody
    { label, facet, leanCodePreviewKeys }
    { blocks }
    sourceLocation

end Informal.PreviewCache
