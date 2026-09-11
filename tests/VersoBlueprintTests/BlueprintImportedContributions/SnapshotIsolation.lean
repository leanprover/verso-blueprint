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
  let current : DocumentSnapshot := blueprint_snapshot%
  unless isolatedBlueprint.snapshot.summary.totalEntries == 1 && current.summary.totalEntries == 2 do
    throw <| IO.userError "A captured project followed the caller's unrelated environment"
  let html ← renderManualDocHtmlString extension_impls% isolatedDocument
    (snapshot := isolatedBlueprint.snapshot)
  unless !hasSubstr html "unrelatedTheorem" do
    throw <| IO.userError "An isolated summary acquired an unrelated declaration"

  let summary := Commands.blockFromJsonString! ``Commands.Block.summary
    (toJson ({ showDebugDiagnostics := true } : Commands.Summary)).compress true
  let .other refreshed _ := current.block (.other summary #[])
    | throw <| IO.userError "Projection changed the summary container"
  let .ok (data : Commands.Summary) := fromJson? refreshed.data
    | throw <| IO.userError "Projection lost the typed summary payload"
  unless data.showDebugDiagnostics && data.totalEntries == 2 do
    throw <| IO.userError "Projection changed occurrence-specific diagnostic visibility"

  let errors ← IO.mkRef (#[] : Array String)
  let a : BlockData := { label := `raw_conflict, count := 1, effort := some "small" }
  let b := { a with effort := some "large" }
  let _ ← Informal.traverseManualBlocks
    #[.other (Block.informal a) #[], .other (Block.informal b) #[]]
    extension_impls% (fun message => errors.modify (·.push message))
  unless (← errors.get).any (·.contains "Inconsistent Blueprint metadata") do
    throw <| IO.userError "Traversal silently selected conflicting unprojected semantics"
