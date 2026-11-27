/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.SourceData

/-! Synthetic raw native source constructors for tests. These do not resolve a
declaration, produce evidence or certify the snapshot's status. The context
matches the explicit test-library project unless a control supplies another. -/

open Lean Informal

namespace BlueprintNativeFixture

def associations (node : Name) (placement : Name) (references : Array Data.ExternalRef)
    (project : Name := `blueprintFixtures) (realization : Name := `lean) :
    Array SourceData.NativeAssociation :=
  references.map fun reference => {
    realization := ⟨node, realization⟩, context := ⟨`lean, project⟩, placement, reference }

/-- Synthetic source provenance for pure reducer/rollback tests only. -/
def source (node realization : Name) (role : Option Name) (language : Name) (payload : SourceData.ProviderPayload)
    (project : Name := `blueprintFixtures) : SourceData.SourceSelection := {
  destination := ⟨⟨node, realization⟩, role⟩
  document := ⟨⟨language, project⟩, "synthetic-fixture.lean"⟩
  source := .unavailable "Synthetic reducer fixture; no provider lookup"
  payload }

end BlueprintNativeFixture
