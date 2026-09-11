/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Commands.Graph
import VersoBlueprint.Graph

namespace Verso.VersoBlueprintTests.BlueprintGraph.Shared

open Lean
open Informal
open Informal.Data
open Informal.Environment
open Informal.Graph

def mkInformal (deps : Array Name := #[]) : InformalData :=
  { stx := .missing, useDeclarations := deps.map (fun label => { label }), elabStx := #[] }

def mkDefDecl (name : Name) (typeSorry : Bool := false) : LiterateDef :=
  {
    name
    provedStatus := Data.ProvedStatus.ofRefCounts (if typeSorry then 1 else 0) 0
    typeSorryRefs := if typeSorry then #[.missing] else #[]
  }

def mkThmDecl (name : Name) (typeSorry : Bool := false) (proofSorry : Bool := false) : LiterateThm :=
  {
    name
    provedStatus := Data.ProvedStatus.ofRefCounts (if typeSorry then 1 else 0) (if proofSorry then 1 else 0)
    typeSorryRefs := if typeSorry then #[.missing] else #[]
    proofSorryRefs := if proofSorry then #[.missing] else #[]
  }

def mkDefCode (decl : Name) (typeSorry : Bool := false) : CodeRef :=
  .literate { stx := .missing, definedDefs := #[mkDefDecl decl typeSorry], definedTheorems := #[] }

def mkTheoremCode (decl : Name) (typeSorry : Bool := false) (proofSorry : Bool := false) : CodeRef :=
  .literate { stx := .missing, definedDefs := #[], definedTheorems := #[mkThmDecl decl typeSorry proofSorry] }

def mkState (entries : List (Name × Node)) : Environment.State :=
  let data := entries.foldl (init := ({} : Lean.NameMap Environment.RegisteredNode)) fun acc (label, node) =>
    acc.insert label { toNode := node, origin := `BlueprintGraph.Shared }
  { data }

def hasNodeWith {Ref : Type} (g : Graph Ref) (label : Name) (p : GraphNode Ref → Bool) : Bool :=
  match g.find? (·.label == label) with
  | some node => p node
  | none => false

def hasGraphDataNodeWith (g : GraphData) (label : Name) (p : NodeData → Bool) : Bool :=
  match g.nodes.find? (·.label == label) with
  | some node => p node
  | none => false

def hasGraphDataEdge (g : GraphData) (source target : Name) (axes : Array EdgeAxis) : Bool :=
  g.edges.any fun edge =>
    edge.source == source && edge.target == target && edge.axes == axes

def styleHasToken (style token : String) : Bool :=
  (style.splitOn ",").any (fun part => part.trimAscii.toString == token)

axiom external_axiom_decl : Nat
def external_def_decl : Nat := 1

end Verso.VersoBlueprintTests.BlueprintGraph.Shared
