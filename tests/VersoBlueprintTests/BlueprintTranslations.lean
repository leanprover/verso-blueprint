/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintRealizations

/-! Additional pure P01-P22 controls. All provider/check/review facts are MOCKS;
these are not end-to-end Flag, MaxNat, source import, or browser tests. -/

namespace VersoBlueprintTests.BlueprintTranslations

open Lean Informal.Realizations Informal.Validation Informal.Translations
open BlueprintRealizations

-- This fact is a pure-fixture MOCK; it is not a kernel check.
def mockOwnType : Observation := .check {
  validator := NativeLean.ownTypeValidator, declaration := some leanObject,
  proposition := true, outcome := .passed, coverage := .dependencyClosure }

-- P02/P03: translating a statement differs from completing a full theorem port.
#eval show IO Unit from do
  let reviewed ← withMockEvidence fixture `review reviewKey mockReview
  let r ← registry reviewed
  expect "P02: statement translation complete" ((r.resultFor (.translation translationKey)).complete)
  expect "P02: target proof still pending" (!(r.resultForRequirement proofKey).complete)
  let full : Input := { fixture with translations := fixture.translations.map fun c =>
    { c with value := { c.value with required := #[proofKey] } } }
  let checked ← withMockEvidence full `proof proofKey mockProof
  let r ← registry checked
  expect "P03: target proof checked" ((r.resultForRequirement proofKey).complete)
  expect "P03: correspondence still pending" ((r.resultFor (.translation translationKey)).status == Status.pending)
  let checkedAndReviewed ← withMockEvidence checked `review reviewKey mockReview
  let r ← registry checkedAndReviewed
  expect "P03: explicit full contract complete" ((r.resultFor (.translation translationKey)).complete)

-- A lint result cannot establish mathematical `proves` support. Exact own-type
-- support is sufficient for the minimum route, but it cannot bypass another
-- required judgment on that relation.
#eval show IO Unit from do
  let relationKey : TranslationKey := ⟨`fixture, `formal_proof⟩
  let lintKey : RequirementKey := ⟨.translation relationKey, `lint⟩
  let lintOnly : Input := { fixture with
    translations := fixture.translations.push <| contribution `formalProof {
      key := relationKey, kind := `proves, source := #[leanProofKey], target := #[leanKey], required := #[lintKey] }
    requirements := fixture.requirements.push <| contribution `lintRequirement {
      key := lintKey, expected := .check `lean.lint } }
  let linted ← withMockEvidence lintOnly `lintPassed lintKey
    (.check { validator := `lean.lint, outcome := .passed })
  let r ← registry linted
  expect "proves: lint-only contract has no mathematical support"
    ((r.resultForRequirement lintKey).complete &&
      (r.resultFor (.translation relationKey)).status == Status.unassessed &&
      hasIssue (r.resultFor (.translation relationKey)) "missing-mathematical-support")
  let lintFailed ← withMockEvidence lintOnly `lintFailed lintKey
    (.check { validator := `lean.lint, outcome := .failed })
  let r ← registry lintFailed
  let result := r.resultFor (.translation relationKey)
  expect "proves: missing mathematical support preserves the failed check reason"
    (result.status == .unassessed && !result.localComplete &&
      hasIssue result "missing-mathematical-support" && hasIssue result "check-not-passed")

  let supportKey : RequirementKey := ⟨.translation relationKey, `own_type_support⟩
  let aliceReview : RequirementKey := ⟨.translation relationKey, `alice_mathematical_review⟩
  let supported : Input := { fixture with
    translations := fixture.translations.push <| contribution `formalProof {
      key := relationKey, kind := `proves, source := #[leanProofKey], target := #[leanKey],
      required := #[supportKey, aliceReview] }
    requirements := fixture.requirements ++ #[
      contribution `ownTypeRequirement { key := supportKey, expected := .proves leanObject },
      contribution `aliceReviewRequirement {
        key := aliceReview, expected := .review `mathematicalProof `Alice }] }
  let supported ← withMockEvidence supported `ownTypePassed supportKey mockOwnType
  let rejectedReview ← withMockEvidence supported `aliceRejected aliceReview
    (.review { criterion := `mathematicalProof, reviewer := `Alice, outcome := .failed })
  let r ← registry rejectedReview
  expect "proves: exact native support is independently complete"
    ((r.resultForRequirement supportKey).complete)
  expect "proves: required negative review still blocks conjunction"
    ((r.resultForRequirement aliceReview).status == Status.pending &&
      hasIssue (r.resultForRequirement aliceReview) "review-not-accepted" &&
      (r.resultFor (.translation relationKey)).status == Status.pending &&
      !(r.resultFor (.translation relationKey)).complete)

-- Additional claims stay conjunctive even on a native `proves` relation.
-- All observations here are explicit MOCK input to the pure admission API.
#eval show IO Unit from do
  let relationKey : TranslationKey := ⟨`fixture, `proof_with_extra_claim⟩
  let support : RequirementKey := ⟨.translation relationKey, `nativeSupport⟩
  let extraClaim : ClaimKey := ⟨relationKey, `explanation⟩
  let review : RequirementKey := ⟨.claim extraClaim, `aliceReview⟩
  let base : Input := { fixture with
    translations := fixture.translations.push <| contribution `extraProofRelation {
      key := relationKey, kind := `proves, source := #[leanProofKey], target := #[leanKey],
      required := #[support] }
    requirements := fixture.requirements.push <| contribution `extraNativeSupport {
      key := support, expected := .proves leanObject } }
  let r ← registry (← withMockEvidence base `extraNativePassed support mockOwnType)
  expect "extra claim: no extra claim is required by native own-type support"
    ((r.resultFor (.translation relationKey)).complete)
  let withClaim : Input := { base with claims := base.claims.push <| contribution `extraClaim {
    key := extraClaim, interpretation := "The proof explanation has been independently reviewed." } }
  let r ← registry (← withMockEvidence withClaim `extraNativePassed support mockOwnType)
  expect "extra claim: native support cannot fill an absent claim contract"
    ((r.resultForRequirement support).complete &&
      (r.resultFor (.claim extraClaim)).status == .unassessed &&
      (r.resultFor (.translation relationKey)).status == .unassessed)
  let contracted : Input := { withClaim with
    claims := withClaim.claims.map fun c =>
      if c.value.key == extraClaim then { c with value := { c.value with required := #[review] } } else c
    requirements := withClaim.requirements.push <| contribution `extraReviewRequirement {
      key := review, expected := .review `exposition `AliceMock } }
  let checked ← withMockEvidence contracted `extraNativePassed support mockOwnType
  let r ← registry checked
  expect "extra claim: declared review awaits a judgment"
    ((r.resultForRequirement support).complete && (r.resultFor (.translation relationKey)).status == .pending)
  for outcome in #[Outcome.failed, .passed] do
    let reviewed ← withMockEvidence checked `mockExtraReview review
      (.review { criterion := `exposition, reviewer := `AliceMock, outcome })
    let r ← registry reviewed
    expect "extra claim: only selected approval completes the conjunction"
      ((r.resultForRequirement support).complete &&
        (r.resultFor (.claim extraClaim)).complete == (outcome == .passed) &&
        (r.resultFor (.translation relationKey)).complete == (outcome == .passed))

-- A missing claim contract keeps the translation unassessed while other claims
-- retain their own rejected and blocked assessments.
#eval show IO Unit from do
  let blockedClaim : ClaimKey := ⟨translationKey, `blockedClaim⟩
  let blockedReview : RequirementKey := ⟨.claim blockedClaim, `correspondence_review⟩
  for name in #[`a_uncontracted, `z_uncontracted] do
    let uncontractedClaim : ClaimKey := ⟨translationKey, name⟩
    let input : Input := { fixture with
      claims := fixture.claims ++ #[
        contribution `blockedClaim {
          key := blockedClaim, interpretation := "Provider assessment", required := #[blockedReview] },
        contribution `uncontractedClaim { key := uncontractedClaim, interpretation := "Unassessed claim" }]
      requirements := fixture.requirements.push <| contribution `blockedReview {
        key := blockedReview, expected := .review `statement_correspondence `MockReviewer } }
    let input ← withMockEvidence input `rejectedClaimReview reviewKey
      (.review { criterion := `statement_correspondence, reviewer := `MockReviewer, outcome := .failed })
    let input ← withMockEvidence input `unavailableClaimReview blockedReview
      (.review { criterion := `statement_correspondence, reviewer := `MockReviewer, outcome := .unavailable })
    for input in #[input, reverseInput input] do
      let r ← registry input
      let rejected := r.resultFor (.claim claimKey)
      let blocked := r.resultFor (.claim blockedClaim)
      let result := r.resultFor (.translation translationKey)
      expect "mixed claims: sibling review outcomes remain independent"
        (rejected.status == .pending && hasIssue rejected "review-not-accepted" &&
          blocked.status == .blocked && hasIssue blocked "validation-unavailable" &&
          (r.resultFor (.claim uncontractedClaim)).status == .unassessed)
      expect "mixed claims: unassessed translation includes both sibling reasons"
        (result.status == .unassessed && !result.localComplete &&
          result.diagnostics == canonical (rejected.diagnostics ++ blocked.diagnostics))

-- P05/P06: independent MaxNat-shaped goal descriptors, not actual project checks.
#eval show IO Unit from do
  let ownershipGoal := { goal with fingerprint :=
    "forall k : Nat, MaxNatCoreRel.rel (uPredOwnM (M := natSI.maxNatUR) (MaxNat.mk k)) (UPred.ownM (M := Iris.MaxNat) (Iris.MaxNat.ofNat k)); packages=canonical; relation=x.car=xi.toNat" }
  let ownership : Input := { fixture with requirements := fixture.requirements.map fun c =>
    if c.value.key == proofKey then { c with value := { c.value with expected := .proof ownershipGoal leanObject } } else c }
  let full : Input := { ownership with translations := ownership.translations.map fun c =>
    { c with value := { c.value with required := #[proofKey] } } }
  let checked ← withMockEvidence full `ownership proofKey (mockProof ownershipGoal)
  let checked ← withMockEvidence checked `interpretation reviewKey mockReview
  let r ← registry checked
  expect "P05: selected ownership-shaped contract" ((r.resultFor (.translation translationKey)).complete)
  let thresholdGoal := { ownershipGoal with fingerprint := "forall k, maxNatBupdThresholdRelated k" }
  let wrong ← withMockEvidence full `threshold proofKey (mockProof thresholdGoal)
  let r ← registry wrong
  expect "P06: threshold is not ownership" (hasIssue (r.resultForRequirement proofKey) "wrong-proof")
  let conditionalGoal := { ownershipGoal with fingerprint :=
    "forall B : ResourceBridge LM IM, B.rel a ai -> B.relPred (ownM a) (ownM ai)" }
  let wrong ← withMockEvidence full `conditional proofKey (mockProof conditionalGoal)
  let r ← registry wrong
  expect "P06: missing bridge/premise instantiation" (!(r.resultForRequirement proofKey).complete)

-- P08/P16: conjunction and explicit selection, with two alternatives in one context.
#eval show IO Unit from do
  let otherObject := { leanObject with native := "Fixture.second_required_declaration" }
  let otherProof : RequirementKey := ⟨.declaration leanProofKey otherObject, `complete_proof⟩
  let otherGoal := { goal with fingerprint := "Second independently expected proposition" }
  let alternativeBase : RealizationKey := ⟨leanKey.node, `alternative⟩
  let alternativeKey := alternativeBase.forRole `proof
  let alternativeProof : RequirementKey := ⟨.declaration alternativeKey leanObject, `complete_proof⟩
  let alternative : Realization := {
    key := alternativeKey, role := `proof, context := leanContext
    declarations := #[{ object := leanObject, projection := .implementation, required := #[alternativeProof] }] }
  let input : Input := { fixture with
    objects := fixture.objects.push <| contribution `secondObject {
      key := otherObject, resolution := .resolved, document := some leanDoc }
    realizations := (fixture.realizations.map fun c =>
      if c.value.key == leanProofKey then { c with value := { c.value with
        declarations := c.value.declarations.push { object := otherObject, projection := .implementation, required := #[otherProof] } } }
      else c).push (contribution `alternative alternative)
    requirements := fixture.requirements ++ #[
      contribution `secondRequirement { key := otherProof, expected := .proof otherGoal otherObject },
      contribution `alternativeRequirement { key := alternativeProof, expected := .proof goal leanObject }] }
  let input ← withMockEvidence input `firstProof proofKey mockProof
  let input ← withMockEvidence input `alternativeProof alternativeProof mockProof
  let r ← registry input
  expect "P08: required declarations conjunctive" (!(r.resultFor (.realization leanProofKey)).complete)
  expect "P08: alternative complete independently" ((r.resultFor (.realization alternativeKey)).complete)
  match r.selectRequirement {
      node := leanKey.node, context := leanContext
      role := some `proof, requirement := `complete_proof } with
  | .error d => expect "P16: ambiguous alternative" (d.code == "ambiguous-prerequisite")
  | .ok _ => throw <| IO.userError "Ambiguous selection chose a complete alternative"
  match r.selectRequirement {
      node := leanKey.node, context := leanContext, realization := some `absent
      requirement := `complete_proof } with
  | .error d => expect "P16: missing selection" (d.code == "missing-prerequisite")
  | .ok _ => throw <| IO.userError "Missing selection succeeded"
  let input ← withMockEvidence input `secondProof otherProof (mockProof otherGoal otherObject)
  let r ← registry input
  expect "P08: all required declarations complete" ((r.resultFor (.realization leanProofKey)).complete)
  match r.selectRequirement {
      node := leanKey.node, context := leanContext
      role := some `proof, requirement := `complete_proof } with
  | .error d => expect "P16: two complete alternatives still ambiguous" (d.code == "ambiguous-prerequisite")
  | .ok _ => throw <| IO.userError "Completeness supplied an implicit alternative selection"
  let unresolvedMember : Input := { input with objects := input.objects.map fun c =>
    if c.value.key == otherObject then { c with value := { c.value with resolution := .missing } } else c }
  let r ← registry unresolvedMember
  expect "P08/P21: independent proof retained despite missing other member"
    ((r.resultForRequirement proofKey).complete &&
      (r.resultFor (.realization leanProofKey)).status == Status.blocked)

-- Reversing owned declaration order preserves the contracted sibling's reason.
#eval show IO Unit from do
  let uncontractedObject := { leanObject with native := "Fixture.uncontracted" }
  for reverse in #[false, true] do
    let input : Input := { fixture with
      objects := fixture.objects.push <| contribution `uncontractedObject {
        key := uncontractedObject, resolution := .resolved }
      realizations := fixture.realizations.map fun c =>
        if c.value.key == leanProofKey then
          let declarations := c.value.declarations.push { object := uncontractedObject }
          { c with value := { c.value with declarations := if reverse then declarations.reverse else declarations } }
        else c }
    for (outcome, status, code) in #[(Outcome.failed, Status.pending, "proof-not-complete"),
        (.unavailable, .blocked, "validation-unavailable")] do
      let observed ← withMockEvidence input `contractedProof proofKey
        (.proof { witness := leanObject, actualType := some goal, outcome, coverage := .dependencyClosure })
      let r ← registry observed
      let contracted := r.resultFor (.declaration leanProofKey leanObject)
      let result := r.resultFor (.realization leanProofKey)
      expect "mixed declarations: sibling proof outcomes remain independent"
        (contracted.status == status && hasIssue contracted code &&
          (r.resultFor (.declaration leanProofKey uncontractedObject)).status == .unassessed)
      expect "mixed declarations: unassessed realization includes the sibling reason"
        (result.status == .unassessed && !result.localComplete && result.diagnostics == contracted.diagnostics)

-- P12/P13: prerequisite cycles cannot manufacture closure; correspondence can cycle.
#eval show IO Unit from do
  let cyclic : Input := { fixture with requirements := fixture.requirements.map fun c =>
    { c with value := { c.value with prerequisites :=
      if c.value.key == proofKey then #[reviewKey] else #[proofKey] } } }
  let input ← withMockEvidence cyclic `proof proofKey mockProof
  let input ← withMockEvidence input `review reviewKey mockReview
  let r ← registry input
  for key in #[proofKey, reviewKey] do
    let result := r.resultForRequirement key
    expect "P12: local validation retained" result.localComplete
    expect "P12: cycle blocks closure" (result.status == Status.blocked && hasIssue result "requirement-cycle")
  let reverseKey : TranslationKey := ⟨`fixture, `lean_to_rocq⟩
  let reverseClaim : ClaimKey := ⟨reverseKey, `reverse_correspondence⟩
  let reverseReview : RequirementKey := ⟨.claim reverseClaim, `correspondence_review⟩
  let bidirectional : Input := { fixture with
    translations := fixture.translations.push <| contribution `reverseTranslation {
      key := reverseKey, source := #[leanKey], target := #[rocqKey] }
    claims := fixture.claims.push <| contribution `reverseClaim {
      key := reverseClaim, interpretation := "Separately reviewed reverse claim", required := #[reverseReview] }
    requirements := fixture.requirements.push <| contribution `reverseRequirement {
      key := reverseReview, expected := .review `statement_correspondence `MockReviewer } }
  let input ← withMockEvidence bidirectional `review reviewKey mockReview
  let input ← withMockEvidence input `reverseReview reverseReview mockReview
  let r ← registry input
  expect "P13: legitimate reverse correspondence" (r.translations.all fun t => (r.resultFor (.translation t.key)).complete)

-- P14/P15: pure selection/requirement controls. Existing Graph/autoDeps adapters
-- are deliberately untouched and still need their later integration regressions.
#eval show IO Unit from do
  let proseReview : RequirementKey := ⟨.realization informalKey, `proofread⟩
  let input : Input := { fixture with
    realizations := fixture.realizations.map fun c =>
      if c.value.key == informalKey then { c with value := { c.value with required := #[proseReview] } }
      else c
    requirements := (fixture.requirements.map fun c =>
      if c.value.key == reviewKey then { c with value := { c.value with prerequisites := #[proofKey] } } else c).push
      (contribution `proseRequirement { key := proseReview, expected := .review `proofreading `MockReviewer }) }
  let input ← withMockEvidence input `proseReview proseReview
    (.review { criterion := `proofreading, reviewer := `MockReviewer, outcome := .passed })
  let input ← withMockEvidence input `translationReview reviewKey mockReview
  let r ← registry input
  expect "P14: complete informal statement" ((r.resultFor (.realization informalKey)).complete)
  expect "P14: selected Lean proof still blocks" ((r.resultForRequirement reviewKey).status == Status.blocked)
  match r.selectRequirement {
      node := leanKey.node, context := leanContext, realization := some leanProofKey.name
      role := some `proof, requirement := `complete_proof } with
  | .ok selected => expect "P14: explicit default Lean proof selection" (selected == proofKey)
  | .error d => throw <| IO.userError s!"Unexpected selection failure: {repr d}"
  let cross : Input := { input with
    evidence := #[]
    requirements := input.requirements.map fun c =>
      if c.value.key == proseReview then { c with value := { c.value with prerequisites := #[proofKey] } } else c }
  let cross ← withMockEvidence cross `proseReview proseReview
    (.review { criterion := `proofreading, reviewer := `MockReviewer, outcome := .passed })
  let r ← registry cross
  expect "P15: distinct realizations of same node"
    (proseReview.subject.realization? == some informalKey && proofKey.subject.realization? == some leanProofKey &&
      informalKey.node == leanKey.node && informalKey != leanKey)
  expect "P15: genuine same-label constraint retained"
    ((r.requirement? proseReview).any (·.prerequisites == #[proofKey]) &&
      (r.resultForRequirement proseReview).localComplete && (r.resultForRequirement proseReview).status == Status.blocked)

-- P18/P20: conflicts at every semantic contract key; grouped endpoints aren't
-- expanded into pairwise claims or inferred compositions.
#eval show IO Unit from do
  let badTranslation : Input := { fixture with
    translations := fixture.translations.push <|
    contribution `conflictTranslation { fixture.translations[0]!.value with required := #[proofKey] } }
  let badClaim : Input := { fixture with
    claims := fixture.claims.push <|
    contribution `conflictClaim { fixture.claims[0]!.value with interpretation := "Incompatible relation" } }
  let badRequirement : Input := { fixture with
    requirements := fixture.requirements.push <|
    contribution `conflictRequirement { fixture.requirements[0]!.value with coverage := .dependencyClosure } }
  for input in #[badTranslation, badClaim, badRequirement] do
    expect "P18: conflicting contract" (rejectsWith input "semantic-conflict")
  let splitKey : RealizationKey := ⟨`split_target, `lean⟩
  let split : Input := { fixture with
    nodes := fixture.nodes.push <| contribution `splitNode { label := splitKey.node, title := "Split target" }
    realizations := fixture.realizations.push <| contribution `splitRealization {
      key := splitKey, role := `statement, context := leanContext, documents := #[leanDoc] }
    translations := fixture.translations.map fun c => { c with value := { c.value with target := #[leanKey, splitKey] } } }
  let r ← registry split
  expect "P20: one-to-many across nodes" (r.translations.size == 1 && r.claims.size == 1)
  expect "P20: joint group remains explicit" ((r.translation? translationKey).any (·.target.size == 2))
  let merged : Input := { split with translations := split.translations.map fun c =>
    { c with value := { c.value with source := #[leanKey, splitKey], target := #[rocqKey] } } }
  let r ← registry merged
  expect "P20: many-to-one without inferred claims" (r.translations.size == 1 && r.claims.size == 1)

-- P22: no task fields or rendered-graph dependency exist in this registry API.
#eval show IO Unit from do
  let blocked : Input := { fixture with requirements := fixture.requirements.map fun c =>
    if c.value.key == reviewKey then { c with value := { c.value with prerequisites := #[proofKey] } } else c }
  let r ← registry blocked
  expect "P22: all translations visible" (r.translations.size == 1)
  expect "P22: unfinished contains blocked" (r.unfinished.size == 1 && r.actionable.isEmpty)
  let checked ← withMockEvidence blocked `proof proofKey mockProof
  let r ← registry checked
  expect "P22: now actionable awaiting review" (r.unfinished.size == 1 && r.actionable.size == 1)

-- Independent review R1: an external obligation cannot replace validation of
-- the claim itself. The original review is genuine for its own MOCK subject.
#eval show IO Unit from do
  let otherTranslation : TranslationKey := ⟨`fixture, `other_port⟩
  let otherClaim : ClaimKey := ⟨otherTranslation, `other_claim⟩
  let borrowed : Input := { fixture with
    translations := fixture.translations.push <| contribution `otherTranslation {
      key := otherTranslation, source := #[leanKey], target := #[rocqKey] }
    claims := fixture.claims.push <| contribution `otherClaim {
      key := otherClaim, interpretation := "A different unreviewed reverse claim"
      required := #[reviewKey] } }
  expect "R1: borrowing another claim's review must fail admission"
    (rejectsWith borrowed "wrong-claim-subject")
  let siblingClaim : ClaimKey := ⟨translationKey, `unreviewed_sibling⟩
  let sibling : Input := { fixture with claims := fixture.claims.push <| contribution `siblingClaim {
    key := siblingClaim, interpretation := "Another claim in the same translation", required := #[reviewKey] } }
  expect "R1: a sibling claim's review is not local validation"
    (rejectsWith sibling "wrong-claim-subject")

-- An external review may be a prerequisite, but the second claim still needs
-- its own validation, bound to its own interpretation/assumptions/endpoints.
#eval show IO Unit from do
  let otherTranslation : TranslationKey := ⟨`fixture, `other_port⟩
  let otherClaim : ClaimKey := ⟨otherTranslation, `other_claim⟩
  let otherReview : RequirementKey := ⟨.claim otherClaim, `own_review⟩
  let input : Input := { fixture with
    translations := fixture.translations.push <| contribution `otherTranslation {
      key := otherTranslation, source := #[leanKey], target := #[rocqKey] }
    claims := fixture.claims.push <| contribution `otherClaim {
      key := otherClaim, interpretation := "Independently reviewed reverse claim", required := #[otherReview] }
    requirements := fixture.requirements.push <| contribution `otherRequirement {
      key := otherReview, expected := .review `statement_correspondence `MockReviewer, prerequisites := #[reviewKey] } }
  let reviewedOriginal ← withMockEvidence input `originalReview reviewKey mockReview
  let r ← registry reviewedOriginal
  expect "R1: external review alone leaves own claim pending"
    ((r.resultFor (.translation otherTranslation)).status == Status.pending)
  let reviewedBoth ← withMockEvidence reviewedOriginal `ownReview otherReview mockReview
  let r ← registry reviewedBoth
  expect "R1: own validation plus explicit external prerequisite completes" ((r.resultFor (.translation otherTranslation)).complete)
  let changedInterpretation : Input := { reviewedBoth with claims := reviewedBoth.claims.map fun c =>
    if c.value.key == otherClaim then { c with value := { c.value with interpretation := "Changed claim" } } else c }
  let changedAssumptions : Input := { reviewedBoth with claims := reviewedBoth.claims.map fun c =>
    if c.value.key == otherClaim then { c with value := { c.value with assumptions := #["new premise"] } } else c }
  let changedSelection : Input := { reviewedBoth with translations := reviewedBoth.translations.map fun c =>
    if c.value.key == otherTranslation then { c with value := { c.value with
      target := #[leanKey] } } else c }
  for changed in #[changedInterpretation, changedAssumptions, changedSelection] do
    let current ← registry changed
    expect "R1: own changed claim cannot retain completed translation" (!(current.resultFor (.translation otherTranslation)).complete)
    expect "R1: own review is stale" (hasIssue (current.localResult otherReview) "stale-content")
    expect "R1: original claim review remains independent"
      (current.bindingFor reviewKey == r.bindingFor reviewKey && (current.resultForRequirement reviewKey).complete)

-- Cross-node mathematical obligations remain legal and reuse one checked
-- theorem requirement/evidence for its declaration and proof realization.
#eval show IO Unit from do
  let obligationRealization := (⟨`external_obligation, `lean⟩ : RealizationKey).forRole `proof
  let obligationContext : Context := ⟨`lean, `obligations_project⟩
  let obligationDocument : DocumentKey := ⟨obligationContext, "MockExternalObligation.lean"⟩
  let obligationObject : ObjectKey := ⟨obligationContext, "Fixture.external_preservation"⟩
  let obligationRole := obligationRealization
  let obligationProof : RequirementKey := ⟨.declaration obligationRole obligationObject, `preservation⟩
  let obligationGoal : Goal := {
    context := obligationContext, fingerprint := "Independently expected preservation relation"
    documents := #[obligationDocument] }
  let obligationDeclaration : Informal.Realizations.Declaration := {
    object := obligationObject
    projection := .implementation
    required := #[obligationProof]
  }
  let input : Input := { fixture with
    nodes := fixture.nodes.push <| contribution `obligationNode {
      label := obligationRealization.node, title := "External mathematical obligation" }
    documents := fixture.documents.push <| contribution `obligationDocument {
      key := obligationDocument, text := "MOCK independent preservation theorem source" }
    objects := fixture.objects.push <| contribution `obligationObject {
      key := obligationObject, resolution := .resolved, document := some obligationDocument }
    realizations := fixture.realizations.push <| contribution `obligationRealization {
      key := obligationRole, role := `proof, context := obligationContext
      declarations := #[obligationDeclaration] }
    requirements := (fixture.requirements.map fun c =>
      if c.value.key == reviewKey then { c with value := { c.value with prerequisites := #[obligationProof] } } else c).push
      (contribution `obligationProof { key := obligationProof, expected := .proof obligationGoal obligationObject }) }
  let reviewed ← withMockEvidence input `interpretation reviewKey mockReview
  let r ← registry reviewed
  expect "R1: local review cannot skip external mathematical obligation"
    ((r.localResult reviewKey).complete && (r.resultFor (.translation translationKey)).status == Status.blocked)
  let proved ← withMockEvidence reviewed `preservation obligationProof (mockProof obligationGoal obligationObject)
  let r ← registry proved
  expect "R1: linked cross-node obligation permits completion" ((r.resultFor (.translation translationKey)).complete)
  expect "R1: one theorem validation shared across declaration and proof realization"
    ((r.resultFor (.realization obligationRole)).complete &&
      (r.resultFor (.declaration obligationRole obligationObject)).complete &&
      (r.evidence.filter fun e => match e.observation with | .proof _ => true | _ => false).size == 1)
  let changedContract : Input := { proved with requirements := proved.requirements.map fun c =>
    if c.value.key == obligationProof then { c with value := { c.value with
      expected := .proof { obligationGoal with fingerprint := "Changed preservation proposition" } obligationObject } } else c }
  let current ← registry changedContract
  expect "R1/P10: changing prerequisite content leaves local review current but blocks closure"
    ((current.localResult reviewKey).complete && current.bindingFor reviewKey == r.bindingFor reviewKey &&
      hasIssue (current.resultForRequirement obligationProof) "stale-content" &&
      !(current.resultFor (.translation translationKey)).complete)

/-- MOCK inputs reproducing the proof-only missing helper. No canonical sources
are checked. The original proof requirement is owned by the proof realization and declaration. -/
def withMissingProofHelper : IO Input := do
  let helper := { leanObject with native := "Fixture.proof_only_helper" }
  let helperProof : RequirementKey := ⟨.declaration leanProofKey helper, `complete_proof⟩
  let helperGoal : Goal := { goal with fingerprint := "Helper proposition" }
  let helperDeclaration : Informal.Realizations.Declaration := {
    object := helper
    projection := .implementation
    required := #[helperProof]
  }
  let input : Input := { fixture with
    realizations := fixture.realizations.map fun c =>
      if c.value.key == leanProofKey then { c with value := { c.value with
        declarations := c.value.declarations.push helperDeclaration } } else c
    requirements := fixture.requirements.push <| contribution `helperRequirement {
      key := helperProof, expected := .proof helperGoal helper } }
  let input ← withMockEvidence input `goodProof proofKey mockProof
  withMockEvidence input `currentReview reviewKey mockReview

-- Independent review R2: whole-realization availability must not leak into a
-- declaration query or a statement-only endpoint selection.
#eval show IO Unit from do
  let base ← withMissingProofHelper
  let r ← registry base
  expect "R2: original local proof retained" ((r.resultForRequirement proofKey).complete)
  expect "R2: available declaration remains complete" ((r.resultFor (.declaration leanProofKey leanObject)).complete)
  expect "R2: selected statement port remains complete" ((r.resultFor (.translation translationKey)).complete)
  expect "R2: required proof work remains blocked" ((r.resultFor (.realization leanProofKey)).status == Status.blocked)
  expect "R2: statement realization without its own contract remains unassessed"
    ((r.resultFor (.realization leanKey)).status == Status.unassessed)
  let proofTarget : Input := { base with translations := base.translations.map fun c =>
    { c with value := { c.value with target := #[{ realization := leanProofKey }] } } }
  let proofTarget ← withMockEvidence proofTarget `selectedReview reviewKey mockReview
  let current ← registry proofTarget
  expect "R2: selecting the proof realization retains its missing-helper blocker"
    ((current.resultFor (.translation translationKey)).status == Status.blocked &&
      (current.resultFor (.declaration leanProofKey leanObject)).complete)

-- A current-selection conflict remains pending with available content and is
-- still reported when unrelated source unavailability blocks the assessment.
#eval show IO Unit from do
  let conflicting : Input := { fixture with reviewSelections := #[
    contribution `firstCurrentReview { requirement := reviewKey, judgment := some `firstJudgment },
    contribution `secondCurrentReview { requirement := reviewKey, judgment := some `secondJudgment }] }
  let available ← registry conflicting
  expect "review selection conflict with available content stays pending"
    ((available.localResult reviewKey).status == Status.pending &&
      hasIssue (available.localResult reviewKey) "conflicting-review-selections")
  let unavailableDocuments := conflicting.documents.map fun c =>
    if c.value.key == rocqDoc then { c with value := { c.value with text := "" } } else c
  let unavailableInput := { conflicting with documents := unavailableDocuments }
  let unavailable ← registry unavailableInput
  expect "review selection conflict remains visible alongside unavailable content"
    ((unavailable.localResult reviewKey).status == Status.blocked &&
      hasIssue (unavailable.localResult reviewKey) "conflicting-review-selections" &&
      hasIssue (unavailable.localResult reviewKey) "content-unavailable")

-- Independent review R3: nonempty endpoint IDs/role names are not content.
#eval show IO Unit from do
  let empty : Input := { fixture with
    realizations := fixture.realizations.map fun c =>
      if c.value.key == leanKey || c.value.key == rocqKey || c.value.key == leanProofKey then
        { c with value := { c.value with documents := #[], declarations := #[], required := #[] } }
      else c
    requirements := fixture.requirements.filter (·.value.key == reviewKey)
    bindingInputs := #[] }
  let input ← withMockEvidence empty `emptyReview reviewKey mockReview
  let r ← registry input
  let result := r.resultFor (.translation translationKey)
  expect "R3: current review cannot complete content-free selected endpoints"
    (!result.complete && hasIssue result "content-unavailable")

-- Unselected content and the other endpoint cannot rescue an empty selected
-- realization; existing canonical documents must themselves contain source bytes.
#eval show IO Unit from do
  for emptyKey in #[rocqKey, leanKey] do
    let emptySubject : Subject :=
      if emptyKey == rocqKey then .declaration rocqKey rocqObject
      else .declaration leanKey leanObject
    let emptySelected : Input := { fixture with
      realizations := (fixture.realizations.map fun c =>
        if c.value.key == emptyKey then { c with value := { c.value with documents := #[], declarations := #[] } } else c)
      bindingInputs := fixture.bindingInputs.filter (·.value.subject != emptySubject)
    }
    let input ← withMockEvidence emptySelected `emptySelectedReview reviewKey mockReview
    let r ← registry input
    expect "R3: unrelated proof content or other endpoint cannot fill selected statement"
      (!(r.resultFor (.translation translationKey)).complete && hasIssue (r.localResult reviewKey) "content-unavailable")
  let whitespace : Input := { fixture with documents := fixture.documents.map fun c =>
    if c.value.key == rocqDoc then { c with value := { c.value with text := " \n\t" } } else c }
  let input ← withMockEvidence whitespace `whitespaceReview reviewKey mockReview
  let r ← registry input
  expect "R3: empty canonical bytes do not supply selected content"
    (!(r.resultFor (.translation translationKey)).complete && hasIssue (r.localResult reviewKey) "content-unavailable")
  -- A Lean declaration's content is established by the environment, not by a
  -- document: blank bytes do not block it, a missing semantic descriptor does.
  let leanWhitespace : Input := { fixture with documents := fixture.documents.map fun c =>
    if c.value.key == leanDoc then { c with value := { c.value with text := " \n\t" } } else c }
  let input ← withMockEvidence leanWhitespace `leanWhitespaceReview reviewKey mockReview
  let r ← registry input
  expect "R3: a Lean declaration needs no document bytes"
    ((r.localResult reviewKey).complete && !hasIssue (r.localResult reviewKey) "content-unavailable")
  -- The MOCK evidence helper supplies missing descriptors, so remove it afterwards.
  let input ← withMockEvidence fixture `noDescriptorReview reviewKey mockReview
  let r ← registry { input with
    bindingInputs := input.bindingInputs.filter (·.value.subject != .declaration leanKey leanObject) }
  expect "R3: a selected Lean declaration still needs its semantic descriptor"
    (!(r.localResult reviewKey).complete && hasIssue (r.localResult reviewKey) "semantic-context-unavailable")
  let noStatements : Input := { fixture with
    realizations := (fixture.realizations.map fun c =>
      if c.value.key == leanKey || c.value.key == rocqKey then
        { c with value := { c.value with documents := #[], declarations := #[] } } else c)
    bindingInputs := (fixture.bindingInputs.filter fun c =>
      c.value.subject != (.declaration leanKey leanObject) &&
      c.value.subject != (.declaration rocqKey rocqObject))
  }
  let correspondenceDocument : DocumentKey := ⟨leanContext, "MockCorrespondence.lean"⟩
  let correspondenceObject : ObjectKey := ⟨leanContext, "Fixture.correspondence"⟩
  let correspondenceGoal : Goal := {
    context := leanContext, fingerprint := "MOCK formal correspondence proposition"
    documents := #[correspondenceDocument] }
  let proofContract : Input := { noStatements with
    documents := noStatements.documents.push <| contribution `correspondenceDocument {
      key := correspondenceDocument, text := "MOCK independent correspondence witness source" }
    objects := noStatements.objects.push <| contribution `correspondenceObject {
      key := correspondenceObject, resolution := .resolved, document := some correspondenceDocument }
    requirements := noStatements.requirements.map fun c =>
      if c.value.key == reviewKey then { c with value := { c.value with
        expected := .proof correspondenceGoal correspondenceObject } } else c }
  let input ← withMockEvidence proofContract `correspondenceProof reviewKey (mockProof correspondenceGoal correspondenceObject)
  let input ← withMockEvidence input `localWitness proofKey mockProof
  let r ← registry input
  expect "R3: even a claim-owned proof needs actual selected content"
    (!(r.resultForRequirement reviewKey).complete && hasIssue (r.localResult reviewKey) "content-unavailable")
  expect "R3: independent local theorem proof remains checked" ((r.resultForRequirement proofKey).complete)

-- Formal content can come from a declaration's canonical source: no duplicate
-- prose document or second checked theorem is needed for statement/proof views.
#eval show IO Unit from do
  let declarationBacked : Input := { fixture with realizations := fixture.realizations.map fun c =>
    if c.value.key == leanKey || c.value.key == rocqKey || c.value.key == leanProofKey then { c with value := { c.value with documents := #[] } } else c }
  let input ← withMockEvidence declarationBacked `declarationReview reviewKey mockReview
  let r ← registry input
  expect "R3: selected statement declarations provide content without prose documents"
    ((r.resultFor (.translation translationKey)).complete && !(r.resultForRequirement proofKey).complete)
  let input ← withMockEvidence input `sharedProof proofKey mockProof
  let r ← registry input
  expect "R2/R3: one proof requirement supports its existing declaration and realization"
    ((r.resultFor (.declaration leanProofKey leanObject)).complete && (r.resultFor (.realization leanProofKey)).complete)
  let wholeDeclaration : Input := { fixture with
    realizations := fixture.realizations.map fun c =>
      if c.value.key == leanKey || c.value.key == rocqKey || c.value.key == leanProofKey then
        { c with value := { c.value with documents := #[], declarations := c.value.declarations.map fun d => { d with required := #[] } } } else c
    requirements := fixture.requirements.filter (·.value.key == reviewKey)
    bindingInputs := fixture.bindingInputs.filter (·.value.name == NativeLean.sourceContext)
    translations := fixture.translations.map fun c => { c with value := { c.value with source := #[rocqKey], target := #[leanKey] } } }
  let input ← withMockEvidence wholeDeclaration `wholeReview reviewKey mockReview
  let r ← registry input
  expect "R3: whole formal realization can use declarations without invented roles" ((r.resultFor (.translation translationKey)).complete)

-- Declaration ownership references existing associations and is checked at admission.
#eval show IO Unit from do
  let unknown := { leanObject with native := "Fixture.not_associated" }
  let bad : Input := { fixture with realizations := fixture.realizations.map fun c =>
    if c.value.key == leanKey then { c with value := { c.value with
      declarations := #[{ object := unknown, projection := .statement }] } } else c }
  expect "R2: stale semantic descriptors cannot follow a declaration to another owner"
    (rejectsWith bad "invalid-binding-input")

-- A declaration subject fixes the witness even if a realization or prerequisite
-- refers to the contract without listing it in the declaration's required array.
#eval show IO Unit from do
  let sibling := { leanObject with native := "Fixture.other_theorem" }
  let input : Input := { fixture with
    objects := fixture.objects.push <| contribution `otherTheorem {
      key := sibling, resolution := .resolved }
    requirements := fixture.requirements.map fun record =>
      if record.value.key == reviewKey then
        { record with value.prerequisites := #[proofKey] }
      else record }
  for (onDeclaration, onRealization) in #[(true, false), (false, true), (false, false)] do
    let declarations : Array Informal.Realizations.Declaration := #[{
      object := leanObject, projection := .implementation
      required := if onDeclaration then #[proofKey] else #[] },
      { object := sibling, projection := .implementation }]
    let attached : Input := { input with realizations := input.realizations.map fun record =>
      if record.value.key == leanProofKey then
        { record with value := { record.value with
          required := if onRealization then #[proofKey] else #[]
          declarations } }
      else record }
    let checked ← withMockEvidence attached `checkedOwnWitness proofKey mockProof
    let registry ← registry checked
    expect "declaration proof: the exact owned witness passes through every attachment path"
      (registry.resultForRequirement proofKey).complete
    let wrongWitness : Input := { checked with requirements := checked.requirements.map fun record =>
      if record.value.key == proofKey then
        { record with value.expected := .proof goal sibling }
      else record }
    expect "declaration proof: a resolved sibling cannot supply the witness through any attachment path"
      (rejectsWith wrongWitness "wrong-witness")

-- Realization-scoped proof evidence needs an owned witness before it can
-- discharge the downstream prerequisite, even if the object resolved globally.
#eval show IO Unit from do
  let unowned := { leanObject with native := "Fixture.unowned_theorem" }
  let ownProof : RequirementKey := ⟨.realization leanProofKey, `realization_proof⟩
  let input : Input := { fixture with
    objects := fixture.objects.push <| contribution `unownedWitness {
      key := unowned, resolution := .resolved }
    realizations := fixture.realizations.map fun record =>
      if record.value.key == leanProofKey then { record with value.required := #[ownProof] } else record
    requirements := fixture.requirements.map fun record =>
      if record.value.key == reviewKey then
        { record with value.prerequisites := #[ownProof] }
      else record }
  for (witness, owned) in #[(leanObject, true), (unowned, false)] do
    let contract := contribution `realizationProof { key := ownProof, expected := .proof goal witness }
    let input := { input with requirements := input.requirements.push contract }
    let checked ← withMockEvidence input `checkedRealizationWitness ownProof (mockProof goal witness)
    let reviewed ← withMockEvidence checked `reviewWithProofPrerequisite reviewKey mockReview
    let registry ← registry reviewed
    let proof := registry.resultForRequirement ownProof
    expect "realization proof: only an owned witness discharges its contract and downstream prerequisite"
      (proof.complete == owned &&
        (registry.localResult reviewKey).complete &&
        (registry.resultForRequirement reviewKey).complete == owned)
    unless owned do
      expect "realization proof: missing ownership is a source diagnostic"
        (proof.status == .blocked && hasIssue proof "unknown-declaration" &&
          hasIssue proof "witness-unavailable")

-- A relation's foreign witness and separately named goal source are selected
-- alongside the endpoints. All proof observations in this fixture are mocks.
#eval show IO Unit from do
  let witness := { rocqObject with native := "Foreign.externalProof" }
  let witnessDoc : DocumentKey := ⟨rocqContext, "ExternalProof.v"⟩
  let goalDoc : DocumentKey := ⟨rocqContext, "GoalOnly.v"⟩
  let goal := { goal with context := rocqContext, documents := #[goalDoc] }
  let foreignProof : RequirementKey := ⟨.claim claimKey, `foreignProof⟩
  let input : Input := { fixture with
    documents := fixture.documents ++ #[
      contribution `foreignProofSource { key := witnessDoc, text := "MOCK old witness proof" },
      contribution `foreignGoalSource { key := goalDoc, text := "MOCK separately authored goal" }]
    objects := fixture.objects.push (contribution `foreignWitness {
      key := witness, resolution := .resolved, document := some witnessDoc })
    claims := fixture.claims.map fun record => { record with value.required := #[foreignProof] }
    requirements := fixture.requirements.push (contribution `foreignProof {
      key := foreignProof, expected := .proof goal witness }) }
  let input ← withMockEvidence input `boundNativeProof proofKey mockProof
  let input ← withMockEvidence input `boundForeignProof foreignProof (mockProof goal witness)
  let before ← registry input
  expect "foreign witness: original evidence completes the claim and translation"
    ((before.resultForRequirement foreignProof).complete && (before.resultFor (.translation translationKey)).complete)
  let edit (key : DocumentKey) (text : String) : Input :=
    { input with documents := input.documents.map fun record =>
      if record.value.key == key then { record with value.text := text } else record }
  let changed ← registry (edit witnessDoc "MOCK different witness proof")
  let relocatedDoc := { witnessDoc with path := "relocated/ExternalProof.v" }
  let relocated ← registry { input with
    documents := input.documents.map fun record =>
      if record.value.key == witnessDoc then { record with value.key := relocatedDoc } else record
    objects := input.objects.map fun record =>
      if record.value.key == witness then { record with value.document := some relocatedDoc } else record }
  for current in #[changed, relocated] do
    let result := current.resultForRequirement foreignProof
    expect "foreign witness: bytes and identity each stale a previously checked proof"
      (current.bindingFor foreignProof != before.bindingFor foreignProof &&
        result.status == .pending && hasIssue result "stale-content" &&
        !(current.resultFor (.translation translationKey)).complete &&
        current.bindingFor proofKey == before.bindingFor proofKey &&
        (current.resultForRequirement proofKey).complete)
  let emptyGoal ← registry (edit goalDoc " ")
  let proof := emptyGoal.resultForRequirement foreignProof
  expect "foreign proof: empty selected goal source blocks current assessment"
    (proof.status == .blocked && hasIssue proof "content-unavailable" &&
      !hasIssue proof "witness-unavailable" &&
      emptyGoal.bindingFor foreignProof != before.bindingFor foreignProof &&
      (emptyGoal.resultFor (.translation translationKey)).status == .blocked)
  let emptyWitness ← registry (edit witnessDoc "")
  let proof := emptyWitness.resultForRequirement foreignProof
  expect "foreign proof: empty witness source retains the exact witness diagnostic"
    (proof.status == .blocked && hasIssue proof "content-unavailable" && hasIssue proof "witness-unavailable")

-- A proof scoped to the realization selects the whole owner. A separate
-- declaration-local proof still selects only its witness. Both are mock checks.
#eval show IO Unit from do
  let jointProof : RequirementKey := ⟨.realization leanProofKey, `jointProof⟩
  let extraDoc : DocumentKey := ⟨leanContext, "OwnedExtra.lean"⟩
  let sibling := { leanObject with native := "Fixture.sibling" }
  let siblingIssue : Diagnostic := {
    code := "sibling-source-unavailable", subject := sibling.native
    message := "MOCK selected sibling source is unavailable" }
  let input : Input := { fixture with
    documents := fixture.documents.push (contribution `extraSource {
      key := extraDoc, text := "MOCK source selected by the whole realization" })
    objects := fixture.objects.push (contribution `siblingObject { key := sibling, resolution := .resolved })
    bindingInputs := fixture.bindingInputs.push (contribution `siblingSemantics {
      subject := .declaration leanProofKey sibling, name := NativeLean.sourceContext
      content := "MOCK selected sibling implementation semantics" })
    realizations := fixture.realizations.map fun record =>
      if record.value.key != leanProofKey then record else { record with value := {
        record.value with
        documents := #[extraDoc], required := #[jointProof]
        declarations := record.value.declarations.push { object := sibling } } }
    requirements := (fixture.requirements.map fun record =>
      if record.value.key == reviewKey then { record with value.prerequisites := #[jointProof] }
      else record).push (contribution `jointRequirement { key := jointProof, expected := .proof goal leanObject }) }
  let input ← withMockEvidence input `localProofPassed proofKey mockProof
  let input ← withMockEvidence input `jointProofPassed jointProof mockProof
  let input ← withMockEvidence input `reviewPassed reviewKey mockReview
  let before ← registry input
  expect "realization proof: available owner and sibling allow the proof and dependent review"
    ((before.resultForRequirement jointProof).complete && (before.resultForRequirement reviewKey).complete)
  let emptyDoc : Input := { input with documents := input.documents.map fun record =>
    if record.value.key == extraDoc then { record with value.text := "" } else record }
  let badSibling : Input := { input with realizations := input.realizations.map fun record =>
    if record.value.key != leanProofKey then record else { record with value := {
      record.value with declarations := record.value.declarations.map fun declaration =>
        if declaration.object == sibling then { declaration with sourceIssues := #[siblingIssue] }
        else declaration } } }
  for (candidate, issue) in #[(emptyDoc, "content-unavailable"), (badSibling, siblingIssue.code)] do
    let current ← registry candidate
    let joint := current.resultForRequirement jointProof
    let downstream := current.resultForRequirement reviewKey
    expect "realization proof: unavailable owner content blocks proof and dependent review"
      ((current.resultFor (.realization leanProofKey)).status == .blocked &&
        joint.status == .blocked && hasIssue joint issue && !hasIssue joint "witness-unavailable" &&
        (current.localResult reviewKey).complete && downstream.status == .blocked &&
        hasIssue downstream "unfinished-prerequisite")
    expect "declaration proof: selected sibling and whole-owner document do not widen a native proof"
      (current.bindingFor proofKey == before.bindingFor proofKey && (current.resultForRequirement proofKey).complete)

-- Prerequisite order and repetition are irrelevant to the contract, while
-- producer replay still checks the original records exactly.
#eval show IO Unit from do
  let set := canonical #[proofKey, relationReviewKey]
  let baseline : Input := { fixture with requirements := fixture.requirements.map fun record =>
    if record.value.key == reviewKey then { record with value.prerequisites := set } else record }
  let checked ← withMockEvidence baseline `normalizedProof proofKey mockProof
  let checked ← withMockEvidence checked `normalizedRelationReview relationReviewKey mockReview
  let checked ← withMockEvidence checked `normalizedClaimReview reviewKey mockReview
  let before ← registry checked
  let repeated := set.reverse.push proofKey
  let original ← match checked.requirements.find? (·.value.key == reviewKey) with
    | some record => pure record
    | none => throw <| IO.userError "Missing prerequisite normalization fixture"
  let equivalent := contribution `equivalentClaimReview { original.value with prerequisites := repeated }
  let merged : Input := { checked with requirements := checked.requirements.push equivalent }
  for candidate in #[merged, reverseInput merged] do
    let admitted ← registry candidate
    expect "prerequisites: order and repetition do not change the contract or its binding"
      (admitted.requirements == before.requirements &&
        (admitted.requirement? reviewKey).any (·.prerequisites == set) &&
        admitted.bindingFor reviewKey == before.bindingFor reviewKey &&
        (admitted.resultForRequirement reviewKey).complete)
    expect "prerequisites: inspection retains all original producer records"
      (admitted.contributions.requirements == candidate.requirements)
  let different := { equivalent with value.prerequisites := #[proofKey] }
  let collision := { original with value.prerequisites := repeated }
  expect "prerequisites: changing the set still conflicts"
    (rejectsWith { checked with requirements := checked.requirements.push different } "semantic-conflict")
  expect "prerequisites: one producer cannot replay a different raw record"
    (rejectsWith { checked with requirements := checked.requirements.push collision } "producer-collision")

-- Pilot relocation boundary: these are MOCK observations, not replayed Rocq or
-- Lean checks. Today DocumentKey.path participates in identity and bindings.
#eval show IO Unit from do
  let downstream : TranslationKey := ⟨`fixture, `dependent_port⟩
  let downstreamClaim : ClaimKey := ⟨downstream, `correspondence⟩
  let downstreamReview : RequirementKey := ⟨.claim downstreamClaim, `correspondence_review⟩
  let input : Input := { fixture with
    translations := fixture.translations.push <| contribution `dependentTranslation {
      key := downstream, source := #[rocqKey], target := #[leanKey] }
    claims := fixture.claims.push <| contribution `dependentClaim {
      key := downstreamClaim, interpretation := "Dependent MOCK relation", required := #[downstreamReview] }
    requirements := fixture.requirements.push <| contribution `dependentReview {
      key := downstreamReview, expected := .review `statement_correspondence `MockReviewer, prerequisites := #[reviewKey] } }
  let input ← withMockEvidence input `nativeProof proofKey mockProof
  let input ← withMockEvidence input `upstreamReview reviewKey mockReview
  let input ← withMockEvidence input `downstreamReview downstreamReview mockReview
  let before ← registry input
  expect "pilot: initial contracts complete"
    ((before.resultFor (.translation translationKey)).complete && (before.resultFor (.translation downstream)).complete)
  -- Change only the Rocq document key and every reference to it. Preserve bytes,
  -- semantic inputs, authored relations, requirement identities and old evidence.
  let moved := { rocqDoc with path := "relocated/MockFlag.v" }
  let relocate (key : DocumentKey) := if key == rocqDoc then moved else key
  let relocated : Input := { input with
    documents := input.documents.map fun c => { c with value := { c.value with key := relocate c.value.key } }
    objects := input.objects.map fun c => { c with value := { c.value with document := c.value.document.map relocate } }
    realizations := input.realizations.map fun c => { c with value := { c.value with
      documents := c.value.documents.map relocate } } }
  let after ← registry relocated
  expect "pilot: untouched native proof remains complete" ((after.resultForRequirement proofKey).complete)
  for key in #[reviewKey, downstreamReview] do
    expect "pilot: changed identity makes old review locally stale"
      (after.bindingFor key != before.bindingFor key &&
        (after.localResult key).status == .pending && hasIssue (after.localResult key) "stale-content")
  expect "pilot: upstream pending, downstream blocked"
    ((after.resultFor (.translation translationKey)).status == .pending &&
      (after.resultFor (.translation downstream)).status == .blocked)
  expect "pilot: only upstream translation actionable"
    (after.actionable.map (·.key) == #[translationKey])
  -- Fresh provider output is not a replacement correspondence review.
  let rechecked ← withMockEvidence relocated `freshNativeProof proofKey mockProof
  let current ← registry rechecked
  expect "pilot: native checking cannot renew reviews"
    ((current.localResult reviewKey).status == .pending && (current.localResult downstreamReview).status == .pending)

-- Logical project namespaces already distinguish equal document path spellings.
#eval show IO Unit from do
  let other := { leanDoc with context := { leanContext with project := `otherPackage } }
  let input := { fixture with documents := fixture.documents.push <| contribution `otherPackageDoc {
    key := other, text := "MOCK distinct project source" } }
  let r ← registry input
  expect "pilot: same path in different projects is distinct"
    (other != leanDoc && r.documents.size == fixture.documents.size + 1)
  let conflicting := { input with documents := input.documents.push <| contribution `conflictingDocument {
    key := leanDoc, text := "MOCK changed bytes under the same identity" } }
  expect "pilot: conflicting bytes under one identity reject atomically"
    (rejectsWith conflicting "semantic-conflict")

-- Direct selected content controls review identity. A proof used only as a
-- completion prerequisite is checked independently; selecting that proof as an
-- endpoint makes its content part of the reviewed claim. All facts are MOCKS.
#eval show IO Unit from do
  -- The statement endpoint is reviewed; the separately owned proof is only a
  -- prerequisite to completion.
  let statementInput : Input := { fixture with
    translations := (fixture.translations.map fun c =>
      { c with value := { c.value with target := #[{ realization := leanKey }] } })
    requirements := (fixture.requirements.map fun c =>
      if c.value.key == reviewKey then { c with value := { c.value with prerequisites := #[proofKey] } }
      else c)
  }
  let input ← withMockEvidence statementInput `selectedProof proofKey mockProof
  let input ← withMockEvidence input `selectedStatementReview reviewKey mockReview
  let before ← registry input
  expect "selection: current statement review and proof prerequisite complete"
    ((before.localResult reviewKey).complete && (before.resultFor (.translation translationKey)).complete)
  let proofOnly : Input := { input with bindingInputs := input.bindingInputs.map fun c =>
    if (c.value.subject == .declaration leanProofKey leanObject && c.value.name == NativeLean.sourceContext) ||
        (c.value.subject == proofKey.subject && c.value.name == NativeLean.expectedContextFor proofKey) then
      { c with value := { c.value with content := c.value.content ++ " own proof changed" } } else c }
  let after ← registry proofOnly
  expect "selection: proof-only prerequisite change preserves statement review binding"
    (after.bindingFor reviewKey == before.bindingFor reviewKey && (after.localResult reviewKey).complete)
  expect "selection: changed proof check is stale and still gates completion"
    (!(after.resultForRequirement reviewKey).complete && !(after.localResult proofKey).complete)
  let statementOnly : Input := { input with bindingInputs := input.bindingInputs.map fun c =>
    if c.value.subject == (.declaration leanKey leanObject) && c.value.name == NativeLean.statementContext then
      { c with value := { c.value with content := c.value.content ++ " statement changed" } } else c }
  let statementChanged ← registry statementOnly
  expect "selection: selected statement edit invalidates review"
    (statementChanged.bindingFor reviewKey != before.bindingFor reviewKey &&
      hasIssue (statementChanged.localResult reviewKey) "stale-content")
  let missing : Input := { input with bindingInputs := input.bindingInputs.filter fun c =>
    !(c.value.subject == .declaration leanKey leanObject && c.value.name == NativeLean.statementContext) }
  let missing ← registry missing
  expect "selection: missing selected statement semantics cannot accept review"
    ((missing.localResult reviewKey).status == .blocked &&
      hasIssue (missing.localResult reviewKey) "semantic-context-unavailable")
  -- The native declaration selection is interpreted by its checked statement
  -- descriptor; changing the file's incidental bytes adds no second selection.
  let proseBefore ← registry input
  let proseAfter ← registry { input with documents := input.documents.map fun c =>
    if c.value.key == leanDoc then { c with value := { c.value with text := "MOCK changed document-only source" } } else c }
  expect "selection: native statement semantics replace incidental file bytes"
    (proseBefore.bindingFor reviewKey == proseAfter.bindingFor reviewKey)
  -- Unknown facts remain conservative on selected subjects. The separate proof
  -- realization is not selected merely because its requirement gates completion.
  for (subject, selected) in #[(Subject.declaration leanKey leanObject, true),
      (.realization leanKey, true), (.realization leanProofKey, false)] do
    let custom := contribution `customProviderInput {
      subject, name := `customProvider.policy, content := "MOCK policy A" }
    let withCustom : Input := { input with bindingInputs := input.bindingInputs.push custom }
    let customBefore ← registry withCustom
    for replacement in #[{ custom.value with content := "MOCK policy B" },
        { custom.value with name := `customProvider.otherPolicy }] do
      let changed := { input with bindingInputs := input.bindingInputs.push { custom with value := replacement } }
      let customAfter ← registry changed
      expect "selection: provider facts bind only when their realization is selected"
        ((customBefore.bindingFor reviewKey != customAfter.bindingFor reviewKey) == selected)
  -- What a dependency selected is another node's shape. It binds its own
  -- selection contract and never a review of the selected statement.
  let selectionKey : RequirementKey := ⟨.declaration leanKey leanObject, `statement ++ `dependencySelection⟩
  let selection (content : String) : Input := { input with
    requirements := input.requirements.push <| contribution `selectionContract {
      key := selectionKey, expected := .check dependencySelectionValidator }
    bindingInputs := input.bindingInputs.push <| contribution `selectionDescriptor {
      subject := selectionKey.subject, name := selectedUsesFor selectionKey, content } }
  let selectedTheorem ← registry (selection "MOCK dependency selects a theorem")
  let selectedDefinition ← registry (selection "MOCK dependency selects a definition")
  expect "selection: a dependency's selected target does not stale the statement review"
    (selectedTheorem.bindingFor reviewKey == before.bindingFor reviewKey &&
      selectedDefinition.bindingFor reviewKey == before.bindingFor reviewKey)
  expect "selection: a dependency's selected target binds its own selection contract"
    (selectedTheorem.bindingFor selectionKey != selectedDefinition.bindingFor selectionKey)
  -- A subject cannot publish a reference to a contract nobody supplied. In the
  -- base fixture only the proof declaration's `required` list names `proofKey`.
  let noProofContract : Input := { fixture with
    requirements := fixture.requirements.filter (·.value.key != proofKey) }
  expect "selection: the removed contract is referenced by no prerequisite"
    (!(noProofContract.requirements.any (·.value.prerequisites.contains proofKey)))
  expect "selection: a required contract must exist in the same admitted input"
    (match admit noProofContract with
      | .ok _ => false
      | .error issues => issues.any fun issue => issue.code == "unknown-requirement" &&
          issue.subject == (toJson proofKey).compress && issue.message == "Missing contract requirement")
  let sibling : RequirementKey := ⟨.claim claimKey, `independent_review⟩
  let siblingContract := contribution `siblingReview { key := sibling, expected := .review `independent `MockReviewer }
  let withSibling : Input := { input with
    claims := input.claims.map fun c =>
      if c.value.key == claimKey then { c with value := { c.value with required := #[reviewKey, sibling] } } else c
    requirements := input.requirements.push siblingContract }
  let siblingRegistry ← registry withSibling
  expect "selection: adding a sibling obligation does not stale the local review"
    (siblingRegistry.bindingFor reviewKey == before.bindingFor reviewKey)
  let noteKey := (⟨leanKey.node, `unselected_notes⟩ : RealizationKey).forRole `account
  let noteModel : Informal.Realizations.Realization := {
    key := noteKey
    role := `account
    context := leanContext
    documents := #[leanDoc]
  }
  let noteContribution := contribution `unselectedNotes noteModel
  let unselected : Input := { input with realizations := input.realizations.push noteContribution }
  let unselected ← registry unselected
  expect "selection: unselected realization does not disturb endpoint review"
    (unselected.bindingFor reviewKey == before.bindingFor reviewKey)
  let explicitProofSelection : Input := { input with translations := input.translations.map fun c =>
    if c.value.key == translationKey then { c with value := { c.value with target := #[leanProofKey] } } else c }
  let proofBinding ← registry explicitProofSelection
  expect "selection: direct proof endpoint binds proof content"
    (proofBinding.bindingFor reviewKey != before.bindingFor reviewKey)

end VersoBlueprintTests.BlueprintTranslations
