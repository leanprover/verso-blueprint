/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Authoring
import VersoBlueprint.Realizations.Capture
import VersoBlueprint.Attribute
import VersoBlueprintTests.BlueprintRealizationSemantics.Runtime

open Lean Elab Command Informal Realizations Validation Translations

namespace FIRSemanticFixture

def node : Name := Name.mkSimple "fir.semanticWitness"
def leanKey : RealizationKey := ⟨node, `lean⟩
def proseKey : RealizationKey := ⟨node, `verso⟩
def nativeObject : ObjectKey := ⟨⟨`lean, `firSemanticFixture⟩, "FIRSemanticFixture.semanticWitness"⟩
def proofKey : RequirementKey := ⟨.declaration leanKey nativeObject, `proof⟩
def correspondence : TranslationKey := ⟨`firSemanticFixture, `runtimeCorrespondence⟩
def subjectReview : RequirementKey := ⟨.claim ⟨correspondence, `subject⟩, `review⟩
def closureReview : RequirementKey := ⟨.claim ⟨correspondence, `closure⟩, `review⟩

run_cmd liftCoreM <| Realizations.Authoring.configureProject `firSemanticFixture

/-- The native runtime statement is reflexive under the selected runtime semantics. -/
@[blueprint "fir.semanticWitness"]
theorem semanticWitness : RefinedReturnPost := by rfl

run_cmd liftCoreM <| Realizations.Authoring.stage `correspondence {
  translations := #[{
    key := correspondence
    source := #[{ realization := proseKey, facets := #[`statement] }]
    target := #[{ realization := leanKey, facets := #[`statement] }]
    required := #[proofKey] }]
  claims := #[
    { key := ⟨correspondence, `subject⟩, interpretation := "The selected runtime semantics match the prose"
      required := #[subjectReview] },
    { key := ⟨correspondence, `closure⟩, interpretation := "The selected runtime account retains required obligations"
      required := #[closureReview] }]
  requirements := #[
    { key := subjectReview, expected := .review `runtimeMeaning, prerequisites := #[proofKey] },
    { key := closureReview, expected := .review `runtimeMeaning, coverage := .dependencyClosure
      prerequisites := #[proofKey] }] }

end FIRSemanticFixture
