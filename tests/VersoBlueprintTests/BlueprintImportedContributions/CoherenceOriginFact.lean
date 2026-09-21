/- Copyright (c) 2026 Lean FRO LLC. All rights reserved. Released under Apache 2.0 license. -/

import VersoBlueprint

open Lean Informal

namespace CoherenceOriginFact

theorem declaration : True := trivial

run_cmd do
  let ref := Data.ExternalRef.ofName `CoherenceOriginFact.declaration
  discard <| Environment.contributeSelected `coherent_origin { leanCode := #[.external #[ref]] }
    { id := {
        moduleName := Name.mkSimple "CoherenceOriginFact"
        producer := Name.mkSimple "test.synthetic"
        subject := `coherent_origin
        site := 1
        slot := 0 }
      label := `coherent_origin
      references := #[ref]
      priority := none
      source := none }
  discard <| Environment.contributeSelected `coherent_origin_conflict { leanCode := #[.external #[ref]] }
    { id := {
        moduleName := Name.mkSimple "CoherenceOriginFact"
        producer := Name.mkSimple "test.synthetic"
        subject := `coherent_origin_conflict
        site := 2
        slot := 0 }
      label := `coherent_origin_conflict
      references := #[ref]
      priority := none
      source := none }

end CoherenceOriginFact
