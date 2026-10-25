/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalSourcePersistence.Malformed
import VersoBlueprintTests.BlueprintCanonicalNativePersistence.Harness

open Lean Informal

run_cmd Lean.Elab.Command.liftCoreM do
  let env ← getEnv
  try
    let label := Name.mkSimple "storage.source"
    let state := Environment.informalExt.getState env
    let sources := (state.pendingNodes.getD label {}).registrations.flatMap (·.sources)
    let nativeSources := sources.filter (·.context.language == `lean)
    unless nativeSources.size == 2 &&
        nativeSources.any (·.context.project == `blueprintFixtures) &&
        nativeSources.any (·.context.project == `otherProject) &&
        state.importedConflicts.any (fun issue => issue.label == label && issue.reasons.any (·.contains "source-context-mismatch")) &&
        !state.data.contains label && !(state.leanNameLabels.getD `storedInline #[]).contains label &&
        state.pendingNodes.all (fun _ pending => pending.localRegistrations.isEmpty) do
      throwError "Import dropped a conflicting source context or installed a partial node/index"
    Environment.modify fun state => { state with importedConflictsReported := true }
    CanonicalNativePersistence.rejected "source-context-mismatch" <|
      Environment.contribute label { tags := #["must not restore rejected source"] }
  finally
    setEnv env
