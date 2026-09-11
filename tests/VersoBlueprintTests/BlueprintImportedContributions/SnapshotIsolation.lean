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
  let data := request.resolve state
  unless data.showDebugDiagnostics && data.totalEntries == 2 do
    throw <| IO.userError "Shared summary resolution lost occurrence-specific diagnostic visibility"
  let custom : Commands.SummaryBlockData := { summary := some { totalEntries := 17 } }
  unless (custom.resolve state).totalEntries == 17 do
    throw <| IO.userError "The project summary replaced an explicitly supplied summary"

  let errors ← IO.mkRef (#[] : Array String)
  let missing : BlockOccurrence := { label := `unregistered, count := 1 }
  let _ ← Informal.traverseManualBlocks
    #[.other (Block.informal missing) #[]]
    (current.withExtensions extension_impls%) (fun message => errors.modify (·.push message))
  unless (← errors.get).any (·.contains "Missing rendering node") do
    throw <| IO.userError "Traversal silently accepted a reference outside its rendering context"

-- Explicit models can be built outside elaboration and still acquire traversal anchors.
#eval show IO Unit from do
  let node := RenderNode.ofBlockData {
    label := `synthetic
    kind := .statement .theorem
    count := 1
    tags := #["synthetic"]
  }
  let model : RenderModel := { nodes := ({} : Lean.NameMap RenderNode).insert node.label node }
  let (blocks, state) ← Informal.traverseManualBlocks
    #[.other (Block.informal node.toBlockData.toOccurrence) #[.para #[.text "Synthetic theorem"]]]
    (model.withExtensions extension_impls%)
  unless (TraversalIndex.Nodes.href? state node.label).isSome &&
      (TraversalIndex.Nodes.storedData? state node.label).any (·.globalCount.isSome) do
    throw <| IO.userError "An explicitly supplied occurrence prevented anchor and numbering allocation"
  let html ← Informal.renderManualBlocksHtmlWithState blocks extension_impls% state
  unless hasSubstr html.asString "Synthetic theorem" && hasSubstr html.asString "synthetic" do
    throw <| IO.userError "A synthetic rendering model lost its body or metadata"
