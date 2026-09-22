/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/

import VersoBlueprint

open Lean Informal

private def record (label : Name) (priority : Option String) (id : Contributions.ContributionId) :
    Contributions.Record := { id, label, references := #[], priority, source := none }

run_cmd do
  discard <| Environment.contributeRecord
    (record `coherent_three (some "high") {
      moduleName := Name.mkSimple "CoherenceConflictA"
      producer := Name.mkSimple "test.synthetic"
      subject := `coherent_three
      site := 1
      slot := 0 }) {}
  discard <| Environment.contributeRecord
    (record `coherent_cross_a none {
      moduleName := Name.mkSimple "CoherenceCross"
      producer := Name.mkSimple "test.synthetic"
      subject := `shared_identity
      site := 9
      slot := 0 }) {}
