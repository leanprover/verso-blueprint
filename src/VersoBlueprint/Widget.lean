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

    function equalLspPosition(p1, p2) {
      return p1.line === p2.line && p1.character === p2.character
    }
    function equalLspRange(r1, r2) {
      return equalLspPosition(r1.start, r2.start) && equalLspPosition(r1.end, r2.end)
    }
    function equalLocs(l1, l2) {
      if ((!l1 || !l2) && l1 !== l2) return false
      return l1.length === l2.length && l1.every(([n1, [u1, r1]], i) => {
        const [n2, [u2, r2]] = l2[i]
        return n1 === n2 && u1 === u2 && equalLspRange(r1, r2)
      })
    }

    export default function({ locs, ...props }) {
      const ec = React.useContext(EditorContext)

      // Memoize locs modulo deep equality
      const locRef = React.useRef(locs)
      const locMapRef = React.useRef(new Map(locs))
      if (!equalLocs(locRef.current, locs)) {
        locRef.current = locs
        locMapRef.current = new Map(locs)
      }
      const locMap = locMapRef.current

      const attributer = React.useCallback(function(d) {
        if (d.tag !== 'g' || !d.attributes
          || !String(d.attributes.class ?? '').split(/\s+/).includes('node')
          || !('key' in d) || !locMap.has(d.key)) return
        d.attributes.cursor = 'pointer'
      }, [locMap])

      const onClickNode = React.useCallback((_ev, d) => {
        if (!d || !('key' in d) || !locMap.has(d.key)) return
        const [uri, range] = locMap.get(d.key)
        ec.revealLocation({ uri, range })
      }, [ec, locMap])

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

private def lspRangeContains (range : Lsp.Range) (pos : Lsp.Position) : Bool :=
  range.start ≤ pos && pos ≤ range.end

private def declarationRanges? (env : Lean.Environment) (decl : Name) : Option DeclarationRanges :=
  Lean.declRangeExt.find? (level := .exported) env decl <|>
    Lean.declRangeExt.find? (level := .server) env decl

private def moduleFromSourceLocation? (srcLoc : Informal.Data.SourceLocation) :
    IO (Option Name) := do
  let moduleName ← Lean.Server.moduleFromDocumentUri (System.Uri.pathToUri srcLoc.path)
  if (toString moduleName).startsWith "external:" then
    return none
  return some moduleName

private def manifestSourceLocation?
    (index : PreviewManifest.Index)
    (node : Informal.Graph.NodeData) : Option Informal.Data.SourceLocation := do
  let previewKey ← node.previewKey
  let entry ← index.findEntry? (toString previewKey)
  entry.sourceLocation.location

/-- Merge disk-based and environment-based Blueprint graph models.

The live model is preferred, except that a disk node from outside the current
module's import closure replaces its live unresolved forward reference. A
selected node's dependencies and parent move with the complete node record.
Edges, group children, and render variants are derived later from the merged
model. Live group metadata is preferred, while declared metadata still wins
over an undeclared fallback. -/
private def mergeGraphModel
    (disk : Informal.Graph.GraphData)
    (live : Informal.Graph.GraphModel)
    (importedMods : NameSet)
    (index : PreviewManifest.Index) : IO Informal.Graph.GraphModel := do
  let modOfVertex? (node : Informal.Graph.NodeData) : IO (Option Name) := do
    let some srcLoc := manifestSourceLocation? index node | return none
    moduleFromSourceLocation? srcLoc

  let disk := disk.toModel
  let mut preferredNodes := #[]
  for node in disk.nodes do
    let some moduleName ← modOfVertex? node | continue
    if !(importedMods.contains moduleName) then
      -- This may overwrite a live node - that is fine:
      -- since this node is not in any imported module,
      -- its description in `live` must be an unresolved forward reference
      -- thus containing less data than the on-disk copy.
      preferredNodes := preferredNodes.push node

  let preferred : Informal.Graph.GraphModel := {
    nodes := preferredNodes
    groupMetadata := live.groupMetadata
  }
  let fallback : Informal.Graph.GraphModel := {
    nodes := live.nodes
    groupMetadata := disk.groupMetadata
  }
  return preferred.mergePreferLeft fallback

open Server in
@[server_rpc_method]
def BlueprintGraph.mk (props : Props) : RequestM (RequestTask Html) := do
    -- FIXME: cache this rather than reading on every render.
    let manifestTask ← ServerTask.IO.asTask do
      let dataDir : System.FilePath := "_out" / "site" / "html-multi" / "-verso-data"
      PreviewManifest.readFile (dataDir / PreviewManifest.manifestFilename)

    let doc ← RequestM.readDoc
    let pos := doc.meta.text.lspPosToUtf8Pos props.pos
    -- Find snapshot at current cursor position to inspect the infotree there.
    RequestM.bindWaitFindSnap doc (·.endPos ≥ pos)
        (notFoundX := throw ⟨.invalidParams, s!"no snapshot found at {props.pos}"⟩) fun snapHere => do
      -- Look for a blueprint node at current position.
      let nodeInfos : List (Syntax × Data.NodeInfo) :=
          snapHere.infoTree.deepestNodes fun _ctxt info _arr =>
        match info with
        | .ofCustomInfo ⟨stx, data⟩ =>
          (data.get? Data.NodeInfo).map (stx, ·)
        | _ => none
      let nodeAtSyntax? := nodeInfos.find? fun (stx, _) =>
        stx.getRange?.map (·.contains pos) |>.getD false
      /- Info nodes for a `@[blueprint]` attribute are placed on the attribute's syntax only,
      so are not found by position-based lookup in `nodeAtSyntax?`
      when the cursor is within a `@[blueprint]`-marked declaration.
      Look for such a declaration explicitly. -/
      let nodeAtDeclaration? := nodeInfos.find? fun (_, info) =>
        match info.decl? with
        | none => false
        | some decl =>
          match declarationRanges? snapHere.env decl with
          | none => false
          | some ranges => lspRangeContains ranges.range.toLspRange props.pos
      let currLabel :=
        (nodeAtSyntax? <|> nodeAtDeclaration?).map (·.2.label.toString) |>.getD ""
      let importedMods := currentAndImportedModules snapHere.env

      -- Find snapshot at end of file to retrieve the blueprint graph there,
      -- including all nodes in the current file.
      RequestM.bindWaitFindSnap doc
          (fun s => s.endPos == doc.meta.text.positions[doc.meta.text.positions.size - 1]?.getD 0)
          (notFoundX := throw ⟨.invalidParams, s!"no snapshot found at EOF"⟩) fun snapEnd => do
        -- Extract blueprint graph from the last snapshot.
        let state := informalExt.getState snapEnd.env
        let liveRoots := state.data.toArray.map fun (label, _) => label
        let liveGraphModel :=
          Informal.Graph.buildModel state liveRoots (groupTitles := state.groups.toArray)

        -- Map as 'cheap' since `bindWaitFindSnap` already spawns a dedicated thread.
        RequestM.mapTaskCheap manifestTask fun manifest? => do
          let mut graphModel := liveGraphModel
          let mut manifestWarning? : Option Html := none
          let mut locs := #[]

          match manifest? with
          | .ok manifest =>
            let manifestIndex := manifest.index

            -- If on-disk graph is present, merge nodes in non-imported modules from there.
            if let some diskGraphData := manifest.graphs[0]? then
              graphModel ← mergeGraphModel diskGraphData liveGraphModel importedMods manifestIndex

            for node in graphModel.nodes do
              -- FIXME: Find srcLoc for imported entries via env instead of via manifest, for freshness?
              -- Might need ilean-like data.
              let some srcLoc := manifestSourceLocation? manifestIndex node | continue
              locs := locs.push (node.label, (System.Uri.pathToUri srcLoc.path, srcLoc.range))
          | .error e =>
            manifestWarning? :=
              some <p className="warning">
                Could not load blueprint - please rebuild it to see the whole graph.<br />
                {.text e.toString}
              </p>

          let dot := graphModel.toDotWith { direction := .TB }
          return <Maximizable>
              <ClickableGraphviz locs={locs} dot={dot} centerOnVertex?={currLabel} />
              {match manifestWarning? with
                | some w => w
                | none => <span />}
            </Maximizable>

@[widget_module]
def BlueprintGraph : Component BlueprintGraph.Props :=
  mk_rpc_widget% BlueprintGraph.mk

end BlueprintWidget

show_panel_widgets [BlueprintGraph]
