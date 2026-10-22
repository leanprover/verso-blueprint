/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/
import VersoBlueprint

open Lean Informal

-- Exercise actual registration/export and subsequent import-wide assembly at
-- scale. No timing assertion: the old global pair search makes this ordinary
-- valid input prohibitively expensive, while the indexed path stays bounded.
run_cmd do
  for i in [:200] do
    let label := Name.num `coherence_scale i
    let fact : Contributions.Record := {
      id := ⟨← getMainModule, `test.scale, label, i, 0⟩
      label
      references := #[Data.ExternalRef.ofName (.num `coherence_decl i)]
      priority := none, source := none }
    let some _ ← Environment.contributeSelected label fact.toNodeContribution fact
      | throwError "Valid scale contribution was rejected"
