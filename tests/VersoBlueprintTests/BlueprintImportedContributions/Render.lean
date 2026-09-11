/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedContributions.Doc
import VersoBlueprintTests.Blueprint.Support

open Verso
open Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support

private def splitDoc : Doc.VersoDoc Genre.Manual :=
  .mk (fun _ => %doc VersoBlueprintTests.BlueprintImportedContributions.Doc) "{}"

private def manualImpls : ExtensionImpls := extension_impls%

-- Check the generated preview artifacts, not just successful elaboration.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  let files ← buildManualPreviewDataFiles manualImpls splitDoc
  let some statement := files.manifest.findEntry? "key_theorem--statement" | return false
  let some proof := files.manifest.findEntry? "key_theorem--proof" | return false
  let some statementHtml := files.htmlCache.findHtml? statement.key | return false
  let some proofHtml := files.htmlCache.findHtml? proof.key | return false
  return statement.statementUses == #[{ label := `statement_dep }] &&
    proof.proofUses == #[{ label := `proof_dep, intent := .technical }] &&
    hasSubstr statementHtml "A statement declared in this module." &&
    hasSubstr proofHtml "A proof declared in a different module from its statement."
