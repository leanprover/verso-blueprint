/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary
import VersoBlueprint.Realizations.Capture
import VersoBlueprint.TraversalIndex

open Lean Verso Doc
open Verso.Genre (Manual)
open Verso.Genre.Manual

namespace Informal

/-- Compute the display assessment once for each label in this capture. -/
def Realizations.Capture.Snapshot.assessmentMap (snapshot : Realizations.Capture.Snapshot) :
    Lean.NameMap Realizations.NodeAssessment :=
  snapshot.registry.nodes.foldl (fun map node => map.insert node.label (snapshot.assessmentFor node.label)) {}

/--
Runtime rendering data captured after project imports. Its nodes become the traversal's
canonical registry; blocks contain references and presentation settings only.
-/
structure RenderModel where
  nodes : Array RenderNode := #[]
  graph : Graph.GraphModel := {}
  summary : Commands.Summary := {}
deriving Inhabited

def RenderModel.fromJsonString! (serialized : String) : RenderModel := Id.run do
  match Json.parse serialized >>= fromJson? (α := Array RenderNode × Graph.GraphModel × Commands.Summary) with
  | .error error => panic! s!"Invalid Blueprint render model: {error}"
  | .ok (nodes, graph, summary) => return { nodes, graph, summary }

/-- Capture runtime data without carrying a Lean environment into the generator. -/
elab "blueprint_render_model%" : term => do
  Environment.reportImportedConflicts
  let state := Environment.informalExt.getState (← getEnv)
  let snapshot ← Realizations.Capture.capture
  let snapshot ← match snapshot with
    | .ok snapshot => pure snapshot
    | .error issues => throwError m!"Cannot capture Blueprint realization state: {repr issues}"
  let assessments := snapshot.assessmentMap
  let assessmentFor (label : Name) :=
    match assessments.get? label with
    | some assessment => assessment
    | none => snapshot.assessmentFor label
  let nodes := TraversalIndex.Nodes.capture state (some snapshot) (fun label => some (assessmentFor label))
  let graph := Graph.buildModel snapshot (snapshot.registry.nodes.map (·.label))
    (groupTitles := state.groups.toArray) (assessmentFor := assessmentFor)
  let summary ← Commands.buildSummary snapshot (assessmentFor := assessmentFor)
  let serialized := (toJson (nodes, graph, summary)).compress
  Lean.Elab.Term.elabTerm (← `(RenderModel.fromJsonString! $(quote serialized))) none


/-- Initialize the same node registry later completed by document traversal. -/
def RenderModel.install (model : RenderModel) (state : TraverseState) : TraverseState :=
  let state := TraversalIndex.Nodes.install state model.nodes
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
