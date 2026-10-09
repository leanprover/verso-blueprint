/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint

open Lean Informal

namespace CoherenceEqualB

theorem declaration : True := trivial

run_cmd do
  let ref : Data.ExternalRef := {
    canonical := `CoherenceEqualB.declaration
    written := `CoherenceEqualB.declaration
    present := true }
  discard <| Environment.contributeSelected `coherent_equal
    { leanCode := #[.external #[ref]], priority := some "high" }
    { id := {
        moduleName := Name.mkSimple "CoherenceEqualB"
        producer := Name.mkSimple "test.synthetic"
        subject := `coherent_equal
        site := 1
        slot := 0 }
      label := `coherent_equal
      references := #[ref]
      priority := some "high"
      source := none }

end CoherenceEqualB
