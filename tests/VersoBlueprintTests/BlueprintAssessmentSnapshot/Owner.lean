/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint
import VersoBlueprint.Realizations.Authoring
import VersoManual

open Lean Elab Command Informal
open Realizations Validation Translations
open Verso Genre Manual

namespace BlueprintAssessmentSnapshot

def project : Name := `assessmentSnapshot
def label : Name := Name.mkSimple "assessment.statementProof"
def mutualSelectedLabel : Name := Name.mkSimple "assessment.mutualSelected"
def mutualSiblingLabel : Name := Name.mkSimple "assessment.mutualSibling"
def proofValueLabel : Name := Name.mkSimple "assessment.proofValue"
def leanBase : RealizationKey := ⟨label, `lean⟩
def statement : RealizationKey := leanBase.forRole `statement
def nativeProof : RealizationKey := leanBase.forRole `proof
def mutualSelectedStatement : RealizationKey :=
  (⟨mutualSelectedLabel, `lean⟩ : RealizationKey).forRole `statement
def mutualSiblingStatement : RealizationKey :=
  (⟨mutualSiblingLabel, `lean⟩ : RealizationKey).forRole `statement
def proofValueStatement : RealizationKey :=
  (⟨proofValueLabel, `lean⟩ : RealizationKey).forRole `statement
def proofValueProof : RealizationKey :=
  (⟨proofValueLabel, `lean⟩ : RealizationKey).forRole `proof
def prose : RealizationKey := (⟨label, `verso⟩ : RealizationKey).forRole `statement
def versoProof : RealizationKey := (⟨label, `verso⟩ : RealizationKey).forRole `proof
def nativeObject : ObjectKey := ⟨⟨`lean, project⟩,
  "BlueprintAssessmentSnapshot.witness"⟩
def mutualSelectedObject : ObjectKey := ⟨⟨`lean, project⟩,
  "BlueprintAssessmentSnapshot.mutualSelected"⟩
def mutualSiblingObject : ObjectKey := ⟨⟨`lean, project⟩,
  "BlueprintAssessmentSnapshot.mutualSibling"⟩
def proofValueObject : ObjectKey := ⟨⟨`lean, project⟩,
  "BlueprintAssessmentSnapshot.proofValue"⟩
def statementCheck : RequirementKey := ⟨.declaration statement nativeObject, `statement⟩
def proofCheck : RequirementKey := ⟨.declaration nativeProof nativeObject, `proof⟩
def proofValueStatementCheck : RequirementKey := ⟨.declaration proofValueStatement proofValueObject, `statement⟩
def proofValueProofCheck : RequirementKey := ⟨.declaration proofValueProof proofValueObject, `proof⟩
def customNativeLabel : Name := Name.mkSimple "assessment.customBase"
def customBase : RealizationKey := ⟨customNativeLabel, `customNative⟩
def customBaseStatement : RealizationKey := customBase.forRole `statement
def customBaseProof : RealizationKey := customBase.forRole `proof
def customWitnessObject : ObjectKey := ⟨⟨`lean, project⟩,
  "BlueprintAssessmentSnapshot.customWitness"⟩
def customWitnessStatementCheck : RequirementKey :=
  ⟨.declaration customBaseStatement customWitnessObject, `statement⟩
def customWitnessProofCheck : RequirementKey :=
  ⟨.declaration customBaseProof customWitnessObject, `proof⟩
def customDependentLabel : Name := Name.mkSimple "assessment.customDependent"
def customDependentBase : RealizationKey := ⟨customDependentLabel, `lean⟩
def customDependentStatement : RealizationKey := customDependentBase.forRole `statement
def customDependentProof : RealizationKey := customDependentBase.forRole `proof
def customDependentObject : ObjectKey := ⟨⟨`lean, project⟩,
  "BlueprintAssessmentSnapshot.customDependent"⟩
def customDependentStatementCheck : RequirementKey :=
  ⟨.declaration customDependentStatement customDependentObject, `statement⟩
def customDependentProofCheck : RequirementKey :=
  ⟨.declaration customDependentProof customDependentObject, `proof⟩
def mainDependentLabel : Name := Name.mkSimple "assessment.mainDependent"
def mainDependentBase : RealizationKey := ⟨mainDependentLabel, `lean⟩
def mainDependentStatement : RealizationKey := mainDependentBase.forRole `statement
def mainDependentProof : RealizationKey := mainDependentBase.forRole `proof
def mainDependentObject : ObjectKey := ⟨⟨`lean, project⟩,
  "BlueprintAssessmentSnapshot.mainDependent"⟩
def mainDependentStatementCheck : RequirementKey :=
  ⟨.declaration mainDependentStatement mainDependentObject, `statement⟩
def mainDependentProofCheck : RequirementKey :=
  ⟨.declaration mainDependentProof mainDependentObject, `proof⟩
def unfinishedAlternativeBase : RealizationKey := ⟨label, `authoredAlternative⟩
def unfinishedAlternativeProof : RealizationKey := unfinishedAlternativeBase.forRole `proof
def unfinishedAlternativeDocument : DocumentKey :=
  ⟨⟨`rocq, project⟩, "tests/fixtures/realizations/rocq/Flag.v"⟩
def unfinishedAlternativeCheck : RequirementKey :=
  ⟨.realization unfinishedAlternativeProof, `localCheck⟩
def unfinishedAlternative : Realization := {
  key := unfinishedAlternativeProof
  context := unfinishedAlternativeDocument.context
  role := `proof
  documents := #[unfinishedAlternativeDocument]
  required := #[unfinishedAlternativeCheck] }
def unfinishedAlternativeRequirement : Requirement := {
  key := unfinishedAlternativeCheck
  expected := .check `blueprint.unfinishedAlternative }
def proofRelation : TranslationKey := ⟨project, `nativeProof⟩
def nativeSupport : RequirementKey := ⟨.translation proofRelation, `nativeSupport⟩
def sameFactRelation : TranslationKey := ⟨project, `sameNativeFactAgain⟩
def sameFactSupport : RequirementKey := ⟨.translation sameFactRelation, `sameFactSupport⟩
def alternativeRelation : TranslationKey := ⟨project, `alternativeVersoProof⟩
def alternativeProofReview : RequirementKey := ⟨.translation alternativeRelation, `mathematicalReview⟩
def correspondence : TranslationKey := ⟨project, `proseCorrespondence⟩
def correspondenceClaim : ClaimKey := ⟨correspondence, `statement⟩
def aliceReview : RequirementKey := ⟨.claim correspondenceClaim, `aliceReview⟩
def docstringLabel (decl : Name) : Name := Name.mkSimple s!"assessment.{decl}"
def docstringStatement : RealizationKey :=
  (⟨docstringLabel `documented, `markdown⟩ : RealizationKey).forRole `statement
def docstringReview : RequirementKey := ⟨.realization docstringStatement, `docstringReview⟩
def localDocStatement : RealizationKey :=
  (⟨docstringLabel `localDoc, `verso⟩ : RealizationKey).forRole `statement
def localDocReview : RequirementKey := ⟨.realization localDocStatement, `localDocReview⟩
def highlightedDocStatement : RealizationKey :=
  (⟨docstringLabel `highlightedDoc, `verso⟩ : RealizationKey).forRole `statement
def highlightedDocReview : RequirementKey := ⟨.realization highlightedDocStatement, `highlightedDocReview⟩
def macroDocStatement : RealizationKey :=
  (⟨docstringLabel `macroDoc, `verso⟩ : RealizationKey).forRole `statement
def macroDocReview : RequirementKey := ⟨.realization macroDocStatement, `macroDocReview⟩
def headerUseStatement : RealizationKey :=
  (⟨docstringLabel `headerUse, `verso⟩ : RealizationKey).forRole `statement
def headerUseReview : RequirementKey := ⟨.realization headerUseStatement, `headerUseReview⟩
def docstringProofCheck (decl : Name) : RequirementKey :=
  let base : RealizationKey := ⟨docstringLabel decl, `lean⟩
  let object : ObjectKey := ⟨⟨`lean, project⟩, (`BlueprintAssessmentSnapshot ++ decl).toString⟩
  ⟨.declaration (base.forRole `proof) object, `proof⟩

run_cmd liftCoreM <| Realizations.Authoring.configureProject project

@[blueprint "assessment.statementProof"]
theorem witness : True := True.intro

mutual
  @[blueprint "assessment.mutualSelected"]
  def mutualSelected : Prop := True

  @[blueprint "assessment.mutualSibling"]
  def mutualSibling : Prop := False
end

@[blueprint "assessment.proofValue"]
def proofValue : True := True.intro

theorem customWitness : True := True.intro

@[blueprint "assessment.customDependent" (proofUses := ["assessment.customBase"])]
theorem customDependent : True := True.intro

@[blueprint "assessment.mainDependent" (proofUses := ["assessment.statementProof"])]
theorem mainDependent : True := True.intro

@[blueprint "assessment.docDependencyA"]
theorem docDependencyA : True := True.intro

@[blueprint "assessment.docDependencyB"]
theorem docDependencyB : True := True.intro

/-- The attribute statement is true. Ω 🧭 -/
@[blueprint "assessment.documented" (proofUses := ["assessment.docDependencyA"])]
theorem documented : True := True.intro

namespace DocTargets

def x : Nat := 0

end DocTargets

set_option doc.verso true in
/-- Compare {name}`x` with {Lean.Doc.lean}`x`. The linked binder is {name}`x`. -/
@[blueprint "assessment.localDoc"]
theorem localDoc (x : Nat) : x = x := by rfl

set_option doc.verso true in
/-- The value of {Lean.Doc.lean}`x` is unchanged. Here, {name}`x` names the binder. -/
@[blueprint "assessment.highlightedDoc"]
theorem modelAReviewed (x y : Nat) : x ≤ y → x ≤ y := id

syntax "underBinder " ident : term
macro_rules | `(underBinder $v:ident) => `(fun (_inner : Nat) => $v)

def underBinderProbe : Nat :=
  let x := 13
  (underBinder x) 7

set_option doc.verso true in
/-- Compare {name}`x` with {Lean.Doc.lean}`underBinder x`. -/
@[blueprint "assessment.macroDoc"]
theorem modelAMacroReviewed (x : Nat) : x = x := rfl

theorem headerWitness : True := True.intro

#docs (Manual) assessmentSnapshotDoc "Assessment Snapshot Example" :=
:::::::
:::theorem "assessment.statementProof"
The proposition is true. Ω 🧭 The Lean declaration provides its proof.
:::
:::proof "assessment.statementProof"
An alternative argument remains to be written.
:::
:::theorem "assessment.headerUse" (lean := "headerWitness") (uses := "assessment.docDependencyA")
The first paragraph cites {bpref "assessment.docDependencyA"}[the same statement].

The last paragraph completes the authored body.
:::
:::::::

run_cmd liftCoreM <| Realizations.Authoring.stage `claims {
  translations := #[
    { key := proofRelation, kind := `proves,
      source := #[{ realization := nativeProof }], target := #[{ realization := statement }],
      required := #[nativeSupport] },
    { key := sameFactRelation, kind := `proves,
      source := #[{ realization := nativeProof }], target := #[{ realization := statement }],
      required := #[sameFactSupport] },
    { key := alternativeRelation, kind := `proves,
      source := #[{ realization := versoProof }], target := #[{ realization := statement }],
      required := #[alternativeProofReview] },
    { key := correspondence, kind := `correspondence,
      source := #[{ realization := prose }], target := #[{ realization := statement }] }]
  claims := #[{
    key := correspondenceClaim,
    interpretation := "The prose statement corresponds to the selected Lean proposition.",
    required := #[aliceReview] }]
  requirements := #[
    { key := nativeSupport, expected := .proves nativeObject,
      coverage := .dependencyClosure, prerequisites := #[proofCheck] },
    { key := sameFactSupport, expected := .proves nativeObject,
      coverage := .dependencyClosure, prerequisites := #[proofCheck] },
    { key := alternativeProofReview,
      expected := .review `mathematicalProof `AliceMock },
    { key := docstringReview,
      expected := .review `mathematicalCorrespondence `AliceMock },
    { key := localDocReview,
      expected := .review `mathematicalCorrespondence `AliceMock },
    { key := highlightedDocReview,
      expected := .review `mathematicalCorrespondence `AliceMock },
    { key := macroDocReview,
      expected := .review `mathematicalCorrespondence `AliceMock },
    { key := headerUseReview,
      expected := .review `mathematicalCorrespondence `AliceMock },
    { key := aliceReview, expected := .review `mathematicalCorrespondence `AliceMock,
      prerequisites := #[nativeSupport] }] }

end BlueprintAssessmentSnapshot
