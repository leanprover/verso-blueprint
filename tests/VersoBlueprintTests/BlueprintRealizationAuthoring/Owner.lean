/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Authoring
import VersoBlueprintTests.BlueprintRealizationAdapter.Provider

open Lean Elab Command Term Informal
open Realizations Validation Translations

namespace VersoBlueprintTests.BlueprintRealizationAuthoring.Owner

def node : Name := Name.mkSimple "authoring.flag"
def projectName : Name := `authoringPilot
def leanKey : RealizationKey := ⟨node, `lean⟩
def proseKey : RealizationKey := ⟨node, `docstring⟩
def rocqKey : RealizationKey := ⟨node, `«rocq-reference»⟩
def native : ObjectKey := ⟨⟨`lean, projectName⟩, "VersoBlueprintTests.BlueprintRealizationAuthoring.Owner.involutive"⟩
def proof : RequirementKey := ⟨.declaration leanKey native, `proof⟩
def expectedProof : RequirementKey := ⟨.declaration leanKey native, `expectedProof⟩
def versoLink : TranslationKey := ⟨projectName, `versoToLean⟩
def rocqLink : TranslationKey := ⟨projectName, `rocqToLean⟩

run_cmd liftCoreM <| Realizations.Authoring.configureProject projectName
run_cmd liftCoreM <| Realizations.Authoring.configureProject projectName

set_option doc.verso true in
/-- Toggling the two-state flag twice returns it; the off and on cases both reduce. -/
@[blueprint "authoring.flag"]
theorem involutive : ∀ flag : RealizationAdapterFixture.Flag,
    RealizationAdapterFixture.toggle (RealizationAdapterFixture.toggle flag) = flag := by
  intro flag
  cases flag <;> rfl

/-- This native theorem needs no independently repeated expected proposition. -/
@[blueprint "authoring.unassessed"]
theorem withoutContract : True := True.intro

/-- An ordinary imported dependent selects its target's native complete-proof check. -/
@[blueprint "authoring.nativeDependent" (uses := ["authoring.unassessed"])]
theorem nativeDependent : True := withoutContract

/-- An ordinary default whose native statement is valid and whose proof is admitted. -/
@[blueprint "authoring.nativeAdmitted"]
theorem nativeAdmitted : True := by sorry

/-- The selected admitted prerequisite must stay visible even for a clean local proof. -/
@[blueprint "authoring.admittedDependent" (uses := ["authoring.nativeAdmitted", "authoring.nativeDependent"])]
theorem admittedDependent : True := True.intro

run_cmd liftCoreM do
  let state := Environment.informalExt.getState (← getEnv)
  let some fact := state.factRecords.find? (·.label == node) | throwError "Missing actual attribute fact"
  unless fact.references.size == 1 && fact.references[0]!.range?.isNone &&
      fact.references[0]!.selectionRange?.isNone &&
      (← findDeclarationRanges? `VersoBlueprintTests.BlueprintRealizationAuthoring.Owner.involutive).isSome &&
      state.authoringRecords.any (fun record => record.defaults.contains fact.id) do
    throwError "Raw default must survive attribute-before-range timing without source projection"

-- The expectation may refer forward to its independently authored definition.
run_cmd liftCoreM <| Realizations.Authoring.expectNative `toggleProof node `VersoBlueprintTests.BlueprintRealizationAuthoring.Owner.expected

/-- Independent expected statement, not obtained from the submitted witness. -/
def expected : Prop := ∀ flag : RealizationAdapterFixture.Flag,
  RealizationAdapterFixture.toggle (RealizationAdapterFixture.toggle flag) = flag

-- These endpoints refer forward to Attachment.lean; staging is not admission.
run_cmd liftCoreM <| Realizations.Authoring.stage `correspondences {
  translations := #[
    { key := versoLink, source := #[{ realization := proseKey, facets := #[`statement] }]
      target := #[{ realization := leanKey, facets := #[`statement] }], required := #[proof, expectedProof] },
    { key := rocqLink, source := #[{ realization := rocqKey, facets := #[`statement] }]
      target := #[{ realization := leanKey, facets := #[`statement] }], required := #[proof, expectedProof] }]
  claims := #[
    { key := ⟨versoLink, `statement⟩, interpretation := "The two-case prose states toggle involution"
      required := #[⟨.claim ⟨versoLink, `statement⟩, `correspondence⟩] },
    { key := ⟨rocqLink, `statement⟩, interpretation := "Relate off/on constructors, preserving toggle and involution"
      required := #[⟨.claim ⟨rocqLink, `statement⟩, `correspondence⟩] }]
  requirements := #[
    { key := ⟨.claim ⟨versoLink, `statement⟩, `correspondence⟩, expected := .review `statementCorrespondence },
    { key := ⟨.claim ⟨rocqLink, `statement⟩, `correspondence⟩, expected := .review `statementCorrespondence }] }

-- This site and the consumer's Owner.prefixSite would collide under bare ++.
run_cmd liftCoreM <| Realizations.Authoring.stage `prefixSite {}

run_cmd liftTermElabM do
  let before ← Environment.stagedAuthoring
  match ← Realizations.Authoring.registry with
  | .error issues => unless issues.any (·.code == "unknown-realization") do
      throwError "Expected the staged forward endpoint to remain unresolved: {repr issues}"
  | .ok _ => throwError "Owner alone must not admit a partial model without its forward attachment"
  unless decide (before = (← Environment.stagedAuthoring)) do throwError "Query changed staged source"

end VersoBlueprintTests.BlueprintRealizationAuthoring.Owner
