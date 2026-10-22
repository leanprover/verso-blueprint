/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/

import VersoBlueprint

open Lean Informal

private def record (label : Name) (priority : Option String) (id : Contributions.ContributionId) :
    Contributions.Record := { id, label, references := #[], priority, source := none }

run_cmd do
  discard <| Environment.contributeSelected `coherent_three { priority := some "medium" }
    (record `coherent_three (some "medium") {
      moduleName := Name.mkSimple "CoherenceConflictB"
      producer := Name.mkSimple "test.synthetic"
      subject := `coherent_three
      site := 1
      slot := 0 })
  discard <| Environment.contributeSelected `coherent_cross_b {}
    (record `coherent_cross_b none {
      moduleName := Name.mkSimple "CoherenceCross"
      producer := Name.mkSimple "test.synthetic"
      subject := `shared_identity
      site := 9
      slot := 0 })
