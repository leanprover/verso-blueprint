/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary
import VersoBlueprint.Informal.Uses

open Lean Verso Doc
open Verso.Genre (Manual)

namespace Informal

/--
Final semantic data captured in the generator's Lean environment. Document
occurrences keep their own bodies, source locations, folding, and numbering.
-/
structure DocumentSnapshot where
  nodes : Lean.NameMap BlockData := {}
  graph : Graph.GraphModel := {}
  summary : Json := .null
deriving Inhabited

/-- Reconstruct a captured snapshot once, keeping node lookup logarithmic. -/
def DocumentSnapshot.fromJsonString! (serialized : String) : DocumentSnapshot := Id.run do
  let .ok json := Json.parse serialized | panic! "invalid Blueprint document snapshot JSON"
  let .ok (nodes, graph, summary) :=
      fromJson? (α := Array BlockData × Graph.GraphModel × Json) json
    | panic! "invalid Blueprint document snapshot data"
  return { nodes := nodes.foldl (fun acc node => acc.insert node.label node) {}, graph, summary }

/-- Capture after all source and attachment imports, without exporting Lean environments at runtime. -/
elab "blueprint_snapshot%" : term => do
  Environment.reportImportedConflicts
  let state := Environment.informalExt.getState (← getEnv)
  let nodes := state.data.toArray.map fun (label, node) =>
    BlockData.ofNode label node (node.owner.bind state.authors.get?)
  let graph := Graph.buildModel state (state.data.toArray.map (·.1)) (groupTitles := state.groups.toArray)
  let summary ← Commands.buildSummary
  let serialized := (toJson (nodes, graph, toJson summary)).compress
  Lean.Elab.Term.elabTerm (← `(DocumentSnapshot.fromJsonString! $(quote serialized))) none

private def DocumentSnapshot.blockData (snapshot : DocumentSnapshot) (data : BlockData) : BlockData :=
  match snapshot.nodes.get? data.label with
  | some semantic => data.withSemanticData semantic
  | none => data

private def DocumentSnapshot.inline (snapshot : DocumentSnapshot)
    (recur : Doc.Inline Manual → Doc.Inline Manual)
    (container : Manual.Inline) (content : Array (Doc.Inline Manual)) : Doc.Inline Manual := Id.run do
  let mut container := container
  if container.name == ``Inline.informal then
    if let .ok (data : InlineData) := fromJson? container.data then
      let block := data.block.map (snapshot.blockData ·) <|> snapshot.nodes.get? data.label
      container := { container with data := toJson { data with block } }
  return .other container (content.map recur)

private def DocumentSnapshot.otherBlock (snapshot : DocumentSnapshot)
    (_recurInline : Doc.Inline Manual → Doc.Inline Manual)
    (recur : Doc.Block Manual → Doc.Block Manual)
    (container : Manual.Block) (content : Array (Doc.Block Manual)) : Doc.Block Manual := Id.run do
  let mut container := container
  if container.name == ``Block.informal then
    if let .ok (data : BlockData) := fromJson? container.data then
      container := { container with data := toJson (snapshot.blockData data) }
  else if container.name == `Informal.Block.informalCode then
    if let .ok (data : InlineCodeData) := fromJson? container.data then
      if let some semantic := snapshot.nodes.get? data.label then
        container := { container with data := toJson { data with
          statementUses := semantic.statementUses
          proofUses := semantic.proofUses } }
  else if container.properties.contains `Informal.documentSnapshot then
    if container.name == ``Commands.Block.graph then
      if let .ok (data : Commands.GraphBlockData) := fromJson? container.data then
        container := { container with data := toJson { data with graphModel := snapshot.graph } }
    else if container.name == ``Commands.Block.summary then
      -- Diagnostic visibility belongs to this summary occurrence, not to the generator.
      let summary := match container.data.getObjVal? "showDebugDiagnostics" with
        | .ok flag => snapshot.summary.setObjVal! "showDebugDiagnostics" flag
        | .error _ => snapshot.summary
      container := { container with data := summary }
  return .other container (content.map recur)

/-- Refresh a block tree before traversal, including blocks nested in lists and quotations. -/
def DocumentSnapshot.block (snapshot : DocumentSnapshot) : Doc.Block Manual → Doc.Block Manual :=
  Doc.Block.rewriteOther snapshot.inline snapshot.otherBlock

/-- Apply one final semantic snapshot to every occurrence in a document before traversal. -/
partial def DocumentSnapshot.apply (snapshot : DocumentSnapshot) (part : Part Manual) : Part Manual :=
  if snapshot.nodes.isEmpty then part else
  { part with
    title := part.title.map (Doc.Inline.rewriteOther snapshot.inline)
    content := part.content.map snapshot.block
    subParts := part.subParts.map snapshot.apply }

end Informal
