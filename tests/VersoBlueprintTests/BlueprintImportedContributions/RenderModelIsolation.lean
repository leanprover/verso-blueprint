/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.Blueprint.Support

open Lean Verso Informal
open Verso.Genre
open Verso.VersoBlueprintTests.Blueprint.Support

#docs (Manual) isolatedDocument "Isolated project" :=
:::::::
:::theorem "isolated_theorem"
A theorem belonging to this document.
:::
{blueprint_summary}
:::::::

def isolatedBlueprint : BlueprintDocument := .capture isolatedDocument.toPart

-- A registry or wrapper may import other projects after this document was captured.
@[blueprint "unrelated_theorem"] theorem unrelatedTheorem : True := trivial

#eval show IO Unit from do
  let current : RenderModel := blueprint_render_model%
  unless isolatedBlueprint.model.summary.totalEntries == 1 && current.summary.totalEntries == 2 do
    throw <| IO.userError "A captured project followed the caller's unrelated environment"
  let html ← renderManualDocHtmlString extension_impls% isolatedDocument
    (model := isolatedBlueprint.model)
  unless !hasSubstr html "unrelatedTheorem" do
    throw <| IO.userError "An isolated summary acquired an unrelated declaration"

  let state := current.install (Verso.Genre.Manual.TraverseState.initialize {})
  let request : Commands.SummaryBlockData := { showDebugDiagnostics := true }
  let .ok data := request.resolve state
    | throw <| IO.userError "Missing project summary"
  unless data.showDebugDiagnostics && data.totalEntries == 2 do
    throw <| IO.userError "Shared summary resolution lost occurrence-specific diagnostic visibility"
  let custom : Commands.SummaryBlockData := { summary := some { totalEntries := 17 } }
  unless (custom.resolve state).toOption.any (·.totalEntries == 17) do
    throw <| IO.userError "The project summary replaced an explicitly supplied summary"

  let errors ← IO.mkRef (#[] : Array String)
  let missing : BlockOccurrence := { label := `unregistered, count := 1 }
  let _ ← Informal.traverseManualBlocks
    #[.other (Block.informal missing) #[]]
    (current.withExtensions extension_impls%) (fun message => errors.modify (·.push message))
  unless (← errors.get).any (·.contains "Unknown Blueprint label") do
    throw <| IO.userError "Traversal silently accepted a reference outside its rendering context"

-- Explicit models can be built outside elaboration and still acquire traversal anchors.
#eval show IO Unit from do
  let node := RenderNode.ofBlockData {
    label := `synthetic
    kind := .theorem
    count := 1
    tags := #["synthetic"]
  }
  let model : RenderModel := { nodes := #[node] }
  let (blocks, state) ← Informal.traverseManualBlocks
    #[.other (Block.informal node.toBlockData.toOccurrence) #[.para #[.text "Synthetic theorem"]]]
    (model.withExtensions extension_impls%)
  unless (TraversalIndex.Nodes.href? state node.label).isSome &&
      (TraversalIndex.Nodes.renderedData? state node.label).any (·.globalCount.isSome) do
    throw <| IO.userError "An explicitly supplied occurrence prevented anchor and numbering allocation"
  let html ← Informal.renderManualBlocksHtmlWithState blocks extension_impls% state
  unless hasSubstr html.asString "Synthetic theorem" && hasSubstr html.asString "synthetic" do
    throw <| IO.userError "A synthetic rendering model lost its body or metadata"

-- Captured nodes without a rendered target do not acquire graph membership or numbering.
#eval show IO Unit from do
  let model : RenderModel := blueprint_render_model%
  let initialized := model.install (Verso.Genre.Manual.TraverseState.initialize {})
  unless (GraphApi.finishData initialized "before-traversal" model.graph {}).nodes.isEmpty do
    throw <| IO.userError "Captured nodes counted as rendered graph nodes"
  let (blocks, _) ← traverseManualDocBlocksAndState extension_impls% isolatedDocument
  let graph : Doc.Block Manual := .other (Commands.Block.graph {}) #[]
  let (_, state) ← traverseManualBlocks (blocks ++ #[graph, graph]) (model.withExtensions extension_impls%)
  let cached := TraversalIndex.Graphs.entries state
  unless cached.size == 2 && cached.all (fun entry => entry.toOption.any (·.data.model.isNone)) do
    throw <| IO.userError "Project graph occurrences copied the captured topology"
  for result in GraphApi.cachedEntries state do
    let .ok entry := result | throw <| IO.userError "Could not finish a captured graph"
    unless entry.data.nodes.size == 1 && entry.data.nodes.all (fun node =>
        node.label == `isolated_theorem && node.href.isSome && node.previewKey.isSome &&
          node.title == "Theorem 1") do
      throw <| IO.userError "An unrendered node leaked into the graph or its title"

-- Missing contexts are diagnosed; explicitly supplied empty overviews remain valid.
#eval show IO Unit from do
  let blocks : Array (Doc.Block Manual) := #[
    .other (Commands.Block.graph {}) #[],
    .other (Commands.Block.summary {}) #[]
  ]
  let errors ← IO.mkRef (#[] : Array String)
  let (blocks, state) ← traverseManualBlocks blocks extension_impls%
  let _ ← renderManualBlocksHtmlWithState blocks extension_impls% state
    (logError := fun message => errors.modify (·.push message))
  unless (← errors.get).any (·.contains "Missing captured Blueprint graph") &&
      (← errors.get).any (·.contains "Missing captured Blueprint summary") do
    throw <| IO.userError "Missing project overviews silently became empty data"
  let customGraph : Commands.GraphBlockData := { graphModel := some {} }
  let customSummary : Commands.SummaryBlockData := { summary := some {} }
  unless (customGraph.resolveModel state).toOption.any (·.nodes.isEmpty) &&
      (customSummary.resolve state).toOption.any (·.totalEntries == 0) do
    throw <| IO.userError "Explicitly empty overview data required a project context"
  let malformed := TraversalIndex.RenderOverviews.saveData state `graph (Json.str "invalid")
    |> fun state => TraversalIndex.RenderOverviews.saveData state `summary (Json.str "invalid")
  for result in #[
      (({} : Commands.GraphBlockData).resolveModel malformed).map (fun _ => ()),
      (({} : Commands.SummaryBlockData).resolve malformed).map (fun _ => ())] do
    let .error message := result
      | throw <| IO.userError "A malformed captured overview silently became empty data"
    unless message.contains "Malformed captured Blueprint" do
      throw <| IO.userError "A malformed captured overview silently became empty data"
