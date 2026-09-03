/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprint.Graph
public import VersoBlueprint.Informal.Block.Store
public import VersoBlueprint.Lib.PreviewSource
public import VersoBlueprint.TraversalIndex

public section

/-!
Public graph-data helpers.

`Informal.Graph` owns semantic `GraphModel`, immutable finished `GraphData`, and
the environment builder. This module adds the traversal-state bridge: graph
blocks cache only `GraphModel` plus render options, then page and manifest
consumers call the same `finishData` operation after traversal completes.
-/

namespace Informal.GraphApi

open Lean
open Verso
open Verso.Genre Manual

/-- Stable traversal-cache key for a rendered graph block. -/
def cacheKey (id : Verso.Multi.InternalId) : String :=
  s!"graph:{id}"

private def nodeTitle? (state : TraverseState) (label : Name) : Option String :=
  (Informal.TraversalIndex.Nodes.data? state label).map fun data =>
    data.displayTitle state

private def nodeHref? (state : TraverseState) (label : Name) : Option String :=
  Informal.TraversalIndex.Nodes.href? state label

private def groupTitle? (state : TraverseState) (label : Name) : Option String :=
  (Informal.TraversalIndex.Groups.data? state label).bind fun groupData =>
    let title := groupData.header.trimAscii.toString
    if title.isEmpty then none else some title

private def enrichNode (state : TraverseState) (node : Informal.Graph.NodeData) :
    Informal.Graph.NodeData :=
  let title := (nodeTitle? state node.label).getD node.title
  let href := nodeHref? state node.label <|> node.href
  let previewKey := Informal.PreviewSource.traversalPreviewCandidateKey? state node.label
  { node with title, href, previewKey }

private def enrichGroup (state : TraverseState) (group : Informal.Graph.GroupMetadata) :
    Informal.Graph.GroupMetadata :=
  match groupTitle? state group.label with
  | some title => { group with title, declared := true }
  | none => group

private def hasTraversalNode (state : TraverseState) (label : Name) : Bool :=
  (Informal.TraversalIndex.Nodes.data? state label).isSome

private def hasPreviewCandidate (node : Informal.Graph.NodeData) : Bool :=
  node.previewKey.isSome

private def keepFinalNode (state : TraverseState) (node : Informal.Graph.NodeData) : Bool :=
  hasTraversalNode state node.label ||
    node.warnings.unknownRef ||
    node.href.isSome ||
    hasPreviewCandidate node

private def finalModel
    (state : TraverseState) (model : Informal.Graph.GraphModel) :
    Informal.Graph.GraphModel :=
  {
    nodes := model.nodes.map (enrichNode state) |>.filter (keepFinalNode state)
    groupMetadata := model.groupMetadata.map (enrichGroup state)
  }

/--
Finish one graph after traversal.

This is the single traversal-aware semantic-to-public transition. It enriches
and selects nodes from completed traversal state, then delegates to
`GraphModel.finish` to materialize edges, group membership, and render variants
together. Page JSON and manifest output both call this function.
-/
def finishData
    (state : TraverseState)
    (key : String)
    (model : Informal.Graph.GraphModel)
    (options : Informal.Graph.GraphOptions) : Informal.Graph.GraphData :=
  (finalModel state model).finish key options

/-- Finish one rendered graph block using its stable traversal key. -/
def finishDataForBlock
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (model : Informal.Graph.GraphModel)
    (options : Informal.Graph.GraphOptions) : Informal.Graph.GraphData :=
  finishData state (cacheKey id) model options

/--
Store graph block data during traversal.

The traversal entry stores only semantic data and render options under the
stable block key; call `cachedEntries` after traversal finishes to read the
public, finalized form.
-/
def saveData
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (model : Informal.Graph.GraphModel)
    (options : Informal.Graph.GraphOptions) : TraverseState :=
  let key := cacheKey id
  let cached : Informal.Graph.CachedGraphData := { model := model.canonicalize, options }
  state
    |> (fun state => Informal.TraversalIndex.Graphs.saveId state key id)
    |> (fun state => Informal.TraversalIndex.Graphs.saveData state key cached)

/--
Decode every traversal-cached graph and finalize valid entries for public
manifest/API use while preserving malformed-entry diagnostics.

Call this only with the completed traversal state for the document/site being
emitted. The consumer owns error reporting because it defines the generation
boundary and its diagnostic context.
-/
def cachedEntries (state : TraverseState) :
    Array (Except Informal.TraversalIndex.DecodeError
      (Informal.TraversalIndex.StoredEntry Informal.Graph.GraphData)) :=
  Informal.TraversalIndex.Graphs.entries state |>.map fun
    | .error err => .error err
    | .ok stored =>
        .ok {
          canonicalName := stored.canonicalName
          data := finishData state stored.canonicalName stored.data.model stored.data.options
        }

end Informal.GraphApi
