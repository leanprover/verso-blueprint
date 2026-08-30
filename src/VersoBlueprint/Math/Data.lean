/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean
public import VersoManual
meta import Verso.Instances.Deriving

public section

open Verso Doc Elab
open Verso.Genre Manual

namespace Informal.Math

open Lean Elab Syntax
open Lean.Doc.Syntax

instance : Quote MathMode where
  quote
    | .inline => mkCApp ``Lean.Doc.MathMode.inline #[]
    | .display => mkCApp ``Lean.Doc.MathMode.display #[]

structure BpMathData where
  mode : MathMode
  source : String
  texPrelude : String := ""
deriving FromJson, ToJson, Repr, Quote

end Informal.Math
