/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary

open Lean Verso Doc
open Verso.Genre (Manual)
open Verso.Genre.Manual

namespace Informal

/--
Runtime rendering data captured after project imports. Its nodes become the traversal's
canonical registry; blocks contain references and presentation settings only.
-/
structure RenderModel where
  nodes : Lean.NameMap RenderNode := {}
  graph : Graph.GraphModel := {}
  summary : Commands.Summary := {}
deriving Inhabited

def RenderModel.fromJsonString! (serialized : String) : RenderModel := Id.run do
  let .ok json := Json.parse serialized | panic! "invalid Blueprint render model JSON"
  let .ok (nodes, graph, summary) :=
      fromJson? (α := Array RenderNode × Graph.GraphModel × Commands.Summary) json
    | panic! "invalid Blueprint render model data"
  return { nodes := nodes.foldl (fun acc node => acc.insert node.label node) {}, graph, summary }

/-- Capture runtime data without carrying a Lean environment into the generator. -/
elab "blueprint_render_model%" : term => do
  Environment.reportImportedConflicts
  let state := Environment.informalExt.getState (← getEnv)
  let nodes := TraversalIndex.Nodes.capture state
  let graph := Graph.buildModel state (state.data.toArray.map (·.1)) (groupTitles := state.groups.toArray)
  let summary ← Commands.buildSummary
  let serialized := (toJson (nodes, graph, summary)).compress
  Lean.Elab.Term.elabTerm (← `(RenderModel.fromJsonString! $(quote serialized))) none


/-- Initialize the same node registry later completed by document traversal. -/
def RenderModel.install (model : RenderModel) (state : TraverseState) : TraverseState :=
  let state := model.nodes.foldl (fun state _ node => TraversalIndex.Nodes.saveNode state node) state
  let state := TraversalIndex.RenderOverviews.saveData state `graph model.graph
  TraversalIndex.RenderOverviews.saveData state `summary model.summary

/-- Use Verso's initialization boundary for HTML, TeX, previews, and saved traversal states. -/
def RenderModel.withExtensions (model : RenderModel) (impls : ExtensionImpls) : ExtensionImpls :=
  TraversalIndex.withInitializer impls model.install

/-- A document paired with its complete project rendering context. -/
structure BlueprintDocument where
  text : Part Manual
  model : RenderModel

/-- Capture once at the project boundary; wrappers pass the selected model explicitly. -/
def BlueprintDocument.capture (text : Part Manual)
    (model : RenderModel := by exact blueprint_render_model%) : BlueprintDocument :=
  { text, model }

end Informal
