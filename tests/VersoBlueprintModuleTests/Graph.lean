/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Graph
meta import VersoBlueprint.Graph

namespace VersoBlueprintModuleTests.Graph

open Lean
open Informal
open Informal.Data
open Informal.Graph

local macro "quotedGraphOptions" : term => do
  let options : GraphOptions := { direction := .LR, pack := true }
  return quote options

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
  options.direction == .LR && options.pack &&
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
