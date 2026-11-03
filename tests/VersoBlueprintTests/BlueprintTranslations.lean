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
  let otherProof : RequirementKey := ⟨.declaration leanKey otherObject, `complete_proof⟩
  let otherGoal := { goal with fingerprint := "Second independently expected proposition" }
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
      key := otherReview, expected := .review `statement_correspondence, prerequisites := #[reviewKey] } }
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
      target := #[{ realization := rocqKey, facets := #[`statement] }] } } else c }
  for changed in #[changedInterpretation, changedAssumptions, changedSelection] do
    let current ← registry changed
    expect "R1: own changed claim cannot retain completed translation" (!(current.resultFor (.translation otherTranslation)).complete)
    expect "R1: own review is stale" (hasIssue (current.localResult otherReview) "stale-content")
    expect "R1: original claim review remains independent"
      (current.bindingFor reviewKey == r.bindingFor reviewKey && (current.resultForRequirement reviewKey).complete)

-- Cross-node mathematical obligations remain legal and reuse one checked
-- theorem requirement/evidence for its declaration and proof facet.
#eval show IO Unit from do
  let obligationRealization : RealizationKey := ⟨`external_obligation, `lean⟩
  let obligationContext : Context := ⟨`lean, `obligations_project⟩
  let obligationDocument : DocumentKey := ⟨obligationContext, "MockExternalObligation.lean"⟩
  let obligationObject : ObjectKey := ⟨obligationContext, "Fixture.external_preservation"⟩
  let obligationProof : RequirementKey := ⟨.facet obligationRealization `proof, `preservation⟩
  let obligationGoal : Goal := {
    context := obligationContext, fingerprint := "Independently expected preservation relation"
    documents := #[obligationDocument] }
  let input : Input := { fixture with
    nodes := fixture.nodes.push <| contribution `obligationNode {
      label := obligationRealization.node, title := "External mathematical obligation" }
    documents := fixture.documents.push <| contribution `obligationDocument {
      key := obligationDocument, text := "MOCK independent preservation theorem source" }
    objects := fixture.objects.push <| contribution `obligationObject {
      key := obligationObject, resolution := .resolved, document := some obligationDocument }
    realizations := fixture.realizations.push <| contribution `obligationRealization {
      key := obligationRealization, context := obligationContext
      facets := #[{ name := `proof, declarations := #[obligationObject], required := #[obligationProof] }]
      declarations := #[{ object := obligationObject, required := #[obligationProof] }] }
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
  expect "R1: one theorem validation shared across declaration and proof facet"
    ((r.resultFor (.facet obligationRealization `proof)).complete &&
      (r.resultFor (.declaration obligationRealization obligationObject)).complete &&
      (r.evidence.filter fun e => match e.observation with | .proof _ => true | _ => false).size == 1)
  let changedContract : Input := { proved with requirements := proved.requirements.map fun c =>
    if c.value.key == obligationProof then { c with value := { c.value with
      expected := .proof { obligationGoal with fingerprint := "Changed preservation proposition" } obligationObject } } else c }
  let current ← registry changedContract
  expect "R1/P10: changed external mathematical obligation invalidates linked local review"
    (hasIssue (current.localResult reviewKey) "stale-content" && !(current.resultFor (.translation translationKey)).complete)

/-- MOCK inputs reproducing the proof-only missing helper. No canonical sources
are checked. The original proof requirement is shared by its facet/declaration. -/
def withMissingProofHelper : IO Input := do
  let helper := { leanObject with native := "Fixture.proof_only_helper" }
  let helperProof : RequirementKey := ⟨.declaration leanKey helper, `complete_proof⟩
  let helperGoal : Goal := { goal with fingerprint := "Helper proposition" }
  let input : Input := { fixture with
    realizations := fixture.realizations.map fun c =>
      if c.value.key == leanKey then { c with value := { c.value with
        declarations := c.value.declarations.push { object := helper, required := #[helperProof] }
        facets := c.value.facets.map fun f =>
          if f.name == `proof then { f with
            declarations := f.declarations.push helper
            required := f.required.push helperProof } else f } }
      else c
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
  expect "R2: available declaration remains complete" ((r.resultFor (.declaration leanKey leanObject)).complete)
  expect "R2: selected statement port remains complete" ((r.resultFor (.translation translationKey)).complete)
  expect "R2: required proof work remains blocked" ((r.resultFor (.facet leanKey `proof)).status == Status.blocked)
  expect "R2: full realization remains blocked" ((r.resultFor (.realization leanKey)).status == Status.blocked)
  for facets in #[#[`proof], #[`statement, `proof], #[]] do
    let selected : Input := { base with translations := base.translations.map fun c =>
      { c with value := { c.value with target := #[{ realization := leanKey, facets }] } } }
    let selected ← withMockEvidence selected `selectedReview reviewKey mockReview
    let current ← registry selected
    expect "R2: selecting proof or whole realization preserves missing-helper blocker"
      ((current.resultFor (.translation translationKey)).status == Status.blocked &&
        (current.resultFor (.declaration leanKey leanObject)).complete)

-- Independent review R3: nonempty endpoint IDs/facet names are not content.
#eval show IO Unit from do
  let empty : Input := { fixture with
    realizations := fixture.realizations.map fun c =>
      if c.value.key == leanKey || c.value.key == rocqKey then { c with value := { c.value with
        facets := #[{ name := `statement }], declarations := #[], required := #[] } }
      else c
    requirements := fixture.requirements.filter (·.value.key == reviewKey)
    bindingInputs := #[] }
  let input ← withMockEvidence empty `emptyReview reviewKey mockReview
  let r ← registry input
  let result := r.resultFor (.translation translationKey)
  expect "R3: current review cannot complete content-free selected endpoints"
    (!result.complete && hasIssue result "content-unavailable")

-- Unselected content and the other endpoint cannot rescue an empty selected
-- facet; existing canonical documents must themselves contain source bytes.
#eval show IO Unit from do
  for emptyKey in #[rocqKey, leanKey] do
    let emptySelected : Input := { fixture with realizations := fixture.realizations.map fun c =>
      if c.value.key == emptyKey then { c with value := { c.value with facets := c.value.facets.map fun f =>
        if f.name == `statement then { f with documents := #[], declarations := #[] } else f } } else c }
    let input ← withMockEvidence emptySelected `emptySelectedReview reviewKey mockReview
    let r ← registry input
    expect "R3: unrelated proof content or other endpoint cannot fill selected statement"
      (!(r.resultFor (.translation translationKey)).complete && hasIssue (r.localResult reviewKey) "content-unavailable")
  let whitespace : Input := { fixture with documents := fixture.documents.map fun c =>
    if c.value.key == leanDoc then { c with value := { c.value with text := " \n\t" } } else c }
  let input ← withMockEvidence whitespace `whitespaceReview reviewKey mockReview
  let r ← registry input
  expect "R3: empty canonical bytes do not supply selected content"
    (!(r.resultFor (.translation translationKey)).complete && hasIssue (r.localResult reviewKey) "content-unavailable")
  let noStatements : Input := { fixture with realizations := fixture.realizations.map fun c =>
    if c.value.key == leanKey || c.value.key == rocqKey then { c with value := { c.value with facets := c.value.facets.map fun f =>
      if f.name == `statement then { f with documents := #[], declarations := #[] } else f } } else c }
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
    if c.value.key == leanKey || c.value.key == rocqKey then { c with value := { c.value with
      facets := c.value.facets.map fun f => { f with documents := #[] } } } else c }
  let input ← withMockEvidence declarationBacked `declarationReview reviewKey mockReview
  let r ← registry input
  expect "R3: selected statement declarations provide content without prose documents"
    ((r.resultFor (.translation translationKey)).complete && !(r.resultForRequirement proofKey).complete)
  let input ← withMockEvidence input `sharedProof proofKey mockProof
  let r ← registry input
  expect "R2/R3: one proof requirement supports its existing declaration and facet"
    ((r.resultFor (.declaration leanKey leanObject)).complete && (r.resultFor (.facet leanKey `proof)).complete)
  let wholeDeclaration : Input := { fixture with
    realizations := fixture.realizations.map fun c =>
      if c.value.key == leanKey || c.value.key == rocqKey then { c with value := { c.value with
        facets := #[], declarations := c.value.declarations.map fun d => { d with required := #[] } } } else c
    requirements := fixture.requirements.filter (·.value.key == reviewKey)
    bindingInputs := fixture.bindingInputs.filter (·.value.name == NativeLean.sourceContext)
    translations := fixture.translations.map fun c => { c with value := { c.value with source := #[rocqKey], target := #[leanKey] } } }
  let input ← withMockEvidence wholeDeclaration `wholeReview reviewKey mockReview
  let r ← registry input
  expect "R3: whole formal realization can use declarations without invented facets" ((r.resultFor (.translation translationKey)).complete)

-- Facet membership references existing associations and is checked at admission.
#eval show IO Unit from do
  let unknown := { leanObject with native := "Fixture.not_associated" }
  let bad : Input := { fixture with realizations := fixture.realizations.map fun c =>
    if c.value.key == leanKey then { c with value := { c.value with facets := c.value.facets.map fun f =>
      if f.name == `statement then { f with declarations := #[unknown] } else f } } else c }
  expect "R2: selected declaration must belong to its realization" (rejectsWith bad "unknown-facet-declaration")

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
      key := downstreamReview, expected := .review `statement_correspondence, prerequisites := #[reviewKey] } }
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
      facets := c.value.facets.map fun f => { f with documents := f.documents.map relocate } } } }
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

-- Explicit review scope, not the facet's spelling, controls content identity.
-- All facts below are MOCK provider inputs; actual proof edits are covered by
-- BlueprintRealizationSemantics and its ordinary-import mutation runner.
#eval show IO Unit from do
  -- No scope on this review: the default must preserve statement assessment,
  -- even when a translation endpoint selects a facet named `proof`.
  let statementInput : Input := { fixture with
    translations := fixture.translations.map fun c => { c with value := { c.value with
      target := #[{ realization := leanKey, facets := #[`proof] }] } }
    requirements := fixture.requirements.map fun c =>
      if c.value.key == reviewKey then { c with value := { c.value with prerequisites := #[proofKey] } }
      else if c.value.key == proofKey then { c with value := { c.value with scope := .implementation } }
      else c }
  let input ← withMockEvidence statementInput `scopeProof proofKey mockProof
  let input ← withMockEvidence input `scopeReview reviewKey mockReview
  let before ← registry input
  expect "scope: initial statement correspondence completes" ((before.resultForRequirement reviewKey).complete)
  let changeInput (matchesName : Name → Bool) : Input := { input with bindingInputs := input.bindingInputs.map fun c =>
    if (matchesName c.value.name) then { c with value := { c.value with content := c.value.content ++ " changed" } } else c }
  let proofChanged ← registry <| changeInput fun name =>
    name == NativeLean.sourceContext || name == NativeLean.expectedContextFor proofKey
  -- The Rocq provider has no S/P split: preserve its conservative content.
  let proofOnly : Input := { input with bindingInputs := input.bindingInputs.map fun c =>
    if c.value.name == NativeLean.expectedContextFor proofKey ||
        (c.value.subject == .declaration leanKey leanObject && c.value.name == NativeLean.sourceContext) then
      { c with value := { c.value with content := c.value.content ++ " own proof changed" } } else c }
  let after ← registry proofOnly
  expect "scope: proof-only change preserves local statement review"
    (after.bindingFor reviewKey == before.bindingFor reviewKey && (after.localResult reviewKey).complete)
  expect "scope: proof check must be refreshed and still gates completion"
    (!(after.resultForRequirement reviewKey).complete && !(after.localResult proofKey).complete)
  expect "scope: foreign source remains conservatively bound"
    (proofChanged.bindingFor reviewKey != before.bindingFor reviewKey)
  let statementChanged ← registry <| changeInput (· == NativeLean.statementContext)
  expect "scope: statement edit invalidates review"
    (statementChanged.bindingFor reviewKey != before.bindingFor reviewKey &&
      hasIssue (statementChanged.localResult reviewKey) "stale-content")
  let missing : Input := { input with
    bindingInputs := input.bindingInputs.filter (·.value.name != NativeLean.expectedStatementContextFor proofKey) }
  let missing ← registry missing
  expect "scope: missing prerequisite statement context cannot accept review"
    ((missing.localResult reviewKey).status == .blocked &&
      hasIssue (missing.localResult reviewKey) "semantic-context-unavailable")
  -- A Lean-language document alone is not a semantic descriptor. Keep its bytes.
  let proseOnly : Input := { input with realizations := input.realizations.map fun c =>
    if c.value.key == leanKey then { c with value := { c.value with facets := c.value.facets.map fun f =>
      if f.name == `proof then { f with declarations := #[] } else f } } else c }
  let proseBefore ← registry proseOnly
  let proseAfter ← registry { proseOnly with documents := proseOnly.documents.map fun c =>
    if c.value.key == leanDoc then { c with value := { c.value with text := "MOCK changed document-only source" } } else c }
  expect "scope: document-only Lean content remains conservatively byte-bound"
    (proseBefore.bindingFor reviewKey != proseAfter.bindingFor reviewKey)
  -- Unknown provider facts stay conservative, including selected facet/parent
  -- facts reached through endpoints rather than the requirement's own subject.
  for subject in #[Subject.declaration leanKey leanObject, .facet leanKey `proof, .realization leanKey] do
    let custom := contribution `customProviderInput {
      subject, name := `customProvider.policy, content := "MOCK policy A" }
    let withCustom : Input := { input with bindingInputs := input.bindingInputs.push custom }
    let customBefore ← registry withCustom
    for replacement in #[{ custom.value with content := "MOCK policy B" },
        { custom.value with name := `customProvider.otherPolicy }] do
      let changed := { input with bindingInputs := input.bindingInputs.push { custom with value := replacement } }
      let customAfter ← registry changed
      expect "scope: selected custom provider facts and their names remain bound"
        (customBefore.bindingFor reviewKey != customAfter.bindingFor reviewKey)
  let sibling : RequirementKey := ⟨.claim claimKey, `independent_review⟩
  let siblingContract := contribution `siblingReview { key := sibling, expected := .review `independent }
  let withSibling : Input := { input with requirements := input.requirements.push siblingContract }
  let siblingRegistry ← registry withSibling
  expect "scope: unrelated sibling obligation does not disturb a local review"
    (siblingRegistry.bindingFor reviewKey == before.bindingFor reviewKey)
  let unselected : Input := { input with realizations := input.realizations.map fun c =>
    if c.value.key == leanKey then { c with value := { c.value with
      facets := c.value.facets.push { name := `unselected_notes, documents := #[leanDoc] } } } else c }
  let unselected ← registry unselected
  expect "scope: unselected facet metadata does not disturb endpoint review"
    (unselected.bindingFor reviewKey == before.bindingFor reviewKey)
  let implementationInput : Input := { input with requirements := input.requirements.map fun c =>
    if c.value.key == reviewKey then { c with value := { c.value with scope := .implementation } } else c }
  let implementation ← registry implementationInput
  expect "scope: changing the review contract invalidates its old evidence"
    (implementation.bindingFor reviewKey != before.bindingFor reviewKey &&
      hasIssue (implementation.localResult reviewKey) "stale-content")
  let reviewedImplementation ← withMockEvidence implementationInput `implementationReview reviewKey mockReview
  let implementationBefore ← registry reviewedImplementation
  let implementationAfter ← registry { reviewedImplementation with bindingInputs := proofOnly.bindingInputs }
  expect "scope: explicit implementation review is current before an own-proof edit"
    ((implementationBefore.localResult reviewKey).complete)
  expect "scope: explicit implementation review goes stale on an own-proof edit"
    (implementationBefore.bindingFor reviewKey != implementationAfter.bindingFor reviewKey &&
      hasIssue (implementationAfter.localResult reviewKey) "stale-content")

end VersoBlueprintTests.BlueprintTranslations
