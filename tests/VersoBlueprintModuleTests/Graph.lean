/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Graph
import VersoBlueprint.GraphApi
meta import VersoBlueprint.Graph
meta import VersoBlueprint.GraphApi

namespace VersoBlueprintModuleTests.Graph

open Lean
open Informal
open Informal.Data
open Informal.Graph

local macro "quotedGraphOptions" : term => do
  let options : GraphOptions := { direction := .LR, pack := true }
  return quote options

local macro "graphApiCacheKeyContract" : term => do
  return quote <| Informal.GraphApi.cacheKey (default : Verso.Multi.InternalId)

private def graphNode (label : Name) (statementUses : Array UseRef := #[]) : NodeData := {
  label
  title := label.toString
  displayLabel := label.toString
  statementUses
  visual := { fillcolor := "#ffffff" }
}

/-- info: true -/
#guard_msgs in
#eval
  let options : GraphOptions := quotedGraphOptions
  let model : GraphModel := {
    nodes := #[
      graphNode `module_graph_source,
      graphNode `module_graph_target #[{ label := `module_graph_source }]
    ]
  }
  let finalized := model.finish "module-graph" options
  let apiFinalized := Informal.GraphApi.finishData
    (Verso.Genre.Manual.TraverseState.initialize {}) "module-graph-api" {} options
  options.direction == .LR && options.pack &&
    (graphApiCacheKeyContract : String) ==
      Informal.GraphApi.cacheKey (default : Verso.Multi.InternalId) &&
    apiFinalized.key == "module-graph-api" && apiFinalized.nodes.isEmpty &&
    finalized.key == "module-graph" &&
    finalized.nodes.size == 2 && finalized.edges.size == 1 &&
    (match finalized.edges[0]? with
      | some edge =>
          edge.source == `module_graph_source &&
            edge.target == `module_graph_target &&
            edge.axes == #[EdgeAxis.statement]
      | none => false) &&
    (match finalized.variants[0]? with
      | some variant => variant.key == "full" && variant.options == options
      | none => false)

end VersoBlueprintModuleTests.Graph
