/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Graph
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.TraversalIndex

/-!
Public graph-data helpers.

`Informal.Graph` owns the stable graph data structures and the semantic
environment builder. This module adds the traversal-state bridge: graph blocks
store semantic `GraphData` plus render options during traversal, and
renderers/manifests finalize that cached object against the completed traversal
state to add hrefs, display titles, and Lean-computed graph render variants.
-/

namespace Informal.GraphApi

open Lean
open Verso
open Verso.Genre Manual

/-- Stable traversal-cache key for a rendered graph block. -/
def cacheKey (id : Verso.Multi.InternalId) : String :=
  s!"graph:{id}"

/-- Attach the rendered block key to graph data. -/
def keyedData (id : Verso.Multi.InternalId) (data : Informal.Graph.GraphData) :
    Informal.Graph.GraphData :=
  { data with key := cacheKey id }

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
  let previewKey := (Informal.PreviewSource.traversalLookupKey? state node.label).getD ""
  { node with title, href, previewKey }

private def enrichGroup (state : TraverseState) (group : Informal.Graph.GroupData) :
    Informal.Graph.GroupData :=
  match groupTitle? state group.label with
  | some title => { group with title, declared := true }
  | none => group

private def hasTraversalNode (state : TraverseState) (label : Name) : Bool :=
  (Informal.TraversalIndex.Nodes.data? state label).isSome

private def hasPreviewKey (node : Informal.Graph.NodeData) : Bool :=
  !node.previewKey.trimAscii.toString.isEmpty

private def keepFinalNode (state : TraverseState) (node : Informal.Graph.NodeData) : Bool :=
  hasTraversalNode state node.label ||
    node.warnings.unknownRef ||
    node.href.isSome ||
    hasPreviewKey node

private def labelSet (nodes : Array Informal.Graph.NodeData) : Lean.NameSet :=
  nodes.foldl (init := {}) fun acc node => acc.insert node.label

private def keepEdge (labels : Lean.NameSet) (edge : Informal.Graph.EdgeData) : Bool :=
  labels.contains edge.source && labels.contains edge.target

private def filterGroupChildren? (labels : Lean.NameSet) (group : Informal.Graph.GroupData) :
    Option Informal.Graph.GroupData :=
  let children := group.children.filter (fun child => labels.contains child)
  if children.isEmpty then
    none
  else
    some { group with children }

private def filterFinalData
    (state : TraverseState) (data : Informal.Graph.GraphData) :
    Informal.Graph.GraphData :=
  let nodes := data.nodes.filter (keepFinalNode state)
  let labels := labelSet nodes
  {
    data with
      nodes
      edges := data.edges.filter (keepEdge labels)
      groups := data.groups.filterMap (filterGroupChildren? labels)
  }

/--
Finalize graph data against a completed traversal state.

This is the single projection from semantic graph data to public graph data:
rendered page JSON and manifest/cache output both use it so href, title, and
group metadata stay consistent. The projection keeps nodes that are backed by
the current traversal, nodes with an explicit href/preview key, and unknown-ref
diagnostics; imported or code-only semantic nodes with no rendered occurrence in
the current site are omitted from the public graph.
-/
def finalData (state : TraverseState) (data : Informal.Graph.GraphData) :
    Informal.Graph.GraphData :=
  filterFinalData state {
    data with
      nodes := data.nodes.map (enrichNode state)
      groups := data.groups.map (enrichGroup state)
  }

/-- Finalize graph data and attach Lean-computed render variants. -/
def finalDataWithVariants
    (state : TraverseState)
    (data : Informal.Graph.GraphData)
    (options : Informal.Graph.GraphOptions) : Informal.Graph.GraphData :=
  let data := finalData state data
  { data with variants := data.renderVariants options }

/--
Finalize a graph block's semantic graph data for public page JSON.

Use this when rendering one graph block from its block payload and rendered
block id.
-/
def finalDataForBlock
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (data : Informal.Graph.GraphData) : Informal.Graph.GraphData :=
  finalData state (keyedData id data)

/--
Finalize a graph block's semantic graph data and attach render variants.

This is the render-ready form used by generated graph pages and manifest
clients that render graphs without scraping the graph page HTML.
-/
def finalDataForBlockWithOptions
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (data : Informal.Graph.GraphData)
    (options : Informal.Graph.GraphOptions) : Informal.Graph.GraphData :=
  finalDataWithVariants state (keyedData id data) options

/--
Store graph block data during traversal.

The cached payload deliberately remains semantic data plus the stable block key;
call `cachedData` after traversal finishes to read the public, finalized form.
-/
def saveData
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (data : Informal.Graph.GraphData)
    (options : Informal.Graph.GraphOptions) : TraverseState :=
  let key := cacheKey id
  let data := keyedData id data
  let cached : Informal.Graph.CachedGraphData := { data, options }
  state
    |> (fun state => Informal.TraversalIndex.Graphs.saveId state key id)
    |> (fun state => Informal.TraversalIndex.Graphs.saveData state key cached)

/--
Read every traversal-cached graph and finalize it for public manifest/API use.

Call this only with the completed traversal state for the document/site being
emitted.
-/
def cachedData (state : TraverseState) : Array Informal.Graph.GraphData :=
  Informal.TraversalIndex.Graphs.allData state |>.map fun cached =>
    finalDataWithVariants state cached.data cached.options

end Informal.GraphApi
