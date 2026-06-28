/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias, Wojciech Nawrocki
-/

import Lean
import Lean.Server.Utils
import ProofWidgets.Component.Panel.Basic
import ProofWidgets.Component.OfRpcMethod
import ProofWidgets.Component.GraphDisplay
import VersoBlueprint.Graph
import VersoBlueprint.PreviewManifest
import VersoBlueprint.Data
import VersoBlueprint.Environment

open Lean Elab Command
open ProofWidgets Jsx

section BlueprintWidget

private structure GraphNodeLabel.Props where
  label : String
  width : Nat
  height : Nat
  shape : String
  fillColor : String
  borderColor : String
  borderWidth : String
  textColor : String
  selected : Bool
  dashArray? : Option String := none
  tooltip? : Option String := none
  location? : Option (String × Lsp.Range) := none
  deriving FromJson, ToJson

@[widget_module]
private def GraphNodeLabel : Component GraphNodeLabel.Props where
  javascript := r#"
    import * as React from 'react'
    import { EditorContext } from '@leanprover/infoview'

    export default function({
      label,
      width,
      height,
      shape,
      fillColor,
      borderColor,
      borderWidth,
      textColor,
      selected,
      dashArray,
      tooltip,
      location,
    }) {
      const ec = React.useContext(EditorContext)
      const clickable = !!location
      const w = Number(width) || 80
      const h = Number(height) || 28
      const strokeWidth = Number(borderWidth) || 2
      const maxChars = Math.max(1, Math.floor((w - 16) / 7))
      const text = label.length > maxChars ? `${label.slice(0, Math.max(1, maxChars - 3))}...` : label

      const revealLocation = React.useCallback((event) => {
        if (!location) return
        event.preventDefault()
        event.stopPropagation()
        const [uri, range] = location
        ec.revealLocation({ uri, range })
      }, [ec, location])

      const onKeyDown = React.useCallback((event) => {
        if (event.key === 'Enter' || event.key === ' ') revealLocation(event)
      }, [revealLocation])

      const shapeProps = {
        fill: fillColor,
        stroke: selected ? '#2563eb' : borderColor,
        strokeWidth: selected ? Math.max(strokeWidth, 3) : strokeWidth,
        strokeDasharray: dashArray || undefined,
      }
      const shapeElement = shape === 'ellipse'
        ? React.createElement('ellipse', { cx: 0, cy: 0, rx: w / 2, ry: h / 2, ...shapeProps })
        : React.createElement('rect', { x: -w / 2, y: -h / 2, width: w, height: h, rx: 6, ry: 6, ...shapeProps })

      return React.createElement('g', {
        onClick: revealLocation,
        onKeyDown,
        role: clickable ? 'button' : undefined,
        tabIndex: clickable ? 0 : undefined,
        'aria-label': clickable ? `Jump to ${label}` : label,
        style: { cursor: clickable ? 'pointer' : 'default' },
      }, [
        tooltip ? React.createElement('title', { key: 'title' }, tooltip) : null,
        React.cloneElement(shapeElement, { key: 'shape' }),
        React.createElement('text', {
          key: 'text',
          textAnchor: 'middle',
          dominantBaseline: 'central',
          fill: textColor,
          style: {
            fontFamily: 'var(--vscode-editor-font-family, sans-serif)',
            fontSize: '12px',
            fontWeight: selected ? 600 : 400,
            pointerEvents: 'none',
            userSelect: 'none',
          },
        }, text),
      ])
    }
  "#

open Informal Environment

private def graphLabelWidth (label : String) : Nat :=
  Nat.min 220 (Nat.max 72 (label.length * 7 + 24))

private def graphLabelHeight : Nat := 28

private def styleHasToken (style token : String) : Bool :=
  (style.splitOn ",").any fun part => part.trimAscii.toString == token

private def strokeDashArray? (style : String) : Option String :=
  if styleHasToken style "dotted" then
    some "2 4"
  else if styleHasToken style "dashed" then
    some "6 4"
  else
    none

private def graphDisplayVertex (node : Informal.Graph.NodeData)
    (location? : Option (String × Lsp.Range)) (selected : Bool) : GraphDisplay.Vertex :=
  let width := graphLabelWidth node.displayLabel
  let height := graphLabelHeight
  {
    id := node.label.toString
    label := Html.ofComponent GraphNodeLabel {
      label := node.displayLabel
      width
      height
      shape := node.visual.shape
      fillColor := node.visual.fillcolor
      borderColor := node.visual.color
      borderWidth := node.visual.penwidth
      textColor := node.visual.fontcolor
      selected
      dashArray? := strokeDashArray? node.visual.style
      tooltip? := node.visual.tooltip?
      location?
    } #[]
    boundingShape := .rect width.toFloat height.toFloat
    details? := node.visual.tooltip?.map Html.text
  }

private def edgeHasAxis (edge : Informal.Graph.EdgeData) (axis : Informal.Graph.EdgeAxis) : Bool :=
  edge.axes.any (· == axis)

private def graphDisplayEdgeAttrs (edge : Informal.Graph.EdgeData) : Array (String × Json) :=
  let isStatement := edgeHasAxis edge .statement
  let isProof := edgeHasAxis edge .proof
  if isStatement && isProof then
    #[("strokeWidth", 3)]
  else if isProof then
    #[("strokeDasharray", "2 4"), ("strokeWidth", 2)]
  else
    #[]

private def graphDisplayEdge (edge : Informal.Graph.EdgeData) : GraphDisplay.Edge := {
  source := edge.source.toString
  target := edge.target.toString
  attrs := graphDisplayEdgeAttrs edge
}

private def graphDisplayForces : Array GraphDisplay.ForceParams := #[
  .link { distance? := some 120.0, strength? := some 0.7 },
  .collide { radius? := some 56.0 },
  .manyBody { strength? := some (-220.0) },
  .x { strength? := some 0.05 },
  .y { strength? := some 0.05 }
]

/-- All imported modules plus the current module. -/
private def currentAndImportedModules (env : Lean.Environment) : NameSet :=
  let modules := env.header.moduleNames.foldl (init := ({} : NameSet)) fun modules moduleName =>
    modules.insert moduleName
  if env.mainModule.isAnonymous then modules else modules.insert env.mainModule

structure BlueprintGraph.Props extends PanelWidgetProps where
  deriving Server.RpcEncodable

private def moduleFromSourceLocation? (srcLoc : Informal.Data.SourceLocation) :
    IO (Option Name) := do
  let moduleName ← Lean.Server.moduleFromDocumentUri (System.Uri.pathToUri srcLoc.path)
  if (toString moduleName).startsWith "external:" then
    return none
  return some moduleName

/-- Merge disk-based and environment-based blueprint graphs.
The latter is assumed more up-to-date.
- Nodes in `live` are always included in the output.
- Nodes in `disk` are included if they have a source location,
  allowing the source module to be determined,
  and the source module is not one of the imported ones.
- Edges in `live` are included as long as both endpoints are included.
- Edges in `disk` are included when at least one of src/tgt is in a non-imported module
  (determined via source location like above).
- Groups in `live` are always included,
  but have their members filtered to only contain included nodes.
- Groups in `disk` are always included.
  When the same group exists in `live`,
  the union of members is computed
  whereas other group data is taken from `live`.
  Members are similarly filtered to contain only included nodes. -/
private def mergeGraphData (disk live : Informal.Graph.GraphData) (importedMods : NameSet) (index : PreviewManifest.Index)
    : IO Informal.Graph.GraphData := do
  let modOfVertex? (node : Informal.Graph.NodeData) : IO (Option Name) := do
    let some srcLoc := (index.findEntry? node.previewKey).bind (·.sourceLocation.location)
      | return none
    moduleFromSourceLocation? srcLoc

  let mut nodes : NameMap Informal.Graph.NodeData :=
    live.nodes.foldl (init := {}) (fun m n => m.insert n.label n)
  let mut diskNodeLabels : NameSet := {}
  for node in disk.nodes do
    let some moduleName ← modOfVertex? node | continue
    if !(importedMods.contains moduleName) then
      diskNodeLabels := diskNodeLabels.insert node.label
      -- This may overwrite a live node - that is fine:
      -- since this node is not in any imported module,
      -- its description in `live` must be an unresolved forward reference
      -- thus containing less data than the on-disk copy.
      nodes := nodes.insert node.label node

  let mut edges : Array Informal.Graph.EdgeData := #[]
  for edge in live.edges do
    if nodes.contains edge.source && nodes.contains edge.target then
      edges := edges.push edge
  for edge in disk.edges do
    if (diskNodeLabels.contains edge.source || diskNodeLabels.contains edge.target) then
      edges := edges.push edge

  let mut groups : NameMap Informal.Graph.GroupData := {}
  for group in live.groups do
    let children := group.children.filter nodes.contains
    groups := groups.insert group.label { group with children }

  for group in disk.groups do
    if !groups.contains group.label then
      let children := group.children.filter nodes.contains
      groups := groups.insert group.label { group with children }
    else
      let group0 := groups.get! group.label
      let mut children : NameSet := group0.children.foldl (init := ∅) NameSet.insert
      for c in group.children do
        if nodes.contains c then
          children := children.insert c
      groups := groups.insert group.label { group0 with children := children.toArray }

  return { live with nodes := nodes.valuesArray, edges, groups := groups.valuesArray }

open Server in
@[server_rpc_method]
def BlueprintGraph.mk (props : Props) : RequestM (RequestTask Html) := do
    let manifestTask ← ServerTask.IO.asTask do
      let dataDir : System.FilePath := "_out" / "html-multi" / "-verso-data"
      PreviewManifest.readFile (dataDir / PreviewManifest.manifestFilename)

    let doc ← RequestM.readDoc
    let pos := doc.meta.text.lspPosToUtf8Pos props.pos
    -- Find snapshot at current cursor position to inspect the infotree there.
    RequestM.bindWaitFindSnap doc (·.endPos ≥ pos)
        (notFoundX := throw ⟨.invalidParams, s!"no snapshot found at {props.pos}"⟩) fun snapHere => do
      -- Look for a blueprint node at current position.
      let nodeInfos : List Data.NodeInfo := snapHere.infoTree.deepestNodes fun _ctxt info _arr =>
        match info with
        | .ofCustomInfo ⟨stx, data⟩ =>
          if stx.getRange?.map (·.contains pos) |>.getD false then
            data.get? Data.NodeInfo
          else
            none
        | _ => none
      let currLabel? := nodeInfos.head?.map (·.label)
      let importedMods := currentAndImportedModules snapHere.env

      -- Find snapshot at end of file to retrieve the blueprint graph there,
      -- including all nodes in the current file.
      RequestM.bindWaitFindSnap doc
          (fun s => s.endPos == doc.meta.text.positions[doc.meta.text.positions.size - 1]?.getD 0)
          (notFoundX := throw ⟨.invalidParams, s!"no snapshot found at EOF"⟩) fun snapEnd => do
        -- Extract blueprint graph from the last snapshot.
        let state := informalExt.getState snapEnd.env
        let liveRoots := state.data.toArray.map fun (label, _) => label
        let liveGraphData := Informal.Graph.buildData state liveRoots (groupTitles := state.groups.toArray)

        RequestM.mapTaskCheap manifestTask fun manifest? => do
          let mut graphData := liveGraphData
          let mut manifestWarning : Option String := none
          let mut locations : NameMap (String × Lsp.Range) := {}

          if let .ok manifest := manifest? then
            let manifestIndex := manifest.index

            -- If on-disk graph is present, merge nodes in non-imported modules from there.
            if let some diskGraphData := manifest.graphs[0]? then
              graphData ← mergeGraphData diskGraphData liveGraphData importedMods manifestIndex

            for node in graphData.nodes do
              -- FIXME: Find srcLoc for imported entries via env instead of via manifest?
              -- Might need ilean-like data.
              let some srcLoc := (manifestIndex.findEntry? node.previewKey).bind (·.sourceLocation.location)
                | continue
              locations := locations.insert node.label (s!"file://{srcLoc.path}", srcLoc.range)
          else
            manifestWarning := some "Blueprint hasn't been built - please build it to see the whole graph."

          let vertices := graphData.nodes.map fun node =>
            graphDisplayVertex node (locations.get? node.label) (currLabel? == some node.label)
          let edges := graphData.edges.map graphDisplayEdge
          let graphHtml : Html :=
            if vertices.isEmpty then
              <p>No Blueprint graph nodes found.</p>
            else
              <GraphDisplay vertices={vertices} edges={edges} forces={graphDisplayForces} />
          return <div>
              {graphHtml}
              {match manifestWarning with
                | some warning => <p className="warning">{.text warning}</p>
                | none => <span />}
            </div>

@[widget_module]
def BlueprintGraph : Component BlueprintGraph.Props :=
  mk_rpc_widget% BlueprintGraph.mk

end BlueprintWidget

show_panel_widgets [BlueprintGraph]
