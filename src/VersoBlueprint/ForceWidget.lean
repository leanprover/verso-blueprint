/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Wojciech Nawrocki
-/

import Lean
import ProofWidgets.Component.Panel.Basic
import ProofWidgets.Component.OfRpcMethod
import ProofWidgets.Component.ForceGraphDisplay
import ProofWidgets.Component.Maximizable
import ProofWidgets.Component.HtmlDisplay
import VersoBlueprint.Graph
import VersoBlueprint.PreviewManifest
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.Lib.PreviewSource

open Lean Elab Command
open ProofWidgets Jsx

section BlueprintWidget

open Informal Environment

structure RevealLocationLink.Props where
  uri : Lsp.DocumentUri
  range : Lsp.Range
  className? : Option String := none
  deriving FromJson, ToJson

open ProofWidgets in
@[widget_module]
def RevealLocationLink : Component RevealLocationLink.Props where
  javascript := "
    import * as React from 'react'
    import { EditorContext } from '@leanprover/infoview'

    export default function(props0) {
      const { children, uri, range, ...props } = props0
      const ec = React.useContext(EditorContext)
      return React.createElement('a', {
        ...props,
        onClick: () => {
          ec.revealLocation({ uri, range })
        },
      },
      children)
    }
  "

structure BlueprintGraph.Props extends PanelWidgetProps where
  deriving Server.RpcEncodable

open ProofWidgets Jsx in
def mkLabel (label : String) (srcLoc? : Option Informal.Data.SourceLocation)
    (stroke := "var(--vscode-editor-foreground)")
    (fill := "var(--vscode-editor-background)") :
    Nat × Nat × Html :=
  let len := label.length + 3
  let w := min (15 + (len.toFloat * 6).toUSize.toNat) 200
  let h := max 20 (20 * (1 + len / 15))
  let x : Int := -w/2
  let y : Int := -h/2
  (w, h, <g>
      <rect
        fill={fill}
        stroke={stroke}
        strokeWidth={.num 1.5}
        width={w} height={h} x={x} y={y}
        rx={5}
      />
      <foreignObject width={w} height={h} x={.num (x + 5 : Int)} y={y}>
        <span className="font-code">{.text label}</span>
        {match srcLoc? with
          | some l => <RevealLocationLink uri={s!"file://{l.path}"} range={l.range} className?="link pointer dim codicon codicon-go-to-file" />
          | none => <span/>}
      </foreignObject>
    </g>
  )

private def graphLabels (data : Informal.Graph.GraphData) : NameSet :=
  data.nodes.foldl (init := ({} : NameSet)) fun labels node =>
    labels.insert node.label

private def graphNodeMap (nodes : Array Informal.Graph.NodeData) :
    NameMap Informal.Graph.NodeData :=
  nodes.foldl (init := ({} : NameMap Informal.Graph.NodeData)) fun nodeMap node =>
    nodeMap.insert node.label node

private def graphCommonLabels
    (disk live : Informal.Graph.GraphData) : NameSet :=
  let liveLabels := graphLabels live
  disk.nodes.foldl (init := ({} : NameSet)) fun labels node =>
    if liveLabels.contains node.label then labels.insert node.label else labels

private def edgeSeenContains
    (seen : NameMap NameSet) (edge : Informal.Graph.EdgeData) : Bool :=
  (seen.getD edge.source ({} : NameSet)).contains edge.target

private def edgeSeenInsert
    (seen : NameMap NameSet) (edge : Informal.Graph.EdgeData) : NameMap NameSet :=
  let targets := seen.getD edge.source ({} : NameSet)
  seen.insert edge.source (targets.insert edge.target)

private def pushUniqueEdge
    (state : Array Informal.Graph.EdgeData × NameMap NameSet)
    (edge : Informal.Graph.EdgeData) :
    Array Informal.Graph.EdgeData × NameMap NameSet :=
  let (edges, seen) := state
  if edgeSeenContains seen edge then
    state
  else
    (edges.push edge, edgeSeenInsert seen edge)

private def mergeGraphData
    (disk live : Informal.Graph.GraphData) : Informal.Graph.GraphData :=
  let diskLabels := graphLabels disk
  let liveByLabel := graphNodeMap live.nodes
  let nodes :=
    disk.nodes.foldl (init := #[]) fun nodes node =>
      nodes.push ((liveByLabel.get? node.label).getD node)
  let nodes :=
    live.nodes.foldl (init := nodes) fun nodes node =>
      if diskLabels.contains node.label then nodes else nodes.push node
  let commonLabels := graphCommonLabels disk live
  let diskEdges := disk.edges.filter fun edge =>
    !commonLabels.contains edge.target
  let (edges, _) :=
    (live.edges ++ diskEdges).foldl
      (init := ((#[] : Array Informal.Graph.EdgeData), ({} : NameMap NameSet)))
      pushUniqueEdge
  {
    disk with
      nodes
      edges
      groups := live.groups ++ disk.groups
  }

open Server in
@[server_rpc_method]
def BlueprintGraph.mk (props : Props) : RequestM (RequestTask Html) := do
    let dataDir : System.FilePath := "_out" / "html-multi" / "-verso-data"
    let manifestPath := dataDir / PreviewManifest.manifestFilename
    let manifest? := (← EIO.toBaseIO <| PreviewManifest.readFile manifestPath).toOption
    let diskGraph? := manifest?.bind fun manifest => manifest.graphs[0]?
    let manifestIndex? := manifest?.map fun manifest => manifest.index

    let htmlCachePath := dataDir / PreviewManifest.htmlCacheFilename
    let htmlCacheIndex? := (← EIO.toBaseIO <| PreviewManifest.HtmlCache.readFile htmlCachePath).toOption

    RequestM.withWaitFindSnapAtPos props.pos fun snap => do
      let state := informalExt.getState snap.env
      let liveRoots := state.data.toArray.map fun (label, _) => label
      let liveGraphData :=
        Informal.Graph.buildData state liveRoots (groupTitles := state.groups.toArray)
      let graphData? :=
        match diskGraph? with
        | some diskGraph => some (mergeGraphData diskGraph liveGraphData)
        | none =>
          if liveGraphData.nodes.isEmpty then none else some liveGraphData
      let some graphData := graphData?
        | return <b>No blueprint graph is present. Please add at least one node and build the blueprint.</b>
      let diskGraphWarning? :=
        match diskGraph? with
        | some _ => none
        | none => some "Blueprint hasn't been built - please build it to see the whole graph."

      let pos := (← RequestM.readDoc).meta.text.lspPosToUtf8Pos props.pos
      let nodeInfos : List Environment.NodeInfo := snap.infoTree.deepestNodes fun _ctxt info _arr =>
        match info with
        | .ofCustomInfo ⟨stx, data⟩ =>
          if stx.getRange?.map (·.contains pos) |>.getD false then
            data.get? Environment.NodeInfo
          else
            none
        | _ => none
      let currLabel := nodeInfos.head?.map (·.label.toString) |>.getD ""

      -- Build GraphDisplay props
      let mut verts : Array ForceGraphDisplay.Vertex := #[]
      let mut maxLabelRadius := 0.0
      for node in graphData.nodes do
        let nodeId := node.label.toString
        let previewHtml? := htmlCacheIndex?.bind fun htmlCacheIndex =>
          htmlCacheIndex.findHtml? node.previewKey
        let srcLoc? := manifestIndex?.bind fun manifestIndex =>
          (manifestIndex.findEntry? node.previewKey).bind (·.sourceLocation.location)
        let (w, h, label) := mkLabel nodeId srcLoc?
          (stroke :=
            if nodeId == currLabel then "var(--vscode-lean4-infoView\\.turnstile)"
            else "var(--vscode-editor-foreground)")
        maxLabelRadius := max maxLabelRadius (Float.sqrt <| (w.toFloat/2)^2 + (h.toFloat/2)^2)
        verts := verts.push {
            id := nodeId
            label
            boundingShape := .rect w.toFloat h.toFloat
            details? := <div dangerouslySetInnerHTML={json%{ __html: $(previewHtml?.getD "") }} />
          }

      -- Return GraphDisplay
      let edges := graphData.edges.map fun edge => {
        source := edge.source.toString
        target := edge.target.toString
      }

      return <Maximizable>
        <div>
          <ForceGraphDisplay
            vertices={verts}
            edges={edges}
            forces={#[
              .link { distance? := some (maxLabelRadius * 2) },
              .manyBody { strength? := some (-150) },
              .x { strength? := some 0.01 },
              .y { strength? := some 0.01 }
            ]}
            showDetails={true}
            centerOnVertex?={currLabel}
          />
          {match diskGraphWarning? with
            | some warning => <p className="warning">{.text warning}</p>
            | none => <span/>}
        </div>
      </Maximizable>

@[widget_module]
def BlueprintGraph : Component BlueprintGraph.Props :=
  mk_rpc_widget% BlueprintGraph.mk

end BlueprintWidget

show_panel_widgets [BlueprintGraph]
