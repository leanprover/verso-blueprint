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

/-- info: true -/
#guard_msgs in
#eval withPrivateProvider false do
  -- In exported module imports, body-hidden theorems and definitions appear as
  -- `.axiomInfo`; both `registerExternalRef` and rendered HTML must recover
  -- their original declaration kind while keeping genuine axioms as `axiom`.
  let env ← getEnv
  let isAxiom (name : Name) := match env.find? name with
    | some (.axiomInfo _) => true
    | _ => false
  let register (name : Name) (authoredKind : NodeKind) :=
    Informal.registerExternalRef {} (System.FilePath.mk ".") {
      written := name, canonical := name, kind := authoredKind
    }
  let htmlOf (ref : ExternalRef) : String := match ref.render with
    | .ok rendered => rendered.html
    | .error _ => ""
  let thmRef ← register `PrivateSorryBoundary.completeBridge .definition
  let defRef ← register `PrivateSorryBoundary.hiddenDef .theorem
  let axRef ← register `PrivateSorryBoundary.genuineAxiom .theorem
  let thmHtml := htmlOf thmRef
  let defHtml := htmlOf defRef
  let axHtml := htmlOf axRef
  return isAxiom `PrivateSorryBoundary.completeBridge &&
    isAxiom `PrivateSorryBoundary.hiddenDef &&
    isAxiom `PrivateSorryBoundary.genuineAxiom &&
    thmRef.present && thmRef.kind == .theorem &&
    thmHtml.contains "data-kind=\"theorem\"" &&
    thmHtml.contains ">theorem<" && !thmHtml.contains "data-kind=\"axiom\"" &&
    defRef.present && defRef.kind == .definition &&
    defHtml.contains "data-kind=\"def\"" &&
    defHtml.contains ">def<" && !defHtml.contains "data-kind=\"axiom\"" &&
    axRef.present && axRef.kind == .theorem &&
    axHtml.contains "data-kind=\"axiom\"" && axHtml.contains ">axiom<"

end Verso.VersoBlueprintTests.SorryImport.PrivateBoundary
