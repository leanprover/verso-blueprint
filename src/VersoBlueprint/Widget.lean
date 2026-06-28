/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias, Wojciech Nawrocki
-/

import Lean
import Lean.Server.Utils
import ProofWidgets.Component.Panel.Basic
import ProofWidgets.Component.OfRpcMethod
import ProofWidgets.Component.GraphvizDisplay
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

private structure ClickableGraphviz.Props extends GraphvizDisplay.Props where
  /-- Each entry is a graph label paired with the URI and range to jump to on click. -/
  locs : Array (Name × (Lsp.DocumentUri × Lsp.Range))
  deriving FromJson, ToJson

@[widget_module]
private def ClickableGraphviz : Component ClickableGraphviz.Props where
  javascript := r#"
    import * as React from 'react'
    import { EditorContext } from '@leanprover/infoview'
    import GraphvizDisplay from 'widget_module:hash,GRAPHVIZ_DISPLAY_HASH'

    export default function({ locs, ...props }) {
      const ec = React.useContext(EditorContext)
      const locMap = new Map(locs)

      const attributer = React.useCallback(function(d) {
        if (d.tag !== 'g' || d.attributes.class !== 'node') return
        d.attributes.cursor = 'pointer'
      }, [])

      const onClickNode = React.useCallback((_ev, d) => {
        if (!('key' in d) || !locMap.has(d.key)) return
        const [uri, range] = locMap.get(d.key)
        ec.revealLocation({ uri, range })
      }, [])

      return React.createElement(GraphvizDisplay, {
        ...props,
        attributer,
        onClickNode,
      })
    }
  "#.replace "GRAPHVIZ_DISPLAY_HASH" (toString GraphvizDisplay.javascriptHash)

open Informal Environment

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
      let currLabel := nodeInfos.head?.map (·.label.toString) |>.getD ""
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
          let mut locs := #[]

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
              locs := locs.push (node.label, (s!"file://{srcLoc.path}", srcLoc.range))
          else
            manifestWarning := some "Blueprint hasn't been built - please build it to see the whole graph."

          let dot := Informal.Graph.graphToDot graphData.toGraph { direction := .TB }
            graphData.groupTitleMap.get?
          return <Maximizable>
              <ClickableGraphviz locs={locs} dot={dot} centerOnVertex?={currLabel} />
              {match manifestWarning with
                | some warning => <p className="warning">{.text warning}</p>
                | none => <span />}
            </Maximizable>

@[widget_module]
def BlueprintGraph : Component BlueprintGraph.Props :=
  mk_rpc_widget% BlueprintGraph.mk

end BlueprintWidget

show_panel_widgets [BlueprintGraph]
