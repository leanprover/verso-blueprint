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

def associations (node : Name) (facets : Array Name) (references : Array Data.ExternalRef)
    (project : Name := `blueprintFixtures) (realization : Name := `lean) :
    Array SourceData.NativeAssociation :=
  references.map fun reference => {
    realization := ⟨node, realization⟩, context := ⟨`lean, project⟩, facets, reference }

/-- Synthetic source provenance for pure reducer/rollback tests only. -/
def source (node realization facet language : Name) (payload : SourceData.ProviderPayload)
    (project : Name := `blueprintFixtures) : SourceData.FacetSource := {
  destination := ⟨⟨node, realization⟩, facet⟩
  context := ⟨language, project⟩
  document := ⟨⟨language, project⟩, "synthetic-fixture.lean"⟩
  source := .unavailable "Synthetic reducer fixture; no provider lookup"
  payload }

end BlueprintNativeFixture
