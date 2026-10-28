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
  let changedDocument : Input := { proved with documents := proved.documents.map fun c =>
    if c.value.key == obligationDocument then { c with value := { c.value with text := c.value.text ++ " changed" } } else c }
  let current ← registry changedDocument
  expect "R1/P10: changed external obligation invalidates linked local review"
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

end VersoBlueprintTests.BlueprintTranslations
