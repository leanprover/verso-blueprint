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

-- P05/P06: independent MaxNat-shaped goal descriptors, not actual project checks.
#eval show IO Unit from do
  let ownershipGoal := { goal with proposition :=
    "forall k : Nat, MaxNatCoreRel.rel (uPredOwnM (M := natSI.maxNatUR) (MaxNat.mk k)) (UPred.ownM (M := Iris.MaxNat) (Iris.MaxNat.ofNat k)); packages=canonical; relation=x.car=xi.toNat" }
  let ownership : Input := { fixture with requirements := fixture.requirements.map fun c =>
    if c.value.key == proofKey then { c with value := { c.value with expected := .proof ownershipGoal leanObject } } else c }
  let full : Input := { ownership with translations := ownership.translations.map fun c =>
    { c with value := { c.value with required := #[proofKey] } } }
  let checked ← withMockEvidence full `ownership proofKey (mockProof ownershipGoal)
  let checked ← withMockEvidence checked `interpretation reviewKey mockReview
  let r ← registry checked
  expect "P05: selected ownership-shaped contract" ((r.resultFor (.translation translationKey)).complete)
  let thresholdGoal := { ownershipGoal with proposition := "forall k, maxNatBupdThresholdRelated k" }
  let wrong ← withMockEvidence full `threshold proofKey (mockProof thresholdGoal)
  let r ← registry wrong
  expect "P06: threshold is not ownership" (hasIssue (r.resultForRequirement proofKey) "wrong-proof")
  let conditionalGoal := { ownershipGoal with proposition :=
    "forall B : ResourceBridge LM IM, B.rel a ai -> B.relPred (ownM a) (ownM ai)" }
  let wrong ← withMockEvidence full `conditional proofKey (mockProof conditionalGoal)
  let r ← registry wrong
  expect "P06: missing bridge/premise instantiation" (!(r.resultForRequirement proofKey).complete)

-- P08/P16: conjunction and explicit selection, with two alternatives in one context.
#eval show IO Unit from do
  let otherObject := { leanObject with native := "Fixture.second_required_declaration" }
  let otherProof : RequirementKey := ⟨.declaration leanKey otherObject, `complete_proof⟩
  let otherGoal := { goal with proposition := "Second independently expected proposition" }
  let alternativeKey : RealizationKey := ⟨leanKey.node, `alternative⟩
  let alternativeProof : RequirementKey := ⟨.facet alternativeKey `proof, `complete_proof⟩
  let alternative : Realization := {
    key := alternativeKey, context := leanContext
    facets := #[{ name := `proof, documents := #[leanDoc], required := #[alternativeProof] }]
    declarations := #[{ object := leanObject, required := #[alternativeProof] }] }
  let input : Input := { fixture with
    objects := fixture.objects.push <| contribution `secondObject {
      key := otherObject, resolution := .resolved, document := some leanDoc }
    realizations := (fixture.realizations.map fun c =>
      if c.value.key == leanKey then { c with value := { c.value with
        declarations := c.value.declarations.push { object := otherObject, required := #[otherProof] } } }
      else c).push (contribution `alternative alternative)
    requirements := fixture.requirements ++ #[
      contribution `secondRequirement { key := otherProof, expected := .proof otherGoal otherObject },
      contribution `alternativeRequirement { key := alternativeProof, expected := .proof goal leanObject }] }
  let input ← withMockEvidence input `firstProof proofKey mockProof
  let input ← withMockEvidence input `alternativeProof alternativeProof mockProof
  let r ← registry input
  expect "P08: required declarations conjunctive" (!(r.resultFor (.realization leanKey)).complete)
  expect "P08: alternative complete independently" ((r.resultFor (.realization alternativeKey)).complete)
  match r.selectRequirement {
      node := leanKey.node, context := leanContext
      facet := some `proof, requirement := `complete_proof } with
  | .error d => expect "P16: ambiguous alternative" (d.code == "ambiguous-prerequisite")
  | .ok _ => throw <| IO.userError "Ambiguous selection chose a complete alternative"
  match r.selectRequirement {
      node := leanKey.node, context := leanContext, realization := some `absent
      requirement := `complete_proof } with
  | .error d => expect "P16: missing selection" (d.code == "missing-prerequisite")
  | .ok _ => throw <| IO.userError "Missing selection succeeded"
  let input ← withMockEvidence input `secondProof otherProof (mockProof otherGoal otherObject)
  let r ← registry input
  expect "P08: all required declarations complete" ((r.resultFor (.realization leanKey)).complete)
  match r.selectRequirement {
      node := leanKey.node, context := leanContext
      facet := some `proof, requirement := `complete_proof } with
  | .error d => expect "P16: two complete alternatives still ambiguous" (d.code == "ambiguous-prerequisite")
  | .ok _ => throw <| IO.userError "Completeness supplied an implicit alternative selection"
  let unresolvedMember : Input := { input with objects := input.objects.map fun c =>
    if c.value.key == otherObject then { c with value := { c.value with resolution := .missing } } else c }
  let r ← registry unresolvedMember
  expect "P08/P21: independent proof retained despite missing other member"
    ((r.resultForRequirement proofKey).complete && (r.resultFor (.realization leanKey)).status == Status.blocked)

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
      key := reverseReview, expected := .review `statement_correspondence } }
  let input ← withMockEvidence bidirectional `review reviewKey mockReview
  let input ← withMockEvidence input `reverseReview reverseReview mockReview
  let r ← registry input
  expect "P13: legitimate reverse correspondence" (r.translations.all fun t => (r.resultFor (.translation t.key)).complete)

-- P14/P15: pure selection/requirement controls. Existing Graph/autoDeps adapters
-- are deliberately untouched and still need their later integration regressions.
#eval show IO Unit from do
  let proseReview : RequirementKey := ⟨.facet informalKey `statement, `proofread⟩
  let input : Input := { fixture with
    realizations := fixture.realizations.map fun c =>
      if c.value.key == informalKey then { c with value := { c.value with
        facets := c.value.facets.map fun f => if f.name == `statement then { f with required := #[proseReview] } else f } }
      else c
    requirements := (fixture.requirements.map fun c =>
      if c.value.key == reviewKey then { c with value := { c.value with prerequisites := #[proofKey] } } else c).push
      (contribution `proseRequirement { key := proseReview, expected := .review `proofreading }) }
  let input ← withMockEvidence input `proseReview proseReview
    (.review { criterion := `proofreading, reviewer := `MockReviewer, outcome := .passed })
  let input ← withMockEvidence input `translationReview reviewKey mockReview
  let r ← registry input
  expect "P14: complete informal statement" ((r.resultFor (.facet informalKey `statement)).complete)
  expect "P14: selected Lean proof still blocks" ((r.resultForRequirement reviewKey).status == Status.blocked)
  match r.selectRequirement {
      node := leanKey.node, context := leanContext, realization := some leanKey.name
      facet := some `proof, requirement := `complete_proof } with
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
    (proseReview.subject.realization? == some informalKey && proofKey.subject.realization? == some leanKey &&
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
      key := splitKey, context := leanContext, facets := #[{ name := `statement, documents := #[leanDoc] }] }
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

end VersoBlueprintTests.BlueprintTranslations
