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
deriving Inhabited, Repr

instance : Lean.ToJson Entry where
  toJson entry := .arr #[toJson entry.label, toJson entry.facet, toJson entry.blocks]

instance : Lean.FromJson Entry where
  fromJson? v := do
    match v with
    | .arr arr =>
      let some label := arr[0]? | throw "expected preview label"
      let some facet := arr[1]? | throw "expected preview facet"
      let some blocks := arr[2]? | throw "expected preview blocks"
      return {
        label := ← fromJson? label
        facet := ← fromJson? facet
        blocks := ← fromJson? blocks
      }
    | _ =>
      return {
        label := ← v.getObjValAs? Name "label"
        facet := ← v.getObjValAs? Facet "facet"
        blocks := ← v.getObjValAs? (Array (Verso.Doc.Block Verso.Genre.Manual)) "blocks"
      }

def Entry.ofBlocks (label : Name) (facet : Facet)
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) : Entry :=
  { label, facet, blocks }

end Informal.PreviewCache
