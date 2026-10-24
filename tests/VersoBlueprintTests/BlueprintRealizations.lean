/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Translations

/-! Pure P01-P22 acceptance controls. ALL source resolution, proof, executable
check and review observations in this file are MOCK provider inputs. This does
not load/check the canonical Flag or MaxNat projects, run compilers, certify a
foreign theorem, or implement existing environment import/graph adapters. -/

namespace VersoBlueprintTests.BlueprintRealizations

open Lean Informal.Realizations Informal.Validation Informal.Translations

-- Replacing admitted input must recompute bindings through admission. The
-- public contributions accessor cannot update a Registry and retain old caches.
#check_failure (fun (r : Registry) => ({ r with contributions := ({} : Input) } : Registry))

def contribution (id : Name) (value : α) : Contribution α :=
  { origin := { id, moduleName := `MockProvider, source := "synthetic-test-input" }, value }

def expect (label : String) (condition : Bool) : IO Unit :=
  unless condition do throw <| IO.userError s!"Acceptance control failed: {label}"

def registry (input : Input) : IO Registry :=
  match admit input with
  | .ok value => pure value
  | .error issues => throw <| IO.userError s!"Unexpected structural rejection: {repr issues}"

def leanContext : Context := ⟨`lean, `fixture⟩
def rocqContext : Context := ⟨`rocq, `fixture⟩
def informalContext : Context := ⟨`verso, `fixture⟩
def leanKey : RealizationKey := ⟨`toggle_involutive, `lean_port⟩
def rocqKey : RealizationKey := ⟨`toggle_involutive, `rocq_reference⟩
def informalKey : RealizationKey := ⟨`toggle_involutive, `informal⟩
def leanDoc : DocumentKey := ⟨leanContext, "MockFlag.lean"⟩
def rocqDoc : DocumentKey := ⟨rocqContext, "MockFlag.v"⟩
def proseDoc : DocumentKey := ⟨informalContext, "MockExposition.lean"⟩
def leanObject : ObjectKey := ⟨leanContext, "Fixture.toggle_involutive"⟩
def rocqObject : ObjectKey := ⟨rocqContext, "TranslationHarnessReuse.Flag.toggle_involutive"⟩
def proofKey : RequirementKey := ⟨.facet leanKey `proof, `complete_proof⟩
def translationKey : TranslationKey := ⟨`fixture, `rocq_to_lean⟩
def claimKey : ClaimKey := ⟨translationKey, `statement_correspondence⟩
def reviewKey : RequirementKey := ⟨.claim claimKey, `correspondence_review⟩
def goal : Goal := {
  context := leanContext
  proposition := "forall flag : Fixture.Flag, Fixture.toggle (Fixture.toggle flag) = flag"
  documents := #[leanDoc] }

def fixture : Input := {
  nodes := #[contribution `node { label := `toggle_involutive, title := "Toggle involution" }]
  documents := #[
    contribution `leanDoc { key := leanDoc, text := "MOCK canonical Lean statement and proof bytes" },
    contribution `rocqDoc { key := rocqDoc, text := "MOCK canonical Rocq statement and proof bytes" },
    contribution `proseDoc { key := proseDoc, text := "MOCK independent informal statement and two-case argument" }]
  objects := #[
    contribution `leanObject { key := leanObject, resolution := .resolved, document := some leanDoc },
    contribution `rocqObject { key := rocqObject, resolution := .resolved, document := some rocqDoc }]
  realizations := #[
    contribution `leanRealization {
      key := leanKey, context := leanContext
      facets := #[{ name := `statement, documents := #[leanDoc], declarations := #[leanObject] },
        { name := `proof, documents := #[leanDoc], declarations := #[leanObject], required := #[proofKey] }]
      declarations := #[{ object := leanObject, required := #[proofKey] }] },
    contribution `rocqRealization {
      key := rocqKey, context := rocqContext
      facets := #[{ name := `statement, documents := #[rocqDoc], declarations := #[rocqObject] },
        { name := `proof, documents := #[rocqDoc], declarations := #[rocqObject] }]
      declarations := #[{ object := rocqObject }] },
    contribution `proseRealization {
      key := informalKey, context := informalContext
      facets := #[{ name := `statement, documents := #[proseDoc] }, { name := `proof, documents := #[proseDoc] }] }]
  translations := #[contribution `translation {
    key := translationKey
    source := #[{ realization := rocqKey, facets := #[`statement] }]
    target := #[{ realization := leanKey, facets := #[`statement] }] }]
  claims := #[contribution `claim {
    key := claimKey, interpretation := "Related off/on constructors preserve toggle and involution"
    required := #[reviewKey] }]
  requirements := #[
    contribution `proofRequirement { key := proofKey, expected := .proof goal leanObject },
    contribution `reviewRequirement { key := reviewKey, expected := .review `statement_correspondence }]
  bindingInputs := #[
    contribution `mockLeanSemantics {
      subject := .declaration leanKey leanObject
      name := NativeLean.sourceContext, content := "MOCK current Lean semantic closure/provider context" },
    contribution `mockRocqSemantics {
      subject := .declaration rocqKey rocqObject
      name := NativeLean.sourceContext, content := "MOCK current Rocq semantic closure/provider context" },
    contribution `mockExpectedSemantics {
      subject := proofKey.subject, name := NativeLean.expectedContextFor proofKey
      content := "MOCK independently expected proposition semantic closure/provider context" }]
}

/-- Explicit mock of a trusted language boundary. It does not check a Lean term. -/
def mockProof (g : Goal := goal) (witness : ObjectKey := leanObject) : Observation :=
  .proof { witness, actualType := some g, outcome := .passed, coverage := .dependencyClosure }

/-- Explicit mock review. No human reviewed the synthetic source. -/
def mockReview : Observation :=
  .review { criterion := `statement_correspondence, reviewer := `MockReviewer, outcome := .passed }

def withMockEvidence (input : Input) (id : Name) (key : RequirementKey) (observation : Observation) : IO Input := do
  -- Explicit MOCK expected-goal context for additional synthetic proof contracts.
  -- Supply the complete synthetic batch before any observation is bound; adding
  -- a semantic input later would correctly make an earlier connected review stale.
  let mut input := input
  for record in input.requirements do
    if let .proof .. := record.value.expected then
      let proof := record.value.key
      unless input.bindingInputs.any (fun record => record.value.subject == proof.subject &&
          record.value.name == NativeLean.expectedContextFor proof) do
        let context := contribution (id ++ `mockExpectedContext ++ Name.num .anonymous input.bindingInputs.size) {
          subject := proof.subject, name := NativeLean.expectedContextFor proof
          content := "MOCK expected-goal semantic context" }
        input := { input with bindingInputs := input.bindingInputs.push context }
  let r ← registry input
  let some binding := r.bindingFor key | throw <| IO.userError "Missing test requirement"
  return { input with evidence := input.evidence.push <| contribution id { id, requirement := key, binding, observation } }

def reverseInput (input : Input) : Input := {
  nodes := input.nodes.reverse, documents := input.documents.reverse
  objects := input.objects.reverse, realizations := input.realizations.reverse
  translations := input.translations.reverse, claims := input.claims.reverse
  requirements := input.requirements.reverse, evidence := input.evidence.reverse
  bindingInputs := input.bindingInputs.reverse }

def replay (input : Input) : Input := {
  nodes := input.nodes ++ input.nodes, documents := input.documents ++ input.documents
  objects := input.objects ++ input.objects, realizations := input.realizations ++ input.realizations
  translations := input.translations ++ input.translations, claims := input.claims ++ input.claims
  requirements := input.requirements ++ input.requirements, evidence := input.evidence ++ input.evidence
  bindingInputs := input.bindingInputs ++ input.bindingInputs }

def rejectsWith (input : Input) (code : String) : Bool :=
  match admit input with
  | .ok _ => false
  | .error issues => issues.any (·.code == code)

def hasIssue (result : Result) (code : String) : Bool := result.diagnostics.any (·.code == code)

-- P01: independently authored accounts do not manufacture validation.
#eval show IO Unit from do
  let r ← registry fixture
  expect "P01: three distinct realizations" (r.realizations.size == 3)
  expect "P01: prose unassessed" ((r.resultFor (.realization informalKey)).status == Status.unassessed)
  expect "P01: Lean proof pending" ((r.resultForRequirement proofKey).status == Status.pending)
  expect "P01: correspondence pending" (!(r.resultFor (.translation translationKey)).complete)
  expect "P01: public proof facet" ((r.resultFor (.facet leanKey `proof)).status == Status.pending)

-- P04/P06: expected proposition and project are independent of a candidate.
#eval show IO Unit from do
  let wrongGoal := { goal with proposition := "True" }
  let wrong ← withMockEvidence fixture `wrong proofKey (mockProof wrongGoal)
  let r ← registry wrong
  expect "P04: unrelated complete theorem" (hasIssue (r.resultForRequirement proofKey) "wrong-proof")
  let otherProject := { leanObject with context := ⟨`lean, `otherProject⟩ }
  let wrong ← withMockEvidence fixture `wrongProject proofKey (mockProof goal otherProject)
  let r ← registry wrong
  expect "P04: same-spelled foreign project" (!(r.resultForRequirement proofKey).complete)
  let partialProof : Observation := .proof {
    witness := leanObject, actualType := some goal, outcome := .passed, coverage := .subject }
  let partialInput ← withMockEvidence fixture `partial proofKey partialProof
  let r ← registry partialInput
  expect "P06: incomplete proof coverage" (hasIssue (r.resultForRequirement proofKey) "insufficient-coverage")
  let wrongKind ← withMockEvidence fixture `wrongKind proofKey mockReview
  let r ← registry wrongKind
  expect "P04: review cannot prove a theorem" (hasIssue (r.resultForRequirement proofKey) "wrong-evidence-kind")
  let missingType ← withMockEvidence fixture `missingType proofKey
    (.proof { witness := leanObject, outcome := .passed, coverage := .dependencyClosure })
  let r ← registry missingType
  expect "P04: passed flag without checked type insufficient" (!(r.resultForRequirement proofKey).complete)
  let proof ← withMockEvidence fixture `proof proofKey (mockProof { goal with documents := #[] })
  let r ← registry proof
  expect "P04: type identity distinct from source navigation" ((r.resultForRequirement proofKey).complete)

-- P07: empty or not-applicable validation cannot produce success.
#eval show IO Unit from do
  let r ← registry fixture
  expect "P07: empty requirements" (!(r.resultFor (.realization rocqKey)).complete)
  let noSource : Input := { fixture with translations := fixture.translations.map fun c =>
    { c with value := { c.value with source := #[] } } }
  expect "P07: empty endpoint" (rejectsWith noSource "invalid-endpoints")
  let notApplicable : Observation := .proof {
    witness := leanObject, outcome := .notApplicable }
  let input ← withMockEvidence fixture `na proofKey notApplicable
  let r ← registry input
  expect "P07: not applicable is not a proof" (!(r.resultForRequirement proofKey).complete)

-- P09/P10/P11: content binding is deterministic and never renewed by replay.
#eval show IO Unit from do
  let input ← withMockEvidence fixture `review reviewKey mockReview
  let r ← registry input
  let repeated ← registry (reverseInput (replay input))
  expect "P09: deterministic binding" (r.bindingFor reviewKey == repeated.bindingFor reviewKey)
  expect "P09/P17: evidence replay" (repeated.evidence.size == 1 && (repeated.resultForRequirement reviewKey).complete)
  let changedLookup : Input := { input with objects := input.objects.map fun c =>
    { c with value := { c.value with explanation := "MOCK different diagnostic wording" } } }
  let sameContent ← registry changedLookup
  expect "P09: lookup logs are not reviewed content"
    (sameContent.bindingFor reviewKey == r.bindingFor reviewKey && (sameContent.resultForRequirement reviewKey).complete)
  for document in #[leanDoc, rocqDoc] do
    let changed : Input := { input with documents := input.documents.map fun c =>
      if c.value.key == document then { c with value := { c.value with text := c.value.text ++ " changed" } } else c }
    let changedRegistry ← registry changed
    expect "P10: endpoint bytes changed" (hasIssue (changedRegistry.resultForRequirement reviewKey) "stale-content")
  let changedClaim : Input := { input with claims := input.claims.map fun c =>
    { c with value := { c.value with assumptions := #["new assumption"] } } }
  let changedRegistry ← registry changedClaim
  expect "P10: assumptions changed" (hasIssue (changedRegistry.resultForRequirement reviewKey) "stale-content")
  let changedFacets : Input := { input with translations := input.translations.map fun c =>
    { c with value := { c.value with target := #[{ realization := leanKey, facets := #[`proof] }] } } }
  let changedRegistry ← registry changedFacets
  expect "P10: selected facet changed" (hasIssue (changedRegistry.resultForRequirement reviewKey) "stale-content")
  let missingBinding : Input := { input with evidence := input.evidence.map fun c =>
    { c with value := { c.value with binding := "" } } }
  let r ← registry missingBinding
  expect "P11: missing binding" (!(r.resultForRequirement reviewKey).complete)
  let closureReview : Input := { fixture with requirements := fixture.requirements.map fun c =>
    if c.value.key == reviewKey then { c with value := { c.value with coverage := .dependencyClosure } } else c }
  let input ← withMockEvidence closureReview `partialReview reviewKey mockReview
  let r ← registry input
  expect "P11: partial review is not closure review" (hasIssue (r.resultForRequirement reviewKey) "insufficient-coverage")

-- P10: a linked formal obligation is also part of the reviewed contract.
#eval show IO Unit from do
  let withObligation : Input := { fixture with
    requirements := fixture.requirements.map fun c =>
      if c.value.key == reviewKey then { c with value := { c.value with prerequisites := #[proofKey] } } else c }
  let input ← withMockEvidence withObligation `review reviewKey mockReview
  let changedGoal : Goal := { goal with proposition := "Changed independently expected obligation" }
  let changed : Input := { input with requirements := input.requirements.map fun c =>
    if c.value.key == proofKey then { c with value := { c.value with expected := .proof changedGoal leanObject } } else c }
  let r ← registry changed
  expect "P10: formal obligation changed" (hasIssue (r.resultForRequirement reviewKey) "stale-content")

-- P17/P18/P19: replay, producer collisions, and semantic conflicts are different.
#eval show IO Unit from do
  let r ← registry (reverseInput fixture)
  expect "P19: forward/import order independent" (r.bindingFor proofKey == (← registry fixture).bindingFor proofKey)
  expect "P19: separate realization producers share node" (r.realizations.size == 3 && r.nodes.size == 1)
  let nodeConflict : Input := { fixture with
    nodes := fixture.nodes.push <|
    contribution `otherNode { label := `toggle_involutive, title := "Conflicting title" } }
  expect "P18: conflicting shared metadata" (rejectsWith nodeConflict "semantic-conflict")
  let collision : Input := { fixture with
    nodes := fixture.nodes.push <|
    contribution `node { label := `other, title := "Same producer ID, other node" } }
  expect "P18: producer collision" (rejectsWith collision "producer-collision")
  let first := fixture.realizations[0]!
  let conflicting : Input := { fixture with
    realizations := fixture.realizations.push <|
    contribution `otherProducer { first.value with required := #[proofKey] } }
  expect "P18: semantic key conflict across producers" (rejectsWith conflicting "semantic-conflict")
  match admit conflicting, admit (reverseInput conflicting) with
  | .error a, .error b =>
    expect "P18: deterministic diagnostics" (a == b)
    expect "P18: both origins retained" (a.any fun d => d.code == "semantic-conflict" && d.origins.size == 2)
  | _, _ => throw <| IO.userError "Expected incompatible realization rejection"
  let unresolved : Input := { fixture with
    requirements := fixture.requirements.push <| contribution `badReference {
    key := ⟨.facet ⟨`missing, `lean⟩ `proof, `required⟩, expected := .review `missing } }
  expect "P19: unresolved subject rejected" (rejectsWith unresolved "invalid-requirement")

-- P21: missing/ambiguous/unsupported source and unavailable validators stay explicit.
#eval show IO Unit from do
  for resolution in #[Resolution.missing, .ambiguous, .unsupported] do
    let input : Input := { fixture with objects := fixture.objects.map fun c =>
      if c.value.key == rocqObject then { c with value := { c.value with resolution } } else c }
    let r ← registry input
    let result := r.resultFor (.translation translationKey)
    expect "P21: source provider unavailable" (result.status == Status.blocked && hasIssue result "object-unavailable")
    expect "P21: unfinished translation retained" (r.unfinished.size == 1 && r.actionable.isEmpty)
  let unavailableProof : Observation := .proof {
    witness := leanObject, outcome := .unavailable
    explanation := "MOCK checker unavailable" }
  let input ← withMockEvidence fixture `unavailable proofKey unavailableProof
  let r ← registry input
  expect "P21: validation provider unavailable"
    ((r.resultForRequirement proofKey).status == Status.blocked &&
      hasIssue (r.resultForRequirement proofKey) "validation-unavailable")

-- Open named executable validators accommodate lint/tests without declaring
-- either result to be a proof or a correspondence review. Still ALL MOCKS.
#eval show IO Unit from do
  let rustContext : Context := ⟨`rust, `fixture⟩
  let rustKey : RealizationKey := ⟨leanKey.node, `rust_implementation⟩
  let rustDoc : DocumentKey := ⟨rustContext, "MockFlag.rs"⟩
  let testsKey : RequirementKey := ⟨.facet rustKey `implementation, `tests⟩
  let input : Input := { fixture with
    documents := fixture.documents.push <| contribution `rustDoc { key := rustDoc, text := "MOCK Rust source" }
    realizations := fixture.realizations.push <| contribution `rustRealization {
      key := rustKey, context := rustContext
      facets := #[{ name := `implementation, documents := #[rustDoc], required := #[testsKey] }] }
    requirements := fixture.requirements.push <| contribution `rustTests {
      key := testsKey, expected := .check `rust.flag_tests } }
  let wrong ← withMockEvidence input `wrongValidator testsKey
    (.check { validator := `verso.prose_lint, outcome := .passed })
  let r ← registry wrong
  expect "named tests: lint result is insufficient" (hasIssue (r.resultForRequirement testsKey) "wrong-validator")
  let passed ← withMockEvidence input `rustTestsPassed testsKey
    (.check { validator := `rust.flag_tests, outcome := .passed })
  let r ← registry passed
  expect "named tests: selected contract complete" ((r.resultFor (.realization rustKey)).complete)
  expect "named tests: no effect on Lean proof" (!(r.resultForRequirement proofKey).complete)

-- Unknown facet selection and a proof contract in the wrong project fail admission.
#eval show IO Unit from do
  let unknownFacet : Input := { fixture with translations := fixture.translations.map fun c =>
    { c with value := { c.value with source := #[{ realization := rocqKey, facets := #[`absent] }] } } }
  expect "endpoint facet must exist" (rejectsWith unknownFacet "unknown-facet")
  let foreignGoal : Goal := ⟨rocqContext, "Independent foreign statement", #[]⟩
  let wrongContext : Input := { fixture with requirements := fixture.requirements.map fun c =>
    if c.value.key == proofKey then { c with value := { c.value with expected := .proof foreignGoal rocqObject } } else c }
  expect "proof expected in selected realization context" (rejectsWith wrongContext "wrong-project")

end VersoBlueprintTests.BlueprintRealizations
