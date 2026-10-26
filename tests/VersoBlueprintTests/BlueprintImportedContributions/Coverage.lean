/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintImportedContributions.Attachment
import VersoBlueprintTests.Blueprint.Support
import VersoBlueprint.Realizations.Capture

open Lean Informal Verso.Genre Elab Command Term Realizations
open Verso.VersoBlueprintTests.Blueprint.Support

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error error => throwError "Capture failed: {repr error}"

@[blueprint "dependency_only" (uses := ["statement_dep"]) (proofUses := ["proof_dep"])]
theorem dependencyOnly : True := trivial

run_cmd liftTermElabM do
  let snapshot ← obtain (← Capture.capture)
  let summary ← liftM (m := CoreM) (Commands.buildSummary snapshot)
  for label in #[`key_theorem, `dependency_only] do
    unless summary.pendingInformalEntries.any (·.label == label) do
      throwError "Dependency-only payload for {label} incorrectly counted as informal coverage"
  unless summary.leanOnlyEntries == 1 do
    throwError "Expected the undocumented dependency-only theorem in the Lean-only count"

#docs (Manual) coverageDoc "Coverage" :=
:::::::
{include 0 VersoBlueprintTests.BlueprintImportedContributions.Statement}
{blueprint_summary}
:::::::

#eval show IO Unit from do
  let html ← renderManualDocHtmlString extension_impls% coverageDoc
  unless hasSubstr html "Missing informal coverage (3)" &&
      hasSubstr html "dependencyOnly" do
    throw <| IO.userError "Rendered summary omitted missing informal coverage"

#docs (Manual) completedCoverageDoc "Completed informal coverage" :=
:::::::
:::theorem "dependency_only"
The actual informal statement.
:::
:::proof "dependency_only"
The actual informal proof.
:::
:::::::

run_cmd liftTermElabM do
  let snapshot ← obtain (← Capture.capture)
  let summary ← liftM (m := CoreM) (Commands.buildSummary snapshot)
  unless !summary.pendingInformalEntries.any (·.label == `dependency_only) &&
      summary.pendingInformalEntries.any (·.label == `key_theorem) do
    throwError "Coverage did not distinguish new bodies from dependency metadata"
