/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Dependencies
import VersoBlueprint.Realizations.Existing
import VersoBlueprint.Graph
import VersoBlueprintTests.BlueprintRealizationDependencies.Provider

/-! Actual accepted uses and native proofs. Graph/CodeHealth are test oracles for
supported theorem-local policy only. All contract corruptions are explicitly
synthetic; no mock successful proof/check/review observations are supplied. -/

open Lean Meta Elab Term Command
open Informal.Realizations Informal.Validation Informal.Translations
open Informal.Realizations.Existing Informal.Realizations.Dependencies

namespace VersoBlueprintTests.BlueprintRealizationDependencies

private def context : Informal.Realizations.Context := ⟨`lean, `dependencyPilot⟩
private def label (s : String) : Name := Name.mkSimple ("dependencies." ++ s)

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error error => throwError "Unexpected rejection: {repr error}"

private def proofKey (p : Projection) : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩

private def join (a b : Input) : Input := {
  nodes := a.nodes ++ b.nodes, documents := a.documents ++ b.documents
  objects := a.objects ++ b.objects, realizations := a.realizations ++ b.realizations
  translations := a.translations ++ b.translations, claims := a.claims ++ b.claims
  requirements := a.requirements ++ b.requirements, evidence := a.evidence ++ b.evidence }

private def edge (axis : Array SelectedUse) (name : Name) : TermElabM (Except Diagnostic RequirementKey) := do
  let some (_, result) := axis.find? (fun e => e.1.label == name) | throwError "Missing effective edge {name}"
  return result

private def edgeError (registry : Registry) (name : Name) (code : String)
    (view : Informal.Realizations.Context := context) : TermElabM Unit := do
  let selected ← obtain (← selectUses registry view (label "source"))
  match ← edge selected.1 name with
  | .error diagnostic => ensure (diagnostic.code == code) s!"{name}: expected {code}, got {diagnostic.code}"
  | .ok _ => throwError "Expected diagnostic {code} for {name}"

private def changeRequirement (input : Input) (key : RequirementKey) (f : Requirement → Requirement) : Input :=
  { input with requirements := input.requirements.map fun record =>
      if record.value.key == key then { record with value := f record.value } else record }

private def clearDeclarationRequirement (input : Input) (owner : RealizationKey) : Input :=
  { input with realizations := input.realizations.map fun record =>
      if record.value.key == owner then { record with value := { record.value with
        declarations := record.value.declarations.map fun decl => { decl with required := #[] } } }
      else record }

-- Synthetic contract key corruption updates references, never proof bindings or
-- observations. This constructs an admitted negative input, not new validation.
private def rekey (input : Input) (old new : RequirementKey) : Input := Id.run do
  let keys (xs : Array RequirementKey) := xs.map fun key => if key == old then new else key
  return { input with
    realizations := input.realizations.map fun record => { record with value := { record.value with
      required := keys record.value.required
      declarations := record.value.declarations.map fun decl => { decl with required := keys decl.required }
      facets := record.value.facets.map fun facet => { facet with required := keys facet.required } } }
    requirements := input.requirements.map fun record => { record with value := { record.value with
      key := if record.value.key == old then new else record.value.key
      prerequisites := keys record.value.prerequisites } }
    evidence := input.evidence.map fun record => { record with value := { record.value with
      requirement := if record.value.requirement == old then new else record.value.requirement } } }

private def authored (id : Name) (value : α) : Contribution α := {
  origin := {
    id := `dependencyControls ++ id
    moduleName := `VersoBlueprintTests.BlueprintRealizationDependencies
    source := "tests/VersoBlueprintTests/BlueprintRealizationDependencies.lean" }
  value }

-- Real native availability failure in a normal same-toolchain Lean environment
-- without the fixture module. This is a labeled negative environment injection,
-- not a fake unavailable observation and never a successful proof replacement.
private unsafe def unavailableCheck (witness : ObjectKey) (expected : Syntax)
    (documents : Array DocumentKey) : CoreM (Except Diagnostic NativeLean.Checked) := do
  liftM enableInitializersExecution
  let env ← liftM <| importModules #[{ module := `Lean }] {} (level := .server)
  withEnv env <| MetaM.run' <| TermElabM.run' <|
    NativeLean.check context.project witness expected documents

private unsafe def runControls : CommandElabM Unit := liftTermElabM do
  let sourceLabel := label "source"
  let before ← Informal.Environment.getNode? sourceLabel
  let some source := before | throwError "Missing accepted source"
  let beforeLabels ← Informal.Environment.labelsForLeanDecl `DependencySelectionFixture.source
  let expected ← `(term| True)
  let clean ← obtain (← project context.project (label "clean"))
  let admitted ← obtain (← project context.project (label "admitted"))
  let other ← obtain (← project context.project (label "other"))
  let cleanInput ← obtain (← clean.validate expected)
  let admittedInput ← obtain (← admitted.validate expected)
  let otherInput ← obtain (← other.validate expected)
  -- The source has accepted proof-axis uses, beyond the docstring-only Existing
  -- projection. Check its actual theorem directly; do not widen that adapter.
  let localSource ← obtain (← NativeLean.check context.project
    ⟨context, "DependencySelectionFixture.source"⟩ expected)
  let input := join (join cleanInput admittedInput) otherInput
  let registry ← obtain (admit input)
  let selected ← obtain (← selectUses registry context sourceLabel)
  ensure (decide (selected.1.map (·.1) = Informal.Graph.statementUses source) &&
    decide (selected.2.map (·.1) = Informal.Graph.proofUses source))
    "Effective axes, ordering and all UseRef metadata must be preserved exactly"
  ensure (selected.1.any fun e => e.1.label == label "clean" && e.1.origin == .manual && e.1.intent == .technical)
    "Manual technical metadata survives effective automatic/manual precedence"
  ensure (selected.1.any fun e => e.1.label == label "admitted" && e.1.intent == .auxiliary)
    "Auxiliary intent remains attached to the selected edge"
  ensure (selected.2.any fun e => e.1.label == label "other" && e.1.origin == .automatic)
    "Actual proof inference remains automatic, not reinterpreted as producer scope"
  let cleanKey ← obtain (← edge selected.1 (label "clean"))
  let cleanProofKey ← obtain (← edge selected.2 (label "clean"))
  let admittedKey ← obtain (← edge selected.1 (label "admitted"))
  ensure (cleanKey == proofKey clean && cleanProofKey == cleanKey && admittedKey == proofKey admitted)
    "One target on both axes selects the same declaration obligation without merging axes"
  ensure ((registry.resultForRequirement cleanKey).complete &&
    (registry.resultForRequirement admittedKey).status == .pending &&
    localSource.observation.outcome == .passed)
    "Actual clean proof completes, admitted target remains pending, local source proof is independent"
  for (name, key) in #[(label "clean", cleanKey), (label "admitted", admittedKey)] do
    let some target ← Informal.Environment.getNode? name | throwError "Missing accepted target"
    ensure (Informal.Graph.nodeLocalStatementFormalized {} target) "Both native statements are clean"
    ensure ((registry.resultForRequirement key).complete == Informal.Graph.nodeLocalFormalized {} target)
      "Supported theorem-local complete-proof policy agrees with canonical Graph/CodeHealth"
  for (name, code) in #[(label "missing", "missing-target"), (label "definition", "unsupported-target"),
      (label "grouped", "unsupported-target"), (Name.mkSimple "adapter.nonroundtrip", "unsupported-identity")] do
    edgeError registry name code
  match ← edge selected.2 (label "missing") with
  | .error diagnostic => ensure (diagnostic.code == "missing-target") "Unresolved target stays on both axes"
  | .ok _ => throwError "Missing proof-side edge was hidden"
  let empty ← obtain (← selectUses registry context (label "empty"))
  ensure (empty.1.isEmpty && empty.2.isEmpty) "A supported empty source is a successful empty pair"
  for (name, code) in #[(label "absent", "missing-source"), (label "definition", "unsupported-source")] do
    match ← selectUses registry context name with
    | .error diagnostic => ensure (diagnostic.code == code) "Source failure is not an empty dependency list"
    | .ok _ => throwError "Missing/unsupported source must not become no dependencies"
  match ← selectUses registry ⟨`rocq, context.project⟩ sourceLabel with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-view") "Only an explicit Lean view is supported"
  | .ok _ => throwError "Foreign view must not be silently treated as Lean"
  match ← selectUses registry ⟨`lean, .anonymous⟩ sourceLabel with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-view") "Missing project context is explicit"
  | .ok _ => throwError "A missing context must not acquire a default project"
  edgeError registry (label "clean") "wrong-default-context" ⟨`lean, `otherProject⟩
  let noDefault ← obtain (admit {})
  edgeError noDefault (label "clean") "missing-prerequisite"

  -- Selection does not inspect evidence or complete a caller's arbitrary goal.
  let noEvidence ← obtain (admit { input with evidence := #[] })
  let noEvidenceUses ← obtain (← selectUses noEvidence context sourceLabel)
  ensure ((← obtain (← edge noEvidenceUses.1 (label "clean"))) == cleanKey &&
    !(noEvidence.resultForRequirement cleanKey).complete) "Selection is independent of completion"
  let wrongExpected ← `(term| False)
  let wrongChecked ← obtain (← NativeLean.check context.project clean.witness wrongExpected)
  ensure (wrongChecked.observation.outcome == .failed) "The actual wrong expectation fails native matching"
  let wrongGoal := changeRequirement input cleanKey fun req =>
    { req with expected := .proof wrongChecked.goal clean.witness }
  let wrongGoal := { wrongGoal with evidence := wrongGoal.evidence.filter (·.value.requirement != cleanKey) }
  let wrongGoalRegistry ← obtain (admit wrongGoal)
  let some wrongBinding := wrongGoalRegistry.bindingFor cleanKey | throwError "Missing wrong-goal binding"
  let wrongGoalRegistry ← obtain (admit { wrongGoal with evidence := wrongGoal.evidence.push (authored `wrongGoal {
    id := `wrongGoal, requirement := cleanKey, binding := wrongBinding
    observation := .proof wrongChecked.observation }) })
  let wrongGoalUses ← obtain (← selectUses wrongGoalRegistry context sourceLabel)
  ensure ((← obtain (← edge wrongGoalUses.1 (label "clean"))) == cleanKey &&
    !(wrongGoalRegistry.resultForRequirement cleanKey).complete)
    "Contract selection is not certification of an independently elaborated wrong proposition"

  -- A genuinely checked complete alternative for the same admitted node cannot
  -- substitute for its selected default proof. No mock success is constructed.
  let alternative : RealizationKey := ⟨label "admitted", `alternative⟩
  let alternativeKey : RequirementKey := ⟨.declaration alternative clean.witness, `proof⟩
  let fresh ← obtain (← NativeLean.check context.project clean.witness expected
    (clean.input.objects.filterMap (·.value.document)))
  let withAlternative := { input with
    realizations := input.realizations.push (authored `alternative {
      key := alternative, context
      declarations := #[{ object := clean.witness, required := #[alternativeKey] }] })
    requirements := input.requirements.push (authored `alternativeRequirement {
      key := alternativeKey, expected := .proof fresh.goal clean.witness, coverage := .dependencyClosure }) }
  let alternativeRegistry ← obtain (admit withAlternative)
  let some alternativeBinding := alternativeRegistry.bindingFor alternativeKey | throwError "Missing alternative binding"
  let withAlternative := { withAlternative with evidence := withAlternative.evidence.push (authored `alternativeEvidence {
    id := `completeAlternative, requirement := alternativeKey, binding := alternativeBinding
    observation := .proof fresh.observation }) }
  let alternativeRegistry ← obtain (admit withAlternative)
  let alternativeUses ← obtain (← selectUses alternativeRegistry context sourceLabel)
  ensure ((alternativeRegistry.resultForRequirement alternativeKey).complete &&
    (alternativeRegistry.resultForRequirement admittedKey).status == .pending &&
    (← obtain (← edge alternativeUses.1 (label "admitted"))) == admittedKey)
    "Complete alternative is not implicitly selected instead of admitted default"
  let explicit := changeRequirement withAlternative admittedKey fun req => { req with prerequisites := #[alternativeKey] }
  let explicitRegistry ← obtain (admit explicit)
  let _ ← obtain (← selectUses explicitRegistry context sourceLabel)
  ensure ((explicitRegistry.requirement? admittedKey).any (·.prerequisites == #[alternativeKey]) &&
    explicitRegistry.contributions == explicit) "Explicit same-node cross-realization prerequisite remains untouched"

  -- Synthetic contract corruptions. Existing admission rejects invalid contexts;
  -- otherwise the adapter rejects policy-incompatible admitted contracts.
  for expectation in #[Expectation.review `proofread, .check `unitTests] do
    let bad ← obtain (admit (changeRequirement input cleanKey fun req => { req with expected := expectation }))
    edgeError bad (label "clean") "not-proof-requirement"
  let coverage ← obtain (admit (changeRequirement input cleanKey fun req => { req with coverage := .subject }))
  edgeError coverage (label "clean") "insufficient-coverage"
  let unrequired ← obtain (admit (clearDeclarationRequirement input clean.leanKey))
  edgeError unrequired (label "clean") "unrequired-default-proof"
  let facetKey : RequirementKey := ⟨.facet clean.leanKey `proof, `proof⟩
  let wrongSubject ← obtain (admit (rekey input cleanKey facetKey))
  edgeError wrongSubject (label "clean") "wrong-default-subject"
  let otherDeclarationKey : RequirementKey := ⟨.declaration clean.leanKey other.witness, `proof⟩
  let wrongDeclaration := rekey input cleanKey otherDeclarationKey
  let wrongDeclaration := changeRequirement wrongDeclaration otherDeclarationKey fun req =>
    { req with expected := .proof fresh.goal other.witness }
  let wrongDeclaration := { wrongDeclaration with realizations := wrongDeclaration.realizations.map fun record =>
    if record.value.key == clean.leanKey then { record with value := { record.value with
      declarations := record.value.declarations.map fun decl => { decl with object := other.witness }
      facets := record.value.facets.map fun facet => { facet with declarations := #[other.witness] } } }
    else record }
  let wrongDeclarationRegistry ← obtain (admit wrongDeclaration)
  edgeError wrongDeclarationRegistry (label "clean") "wrong-default-subject"
  let wrongWitness := clearDeclarationRequirement (changeRequirement input cleanKey fun req =>
    { req with expected := .proof fresh.goal other.witness }) clean.leanKey
  let wrongWitnessRegistry ← obtain (admit wrongWitness)
  edgeError wrongWitnessRegistry (label "clean") "wrong-default-witness"
  let foreignContext : Informal.Realizations.Context := ⟨`lean, `otherProject⟩
  let foreignGoal := { fresh.goal with context := foreignContext, documents := #[] }
  let foreignWitness := { clean.witness with context := foreignContext }
  let wrongContext := changeRequirement input cleanKey fun req => { req with expected := .proof foreignGoal foreignWitness }
  match admit wrongContext with
  | .error diagnostics => ensure (diagnostics.any (·.code == "wrong-project")) "Invalid goal context must be diagnostic"
  | .ok _ => throwError "Context-invalid contracts must not bypass pure admission"
  let mismatchedWitness := changeRequirement input cleanKey fun req => { req with expected := .proof fresh.goal foreignWitness }
  match admit mismatchedWitness with
  | .error diagnostics => ensure (diagnostics.any (·.code == "invalid-requirement")) "Witness/goal context disagreement is invalid"
  | .ok _ => throwError "Witness and goal contexts must agree"
  let ambiguous := { input with requirements := input.requirements.push (authored `ambiguous {
    key := facetKey, expected := .proof fresh.goal clean.witness, coverage := .dependencyClosure }) }
  let ambiguousRegistry ← obtain (admit ambiguous)
  ensure ((ambiguousRegistry.resultForRequirement cleanKey).complete) "One ambiguous candidate actually completes"
  edgeError ambiguousRegistry (label "clean") "ambiguous-prerequisite"
  let missingDefault := clearDeclarationRequirement withAlternative admitted.leanKey
  let missingDefault := { missingDefault with
    realizations := missingDefault.realizations.map fun record => { record with value := { record.value with
      facets := record.value.facets.map fun facet => { facet with required := facet.required.filter (· != admittedKey) } } }
    requirements := missingDefault.requirements.filter (·.value.key != admittedKey)
    evidence := missingDefault.evidence.filter (·.value.requirement != admittedKey) }
  let missingRegistry ← obtain (admit missingDefault)
  ensure ((missingRegistry.resultForRequirement alternativeKey).complete) "Alternative remains genuinely complete"
  edgeError missingRegistry (label "admitted") "missing-prerequisite"

  let absent ← obtain (← unavailableCheck clean.witness expected (clean.input.objects.filterMap (·.value.document)))
  ensure (absent.observation.outcome == .unavailable) "Actual native check without Provider must remain unavailable"
  let unavailable := { input with evidence := input.evidence.map fun record =>
    if record.value.requirement == cleanKey then
      { record with value := { record.value with observation := .proof absent.observation } } else record }
  let unavailableRegistry ← obtain (admit unavailable)
  let unavailableUses ← obtain (← selectUses unavailableRegistry context sourceLabel)
  ensure ((← obtain (← edge unavailableUses.1 (label "clean"))) == cleanKey &&
    (unavailableRegistry.resultForRequirement cleanKey).status == .blocked)
    "Selection stays fixed; native unavailability is preserved by the existing evaluator"
  let after ← Informal.Environment.getNode? sourceLabel
  ensure (reprStr before == reprStr after && beforeLabels ==
    (← Informal.Environment.labelsForLeanDecl `DependencySelectionFixture.source))
    "Accepted source/membership and contracts remain read-only"
  logInfo "Dependencies: axes/metadata preserved; clean proof complete; admitted proof pending; unresolved edges retained"

/-- info: Dependencies: axes/metadata preserved; clean proof complete; admitted proof pending; unresolved edges retained -/
#guard_msgs in
#eval runControls

end VersoBlueprintTests.BlueprintRealizationDependencies
