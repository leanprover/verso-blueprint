/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/

import VersoBlueprint

open Lean Informal

private def record (label : Name) (priority : Option String) (id : Contributions.ContributionId) :
    Contributions.Record := { id, label, references := #[], priority, source := none }

run_cmd do
  discard <| Environment.contributeSelected `coherent_three { priority := some "low" }
    (record `coherent_three (some "low") {
      moduleName := Name.mkSimple "CoherenceConflictC"
      producer := Name.mkSimple "test.synthetic"
      subject := `coherent_three
      site := 1
      slot := 0 })
