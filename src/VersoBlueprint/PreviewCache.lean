/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.Source.Data

namespace Informal.PreviewCache

open Lean

inductive Facet where
  | statement
  | proof
deriving Inhabited, Repr, BEq, ToJson, FromJson

def Facet.suffix : Facet → String
  | .statement => "statement"
  | .proof => "proof"

/-- Select the first available facet, preferring the statement over the proof.
The caller decides which payloads are available (for example, nonempty bodies). -/
def Facet.select? {α : Type} (fetch : Facet → Option α) : Option (Facet × α) :=
  ((.statement, ·) <$> fetch .statement) <|> ((.proof, ·) <$> fetch .proof)

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
The selected facet's target and provenance. This projection can be decoded
without decoding its document body when resolving links or source metadata.
-/
structure Occurrence where
  /-- Anchor of the selected occurrence; other occurrences may retain their own page anchors. -/
  target : Option Verso.Multi.InternalId := none
  /-- Source location result for the source that produced this preview facet. -/
  sourceLocation : Informal.Data.SourceLocationResult :=
    Informal.Data.SourceLocationResult.unavailable "preview source location unavailable"
  /-- Original-source provenance owned by the selected occurrence of this facet. -/
  sourceRef : Option Informal.Source.Ref := none
  /-- Presentation defaults belong to the selected facet, not the semantic node. -/
  foldProofBlock : Bool := false
  foldCodeBlock : Bool := false
deriving Inhabited, Repr, ToJson, FromJson

/-- The selected facet's occurrence metadata and body form one persisted record. -/
structure Entry extends Occurrence where
  label : Name
  facet : Facet
  blocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
  /-- HTML-cache keys for associated Lean code previews. -/
  leanCodePreviewKeys : Array String := #[]
deriving Inhabited, Repr, ToJson, FromJson

def Entry.metadata (entry : Entry) : Metadata := {
  label := entry.label
  facet := entry.facet
  leanCodePreviewKeys := entry.leanCodePreviewKeys
}

def Entry.hasRenderedBody (entry : Entry) : Bool :=
  !entry.blocks.isEmpty

def Entry.ofBlocks (label : Name) (facet : Facet)
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual))
    (sourceLocation : Informal.Data.SourceLocationResult :=
      Informal.Data.SourceLocationResult.unavailable "preview source location unavailable")
    (leanCodePreviewKeys : Array String := #[])
    (sourceRef : Option Informal.Source.Ref := none) : Entry :=
  { label, facet, blocks, sourceLocation, leanCodePreviewKeys, sourceRef }

end Informal.PreviewCache
