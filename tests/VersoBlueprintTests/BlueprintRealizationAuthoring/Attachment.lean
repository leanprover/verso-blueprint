/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintRealizationAuthoring.Owner

open Lean Elab Command Informal
open Realizations

namespace VersoBlueprintTests.BlueprintRealizationAuthoring.Attachment

def context : Realizations.Context := ⟨`rocq, `TranslationHarnessReuse⟩
def source : DocumentKey := ⟨context, "tests/fixtures/realizations/rocq/Flag.v"⟩
def config : DocumentKey := ⟨context, "tests/fixtures/realizations/rocq/_RocqProject"⟩
def reference : ObjectKey := ⟨context, "TranslationHarnessReuse.Flag.toggle_involutive"⟩
def batch : Environment.AuthoredBatch := {
  sources := #[source, config]
  references := #[(reference, some source)]
  realizations := #[{
    key := Owner.rocqKey, context
    facets := #[{ name := `statement, documents := #[source, config], declarations := #[reference] },
      { name := `proof, documents := #[source, config], declarations := #[reference] }]
    declarations := #[{ object := reference }] }] }

run_cmd liftCoreM do
  let before ← Environment.stagedAuthoring
  match ← Environment.stageAuthored `notEnrolled batch with
  | .error issues => unless issues.any (·.code == "missing-project") do throwError "Wrong project diagnostic"
  | .ok _ => throwError "Importing Owner implicitly enrolled Attachment"
  unless decide (before = (← Environment.stagedAuthoring)) do throwError "Failed stage changed buffers"

run_cmd liftCoreM <| Realizations.Authoring.configureProject Owner.projectName
run_cmd liftCoreM <| Realizations.Authoring.stage `rocq batch
run_cmd liftCoreM <| Realizations.Authoring.stage `rocq batch

end VersoBlueprintTests.BlueprintRealizationAuthoring.Attachment
