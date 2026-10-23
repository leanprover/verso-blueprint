/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Existing
import VersoBlueprintTests.BlueprintRealizationAdapter.Provider

/-! One source-backed example through the existing opt-in APIs. Only the native
Lean proof is actually checked. Rocq identity is an authored reference with
unsupported resolution; readable source/config and Qed establish no foreign
checking. No successful foreign observation or human review is supplied. -/

open Lean Elab Term Command
open Informal.Realizations Informal.Validation Informal.Translations
open Informal.Realizations.Existing

namespace VersoBlueprintTests.BlueprintRealizationThreeWay

private def sourcePath := "tests/fixtures/realizations/rocq/Flag.v"
private def configPath := "tests/fixtures/realizations/rocq/_RocqProject"
private def sourceText : String := include_str "../fixtures/realizations/rocq/Flag.v"
private def configText : String := include_str "../fixtures/realizations/rocq/_RocqProject"

private def authored (id : Name) (value : α) : Contribution α := {
  origin := {
    id := `threeWayFlag ++ id
    moduleName := `VersoBlueprintTests.BlueprintRealizationThreeWay
    source := "tests/VersoBlueprintTests/BlueprintRealizationThreeWay.lean" }
  value }

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error error => throwError "Unexpected rejection: {repr error}"

private def binding (r : Registry) (key : RequirementKey) : TermElabM String := do
  let some value := r.bindingFor key | throwError "Missing binding"
  return value

private def statusText (result : Result) : String :=
  match result.status with
  | .complete => "complete"
  | .unassessed => "unassessed"
  | .pending => "pending"
  | .blocked => "blocked"

/-- info: Flag: Lean proof=complete; Verso=unassessed; Verso-to-Lean=pending; Rocq-to-Lean=blocked; realizations=3; translations=2 -/
#guard_msgs in
run_cmd liftTermElabM do
  let label := Name.mkSimple "adapter.flag.involutive"
  let before ← Informal.Environment.getNode? label
  let labelsBefore ← Informal.Environment.labelsForLeanDecl `RealizationAdapterFixture.flagInvolutive
  let p ← obtain (← project `flagPilot label)
  ensure (p.docstringFormat == `verso) "Use actual accepted Verso source"
  let expected ← `(term| ∀ flag : RealizationAdapterFixture.Flag,
    RealizationAdapterFixture.toggle (RealizationAdapterFixture.toggle flag) = flag)
  let native ← obtain (← p.validate expected)
  let proof : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩
  let nativeRegistry ← obtain (admit native)
  let nativeBinding ← binding nativeRegistry proof
  ensure ((nativeRegistry.resultForRequirement proof).complete) "Actual native proof must complete"
  -- These equalities check build inputs/current bytes, not Rocq symbol resolution.
  let currentSource ← liftM <| IO.FS.readFile sourcePath
  let currentConfig ← liftM <| IO.FS.readFile configPath
  ensure (sourceText == currentSource && configText == currentConfig)
    "Compiled fixture bytes must equal current source and configuration"
  ensure (sourceText.contains "Theorem toggle_involutive" &&
    configText.startsWith "-Q . TranslationHarnessReuse\n") "Expected local source/config fixture"
  let rocqContext : Informal.Realizations.Context := ⟨`rocq, `TranslationHarnessReuse⟩
  let rocqKey : RealizationKey := ⟨label, `«rocq-reference»⟩
  let rocqObject : ObjectKey := ⟨rocqContext, "TranslationHarnessReuse.Flag.toggle_involutive"⟩
  let sourceDoc : DocumentKey := ⟨rocqContext, sourcePath⟩
  let configDoc : DocumentKey := ⟨rocqContext, configPath⟩
  let versoTranslation : TranslationKey := ⟨`flagPilot, `versoToLean⟩
  let rocqTranslation : TranslationKey := ⟨`flagPilot, `rocqToLean⟩
  let versoClaim : ClaimKey := ⟨versoTranslation, `statement⟩
  let rocqClaim : ClaimKey := ⟨rocqTranslation, `statement⟩
  let versoReview : RequirementKey := ⟨.claim versoClaim, `correspondence⟩
  let rocqReview : RequirementKey := ⟨.claim rocqClaim, `correspondence⟩
  let input := { native with
    documents := native.documents ++ #[
      authored `rocqSource { key := sourceDoc, text := sourceText },
      authored `rocqConfig { key := configDoc, text := configText }]
    objects := native.objects.push (authored `rocqObject {
      key := rocqObject, resolution := .unsupported, document := some sourceDoc
      explanation := "Authored Rocq reference only: source-native resolver/checker is not connected" })
    realizations := native.realizations.push (authored `rocqRealization {
      key := rocqKey, context := rocqContext
      facets := #[{ name := `statement, documents := #[sourceDoc, configDoc], declarations := #[rocqObject] },
        { name := `proof, documents := #[sourceDoc, configDoc], declarations := #[rocqObject] }]
      declarations := #[{ object := rocqObject }] })
    translations := #[
      authored `versoTranslation {
        key := versoTranslation, source := #[{ realization := p.informalKey, facets := #[`statement] }]
        target := #[{ realization := p.leanKey, facets := #[`statement] }], required := #[proof] },
      authored `rocqTranslation {
        key := rocqTranslation, source := #[{ realization := rocqKey, facets := #[`statement] }]
        target := #[{ realization := p.leanKey, facets := #[`statement] }], required := #[proof] }]
    claims := #[
      authored `versoClaim {
        key := versoClaim, interpretation := "The Verso two-case account states toggle involution"
        required := #[versoReview] },
      authored `rocqClaim {
        key := rocqClaim
        interpretation := "Relate Rocq off/on to Lean off/on; this relation preserves toggle and the universal two-state involution statement"
        required := #[rocqReview] }]
    requirements := native.requirements ++ #[
      authored `versoReview { key := versoReview, expected := .review `statementCorrespondence },
      authored `rocqReview { key := rocqReview, expected := .review `statementCorrespondence }] }
  let r ← obtain (admit input)
  ensure (r.nodes.size == 1 && r.realizations.size == 3 && r.translations.size == 2)
    "One node has three realizations and exactly two explicit translations"
  ensure ((r.realization? p.informalKey).isSome && (r.realization? p.leanKey).isSome &&
    (r.realization? rocqKey).isSome) "Existing identities remain discoverable"
  ensure ((← binding r proof) == nativeBinding && (r.resultForRequirement proof).complete)
    "Adding a blocked source does not stale independent actual native proof evidence"
  ensure ((r.resultFor (.realization p.informalKey)).status == .unassessed)
    "Readable Verso source is not proofreading"
  ensure ((r.resultFor (.translation versoTranslation)).status == .pending &&
    (r.resultForRequirement versoReview).status == .pending) "Verso correspondence awaits its own review"
  let rocqResult := r.resultFor (.translation rocqTranslation)
  ensure (rocqResult.status == .blocked && (r.resultForRequirement rocqReview).status == .blocked &&
    rocqResult.diagnostics.any (·.code == "object-unavailable"))
    "Rocq endpoint must select its unresolved declaration, not readable documents alone"
  ensure (r.objects.any fun o => o.key == rocqObject && o.resolution == .unsupported &&
    o.explanation.contains "resolver/checker is not connected") "Preserve the actual capability gap"
  ensure (r.evidence.size == native.evidence.size && r.evidence.all fun e =>
    match e.observation with
    | .proof observation => observation.witness == p.witness && observation.outcome == .passed
    | _ => false) "Only actual native evidence exists; no foreign success or human review"
  ensure (r.unfinished.size == 2 && r.unfinished.any (·.key == rocqTranslation) &&
    r.actionable.size == 1 && r.actionable.any (·.key == versoTranslation))
    "Blocked work stays in unfinished inventory while actionable work excludes it"
  let rocqBinding ← binding r rocqReview
  let versoBinding ← binding r versoReview
  -- Synthetic in-memory content/contract mutations, not edits or certifications
  -- of the real Rocq development. They supply no new evidence.
  for document in #[sourceDoc, configDoc] do
    let changed := { input with documents := input.documents.map fun record =>
      if record.value.key == document then
        { record with value := { record.value with text := record.value.text ++ "\nmutation control\n" } }
      else record }
    let changedRegistry ← obtain (admit changed)
    ensure ((← binding changedRegistry rocqReview) != rocqBinding &&
      (← binding changedRegistry versoReview) == versoBinding &&
      (← binding changedRegistry proof) == nativeBinding && (changedRegistry.resultForRequirement proof).complete)
      "Selected source/config affects Rocq correspondence, not another account or the local proof"
  let changedClaim := { input with claims := input.claims.map fun record =>
    if record.value.key == rocqClaim then
      { record with value := { record.value with interpretation := record.value.interpretation ++ "; extra premise" } }
    else record }
  let changedRegistry ← obtain (admit changedClaim)
  ensure ((← binding changedRegistry rocqReview) != rocqBinding &&
    (← binding changedRegistry proof) == nativeBinding && (changedRegistry.resultForRequirement proof).complete)
    "Claim interpretation has its own binding, independent of the native theorem"
  -- Explicit empty/missing-source observations. Neither an absent provider nor
  -- an absent file can be repaired by some other readable/complete realization.
  let emptySource := { input with documents := input.documents.map fun record =>
    if record.value.key == sourceDoc then { record with value := { record.value with text := "" } } else record }
  let emptyRegistry ← obtain (admit emptySource)
  ensure ((emptyRegistry.resultFor (.translation rocqTranslation)).status == .blocked &&
    (emptyRegistry.resultFor (.translation rocqTranslation)).diagnostics.any (·.code == "content-unavailable"))
    "Empty source is explicitly unavailable"
  let missingSource := { emptySource with objects := emptySource.objects.map fun record =>
    if record.value.key == rocqObject then
      { record with value := { record.value with
        resolution := .missing, document := none
        explanation := "Synthetic missing-source control" } }
    else record }
  let missingRegistry ← obtain (admit missingSource)
  ensure ((missingRegistry.resultFor (.translation rocqTranslation)).status == .blocked &&
    missingRegistry.unfinished.any (·.key == rocqTranslation) && (missingRegistry.resultForRequirement proof).complete)
    "Missing selected source remains discoverable without erasing the native proof"
  let wrongProject := { input with realizations := input.realizations.map fun record =>
    if record.value.key == rocqKey then
      { record with value := { record.value with context := ⟨`rocq, `otherProject⟩ } }
    else record }
  match admit wrongProject with
  | .error issues => ensure (issues.any (·.code == "wrong-project")) "Wrong project must be explicit"
  | .ok _ => throwError "Same-spelled source reference must not be silently rebound to another project"
  let alternative : RealizationKey := ⟨label, `alternativeSource⟩
  let withAlternative := { input with realizations := input.realizations.push (authored `alternative {
    key := alternative, context := rocqContext, facets := #[{ name := `statement, documents := #[sourceDoc, configDoc] }] }) }
  let alternativeRegistry ← obtain (admit withAlternative)
  ensure ((alternativeRegistry.resultFor (.realization alternative)).status == .unassessed &&
    (alternativeRegistry.resultFor (.translation rocqTranslation)).status == .blocked &&
    (alternativeRegistry.resultForRequirement proof).complete)
    "A readable alternative is not silently selected instead of the authored Rocq endpoint"
  let after ← Informal.Environment.getNode? label
  ensure (reprStr before == reprStr after && labelsBefore ==
    (← Informal.Environment.labelsForLeanDecl `RealizationAdapterFixture.flagInvolutive))
    "Composition/querying does not mutate accepted Blueprint membership"
  logInfo m!"Flag: Lean proof={statusText (r.resultForRequirement proof)}; Verso={statusText (r.resultFor (.realization p.informalKey))}; Verso-to-Lean={statusText (r.resultFor (.translation versoTranslation))}; Rocq-to-Lean={statusText rocqResult}; realizations={r.realizations.size}; translations={r.translations.size}"

end VersoBlueprintTests.BlueprintRealizationThreeWay
