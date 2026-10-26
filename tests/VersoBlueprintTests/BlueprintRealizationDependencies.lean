/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Dependencies
import VersoBlueprint.Realizations.DependencyReport
import VersoBlueprint.Realizations.Existing
import VersoBlueprint.Realizations.Capture
import VersoBlueprint.Graph
import VersoBlueprintTests.BlueprintRealizationDependencies.Provider

/-! Actual accepted uses and native proof observations. The pure selector is
checked against its admitted contract and source facts; no legacy graph status
projection is treated as completion authority. All contract corruptions are
explicitly synthetic, and successful observations come from native checks. -/

open Lean Meta Elab Term Command
open Informal.Realizations Informal.Validation Informal.Translations
open Informal.Realizations.Existing
open Informal.Realizations.NativeSource Informal.Realizations.Dependencies

namespace VersoBlueprintTests.BlueprintRealizationDependencies

private def context : Informal.Realizations.Context := ⟨`lean, `dependencyPilot⟩
private def label (s : String) : Name := Name.mkSimple ("dependencies." ++ s)

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error error => throwError "Unexpected rejection: {repr error}"

private def proofKey (p : PreparedModel) : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩

-- The imported adapter provider deliberately contains an identity that the
-- native codec rejects. Remove just that invalid target inside a restored
-- environment so this test can capture the real dependency source and check
-- that its authored edge remains a missing-target diagnostic.
private def captureWithoutUnsupportedTarget : TermElabM Informal.Realizations.Capture.Snapshot := do
  withEnv (← getEnv) do
    let unsupported := Name.mkSimple "adapter.nonroundtrip"
    Informal.Environment.modify fun state => { state with
      data := state.data.erase unsupported
      pendingNodes := state.pendingNodes.erase unsupported
      factRecords := state.factRecords.filter (·.label != unsupported) }
    obtain (← Informal.Realizations.Capture.capture)

private def join (a b : Input) : Input := {
  nodes := a.nodes ++ b.nodes, documents := a.documents ++ b.documents
  objects := a.objects ++ b.objects, realizations := a.realizations ++ b.realizations
  translations := a.translations ++ b.translations, claims := a.claims ++ b.claims
  requirements := a.requirements ++ b.requirements, evidence := a.evidence ++ b.evidence
  bindingInputs := a.bindingInputs ++ b.bindingInputs }

private def edge (axis : Array SelectedUse) (name : Name) : TermElabM (Except Diagnostic RequirementKey) := do
  let some (_, result) := axis.find? (fun e => e.1.label == name) | throwError "Missing effective edge {name}"
  return result

private def field (value : Json) (name : String) : TermElabM Json :=
  obtain (value.getObjVal? name)

private def entries (value : Json) (name : String) : TermElabM (Array Json) := do
  obtain ((← field value name).getArr?)

private def reportedEdge (report : Json) (axis : String) (name : Name) : TermElabM Json := do
  for entry in ← entries (← field report "uses") axis do
    if (← field (← field entry "use") "label") == toJson name then
      return ← field entry "selection"
  throwError "Missing reported {axis} edge {name}"

private def assessedEntry (report : Json) (family : String) (key : Json) : TermElabM Json := do
  for entry in ← entries (← field report "registry") family do
    if (← field (← field entry "value") "key") == key then return entry
  throwError "Missing nested report entry in {family}: {key}"

private def reportFor (registry : Registry) (source : Name := label "source") : TermElabM Json := do
  let saved := registry.contributions
  let report ← obtain (← Report.ofSource registry context source)
  ensure ((← field report "registry") == Report.ofRegistry registry &&
    (← field report "source") == toJson source && (← field report "context") == toJson context &&
    (← obtain (Json.parse report.compress)) == report && registry.contributions == saved)
    "Direct-use report retains exact supplied report, explicit identity, structured JSON and read-only input"
  return report

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

-- Synthetic negative slot injection only. withEnv restores the accepted
-- environment through finally, including when the test action throws.
private def withSyntheticProofSlot (slot : Informal.Data.InformalData)
    (action : TermElabM α) : TermElabM α := do
  withEnv (← getEnv) do
    Informal.Environment.modify fun state =>
      match state.data.get? (label "source") with
      | none => state
      | some node => { state with data := state.data.insert (label "source") { node with proof := some slot } }
    action

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
  let statementUses := source.statement.toArray.flatMap (·.deps)
  let proofUses := source.proof.toArray.flatMap (·.deps)
  let beforeLabels ← Informal.Environment.labelsForLeanDecl `DependencySelectionFixture.source
  let consumerBefore ← Informal.Environment.getNode? (label "consumer")
  let consumerLabelsBefore ← Informal.Environment.labelsForLeanDecl `DependencySelectionFixture.consumer
  let some proofSlot := source.proof | throwError "Actual source must have proof uses"
  ensure (proofSlot.stx.isMissing && !proofSlot.hasBody && !proofSlot.deps.isEmpty)
    "The actual imported source has dependency-only proof metadata"
  let expected ← `(term| True)
  let clean ← obtain (← project context.project (label "clean"))
  let admitted ← obtain (← project context.project (label "admitted"))
  let other ← obtain (← project context.project (label "other"))
  let localSource ← obtain (← project context.project sourceLabel)
  let cleanInput ← obtain (← clean.validate expected)
  let admittedInput ← obtain (← admitted.validate expected)
  let otherInput ← obtain (← other.validate expected)
  let sourceInput ← obtain (← localSource.validate expected)
  ensure (localSource.leanKey == ⟨sourceLabel, `lean⟩ &&
    localSource.informalKey == ⟨sourceLabel, `docstring⟩ &&
    localSource.witness == ⟨context, "DependencySelectionFixture.source"⟩ &&
    localSource.moduleName == `VersoBlueprintTests.BlueprintRealizationDependencies.Provider &&
    localSource.docstringFormat == `verso)
    "Projection retains the source's actual canonical identities and native Verso format"
  let rawDoc := "\nThe source uses {uses \"dependencies.clean\" (intent := \"technical\")}[clean support]\nand {uses \"dependencies.admitted\" (intent := \"auxiliary\")}[unfinished support].\n"
  ensure (localSource.input.documents.any fun record =>
    record.value.key.context.language == `verso && record.value.text == rawDoc)
    "Own raw docstring bytes, including uses markup, are unchanged"
  let sourceBytes ← liftM <| IO.FS.readFile localSource.sourcePath
  ensure (localSource.input.documents.any fun record =>
    record.value.key == ⟨context, localSource.sourcePath⟩ && record.value.text == sourceBytes)
    "The native association retains the owning source bytes"
  let input := join (join (join cleanInput admittedInput) otherInput) sourceInput
  let registry ← obtain (admit input)
  let selected ← obtain (← selectUses registry context sourceLabel)
  ensure (decide (selected.1.map (·.1) = statementUses) &&
    decide (selected.2.map (·.1) = proofUses))
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
    (registry.resultForRequirement (proofKey localSource)).complete)
    "Local native proof completes while the admitted Blueprint dependency remains pending, without traversal"
  ensure ((registry.resultFor (.realization localSource.informalKey)).status == .unassessed &&
    (registry.requirement? (proofKey localSource)).any (·.prerequisites.isEmpty))
    "Projection does not assess prose or install mathematical dependencies as prerequisites"
  let consumerUses ← obtain (← selectUses registry context (label "consumer"))
  ensure ((← obtain (← edge consumerUses.1 sourceLabel)) == proofKey localSource)
    "An actual accepted consumer selects the dependency-only source's exact default proof"
  let report ← reportFor registry
  let statementReport ← entries (← field report "uses") "statement"
  let proofReport ← entries (← field report "uses") "proof"
  ensure (Json.arr (statementReport.map (·.getObjValD "use")) == toJson statementUses &&
    Json.arr (proofReport.map (·.getObjValD "use")) == toJson proofUses)
    "Reported effective axes, order and complete UseRef metadata match the actual accepted source"
  for (axis, key, name) in #[("statement", cleanKey, label "clean"),
      ("proof", cleanKey, label "clean"), ("statement", admittedKey, label "admitted")] do
    ensure ((← reportedEdge report axis name) == Json.mkObj [
      ("requirement", toJson key), ("result", toJson (registry.resultForRequirement key))])
      "Report retains exact selected requirement and existing result on each axis"
  let localProofReport ← assessedEntry report "requirements" (toJson (proofKey localSource))
  let proseReport ← assessedEntry report "realizations" (toJson localSource.informalKey)
  ensure ((← field (← field localProofReport "result") "status") == toJson Status.complete &&
    (← field (← field proseReport "result") "status") == toJson Status.unassessed &&
    (← field (← field (← reportedEdge report "statement" (label "admitted")) "result") "status") ==
      toJson Status.pending)
    "Complete local native proof, unassessed prose and pending direct dependency remain distinct"
  for (axis, selectedAxis) in #[("statement", selected.1), ("proof", selected.2)] do
    let .error diagnostic ← edge selectedAxis (label "missing") | throwError "Expected actual missing target"
    ensure ((← reportedEdge report axis (label "missing")) == Json.mkObj [("diagnostic", toJson diagnostic)])
      "Missing edge retains exact selection diagnostic, without fabricated status or dropped edge"
  let consumerReport ← reportFor registry (label "consumer")
  ensure ((← field (← reportedEdge consumerReport "statement" sourceLabel) "requirement") ==
    toJson (proofKey localSource)) "Real consumer reports the exact selected source proof"

  -- Actual accepted source presence is not a supplied source contract. Only a
  -- clean target is provided here; other accepted targets keep missing contracts.
  let sparseRegistry ← obtain (admit cleanInput)
  let sparseReport ← reportFor sparseRegistry
  let sparseRequirements ← entries (← field sparseReport "registry") "requirements"
  ensure (!(sparseRegistry.nodes.any (·.label == sourceLabel)) &&
    sparseRequirements.size == 1 &&
    (← field (← reportedEdge sparseReport "statement" (label "clean")) "requirement") == toJson cleanKey &&
    (← field (← reportedEdge sparseReport "statement" (label "admitted")) "diagnostic").getObjValD "code" ==
      toJson "missing-prerequisite" &&
    (← field (← field sparseRequirements[0]! "value") "key") == toJson cleanKey)
    "Sparse report supplies only its actual clean contract, never source completion or another target's proof"

  -- Synthetic rejected proof representations supply no successful facts. Each
  -- mutation is confined to withEnv, and checked again after normal restoration.
  let preview : Verso.Doc.Block Verso.Genre.Manual := .para #[.text "Synthetic proof body"]
  let placeholder : Syntax := mkIdent `syntheticProofPlaceholder
  let rejectedSlots : Array (String × Informal.Data.InformalData) := #[
    ("nonmissing placeholder without body", { stx := placeholder }),
    ("authored preview body", { stx := placeholder, previewBlocks := #[preview] }),
    ("authored elaboration body", { stx := placeholder, elabStx := #[placeholder] }),
    ("missing syntax with retained preview", { stx := .missing, previewBlocks := #[preview] }),
    ("missing syntax with retained elaboration", { stx := .missing, elabStx := #[placeholder] })]
  for (description, slot) in rejectedSlots do
    withSyntheticProofSlot slot do
      match ← project context.project sourceLabel with
      | .error diagnostic => ensure (diagnostic.code == "unsupported-node") s!"Reject {description}"
      | .ok _ => throwError "Unsupported proof slot passed: {description}"
    ensure (reprStr before == reprStr (← Informal.Environment.getNode? sourceLabel))
      "Synthetic slot injection restores accepted state after normal return"
  let mut caught := false
  try
    withSyntheticProofSlot { stx := placeholder } do
      let some injected ← Informal.Environment.getNode? sourceLabel | throwError "Missing injection source"
      ensure (injected.proof.any (·.stx == placeholder)) "Failure probe runs inside injected environment"
      throwError "synthetic proof-slot action failure"
  catch ex =>
    ensure ((← ex.toMessageData.toString) == "synthetic proof-slot action failure") "Catch only the deliberate test failure"
    caught := true
  ensure (caught && reprStr before == reprStr (← Informal.Environment.getNode? sourceLabel))
    "Synthetic slot injection also restores accepted state after failure"
  for (name, key) in #[(label "clean", cleanKey), (label "admitted", admittedKey)] do
    let some target ← Informal.Environment.getNode? name | throwError "Missing accepted target"
    ensure (target.leanDecls.size == 1) "The accepted concept retains its native declaration inventory"
    ensure ((registry.localResult key).complete == (name == label "clean"))
      "Fresh native observations distinguish the clean theorem from its admitted counterpart"
  for (name, code) in #[(label "missing", "missing-target"), (label "definition", "unsupported-target"),
      (label "grouped", "unsupported-target"), (Name.mkSimple "adapter.nonroundtrip", "unsupported-identity")] do
    edgeError registry name code
  match ← edge selected.2 (label "missing") with
  | .error diagnostic => ensure (diagnostic.code == "missing-target") "Unresolved target stays on both axes"
  | .ok _ => throwError "Missing proof-side edge was hidden"
  let empty ← obtain (← selectUses registry context (label "empty"))
  ensure (empty.1.isEmpty && empty.2.isEmpty) "A supported empty source is a successful empty pair"
  let emptyReport ← reportFor registry (label "empty")
  ensure ((← entries (← field emptyReport "uses") "statement").isEmpty &&
    (← entries (← field emptyReport "uses") "proof").isEmpty) "Supported empty source reports empty axes"
  for (name, code) in #[(label "absent", "missing-source"), (label "definition", "unsupported-source")] do
    match ← selectUses registry context name with
    | .error diagnostic =>
      ensure (diagnostic.code == code) "Source failure is not an empty dependency list"
      match ← Report.ofSource registry context name with
      | .error reported => ensure (reported == diagnostic) "Report preserves exact outer source failure"
      | .ok _ => throwError "Source failure must not become an empty report"
    | .ok _ => throwError "Missing/unsupported source must not become no dependencies"
  match ← selectUses registry ⟨`rocq, context.project⟩ sourceLabel with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-view") "Only an explicit Lean view is supported"
  | .ok _ => throwError "Foreign view must not be silently treated as Lean"
  match ← selectUses registry ⟨`lean, .anonymous⟩ sourceLabel with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-view") "Missing project context is explicit"
  | .ok _ => throwError "A missing context must not acquire a default project"
  for view in #[Informal.Realizations.Context.mk `rocq context.project, ⟨`lean, .anonymous⟩] do
    let .error diagnostic ← selectUses registry view sourceLabel | throwError "Expected view failure"
    match ← Report.ofSource registry view sourceLabel with
    | .error reported => ensure (reported == diagnostic) "Report preserves exact outer view failure"
    | .ok _ => throwError "Invalid view must not acquire a report"
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
      key := alternativeKey, expected := .proof fresh.goal clean.witness, coverage := .dependencyClosure })
    bindingInputs := input.bindingInputs ++ fresh.semanticContext.toArray.map (fun content => authored `alternativeContext {
      subject := alternativeKey.subject, name := NativeLean.expectedContextFor alternativeKey, content }) }
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
  let alternativeReport ← reportFor alternativeRegistry
  let selectedDefault ← reportedEdge alternativeReport "statement" (label "admitted")
  ensure ((← field selectedDefault "requirement") == toJson admittedKey &&
    (← field (← field selectedDefault "result") "status") == toJson Status.pending)
    "Report keeps pending default despite genuinely complete alternative"
  let explicit := changeRequirement withAlternative admittedKey fun req => { req with prerequisites := #[alternativeKey] }
  let explicitRegistry ← obtain (admit explicit)
  let _ ← obtain (← selectUses explicitRegistry context sourceLabel)
  let _ ← reportFor explicitRegistry
  ensure ((explicitRegistry.requirement? admittedKey).any (·.prerequisites == #[alternativeKey]) &&
    explicitRegistry.contributions == explicit) "Explicit same-node cross-realization prerequisite remains untouched"

  -- Synthetic contract corruptions. Existing admission rejects invalid contexts;
  -- otherwise the adapter rejects policy-incompatible admitted contracts.
  for expectation in #[Expectation.review `proofread, .check `unitTests, .check `proof,
      .check NativeLean.statementValidator] do
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
  let wrongDeclaration := { wrongDeclaration with
    bindingInputs := wrongDeclaration.bindingInputs.filter
      (·.value.subject != .declaration clean.leanKey clean.witness)
    realizations := wrongDeclaration.realizations.map fun record =>
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
  let ambiguousReport ← reportFor ambiguousRegistry
  let ambiguousUses ← obtain (← selectUses ambiguousRegistry context sourceLabel)
  let .error ambiguity ← edge ambiguousUses.1 (label "clean") | throwError "Expected selector ambiguity"
  ensure ((← reportedEdge ambiguousReport "statement" (label "clean")) ==
    Json.mkObj [("diagnostic", toJson ambiguity)]) "Ambiguity stays an exact diagnostic, not a validation status"
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
  let unavailableReport ← reportFor unavailableRegistry
  let unavailableEdge ← reportedEdge unavailableReport "statement" (label "clean")
  ensure ((← field unavailableEdge "requirement") == toJson cleanKey &&
    (← field (← field unavailableEdge "result") "status") == toJson Status.blocked)
    "Actual native unavailability reports blocked existing validation with unchanged selected key"
  let after ← Informal.Environment.getNode? sourceLabel
  ensure (reprStr before == reprStr after && beforeLabels ==
    (← Informal.Environment.labelsForLeanDecl `DependencySelectionFixture.source) &&
    reprStr consumerBefore == reprStr (← Informal.Environment.getNode? (label "consumer")) &&
    consumerLabelsBefore == (← Informal.Environment.labelsForLeanDecl `DependencySelectionFixture.consumer))
    "Accepted source/membership and contracts remain read-only"
  logInfo "Selector fixture: axes/metadata preserved; clean contract complete; admitted contract pending; unresolved edges retained"
  logInfo "Projection fixture: native proof checked locally; prose unassessed; Blueprint dependency remains pending"

-- Public consumer behavior comes from an ordinary capture of the imported
-- source, not from the hand-assembled Registry used by the pure selector tests.
-- First retain the full-batch rejection from the separate invalid-identity
-- fixture, then isolate only that intentionally unsupported target below.
run_cmd liftTermElabM do
  match ← Informal.Realizations.Capture.capture with
  | .error diagnostics =>
    ensure (diagnostics.any (·.code == "unsupported-native-identity"))
      s!"Full source capture must expose the invalid imported identity: {repr diagnostics}"
  | .ok _ => throwError "Full source capture accepted the deliberately invalid imported identity"

run_cmd liftTermElabM do
  let snapshot ← captureWithoutUnsupportedTarget
  let sourceLabel := label "source"
  let some source ← Informal.Environment.getNode? sourceLabel
    | throwError "Missing actual dependency source"
  let statementRefs := source.statement.toArray.flatMap (·.deps)
  let proofRefs := source.proof.toArray.flatMap (·.deps)
  let capturedStatement := snapshot.uses.filter fun use =>
    use.source == sourceLabel && use.realization.all (· == `lean) && use.facet == `statement
  let capturedProof := snapshot.uses.filter fun use =>
    use.source == sourceLabel && use.realization.all (· == `lean) && use.facet == `proof
  let mergeReferences (uses : Array Informal.Realizations.Capture.SelectedUse) :=
    Informal.Data.UseRef.mergeByLabel #[] (uses.map (·.reference))
  unless mergeReferences capturedStatement == statementRefs && mergeReferences capturedProof == proofRefs do
    throwError s!"Ordinary capture changed the real source uses: statement source={repr statementRefs}; " ++
      s!"captured={repr (mergeReferences capturedStatement)}; proof source={repr proofRefs}; " ++
      s!"captured={repr (mergeReferences capturedProof)}"
  ensure (capturedStatement.any fun use => use.realization.isNone &&
    use.reference.label == label "admitted" && use.reference.origin == .manual &&
    use.reference.intent == .auxiliary)
    "The shared manual statement edge retains its scope, origin, and intent"
  ensure (capturedStatement.any fun use => use.realization.isNone &&
    use.reference.label == label "clean" && use.reference.origin == .manual &&
    use.reference.intent == .technical)
    "A shared manual edge retains authored precedence metadata beside its automatic twin"
  ensure (capturedStatement.any fun use => use.realization == some `lean &&
    use.reference.label == label "clean" && use.reference.origin == .automatic)
    "The inferred native dependency remains scoped to the Lean realization"
  let assessment := snapshot.assessmentFor sourceLabel
  ensure (assessment.nativeProofComplete && !assessment.requiredComplete)
    "The source's checked native proof remains distinct from unfinished selected Blueprint requirements"
  let findUse (uses : Array Informal.Realizations.Capture.SelectedUse) (facet target : Name) :=
    uses.find? (fun use => use.facet == facet && use.reference.label == target)
  match findUse capturedStatement `statement (label "clean") with
  | some use =>
    match use.selected with
    | .ok keys =>
      ensure (keys.size == 1 &&
        (snapshot.registry.localResult keys[0]!).complete &&
        (snapshot.registry.resultForRequirement keys[0]!).complete)
        "The actual complete clean dependency selects its current native requirement"
    | .error diagnostic => throwError "Clean target was not selected: {diagnostic.code}"
  | none => throwError "Actual statement dependency to clean was lost"
  match findUse capturedStatement `statement (label "admitted") with
  | some use =>
    match use.selected with
    | .ok keys =>
      ensure (keys.size == 1 && !(snapshot.registry.resultForRequirement keys[0]!).complete)
        "The actual admitted dependency remains selected and unfinished"
    | .error diagnostic => throwError "Admitted target was not selected: {diagnostic.code}"
  | none => throwError "Actual statement dependency to admitted was lost"
  for (uses, facet) in #[(capturedStatement, `statement), (capturedProof, `proof)] do
    let some edge := findUse uses facet (label "missing")
      | throwError "Actual unresolved {facet} dependency was dropped"
    match edge.selected with
    | .error diagnostic => do
      ensure (diagnostic.code == "missing-target") "An unresolved source edge remains an explicit selection diagnostic"
    | .ok _ => throwError "A missing target acquired a successful requirement"
  let some unsupported := findUse capturedStatement `statement (Name.mkSimple "adapter.nonroundtrip")
    | throwError "The real source's unsupported-identity dependency was dropped"
  match unsupported.selected with
  | .error diagnostic => do
      ensure (diagnostic.code == "missing-target") "An intentionally omitted invalid target remains an unresolved edge"
  | .ok _ => throwError "An unsupported native identity acquired a successful requirement"

-- Several full reports and native negative checks share this guarded command.
-- The larger test-only budget changes no provider or evaluation policy.
set_option maxHeartbeats 1000000 in
/--
info: Selector fixture: axes/metadata preserved; clean contract complete; admitted contract pending; unresolved edges retained
---
info: Projection fixture: native proof checked locally; prose unassessed; Blueprint dependency remains pending
-/
#guard_msgs in
#eval runControls

end VersoBlueprintTests.BlueprintRealizationDependencies
