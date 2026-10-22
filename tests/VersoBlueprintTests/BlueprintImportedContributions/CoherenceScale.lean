/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/
import VersoBlueprintTests.BlueprintImportedContributions.CoherenceScaleProvider

open Lean Informal

run_cmd do
  unless (← Environment.importedConflicts).isEmpty do
    throwError "Independent identities conflicted during scale import"
  for i in [:200] do
    let label := Name.num `coherence_scale i
    let declaration := Name.num `coherence_decl i
    let some node ← Environment.getNode? label
      | throwError "Scale import omitted an accepted label"
    unless node.leanDecls == #[declaration] &&
        (← Environment.labelsForLeanDecl declaration) == #[label] do
      throwError "Scale import changed accepted declaration membership/indexing"
