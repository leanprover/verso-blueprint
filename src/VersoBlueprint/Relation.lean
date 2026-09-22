/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import VersoBlueprint.PreviewCache

public section

namespace Informal.Relation

open Lean

/-- Metadata for one dependency facet. The related entry owns the endpoint;
keeping these fields together prevents statement/proof metadata from leaking. -/
structure Dependency where
  facet : PreviewCache.Facet
  origin : Data.UseOrigin := .manual
  intent : Data.UseIntent := .regular
deriving Inhabited, Repr, BEq, ToJson, FromJson

def Dependency.ofUseRef (useRef : Data.UseRef) (facet : PreviewCache.Facet) : Dependency :=
  { facet
    origin := useRef.origin, intent := useRef.intent }

def addUse (dependencies : Array Dependency) (useRef : Data.UseRef) (facet : PreviewCache.Facet) :
    Array Dependency :=
  let dependency := Dependency.ofUseRef useRef facet
  if dependencies.contains dependency then dependencies else dependencies.push dependency

end Informal.Relation
