/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.CoherenceEqualB
import VersoBlueprintTests.BlueprintImportedContributions.CoherenceEqualA
import VersoBlueprint

open Lean Informal Verso.Genre

-- Reversed imports retain both supports and agree on their selected scalar.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let some node ← Environment.getNode? `coherent_equal | return false
  let labelsA ← Environment.labelsForLeanDecl `CoherenceEqualA.declaration
  let labelsB ← Environment.labelsForLeanDecl `CoherenceEqualB.declaration
  return (← Environment.importedConflicts).isEmpty &&
    node.priority == some "high" && node.externalRefs.size == 2 &&
    labelsA == #[`coherent_equal] && labelsB == #[`coherent_equal]

#docs (Manual) coherenceEqualDoc "Equal selected facts" :=
:::::::
{blueprint_node "coherent_equal"}
{blueprint_summary}
{blueprint_graph}
:::::::

def coherenceEqualBlueprint : BlueprintDocument := .capture coherenceEqualDoc.toPart

#eval show IO Unit from do
  let model := coherenceEqualBlueprint.model
  let some rendered := model.nodes.find? (·.label == `coherent_equal)
    | throw <| IO.userError "Capture omitted the selected node"
  let some graphNode := model.graph.nodes.find? (·.label == `coherent_equal)
    | throw <| IO.userError "Graph omitted the selected node"
  let some summaryItem := model.summary.pendingInformalEntries.find? (·.label == `coherent_equal)
    | throw <| IO.userError "Summary omitted the selected formalization"
  unless model.summary.totalEntries == 1 && graphNode.kind == some .definition &&
      rendered.priority == some "high" &&
      rendered.externalRefs.any (·.canonical == `CoherenceEqualA.declaration) &&
      rendered.externalRefs.any (·.canonical == `CoherenceEqualB.declaration) &&
      summaryItem.leanObjects.contains `CoherenceEqualA.declaration &&
      summaryItem.leanObjects.contains `CoherenceEqualB.declaration do
    throw <| IO.userError "Capture, graph, and summary lost accepted selected associations"
