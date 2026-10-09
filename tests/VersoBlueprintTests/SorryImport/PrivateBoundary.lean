/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprintTests.SorryImport.PrivateProvider

open Lean Informal.Data

namespace Verso.VersoBlueprintTests.SorryImport.PrivateBoundary

-- Reuse Lake's actual cache-in-place artifacts and explicitly select visibility;
-- the surrounding legacy module must not accidentally grant import-all coverage.
private unsafe def withPrivateProvider (importAll : Bool) (action : CoreM Bool) : CoreM Bool := do
  liftM enableInitializersExecution
  let output ← liftM <| IO.Process.output {
    cmd := "./scripts/lean-low-priority"
    args := #["lake", "-q", "query", "-J", "+VersoBlueprintTests.SorryImport.PrivateBoundary:setup"]
  }
  unless output.exitCode == 0 do throwError "Private provider setup failed: {output.stderr}"
  let setup : ModuleSetup ← ofExcept <| Json.parse output.stdout >>= fromJson?
  let env ← liftM <| importModules
    #[{ module := `VersoBlueprintTests.SorryImport.PrivateProvider, importAll }]
    {} (loadExts := true) (level := .exported) (arts := setup.importArts)
  withEnv env action

/-- info: true -/
#guard_msgs in
#eval withPrivateProvider false do
  let status ← analyzeDeclaration `PrivateSorryBoundary.exposedHoleConsumer
  return !status.isProved && (status.hasKnownSorry || status.hasUnverifiedCoverage)

/-- info: true -/
#guard_msgs in
#eval withPrivateProvider true do
  let hole ← analyzeDeclaration `PrivateSorryBoundary.exposedHoleConsumer
  let complete ← analyzeDeclaration `PrivateSorryBoundary.exposedCompleteConsumer
  return !hole.isProved && hole.hasKnownSorry && complete.isProved

end Verso.VersoBlueprintTests.SorryImport.PrivateBoundary
