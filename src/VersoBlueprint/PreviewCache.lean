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

/--
Preview payload stored during traversal.
`blocks` are already in the Manual genre and can be rendered by later HTML consumers.
-/
-- TODO: long-term, consider a single shared preview representation that can also
-- serve the widget path (currently fed from `elabStx`) in a phase-safe way.
structure Entry where
  label : Name
  facet : Facet
  blocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
deriving Inhabited, Repr, ToJson, FromJson

def Entry.ofBlocks (label : Name) (facet : Facet)
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) : Entry :=
  { label, facet, blocks }

end Informal.PreviewCache
