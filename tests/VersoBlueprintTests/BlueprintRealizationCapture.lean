/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalSourcePersistence.Attachment
import VersoBlueprintTests.BlueprintRealizationCapture.FenceOwner
import VersoBlueprintTests.BlueprintRealizationCapture.IncrementalFenceOwner
import VersoBlueprint.Realizations.Capture
import VersoBlueprint.Realizations.Authoring

open Lean Meta Elab Command Term Informal
open Realizations Validation Translations

set_option trace.blueprint.capture true

namespace RealizationCaptureFixture

-- Recipe steps are projections of raw registrations, never independent inputs.
#check_failure (fun (p : Informal.Realizations.Capture.Plan) => { p with ordinary := #[] })

/-- Native validity does not require an independent restatement. -/
@[blueprint "capture.complete"]
theorem complete : True := True.intro

/-- An admitted native proof remains unfinished. -/
@[blueprint "capture.admitted"]
theorem admitted : True := by sorry

/-- A clean local proof with an unfinished mathematical prerequisite. -/
@[blueprint "capture.dependent" (proofUses := ["capture.admitted"])]
theorem dependent : True := True.intro

/-- Missing labels remain visible and block the Blueprint closure. -/
@[blueprint "capture.missing" (uses := ["capture.absent"])]
theorem missing : True := True.intro

/-- Forward references are collected before selection. -/
@[blueprint "capture.cycleA" (uses := ["capture.cycleB"])]
theorem cycleA : True := True.intro

/-- Cycles use the existing evaluator and cannot certify themselves. -/
@[blueprint "capture.cycleB" (uses := ["capture.cycleA"])]
theorem cycleB : True := True.intro

/-- One concept can select several native declarations. -/
@[blueprint "capture.grouped"]
theorem groupedComplete : True := True.intro

@[blueprint "capture.grouped"]
theorem groupedAdmitted : True := by sorry

/-- A multi-declaration target requires every selected declaration. -/
@[blueprint "capture.groupedDependent" (uses := ["capture.grouped"]) (proofUses := ["capture.grouped"])]
theorem groupedDependent : True := True.intro

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with | .ok value => pure value | .error issues => throwError "{repr issues}"

private def key (label : String) (declaration : Name) (name : Name := `proof) : RequirementKey :=
  ⟨.declaration ((⟨Name.mkSimple label, `lean⟩ : RealizationKey).forRole `proof)
    ⟨⟨`lean, `blueprintFixtures⟩, declaration.toString⟩, name⟩

private def implementationKey (label : String) (declaration : Name) : RequirementKey :=
  ⟨.declaration ((⟨Name.mkSimple label, `lean⟩ : RealizationKey).forRole `implementation)
    ⟨⟨`lean, `blueprintFixtures⟩, declaration.toString⟩, `implementation⟩

-- Real imported sources and fresh kernel observations; no mocked provider facts.
run_cmd liftTermElabM do
  let before := Environment.informalExt.getState (← getEnv)
  ensure before.authoringRecords.isEmpty "Control accidentally enrolled opt-in defaults"
  let start ← IO.monoMsNow
  let plan := Capture.plan (Capture.Raw.ofState before)
  let reads ← IO.mkRef (#[] : Array System.FilePath)
  let observations ← obtain (← Capture.observe plan fun path => do
    reads.modify (·.push path)
    IO.FS.readFile path)
  let observedAt ← IO.monoMsNow
  let snapshot ← obtain (Capture.evaluate plan observations)
  let evaluatedAt ← IO.monoMsNow
  let elapsed := evaluatedAt - start
  logInfo m!"split phases: observe {observedAt - start} ms; evaluate {evaluatedAt - observedAt} ms"
  let paths ← reads.get
  ensure (paths.isEmpty && plan.documents.isEmpty && observations.documents.isEmpty &&
    !observations.native.isEmpty && !observations.documented.isEmpty &&
    observations.native.any (·.request.name == `storedInline))
    "Compiled inline Lean, docstrings and authored prose must perform no source reads"
  let reversed : Capture.Observations := {
    documents := observations.documents.reverse, native := observations.native.reverse
    documented := observations.documented.reverse
    checks := observations.checks.reverse, specifications := observations.specifications.reverse
    expected := observations.expected.reverse }
  let replay ← obtain (Capture.evaluate plan reversed)
  ensure (snapshot.registry.contributions == replay.registry.contributions &&
    snapshot.sourceDiagnostics == replay.sourceDiagnostics && reprStr snapshot.uses == reprStr replay.uses)
    "Observation insertion order changed exact contributions, bindings, diagnostics or selected-use metadata"
  let nativeInventory (s : Capture.Snapshot) := s.nativeChecks.map fun c =>
    (c.declaration, c.kind, c.statement, c.body, c.status)
  ensure (nativeInventory snapshot == nativeInventory replay) "Observation order changed native inventory"
  -- Answers are identified by the request they answer, not by a plan position.
  -- A separately built plan of the same source state, whose requests sit at
  -- different positions, accepts the same answers and yields the same snapshot.
  let rebuiltRaw := Capture.Raw.ofState (Environment.informalExt.getState (← getEnv))
  let reorderedPlan := Capture.plan { rebuiltRaw with nodes := rebuiltRaw.nodes.reverse }
  ensure (reorderedPlan.checks.map (·.witness) != plan.checks.map (·.witness))
    "Cross-plan control must place its requests at different positions"
  let crossPlan ← obtain (Capture.evaluate reorderedPlan observations)
  let registryView (s : Capture.Snapshot) := (s.registry.nodes, s.registry.documents, s.registry.objects,
    s.registry.realizations, s.registry.requirements, s.registry.evidence, s.registry.bindingInputs)
  ensure (registryView snapshot == registryView crossPlan && snapshot.sourceDiagnostics == crossPlan.sourceDiagnostics &&
    snapshot.registry.nodes.all fun node =>
      (snapshot.assessmentFor node.label).details == (crossPlan.assessmentFor node.label).details)
    "Answers observed for one plan must serve a separately built plan of the same source state"
  -- Fault injection only at the pure boundary; successful facts come from real
  -- providers, never mocked proof success.
  let rejects (code : String) (batch : Capture.Observations) : TermElabM Unit := do
    match Capture.evaluate plan batch with
    | .ok _ => throwError "Malformed observation batch was admitted: {code}"
    | .error issues => ensure (issues.any (·.code == code)) s!"Wrong batch rejection: {repr issues}"
  let some native := observations.native[0]? | throwError "Missing actual native request"
  rejects "duplicate-observation" { observations with native := observations.native.push native }
  let unrequested ← obtain (Capture.evaluate plan { observations with native := observations.native.push {
    native with request := { native.request with name := `unrequestedDeclaration } } })
  ensure (unrequested.registry.contributions == snapshot.registry.contributions &&
    unrequested.sourceDiagnostics == snapshot.sourceDiagnostics)
    "An unrequested compiled answer changed the snapshot"
  for batch in #[
      { observations with native := observations.native.extract 1 observations.native.size },
      { observations with documented := observations.documented.extract 1 observations.documented.size },
      { observations with checks := observations.checks.extract 1 observations.checks.size }] do
    rejects "missing-observation" batch
  let some check := observations.checks[0]? | throwError "Missing actual check control"
  let .ok checked := check.result | throwError "Expected a real checked declaration"
  rejects "mismatched-observation" { observations with checks := observations.checks.modify 0 fun entry =>
    { entry with result := .ok { checked with declaration := { checked.declaration with native := "wrong.witness" } } } }
  let some proofAnswer := observations.checks.find? (·.request.witness.native == (``complete).toString)
    | throwError "Missing checked theorem for malformed role controls"
  let .ok proofValue := proofAnswer.result | throwError "Expected a real theorem observation"
  let some classification := proofValue.classification | throwError "Expected a classified theorem"
  let rejectCheck (value : NativeLean.CheckedDeclaration) := rejects "mismatched-observation"
    { observations with checks := observations.checks.map fun entry =>
        if entry.request == proofAnswer.request then { entry with result := .ok value } else entry }
  ensure (proofValue.body.proposition && proofValue.roles == #[`statement, `proof] &&
    proofValue.statement.outcome == .passed && proofValue.body.outcome == .passed)
    "The role controls must start from a genuinely checked proof"
  let rejectRoles (roles : Array Name) :=
    rejectCheck { proofValue with classification := some { classification with roles } }
  rejectRoles (proofValue.roles.push `unexpected)
  rejectRoles (proofValue.roles.push `implementation)
  rejectRoles #[`proof]
  rejectCheck { proofValue with classification := some { classification with statementKind := .definition } }
  let unknown := NativeLean.CheckedDeclaration.ofClassification proofValue.declaration none
    proofValue.status proofValue.assumptions
  ensure (unknown.roles.isEmpty && unknown.statement.outcome == .unavailable &&
    unknown.body.outcome == .unavailable && !unknown.body.proposition)
    "An unavailable classification cannot derive any passing check even from a complete inspection"
  logInfo m!"ordinary capture: {snapshot.registry.nodes.size} nodes in {elapsed} ms"
  let registry := snapshot.registry
  -- Public consumer projections retain native validity separately from Blueprint
  -- prerequisites, and do not borrow validity from a complete sibling.
  let completeView := snapshot.assessmentFor (Name.mkSimple "capture.complete")
  ensure (completeView.hasNativeDeclarations && completeView.nativeStatementComplete &&
    completeView.nativeBodyComplete && completeView.requiredComplete &&
    completeView.proofDependenciesComplete) "Complete public assessment lost its native checks"
  let admittedView := snapshot.assessmentFor (Name.mkSimple "capture.admitted")
  ensure (admittedView.nativeStatementComplete && !admittedView.nativeBodyComplete &&
    !admittedView.requiredComplete) "Public assessment hid an admitted native body"
  for label in #["capture.dependent", "capture.missing", "capture.cycleA", "capture.groupedDependent"] do
    let view := snapshot.assessmentFor (Name.mkSimple label)
    ensure (view.nativeBodyComplete && !view.requiredComplete && !view.proofDependenciesComplete)
      s!"Public assessment conflated local proof and prerequisites for {label}"
  let groupedView := snapshot.assessmentFor (Name.mkSimple "capture.grouped")
  ensure (groupedView.nativeStatementComplete && !groupedView.nativeBodyComplete &&
    !groupedView.requiredComplete) "Public assessment borrowed the complete sibling's proof"
  -- Statement-only is a legal theorem-shaped classification in isolation.
  -- It cannot override the same declaration's independently prepared proof role.
  let some admittedAnswer := observations.checks.find? (·.request.witness.native == (toString ``groupedAdmitted))
    | throwError "Missing the genuinely admitted sibling's check"
  let .ok admittedCheck := admittedAnswer.result | throwError "Missing classified admitted sibling"
  let some admittedClassification := admittedCheck.classification
    | throwError "The admitted sibling must have a known classification"
  let weakenedCheck := { admittedCheck with
    classification := some { admittedClassification with roles := #[`statement] } }
  ensure (admittedCheck.roles == #[`statement, `proof] && admittedCheck.body.outcome == .failed &&
      weakenedCheck.rolesAgree)
    "Disagreement control must retain genuinely failed proof evidence and a legal replay shape"
  let disagreement ← obtain (Capture.evaluate plan { observations with checks := observations.checks.map fun answer =>
    if answer.request == admittedAnswer.request then { answer with result := .ok weakenedCheck } else answer })
  let groupedLabel := Name.mkSimple "capture.grouped"
  let disagreed := disagreement.assessmentFor groupedLabel
  let admittedProof := key "capture.grouped" ``groupedAdmitted
  let cleanProof := key "capture.grouped" ``groupedComplete
  ensure (!disagreed.nativeStatementComplete && !disagreed.nativeBodyComplete &&
    disagreed.proofRoleComplete == some false && !disagreed.requiredComplete &&
    (disagreement.registry.requirement? admittedProof).isSome &&
    !(disagreement.registry.localResult admittedProof).complete &&
    !(disagreement.registry.resultForRequirement admittedProof).complete &&
    (disagreement.registry.resultForRequirement cleanProof).complete)
    "Disagreement erased a failed proof obligation or discredited the checked sibling"
  ensure (disagreement.sourceDiagnostics.nodes.any fun (label, diagnostic) =>
    label == groupedLabel && diagnostic.code == "native-role-disagreement" &&
      diagnostic.subject == admittedCheck.declaration.native)
    "Replay disagreement lost its precise declaration and node diagnostic"
  ensure (completeView.details.getObjVal? "assessment" |>.isOk)
    "Public assessment omitted exact subjects and contracts"
  ensure (NodeAssessment.fromJsonString! (toJson completeView).compress == completeView)
    "Serializable captured assessment did not round-trip"
  ensure (completeView.selectedLeanUseCount == 0 &&
    completeView.leanDependencyMessage == "No Lean prerequisites selected")
    "An empty Lean dependency selection was presented as completed work"
  -- Projection-only edge controls reuse the actual registry/provider outcomes.
  -- Foreign realizations, foreign contexts and failed native selections must
  -- remain inspectable without confusing the selected native prerequisite set.
  let label := Name.mkSimple "capture.complete"
  let some failedUse := snapshot.uses.find? (·.source == Name.mkSimple "capture.missing")
    | throwError "Missing actual unresolved selection control"
  let nativeUse := { failedUse with source := label, realization := some `lean }
  let foreignUse := { nativeUse with realization := some `rocqTranslation }
  let foreignContext := { nativeUse with context := some ⟨`lean, `otherProject⟩ }
  let completeUse := { nativeUse with
    reference := { nativeUse.reference with label }
    selected := .ok #[key "capture.complete" `RealizationCaptureFixture.complete] }
  for (uses, count, message) in #[
      (#[foreignUse], 0, "No Lean prerequisites selected"),
      (#[foreignContext], 0, "No Lean prerequisites selected"),
      (#[foreignUse, nativeUse], 1, "Selected Lean prerequisites unfinished"),
      (#[foreignUse, completeUse], 1, "Selected Lean prerequisites complete")] do
    let view := ({ snapshot with uses }).assessmentFor label
    ensure (view.selectedLeanUseCount == count && view.leanDependencyMessage == message)
      "Dependency message did not describe the selected Lean subset"
    let inventory ← obtain (view.details.getObjValAs? (Array Json) "uses")
    ensure (inventory.size == uses.size)
      "Full edge inventory lost foreign or unresolved uses"
    ensure (NodeAssessment.fromJsonString! (toJson view).compress == view)
      "Selection count did not survive the public assessment round-trip"
  let missingModel := `capture.noNativeModel
  let view := ({ snapshot with uses := #[{ nativeUse with source := missingModel }] }).assessmentFor missingModel
  ensure (!view.hasNativeDeclarations && view.selectedLeanUseCount == 0 &&
    view.leanDependencyMessage == "No Lean prerequisites selected")
    "A missing native realization was treated as selecting native prerequisites"
  let foreignKey := (⟨Name.mkSimple "storage.source", `rocqTranslation⟩ : RealizationKey).forRole `implementation
  let some foreign := registry.realization? foreignKey | throwError "Imported named realization disappeared"
  ensure (foreign.context.language == `rocq && foreign.role == `implementation &&
      foreign.declarations.isEmpty && (registry.resultFor (.realization foreignKey)).status == .unassessed)
    "Foreign source borrowed a native declaration or validation"
  ensure (before.inventory.get? (Name.mkSimple "storage.source") |>.any fun node =>
      node.sources.any fun source => source.destination.realization == ⟨Name.mkSimple "storage.source", `rocqTranslation⟩ &&
        source.destination.role == some `implementation)
    "Accepted source inventory flattened the imported named destination"
  ensure snapshot.diagnostics.isEmpty s!"Unexpected source/provider diagnostics: {repr snapshot.diagnostics}"
  ensure (registry.nodes.size == before.inventory.size) "Capture omitted ordinary accepted concepts"
  ensure ((registry.resultForRequirement (key "capture.complete" `RealizationCaptureFixture.complete)).complete)
    "Complete native theorem did not complete"
  ensure (!(registry.resultForRequirement (key "capture.admitted" `RealizationCaptureFixture.admitted)).complete)
    "Admitted theorem completed"
  for (label, declaration) in #[("capture.dependent", `RealizationCaptureFixture.dependent),
      ("capture.missing", `RealizationCaptureFixture.missing),
      ("capture.cycleA", `RealizationCaptureFixture.cycleA),
      ("capture.cycleB", `RealizationCaptureFixture.cycleB),
      ("capture.groupedDependent", `RealizationCaptureFixture.groupedDependent)] do
    let requirement := key label declaration
    ensure ((registry.localResult requirement).complete && !(registry.resultForRequirement requirement).complete)
      s!"Native proof and Blueprint closure were conflated for {label}"
  ensure (snapshot.uses.any fun use => use.reference.label == Name.mkSimple "capture.absent" &&
    match use.selected with | .error diagnostic => diagnostic.code == "missing-target" | _ => false)
    "Missing edge disappeared or became an invented target requirement"
  let displayLeft := Name.mkSimple "foo.bar»"
  let displayRight := Name.str (Name.mkSimple "foo") "bar»"
  ensure (displayLeft != displayRight && reprStr displayLeft == reprStr displayRight)
    "Producer-identity collision fixture no longer has equal display spellings"
  let some (_, baseNode) := before.inventory.toArray[0]? | throwError "Missing node metadata fixture"
  let accepted : Data.NodeInventory := { baseNode with
    sources := #[], uses := #[], nativeAssociations := #[] }
  let pending : NameSet := (({} : NameSet).insert displayLeft).insert displayRight
  let collisionRaw : Capture.Raw := {
    nodes := #[(displayLeft, accepted), (displayRight, accepted)]
    registered := pending, facts := [], authored := #[], initialIssues := #[] }
  let collisionPlan := Capture.plan collisionRaw
  match Capture.evaluate collisionPlan {} with
  | .ok _ => throwError "Capture accepted names that cannot round-trip through public graph JSON"
  | .error issues => ensure (issues.any (·.code == "unsupported-public-label")) "Unsupported public names need a specific capture diagnostic"
  let flat := Name.mkSimple "public.dotted"
  let hierarchical := Name.str `public "dotted"
  ensure (flat != hierarchical && flat.toString.toName == flat && hierarchical.toString.toName == hierarchical &&
    Data.Label.publicString flat == Data.Label.publicString hierarchical)
    "Public spelling collision must be between individually round-tripping names"
  let publicRaw : Capture.Raw := { collisionRaw with
    nodes := #[(flat, accepted), (hierarchical, accepted)]
    registered := (({} : NameSet).insert flat).insert hierarchical }
  for nodes in #[publicRaw.nodes, publicRaw.nodes.reverse] do
    let publicPlan := Capture.plan { publicRaw with nodes }
    match Capture.evaluate publicPlan {} with
    | .ok _ => throwError "Capture accepted ambiguous graph/CLI labels"
    | .error issues => ensure (issues.any (·.code == "ambiguous-public-label")) "Public label collisions need a specific capture diagnostic"
  for label in #[flat, hierarchical] do
    let singlePlan := Capture.plan { publicRaw with nodes := #[(label, accepted)] }
    let single ← obtain (Capture.evaluate singlePlan {})
    ensure (single.registry.nodes.size == 1) "Either public spelling is supported when unambiguous"
  -- Unresolved targets also enter the public graph, and must not alias a node.
  let withUse : Data.NodeInventory := { accepted with uses := #[{
      node := flat, role := `statement, reference := { label := hierarchical } }] }
  let targetPlan := Capture.plan { publicRaw with nodes := #[(flat, withUse)] }
  match Capture.evaluate targetPlan {} with
  | .ok _ => throwError "Unresolved dependency target aliased a public node label"
  | .error issues => ensure (issues.any (·.code == "ambiguous-public-label")) "Missing target alias diagnostic"
  let withGroup (parent : Name) : Data.NodeInventory := { accepted with
    parent := some parent }
  let groupRaw : Capture.Raw := { publicRaw with
    nodes := #[(`firstGroupNode, withGroup flat), (`secondGroupNode, withGroup hierarchical)]
    registered := (({} : NameSet).insert `firstGroupNode).insert `secondGroupNode }
  match Capture.evaluate (Capture.plan groupRaw) {} with
  | .ok _ => throwError "Capture accepted ambiguous parent group labels"
  | .error issues => ensure (issues.any (·.code == "ambiguous-public-label")) "Missing group alias diagnostic"
  let separateNamespaces ← obtain (Capture.evaluate
    (Capture.plan { publicRaw with nodes := #[(flat, withGroup hierarchical)] }) {})
  ensure (separateNamespaces.registry.nodes.size == 1) "Node and group label namespaces must stay independent"
  ensure (toJson displayLeft == toJson displayRight)
    "Realization identity collision fixture must retain equal display JSON spellings"
  let some (docLabel, docNode, docSource) := plan.ordinary.findSome? fun node =>
      node.realizations.findSome? fun realization =>
        realization.sources.findSome? fun sourceStep =>
          match sourceStep.source.payload, sourceStep.documented with
          | .prose _ (.attribute _), some (.ok _) => some (node.label, node.accepted, sourceStep.source)
          | _, _ => none
    | throwError "Missing actual attribute-owned Verso source for destination identity control"
  let docLeft := { docSource with destination := { docSource.destination with
    realization := { docSource.destination.realization with name := displayLeft } } }
  let docRight := { docSource with destination := { docSource.destination with
    realization := { docSource.destination.realization with name := displayRight } } }
  let docAccepted := { docNode with sources := #[docLeft, docRight] }
  let docRaw : Capture.Raw := {
    nodes := #[(docLabel, docAccepted)]
    registered := ({} : NameSet).insert docLabel
    facts := before.factRecords.filter (·.label == docLabel)
    authored := #[]
    initialIssues := #[] }
  let docPlan := Capture.plan docRaw
  let docObservations ← obtain (← Capture.observe docPlan)
  let docSnapshot ← obtain (Capture.evaluate docPlan docObservations)
  let generatedSelections := docSnapshot.registry.documents.filter (·.key.path.contains "#selection:")
  let leftSelectionKey := docLeft.selectedDocumentKey
  let rightSelectionKey := docRight.selectedDocumentKey
  let docSourceSteps := docPlan.ordinary.flatMap fun node =>
    node.realizations.flatMap (·.sources)
  let some leftStep := docSourceSteps.find? (·.source.selectedDocumentKey == leftSelectionKey)
    | throwError "Missing planned source step for the first typed docstring owner"
  let some (.ok leftRequest) := leftStep.documented
    | throwError "Expected a current documented-provider request for the first owner"
  let some leftProvider := docObservations.documented.find? (·.request == leftRequest)
    | throwError "Missing native docstring provider observation"
  let expectedDocText ← match leftProvider.result with
    | .ok documented => pure documented.content
    | .error issue => throwError "Native docstring provider failed: {repr issue}"
  ensure (generatedSelections.size == 2 && !expectedDocText.trimAscii.isEmpty &&
    leftSelectionKey != rightSelectionKey &&
    generatedSelections.any (·.key == leftSelectionKey) &&
    generatedSelections.any (·.key == rightSelectionKey) &&
    generatedSelections.all (·.text == expectedDocText))
    "Distinct typed realization owners must retain separate selection identities and the exact equal source text"
  let grouped := (⟨Name.mkSimple "capture.grouped", `lean⟩ : RealizationKey).forRole `proof
  let some groupedModel := registry.realization? grouped | throwError "Missing multi-declaration realization"
  ensure (groupedModel.declarations.size == 2 && !(registry.resultFor (.realization grouped)).complete &&
    (registry.resultForRequirement (key "capture.grouped" `RealizationCaptureFixture.groupedComplete)).complete &&
    !(registry.resultForRequirement (key "capture.grouped" `RealizationCaptureFixture.groupedAdmitted)).complete)
    "Complete sibling lent its native validity to an admitted declaration"
  let inlineKey := implementationKey "storage.source" `storedInline
  ensure ((registry.localResult inlineKey).complete && !(registry.resultForRequirement inlineKey).complete)
    "Real imported inline definition must check locally despite its missing shared dependencies"
  let some acceptedSources := before.inventory.get? (Name.mkSimple "storage.source")
    | throwError "Missing accepted heterogeneous-source fixture"
  let allSourceSteps := plan.ordinary.flatMap fun node => node.realizations.flatMap (·.sources)
  for source in acceptedSources.sources do
    let some role := source.destination.role | continue
    let model := source.destination.realization.forRole role
    ensure (registry.realization? model |>.isSome) s!"Missing ordinary source role {model.name}"
    ensure ((registry.resultFor (.realization model)).status == .unassessed)
      s!"Source presence invented validation for {model.name}"
  for document in registry.documents do
    ensure (document.key.path.startsWith "module:") "Compiled source key must be module-relative"
    let some sourceStep := allSourceSteps.find? (·.source.selectedDocumentKey == document.key)
      | throwError "Selected document lost its source owner"
    let expectedText ← match sourceStep.documented with
      | none => obtain sourceStep.source.selectedText
      | some (.error issue) => throwError "Selected native docstring was unavailable: {repr issue}"
      | some (.ok request) =>
        let some provider := observations.documented.find? (·.request == request)
          | throwError "Selected native docstring lost its provider observation"
        match provider.result with
        | .ok documented => pure documented.content
        | .error issue => throwError "Selected native docstring provider failed: {repr issue}"
    ensure (document.text == expectedText) "Selected document differs from the compiled content"
  for evidence in registry.evidence do
    ensure (registry.bindingFor evidence.requirement == some evidence.binding) "Observation belongs to another candidate"
  ensure ((registry.requirements.filter (·.key.name == `expectedProof)).isEmpty)
    "Capture invented independent expected propositions"
  let after := Environment.informalExt.getState (← getEnv)
  ensure (reprStr before == reprStr after) "Capture mutated persistent Blueprint state"

-- Only explicit external inputs may use the document reader.
run_cmd liftTermElabM do
  let external : DocumentKey := ⟨⟨`rocq, `blueprintFixtures⟩, "tests/fixtures/realizations/rocq/Flag.v"⟩
  let sameFile := { external with context.project := `otherProject }
  let leanFile := { external with path := "tests/VersoBlueprintTests/BlueprintRealizationCapture.lean" }
  let absolute := { external with path := "/unavailable/Flag.v" }
  let raw : Capture.Raw := {
    nodes := #[], registered := {}, facts := [], initialIssues := #[]
    authored := #[{
      origin := { id := `externalSources, moduleName := ← getMainModule, source := "external source test" }
      project := `blueprintFixtures
      authored := { sources := #[external, sameFile, leanFile, absolute] } }] }
  let plan := Capture.plan raw
  let reads ← IO.mkRef 0
  let observations ← obtain (← Capture.observe plan (fun path => do
    reads.modify (· + 1)
    IO.FS.readFile path))
  let snapshot ← obtain (Capture.evaluate plan observations)
  let first := snapshot.registry.document? external
  ensure ((← reads.get) == 1 && first.any (·.text.contains "Theorem toggle_involutive") &&
    first.map (·.text) == (snapshot.registry.document? sameFile).map (·.text) &&
    snapshot.sourceDiagnostics.documents.size == 2 &&
    snapshot.sourceDiagnostics.documents.all (·.2.code == "invalid-external-source"))
    "Capture must read the relative external file once and reject Lean and absolute inputs"
  match Capture.evaluate plan { observations with documents := #[] } with
  | .error issues => ensure (issues.any (·.code == "missing-observation")) "Wrong missing document diagnostic"
  | .ok _ => throwError "Capture evaluated an authored external document without its observation"

run_cmd liftTermElabM do
  let label := Name.mkSimple "storage.source"
  let state := Environment.informalExt.getState (← getEnv)
  let some registered := state.inventory.get? label | throwError "Missing fenced source fixture"
  let sources := registered.sources.filter fun source =>
    source.context.language == `tex || source.context.language == `rust
  let texSources := sources.filter (·.context.language == `tex)
  let some firstTex := texSources[0]? | throwError "Missing first TeX fence"
  let some secondTex := texSources[1]? | throwError "Missing second TeX fence"
  let some rust := sources.find? (·.context.language == `rust) | throwError "Missing Rust fence"
  ensure (firstTex.document == secondTex.document && firstTex.selectedDocumentKey != secondTex.selectedDocumentKey)
    "Two TeX fences in a shared source file must own distinct documents"
  let review (source : SourceData.SourceSelection) : RequirementKey := ⟨source.destination.subject, `review⟩
  let raw : Capture.Raw := {
    nodes := #[(label, { registered with sources, uses := #[], nativeAssociations := #[] })]
    registered := ({} : NameSet).insert label, facts := [], initialIssues := #[]
    authored := #[{
      origin := { id := `fenceReview, moduleName := ← getMainModule, source := ← getFileName }
      project := `blueprintFixtures
      authored := { requirements := sources.map fun source =>
        { key := review source, expected := .review `statementCorrespondence `MockReviewer } } }] }
  let captureWith (raw : Capture.Raw) (reader : System.FilePath → IO String) : TermElabM Capture.Snapshot := do
    let plan := Capture.plan raw
    let observations ← obtain (← Capture.observe plan reader)
    obtain (Capture.evaluate plan observations)
  let selectedText (snapshot : Capture.Snapshot) (source : SourceData.SourceSelection) : Option String :=
    (snapshot.registry.documents.find? (·.key == source.selectedDocumentKey)).map (·.text)
  let real ← captureWith raw IO.FS.readFile
  ensure (real.diagnostics.isEmpty && real.registry.documents.size == sources.size &&
    selectedText real firstTex == some "\\forall x,\\;𝒫(x)\n" &&
    selectedText real secondTex == some "  A second TeX source in the same file.\n" &&
    selectedText real rust == some "fn example() -> &'static str { \"𝒫::bad»name\" }\n")
    s!"Fenced selections did not retain their exact authored bytes: {repr real.registry.documents}"
-- Display paths cannot grant a module ownership of an inline declaration.
run_cmd liftTermElabM do
  let env ← getEnv
  let path := "unqualified-old-file.lean"
  let native := ``CaptureFenceOwner.unrelatedNative
  let owner := `VersoBlueprintTests.BlueprintRealizationCapture.FenceOwner
  let labels := #[
    ("capture.inlineOwnerMissing", Name.anonymous),
    ("capture.inlineOwnerMismatch", ← getMainModule),
    ("capture.inlineOwnerMatched", owner)]
  try
    for (label, moduleName) in labels do
      let label := Name.mkSimple label
      let selection : SourceData.SourceSelection := {
        destination := ⟨⟨label, `lean⟩, none⟩
        document := ⟨⟨`lean, `blueprintFixtures⟩, path⟩
        source := .found { path, range := default }
        payload := .leanInline { moduleName, definedDefs := #[{ name := native }] } }
      let some _ ← Environment.contribute label { sources := #[selection] }
        | throwError "Inline test registration rejected"
    let raw := Capture.Raw.ofState (Environment.informalExt.getState (← getEnv))
    let plan := Capture.plan { raw with
      nodes := raw.nodes.filter (fun (label, _) => labels.any (fun entry => label == Name.mkSimple entry.1)),
      authored := #[] }
    let observations ← obtain (← Capture.observe plan)
    let snapshot ← obtain (Capture.evaluate plan observations)
    for (label, moduleName) in labels do
      let view := snapshot.assessmentFor (Name.mkSimple label)
      let issue := snapshot.sourceDiagnostics.nodes.any fun (node, diagnostic) =>
        node == Name.mkSimple label && diagnostic.code == "source-association-unavailable" &&
          diagnostic.subject == native.toString
      let accepted := moduleName == owner
      ensure (issue == !accepted && view.requiredComplete == accepted &&
        (snapshot.registry.localResult (implementationKey label native)).complete == accepted)
        s!"Capture did not enforce the typed inline source owner for {label}"
  finally
    setEnv env

-- Module DocumentKeys preserve the typed distinction even when pretty-printing collides.
run_cmd liftTermElabM do
  let env ← getEnv
  let atomic := Name.mkSimple "foo.bar»"
  let nested := Name.str (Name.mkSimple "foo") "bar»"
  ensure (atomic != nested && atomic.toString == nested.toString) "Expected ambiguous printed module names"
  let documentKey (moduleName : Name) : TermElabM DocumentKey := do
    setEnv (env.setMainModule moduleName)
    let source ← Environment.sourceAt `moduleKeyFixture `verso (some `statement) `verso
      (.text "module key fixture") .missing
    return source.document
  try
    let atomicKey ← documentKey atomic
    let nestedKey ← documentKey nested
    ensure (atomicKey.context == nestedKey.context && atomicKey.path != nestedKey.path)
      "Distinct typed module names selected the same logical document path"
  finally
    setEnv env

-- Source-association diagnostics retain typed ownership and readable subjects. They appear
-- on the owning non-Lean node's assessment and do not leak to another node.
run_cmd liftTermElabM do
  let state := Environment.informalExt.getState (← getEnv)
  let label := Name.mkSimple "storage.source"
  let .some registered := state.inventory.get? label | throwError "Missing foreign-source diagnostic fixture"
  let destination : SourceData.SourceDestination := ⟨⟨label, `rocqTranslation⟩, some `implementation⟩
  let .some source := registered.sources.find? (·.destination == destination)
    | throwError "Missing arbitrary non-Lean source for diagnostic fixture"
  let source := { source with source := Data.SourceLocationResult.unavailable "test source range unavailable" }
  let selected : Data.NodeInventory := { registered with
    sources := #[source], uses := #[], nativeAssociations := #[] }
  let unrelatedLabel := `capture.diagnosticUnrelated
  let unrelated : Data.NodeInventory := { registered with
    sources := #[], uses := #[], nativeAssociations := #[] }
  let pending := ({} : NameSet).insert label |>.insert unrelatedLabel
  let raw : Capture.Raw := {
    nodes := #[(label, selected), (unrelatedLabel, unrelated)]
    registered := pending, facts := [], authored := #[], initialIssues := #[] }
  let plan := Capture.plan raw
  let observations ← obtain (← Capture.observe plan)
  let snapshot ← obtain (Capture.evaluate plan observations)
  let diagnostics (node : Name) :=
    ((snapshot.assessmentFor node).details.getObjValAs? (Array Json) "sourceDiagnostics").toOption.getD #[]
  let hasUnavailableSource (items : Array Json) := items.any fun item =>
    (item.getObjValAs? String "code").toOption == some "source-association-unavailable"
  ensure (hasUnavailableSource (diagnostics label))
    "Owning non-Lean node assessment dropped its unavailable source-location diagnostic"
  ensure (!(hasUnavailableSource (diagnostics unrelatedLabel)))
    "Unavailable non-Lean source diagnostic leaked to an unrelated node assessment"
  ensure ((diagnostics label).any fun item =>
    (item.getObjValAs? String "subject").toOption == some "«storage.source»/rocqTranslation/implementation")
    "Source-association diagnostic exposed an opaque identity instead of its readable destination"
  -- Injected diagnostic metadata only: the admitted registry and all actual
  -- observations are unchanged. Equal paths in different contexts are distinct.
  let documentIssue : Diagnostic := {
    code := "test-document-failure", subject := "provider input", message := "Injected document failure" }
  for (document, belongs) in #[(source.selectedDocumentKey, true),
      ({ source.selectedDocumentKey with context := { source.context with project := `unrelatedProject } }, false)] do
    let scopedSnapshot := { snapshot with sourceDiagnostics := { documents := #[(document, documentIssue)] } }
    let details := (scopedSnapshot.assessmentFor label).details
    let errors := (details.getObjValAs? (Array Json) "sourceDiagnostics").toOption.getD #[]
    ensure (errors.contains (toJson documentIssue) == belongs)
      "Document diagnostics did not use the full language/project/path identity"
    ensure (scopedSnapshot.diagnostics.contains documentIssue)
      "An unattached document error disappeared from the aggregate capture diagnostics"

-- Prose selections take their text from the compiled syntax, not from a file
-- read at capture. With a reader that fails for every path, a prose-only
-- realization keeps its exact selected text, selected document key and binding.
run_cmd liftTermElabM do
  let state := Environment.informalExt.getState (← getEnv)
  let label := Name.mkSimple "storage.source"
  let .some registered := state.inventory.get? label | throwError "Missing prose source fixture"
  let proseSources := registered.sources.filter fun source => source.payload matches .prose ..
  let some prose := proseSources[0]? | throwError "Missing directive prose source"
  let some role := prose.destination.role | throwError "Directive prose needs a role"
  let model := prose.destination.realization.forRole role
  let review : RequirementKey := ⟨.realization model, `correspondence⟩
  let raw : Capture.Raw := {
    nodes := #[(label, { registered with sources := proseSources, uses := #[], nativeAssociations := #[] })]
    registered := ({} : NameSet).insert label, facts := [], initialIssues := #[]
    authored := #[{
      origin := { id := `proseOnlyReview, moduleName := ← getMainModule, source := ← getFileName }
      project := `blueprintFixtures
      authored := { requirements := #[{ key := review, expected := .review `statementCorrespondence `MockReviewer }] } }] }
  let plan := Capture.plan raw
  ensure plan.documents.isEmpty "A prose-only realization must not request a source document"
  let captureWith (reader : System.FilePath → IO String) : TermElabM Capture.Snapshot := do
    let observations ← obtain (← Capture.observe plan reader)
    obtain (Capture.evaluate plan observations)
  let real ← captureWith IO.FS.readFile
  let unreadable ← captureWith fun path => throw (IO.userError s!"injected unreadable source {path}")
  let expectedText ← obtain prose.selectedText
  let selected (snapshot : Capture.Snapshot) :=
    snapshot.registry.documents.find? (·.key == prose.selectedDocumentKey)
  ensure (!expectedText.trimAscii.isEmpty && (selected real).map (·.text) == some expectedText &&
    selected unreadable == selected real &&
    (unreadable.registry.realization? model).map (·.documents) == some #[prose.selectedDocumentKey] &&
    (real.registry.bindingFor review).isSome &&
    unreadable.registry.bindingFor review == real.registry.bindingFor review &&
    unreadable.diagnostics == real.diagnostics)
    "A prose selection must keep its compiled text, selected key and binding when no source file can be read"

-- A plain native declaration is prepared from the compiled environment, not from
-- its owning file. With a reader that fails for every path, a node with a plain
-- native theorem (no doc-comment prose, no inline block) keeps the same native
-- check results, realization completion and bindings as under the real reader.
run_cmd liftTermElabM do
  let state := Environment.informalExt.getState (← getEnv)
  let label := Name.mkSimple "capture.complete"
  let .some registered := state.inventory.get? label | throwError "Missing plain native fixture"
  let proofModel := (⟨label, `lean⟩ : RealizationKey).forRole `proof
  let review : RequirementKey := ⟨.realization proofModel, `proofReview⟩
  let raw : Capture.Raw := {
    nodes := #[(label, { registered with sources := #[], uses := #[] })]
    registered := ({} : NameSet).insert label, facts := [], initialIssues := #[]
    authored := #[{
      origin := { id := `plainNativeReview, moduleName := ← getMainModule, source := ← getFileName }
      project := `blueprintFixtures
      authored := { requirements := #[{ key := review, expected := .review `proofCorrespondence `MockReviewer }] } }] }
  let plan := Capture.plan raw
  ensure (plan.documents.isEmpty && plan.documented.isEmpty && !plan.native.isEmpty)
    "The control must request only plain native declarations"
  let captureWith (reader : System.FilePath → IO String) : TermElabM Capture.Snapshot := do
    let observations ← obtain (← Capture.observe plan reader)
    obtain (Capture.evaluate plan observations)
  let real ← captureWith IO.FS.readFile
  let unreadable ← captureWith fun path => throw (IO.userError s!"injected unreadable source {path}")
  let checks (snapshot : Capture.Snapshot) := reprStr (snapshot.nativeChecks.map fun checked =>
    (checked.declaration, checked.roles, checked.statement, checked.body, checked.status))
  let completion (snapshot : Capture.Snapshot) := snapshot.registry.realizations.map fun model =>
    (model.key, (snapshot.registry.resultFor (.realization model.key)).status)
  let bindings (snapshot : Capture.Snapshot) := snapshot.registry.requirements.map fun requirement =>
    (requirement.key, snapshot.registry.bindingFor requirement.key)
  ensure ((real.registry.resultFor (.realization proofModel)).complete && (real.registry.bindingFor review).isSome &&
    real.registry.documents.isEmpty && real.diagnostics.isEmpty)
    "The plain native control must complete its proof realization without any source document"
  ensure (checks unreadable == checks real && completion unreadable == completion real &&
    bindings unreadable == bindings real && unreadable.diagnostics == real.diagnostics)
    "A plain native declaration must keep its checks, completion and bindings when no source file can be read"
  let mirror := Name.mkSimple "capture.plainMirror"
  let mirrorNode := { registered with
    sources := #[], uses := #[]
    nativeAssociations := registered.nativeAssociations.map fun association => { association with
      realization := { association.realization with node := mirror }
      reference := { association.reference with
        provenance := .inWorkspace `WrongMirrorOwner "definitely-missing.lean" } } }
  let duplicate := Capture.plan { raw with
    nodes := raw.nodes.push (mirror, mirrorNode), registered := raw.registered.insert mirror }
  let duplicateObservations ← obtain (← Capture.observe duplicate)
  let duplicateSnapshot ← obtain (Capture.evaluate duplicate duplicateObservations)
  ensure (duplicate.checks.size == 2 && duplicateObservations.checks.size == 1 &&
    duplicateSnapshot.nativeChecks.size == 1 &&
    (duplicateSnapshot.assessmentFor label).requiredComplete &&
    !(duplicateSnapshot.assessmentFor mirror).requiredComplete &&
    duplicateSnapshot.sourceDiagnostics.nodes.any (·.1 == mirror))
    "One shared native check must retain owner-specific source availability and completion"

-- A plain native declaration never asks for its owning source path, so a
-- dependency whose module source is not on the source search path is still
-- captured. Under `lake build` the search path holds only the toolchain sources;
-- the control records no path, so locating the file would need that search.
run_cmd liftTermElabM do
  let state := Environment.informalExt.getState (← getEnv)
  let label := Name.mkSimple "storage.native"
  let owner := `VersoBlueprintTests.BlueprintCanonicalSourcePersistence.Owner
  let .some registered := state.inventory.get? label | throwError "Missing imported plain native fixture"
  let associations := registered.nativeAssociations.map fun association => { association with
    reference := { association.reference with provenance := .outWorkspace owner none } }
  ensure (!associations.isEmpty && associations.all (·.reference.provenance.sourcePath?.isNone))
    "The control must record no owning source path"
  -- Without a source search path entry for the owner the old file lookup failed;
  -- with one (an editor session) the control still holds but proves less.
  if (← (← getSrcSearchPath).findModuleWithExt "lean" owner).isSome then return
  let raw : Capture.Raw := {
    nodes := #[(label, { registered with sources := #[], uses := #[], nativeAssociations := associations })]
    registered := ({} : NameSet).insert label, facts := [], authored := #[], initialIssues := #[] }
  let plan := Capture.plan raw
  let observations ← obtain (← Capture.observe plan)
  let snapshot ← obtain (Capture.evaluate plan observations)
  let implementation := (⟨label, `lean⟩ : RealizationKey).forRole `implementation
  ensure (observations.native.all (·.result.isOk) && snapshot.diagnostics.isEmpty &&
    (snapshot.registry.resultFor (.realization implementation)).complete)
    "A plain native declaration whose module source is not on the search path must still be captured"

-- Docstrings from Lean fences and incremental documents come from the same
-- compiled metadata as top-level declarations.
run_cmd liftTermElabM do
  let raw := Capture.Raw.ofState (Environment.informalExt.getState (← getEnv))
  for (label, comment) in #[("capture.fencedAttribute", "A fenced declaration owns this 𝒫 comment."),
      ("capture.incrementalFencedAttribute", "An own comment in an incremental document.")] do
    let label := Name.mkSimple label
    let some (_, node) := raw.nodes.find? (·.1 == label) | throwError "Missing fenced declaration"
    let some source := node.sources.find? (·.ownDocstring.isSome) | throwError "Missing compiled docstring"
    let plan := Capture.plan { raw with nodes := #[(label, node)], facts := raw.facts.filter (·.label == label) }
    let observed ← obtain (← Capture.observe plan fun _ => throw (IO.userError "Unexpected source read"))
    let snapshot ← obtain (Capture.evaluate plan observed)
    ensure (observed.documents.isEmpty && snapshot.sourceDiagnostics.nodes.isEmpty &&
      (snapshot.registry.document? source.selectedDocumentKey).any (·.text.trimAscii.toString == comment))
      "A fenced definition lost its direct compiled docstring"

-- Specifications remain independently authored, with all origin variants kept.
def expectedTrue : Prop := True
def expectedFalse : Prop := False

namespace ScopedSource
scoped notation "scopedSourceTruth" => True
end ScopedSource

open scoped _root_.RealizationCaptureFixture.ScopedSource in
def expectedScoped : Prop := scopedSourceTruth

set_option pp.universes true in
def expectedOption : Prop := True

open scoped _root_.RealizationCaptureFixture.ScopedSource in
set_option pp.universes true in
def expectedNested : Prop := scopedSourceTruth

section
open scoped _root_.RealizationCaptureFixture.ScopedSource
def expectedModuleOpen : Prop := scopedSourceTruth
end

-- Actual owned propositions and native proof, through ordinary authoring and
-- capture. The compiled declaration retains both original ranges.
run_cmd liftTermElabM do
  let originalEnv ← getEnv
  for expected in #[``expectedTrue, ``expectedOption, ``expectedModuleOpen,
      ``expectedScoped, ``expectedNested] do
    try
      Authoring.configureProject `blueprintFixtures
      Authoring.expectNative `sourceWrapper (Name.mkSimple "capture.complete") expected
      let snapshot ← obtain (← Capture.capture)
      ensure ((snapshot.registry.resultForRequirement
        (key "capture.complete" `RealizationCaptureFixture.complete `expectedProof)).complete)
        s!"Owned expected proposition lost its exact source association: {expected}"
      let some ranges ← findDeclarationRanges? expected
        | throwError "Missing original expected-proposition ranges"
      ensure (ranges.range.pos.line > 0 && ranges.selectionRange.pos.line > 0)
        "Compiled specification must retain named declaration ranges"
    finally
      setEnv originalEnv

run_cmd liftCoreM <| Authoring.configureProject `blueprintFixtures
run_cmd liftCoreM <| Authoring.expectNative `expectedComplete (Name.mkSimple "capture.complete") `RealizationCaptureFixture.expectedTrue

run_cmd liftTermElabM do
  let plan := Capture.plan (Capture.Raw.ofState (Environment.informalExt.getState (← getEnv)))
  let observations ← obtain (← Capture.observe plan)
  let snapshot ← obtain (Capture.evaluate plan observations)
  ensure ((snapshot.registry.resultForRequirement (key "capture.complete" `RealizationCaptureFixture.complete `expectedProof)).complete)
    "Independently authored expected proposition did not check"
  let replay ← obtain (Capture.evaluate plan { observations with
    specifications := observations.specifications.reverse, expected := observations.expected.reverse })
  ensure (replay.registry.contributions == snapshot.registry.contributions)
    "Expected-goal table order changed origins, goal documents or bindings"
  let rejects (code : String) (batch : Capture.Observations) : TermElabM Unit := do
    match Capture.evaluate plan batch with
    | .ok _ => throwError "Malformed authored observation batch was admitted"
    | .error issues => ensure (issues.any (·.code == code)) s!"Wrong authored batch rejection: {repr issues}"
  rejects "missing-observation" { observations with specifications := #[] }
  rejects "missing-observation" { observations with expected := #[] }
  let some expected := observations.expected[0]? | throwError "Missing expected-goal result control"
  let originalChecked ← obtain expected.result
  let semanticDiagnostic : Diagnostic := {
    code := "semantic-context-unavailable"
    subject := "Unrelated.TransitiveDependency"
    message := "Injected failure for diagnostic propagation control" }
  let failingSemantics : NativeLean.SemanticContext := fun _ _ _ => pure (.error semanticDiagnostic)
  let checkedWithoutContext ← obtain (← NativeLean.check `blueprintFixtures
    originalChecked.observation.witness (mkCIdent expected.request.expected) expected.request.documents failingSemantics)
  ensure (checkedWithoutContext.semanticContext.isNone &&
    checkedWithoutContext.semanticDiagnostics == #[semanticDiagnostic])
    "Native expected-goal check dropped its semantic-context failure"
  let failedSemantics : Capture.Observations := { observations with
    expected := observations.expected.modify 0 fun entry => { entry with result := .ok checkedWithoutContext } }
  let preserved ← obtain (Capture.evaluate plan failedSemantics)
  ensure (preserved.diagnostics.contains semanticDiagnostic)
    "Expected-proof semantic-context failure was dropped during capture evaluation"
  let assertScoped (snapshot : Capture.Snapshot) (diagnostic : Diagnostic) : TermElabM Unit := do
    for (label, belongs) in #[("capture.complete", true), ("capture.admitted", false)] do
      let details := (snapshot.assessmentFor (Name.mkSimple label)).details
      let errors := (details.getObjValAs? (Array Json) "sourceDiagnostics").toOption.getD #[]
      ensure (errors.contains (toJson diagnostic) == belongs)
        "Transitive semantic failure lost its owning node or leaked to a sibling in the same source file"
  assertScoped preserved semanticDiagnostic
  -- Generic provider subjects must be scoped by the request too. These are
  -- injected failures, not fabricated successful validation observations.
  let genericDiagnostic := { semanticDiagnostic with subject := "native" }
  let genericFailure := { checkedWithoutContext with semanticDiagnostics := #[genericDiagnostic] }
  let generic ← obtain (Capture.evaluate plan { observations with
    expected := observations.expected.modify 0 fun entry => { entry with result := .ok genericFailure } })
  assertScoped generic genericDiagnostic
  let nativeFailure := { observations with native := observations.native.map fun entry =>
    if entry.request.name != ``complete then entry else
      { entry with result := entry.result.map fun prepared => { prepared with
        semanticContext := none, statementContext := none, semanticDiagnostics := #[semanticDiagnostic] } } }
  let native ← obtain (Capture.evaluate plan nativeFailure)
  assertScoped native semanticDiagnostic
  rejects "duplicate-observation" { observations with expected := observations.expected.push expected }
  -- An answer to a request this plan does not make is ignored.
  let unrequestedAnswer := { expected with request := { expected.request with expected := `unrequestedExpectation } }
  let unrequested ← obtain (Capture.evaluate plan
    { observations with expected := observations.expected.push unrequestedAnswer })
  ensure (unrequested.registry.contributions == snapshot.registry.contributions)
    "An unrequested expected-goal answer changed the snapshot"
  -- Compiled expectations are identified by owner and witness.
  let unrelated : DocumentKey := ⟨⟨`rocq, `unrequested⟩, "foreign.v"⟩
  rejects "missing-observation" { observations with expected := observations.expected.modify 0 fun entry =>
    { entry with request := { entry.request with documents := #[unrelated] } } }
  rejects "mismatched-observation" { observations with expected := observations.expected.modify 0 fun entry =>
    { entry with result := .ok { originalChecked with goal := { originalChecked.goal with documents := #[unrelated] } } } }
  rejects "missing-observation" { observations with specifications := observations.specifications.modify 0 fun entry =>
    { entry with request := { entry.request with expected := `wrongSpecification } } }
  let env ← getEnv
  try
    Authoring.expectNative `competingExpectation (Name.mkSimple "capture.complete") `RealizationCaptureFixture.expectedFalse
    match ← Capture.capture with
    | .ok _ => throwError "Competing specification was silently overwritten"
    | .error issues => ensure (issues.any (·.code == "semantic-conflict")) s!"Wrong specification rejection: {repr issues}"
  finally setEnv env

-- A compiled specification requires no document observation.
run_cmd liftTermElabM do
  let plan := Capture.plan (Capture.Raw.ofState (Environment.informalExt.getState (← getEnv)))
  let reads ← IO.mkRef 0
  let observed ← obtain (← Capture.observe plan (fun _ => do
    reads.modify (· + 1)
    throw (IO.userError "Unexpected source read")))
  let snapshot ← obtain (Capture.evaluate plan observed)
  ensure ((← reads.get) == 0 && observed.documents.isEmpty &&
    (snapshot.registry.resultForRequirement (key "capture.complete" ``complete `expectedProof)).complete)
    "A compiled expectation must be checked without opening its specification file"

run_cmd liftTermElabM do
  let env ← getEnv
  try
    Authoring.expectNative `ambiguousWitness (Name.mkSimple "capture.grouped") `RealizationCaptureFixture.expectedTrue
    match ← Capture.capture with
    | .ok _ => throwError "Node-level specification silently selected one of multiple declarations"
    | .error issues => ensure (issues.any (·.code == "ambiguous-native-expectation")) "Wrong multi-witness diagnostic"
  finally setEnv env

private def withDifferentRange (association : SourceData.NativeAssociation) :
    TermElabM SourceData.NativeAssociation := do
  let some ranges ← findDeclarationRanges? association.reference.canonical
    | throwError "Missing compiled ranges for replay control"
  let range? := if association.reference.range?.isSome then none else some ranges.range
  return { association with reference := { association.reference with range? } }

-- Two distinct range snapshots of one declaration must agree when both prepare.
run_cmd liftTermElabM do
  let raw := Capture.Raw.ofState (Environment.informalExt.getState (← getEnv))
  let target := Name.mkSimple "capture.complete"
  let some (_, node) := raw.nodes.find? (·.1 == target) | throwError "Missing native source control"
  let #[association] := node.nativeAssociations | throwError "Expected one registered native source"
  let alternate ← withDifferentRange association
  let alternateRequest := Capture.NativeRequest.ofAssociation alternate.context alternate
  let planFor (associations : Array SourceData.NativeAssociation) :=
    Capture.plan { raw with nodes := #[(target, { node with nativeAssociations := associations })], authored := #[] }
  let plan := planFor #[association, alternate]
  let reversed := planFor #[alternate, association]
  let observed ← obtain (← Capture.observe plan)
  ensure (observed.native.size == 2 && observed.native.all (·.result.isOk) &&
    observed.native.any (·.request == alternateRequest))
    "Sibling control must exercise distinct successful source requests for one declaration"
  let proofKey := key "capture.complete" ``complete
  let snapshot ← obtain (Capture.evaluate plan observed)
  ensure (!snapshot.diagnostics.any (·.code == "source-unavailable") &&
    (snapshot.registry.resultForRequirement proofKey).complete)
    "An unreadable recorded owning path blocked a passed native check"
  let reverseControl ← obtain (Capture.evaluate reversed observed)
  ensure (snapshot.registry.bindingFor proofKey == reverseControl.registry.bindingFor proofKey &&
    (reverseControl.registry.resultForRequirement proofKey).complete)
    "Agreeing source requests changed the proof when reordered"
  for change in #[
      (fun (source : NativeSource.Prepared) => { source with roles := #[`statement] }),
      (fun source => { source with statementContext := some "changed statement descriptor" }),
      (fun source => { source with semanticContext := some "changed body descriptor" })] do
    let changed := { observed with native := observed.native.map fun answer =>
      if answer.request == alternateRequest then
        { answer with result := answer.result.map change }
      else answer }
    let first ← obtain (Capture.evaluate plan changed)
    let second ← obtain (Capture.evaluate reversed { changed with native := changed.native.reverse })
    for disputed in #[first, second] do
      let view := disputed.assessmentFor target
      ensure (!view.nativeStatementComplete && !view.nativeBodyComplete && view.proofRoleComplete == some false &&
        !view.requiredComplete && (disputed.registry.requirement? proofKey).isSome &&
        !(disputed.registry.localResult proofKey).complete &&
        !(disputed.registry.resultForRequirement proofKey).complete)
        "Conflicting sibling answers removed or completed a native requirement"
      ensure (disputed.sourceDiagnostics.nodes.any fun (label, diagnostic) =>
        label == target && diagnostic.code == "ambiguous-source" && diagnostic.subject == (toString ``complete))
        "Conflicting sibling answers lost their scoped owning-source diagnostic"
    ensure (first.sourceDiagnostics == second.sourceDiagnostics &&
      first.registry.bindingFor proofKey == second.registry.bindingFor proofKey)
      "Reordering conflicting siblings selected a different native source"

-- A proposition definition genuinely has one statement contract.
@[blueprint "capture.propositionOnly"]
def propositionOnly : Prop := True

-- A proof-shaped key can be authored with either role, but cannot supply an
-- ordinary proof owner for a node whose native declaration is a proposition.
run_cmd liftTermElabM do
  let env ← getEnv
  try
    let node := Name.mkSimple "capture.propositionOnly"
    let realization := (⟨node, `lean⟩ : RealizationKey).forRole `proof
    let context : Realizations.Context := ⟨`lean, `blueprintFixtures⟩
    let witness : ObjectKey := ⟨context, "RealizationCaptureFixture.complete"⟩
    for role in #[`account, `proof] do
      setEnv env
      Authoring.stage `borrowedProofOwner {
        realizations := #[{ key := realization, context, role, declarations := #[{ object := witness }] }] }
      Authoring.expectNative `borrowedExpectedProof node `RealizationCaptureFixture.expectedTrue
      match ← Capture.capture with
      | .ok _ => throwError "An authored realization supplied another node's native expected proof"
      | .error issues =>
        ensure (issues.any (·.code == "ambiguous-native-expectation")) s!"Wrong owner rejection: {repr issues}"
  finally setEnv env

-- A checked sibling cannot certify an absent member on either placement or
-- supply its contract to a dependent label.
run_cmd liftTermElabM do
  let env ← getEnv
  try
    let target := Name.mkSimple "capture.grouped"
    let dependent := Name.mkSimple "capture.groupedDependent"
    let absentName := `RealizationCaptureFixture.absentNative
    let absent : ObjectKey := ⟨⟨`lean, `blueprintFixtures⟩, absentName.toString⟩
    for placement in #[`statement, `proof] do
      setEnv env
      Environment.modify fun state => Id.run do
        let some node := state.inventory.get? target | return state
        let associations := node.nativeAssociations.map fun association =>
          if association.reference.canonical == ``groupedAdmitted then
            { association with placement, reference := { association.reference with canonical := absentName } }
          else association
        return { state with inventory := state.inventory.insert target { node with nativeAssociations := associations } }
      let snapshot ← obtain (← Capture.capture)
      let missingRole := (⟨target, `lean⟩ : RealizationKey).forRole placement
      let missingResult := snapshot.registry.resultFor (.declaration missingRole absent)
      ensure (missingResult.status == .blocked && missingResult.diagnostics.any (·.code == "missing-declaration") &&
        (snapshot.registry.resultFor (.realization missingRole)).status == .blocked)
        "The missing declaration and its enclosing realization must retain blocked availability"
      ensure ((snapshot.registry.resultForRequirement (key "capture.grouped" ``groupedComplete)).complete)
        "The checked sibling must retain its precise passed proof"
      let mixed := snapshot.assessmentFor target
      ensure (mixed.hasNativeDeclarations && mixed.hasNativeBodyRequirement &&
        !mixed.nativeStatementComplete && !mixed.nativeBodyComplete &&
        !mixed.nativeLocallyComplete && !mixed.requiredComplete && mixed.proofRoleComplete == some false &&
        (Graph.statusesForAssessment mixed).2 == .incomplete)
        "The aggregate cannot count an unclassified declaration as a completed sibling or statement-only proposition"
      ensure (Graph.actionableStageForAssessment? mixed == some "statement")
        "The incomplete native statement must remain visible in the graph work queue"
      let selected := snapshot.uses.filter fun use => use.source == dependent && use.reference.label == target
      ensure (selected.size == 2 && selected.all (fun use =>
        match use.selected with
        | .error diagnostic => diagnostic.code == "missing-declaration" && diagnostic.message.contains absent.native
        | .ok _ => false))
        "Both use axes must identify the same missing target declaration"
      let dependentView := snapshot.assessmentFor dependent
      ensure (dependentView.nativeLocallyComplete && dependentView.selectedLeanUseCount == 2 &&
        !dependentView.statementDependenciesComplete && !dependentView.proofDependenciesComplete &&
        !dependentView.requiredComplete)
        "Failed target selection must block the dependent closure without erasing its local checks"
      let proposition := snapshot.assessmentFor (Name.mkSimple "capture.propositionOnly")
      ensure (proposition.hasNativeDeclarations && proposition.nativeStatementComplete &&
        !proposition.hasNativeBodyRequirement && !proposition.nativeBodyComplete &&
        proposition.nativeLocallyComplete && proposition.requiredComplete &&
        (Graph.actionableStageForAssessment? proposition).isNone)
        "A classified proposition definition must retain its legitimate statement-only completion"
  finally setEnv env

-- Rejected imported state cannot escape as a successful partial registry.
run_cmd liftTermElabM do
  let env ← getEnv
  try
    Environment.modify fun state => { state with importedConflicts := #[{
      kind := .node, label := `rejectedImportedNode, reasons := #["explicit negative import control"] }] }
    let before := Environment.informalExt.getState (← getEnv)
    match ← Capture.capture with
    | .ok _ => throwError "Import rejection produced a partial registry"
    | .error issues => ensure (issues.any (·.code == "imported-conflict")) "Lost import rejection"
    ensure (reprStr before == reprStr (Environment.informalExt.getState (← getEnv))) "Rejected capture mutated its input"
  finally setEnv env


-- An independently authored false expectation does not erase a valid native
-- proof or become satisfied merely because that proof checks against its own type.
@[blueprint "capture.wrongExpected"]
theorem wrongExpected : True := True.intro
run_cmd liftCoreM <| Authoring.expectNative `wrongExpectedGoal (Name.mkSimple "capture.wrongExpected") `RealizationCaptureFixture.expectedFalse

run_cmd liftTermElabM do
  let snapshot ← obtain (← Capture.capture)
  let assessment := snapshot.assessmentFor (Name.mkSimple "capture.wrongExpected")
  ensure (assessment.nativeStatementComplete && assessment.nativeBodyComplete &&
    assessment.requiredComplete && assessment.proofDependenciesComplete)
    "The native-only summary must remain distinct from an independently authored wrong proposition"
  ensure (!(snapshot.registry.resultForRequirement
    (key "capture.wrongExpected" `RealizationCaptureFixture.wrongExpected `expectedProof)).complete)
    "Wrong expected proposition acquired a completed proof"

-- The actual observation scope restores all three kinds of elaborator state
-- even when an unexpected exception escapes a provider. No provider success is
-- supplied by this test.
run_cmd liftTermElabM do
  let before := Environment.informalExt.getState (← getEnv)
  let sentinel ← mkFreshExprMVar (mkConst ``True)
  let metaBefore ← getMCtx
  let infoBefore ← getInfoState
  let result : Except (Array Diagnostic) Unit ← Capture.withObservationState do
    Environment.modify fun state => { state with authoringRecords := #[] }
    sentinel.mvarId!.assign (mkConst ``True.intro)
    discard <| mkFreshExprMVar (mkConst ``True)
    modifyInfoState fun state => { state with enabled := !state.enabled, trees := {} }
    throwError "deliberate observation exception"
  let .error issues := result | throwError "Observation exception escaped conversion"
  ensure (issues.size == 1 && issues[0]!.code == "capture-failed" &&
    issues[0]!.message == "deliberate observation exception") "Lost observation exception diagnostic"
  ensure (reprStr before == reprStr (Environment.informalExt.getState (← getEnv))) "Exception leaked environment mutation"
  ensure (!(← sentinel.mvarId!.isAssigned) && (← getMCtx).mvarCounter == metaBefore.mvarCounter)
    "Exception leaked metavariable mutation"
  let infoAfter ← getInfoState
  ensure (infoAfter.enabled == infoBefore.enabled && infoAfter.trees.size == infoBefore.trees.size)
    "Exception leaked info-state mutation"

-- Inject Lean's runtime heartbeat exception: this tests the resource-failure
-- boundary, not workload cost, and changes neither counters nor limits.
run_cmd liftTermElabM do
  let envBefore ← getEnv
  let sentinel ← mkFreshExprMVar (mkConst ``True)
  let metaBefore ← getMCtx
  let infoBefore ← getInfoState
  let tracesBefore ← getTraceState
  let caught ← tryCatchRuntimeEx
    (do
      let _ : Except (Array Diagnostic) Unit ← Capture.withObservationState do
        withOptions (·.setBool `trace.blueprint.capture.semantic true) do
          withTraceNode `blueprint.capture.semantic (fun _ => pure "injected observation budget failure") do
            modifyEnv (·.setMainModule `ObservationBudgetTemporary)
            sentinel.mvarId!.assign (mkConst ``True.intro)
            discard <| mkFreshExprMVar (mkConst ``True)
            modifyInfoState fun state => { state with enabled := !state.enabled, trees := {} }
            trace[blueprint.capture.semantic] "provider entered before injected resource exception"
            Core.throwMaxHeartbeat `observationBudgetTest `maxHeartbeats 1000
            return .ok ()
      pure false)
    (fun exception => do
      ensure exception.isMaxHeartbeat "Wrong exception escaped observation"
      pure true)
  ensure caught "Observation converted a resource failure into provider output"
  ensure (unsafe ptrEq envBefore (← getEnv)) "Resource failure leaked environment mutation"
  ensure (!(← sentinel.mvarId!.isAssigned) && (← getMCtx).mvarCounter == metaBefore.mvarCounter)
    "Resource failure leaked metavariable mutation"
  let infoAfter ← getInfoState
  ensure (infoAfter.enabled == infoBefore.enabled && infoAfter.trees.size == infoBefore.trees.size)
    "Resource failure leaked info-state mutation"
  ensure ((← getTraceState).traces.size > tracesBefore.traces.size)
    "Resource failure restoration discarded diagnostic traces"

-- Mix a genuinely statement-only proposition definition with a missing
-- proof attachment. There is no successfully classified body to mask the gap.
/--
warning: Label «capture.statementWithMissingProof»: external Lean name 'RealizationCaptureFixture.absentProof' could not be resolved in current namespace/open declarations; keeping parsed name
-/
#guard_msgs in
#docs (Verso.Genre.Manual) missingBodyDoc "Missing native proof" :=
:::::::
:::definition "capture.statementWithMissingProof" (lean := "RealizationCaptureFixture.propositionOnly")
A native proposition has a separate proof attachment.
:::

:::proof "capture.statementWithMissingProof" (lean := "RealizationCaptureFixture.absentProof")
The proof attachment has not been declared.
:::
:::::::

@[blueprint "capture.implementationWithProofUse" (proofUses := ["capture.admitted"])]
def implementationWithProofUse : Nat := by sorry

-- A parsed name retained by a directive is not a resolved registration.
/--
warning: Label «capture.forwardNative»: external Lean name 'RealizationCaptureFixture.declaredLater' could not be resolved in current namespace/open declarations; keeping parsed name
-/
#guard_msgs in
#docs (Verso.Genre.Manual) forwardDoc "Forward native name" :=
:::::::
:::theorem "capture.forwardNative" (lean := "RealizationCaptureFixture.declaredLater")
The native theorem is declared later in this module.
:::
:::::::

theorem declaredLater : True := True.intro

run_cmd liftTermElabM do
  let env ← getEnv
  let state := Environment.informalExt.getState env
  let plan := Capture.plan (Capture.Raw.ofState state)
  let observations ← obtain (← Capture.observe plan)
  let snapshot ← obtain (Capture.evaluate plan observations)

  let mixedLabel := Name.mkSimple "capture.statementWithMissingProof"
  let context : Realizations.Context := ⟨`lean, `blueprintFixtures⟩
  let statement := (⟨mixedLabel, `lean⟩ : RealizationKey).forRole `statement
  let propositionKey : RequirementKey := ⟨.declaration statement ⟨context, toString ``propositionOnly⟩, `statement⟩
  let absentProof := key "capture.statementWithMissingProof" `RealizationCaptureFixture.absentProof
  let missingProof := snapshot.registry.resultFor absentProof.subject
  let mixed := snapshot.assessmentFor mixedLabel
  ensure ((snapshot.registry.localResult propositionKey).complete &&
    missingProof.status == .blocked && missingProof.diagnostics.any (·.code == "missing-declaration"))
    "Control must contain a passed native proposition and an unavailable proof attachment"
  ensure (mixed.hasNativeBodyRequirement && mixed.proofRoleComplete == some false &&
    !mixed.nativeBodyComplete && !mixed.requiredComplete)
    "An unresolved proof placement must keep a body requirement beside a proposition-only declaration"

  let implementationLabel := Name.mkSimple "capture.implementationWithProofUse"
  let implementation := implementationKey "capture.implementationWithProofUse" ``implementationWithProofUse
  let prerequisite := key "capture.admitted" ``admitted
  let implementationView := snapshot.assessmentFor implementationLabel
  ensure ((snapshot.registry.requirement? implementation).any (·.prerequisites.contains prerequisite) &&
    !(snapshot.registry.resultForRequirement prerequisite).complete &&
    !(snapshot.registry.localResult implementation).complete)
    "The missing implementation must select the unfinished proof-axis prerequisite"
  ensure (implementationView.selectedLeanUseCount == 1 &&
    !implementationView.statementDependenciesComplete && !implementationView.proofDependenciesComplete &&
    (Graph.statusesForAssessment implementationView).1 == .blocked &&
    (Graph.actionableStageForAssessment? implementationView).isNone)
    "The graph must keep an implementation with an unfinished proof-axis prerequisite blocked"

  let forwardLabel := Name.mkSimple "capture.forwardNative"
  let forwardObject : ObjectKey := ⟨context, toString ``declaredLater⟩
  let forwardStatement := (⟨forwardLabel, `lean⟩ : RealizationKey).forRole `statement
  let forwardView := snapshot.assessmentFor forwardLabel
  ensure ((env.checked.get.find? ``declaredLater).isSome &&
    (← Environment.labelsForLeanDecl ``declaredLater).isEmpty)
    "Control must have a current declaration and an unresolved registration"
  let forwardResult := snapshot.registry.resultFor (.declaration forwardStatement forwardObject)
  ensure (!observations.checks.any (·.request.witness == forwardObject) &&
    !snapshot.nativeChecks.any (·.declaration == forwardObject) &&
    forwardResult.status == .blocked && forwardResult.diagnostics.any (·.code == "missing-declaration") &&
    !forwardView.nativeStatementComplete && !forwardView.nativeBodyComplete && !forwardView.requiredComplete)
    "A forward-only registration cannot acquire fresh native evidence from its parsed name"
  let some rendered := (TraversalIndex.Nodes.capture state (some snapshot)).find? (·.label == forwardLabel)
    | throwError "Missing captured forward-reference panel"
  let some code := rendered.toBlockData.codeData | throwError "Missing forward-reference code panel"
  let #[reference] := code.displayExternalDecls | throwError "Expected one forward-reference panel entry"
  ensure (reference.canonical == ``declaredLater && !reference.present && reference.observedStatus == some .missing &&
    rendered.statementExternalChecks == #[(``declaredLater, some .missing)])
    "The forward-reference panel must agree with the declaration index and capture"
  let html ← renderPreviewBlocksHtmlWithSnapshot forwardDoc.toPart.content snapshot
  ensure (html.asString.contains "bp_external_status_missing" && html.asString.contains "declaration not found")
    "The rendered forward-reference panel must display the missing declaration"

-- Another label registers the same spelling after its declaration exists.
attribute [blueprint "capture.resolvedLater"] declaredLater

run_cmd liftTermElabM do
  let snapshot ← obtain (← Capture.capture)
  let missing := Name.mkSimple "capture.forwardNative"
  let resolved := Name.mkSimple "capture.resolvedLater"
  let state := Environment.informalExt.getState (← getEnv)
  let panels := TraversalIndex.Nodes.capture state (some snapshot)
  let checks (label : Name) := (panels.find? (·.label == label)).map (·.statementExternalChecks)
  let summary ← Commands.buildSummary snapshot
  ensure ((← Environment.labelsForLeanDecl ``declaredLater) == #[resolved] &&
    (snapshot.assessmentFor resolved).requiredComplete && !(snapshot.assessmentFor missing).requiredComplete &&
    checks resolved == some #[(``declaredLater, some .proved)] &&
    checks missing == some #[(``declaredLater, some .missing)] &&
    summary.missingLeanDecls.any (fun row => row.label == missing && row.canonical == ``declaredLater) &&
    !summary.missingLeanDecls.any (·.label == resolved))
    "A resolved sibling must not supply its registration, panel status or summary to a forward reference"

-- A shared declaration's genuine check still needs evidence at each label.
run_cmd liftTermElabM do
  let state := Environment.informalExt.getState (← getEnv)
  let raw := Capture.Raw.ofState state
  let passed := Name.mkSimple "capture.complete"
  let incomplete := Name.mkSimple "capture.admitted"
  let disagreed := Name.mkSimple "capture.disagreed"
  let some passedNode := state.inventory.get? passed | throwError "Missing passed attachment"
  let some incompleteNode := state.inventory.get? incomplete | throwError "Missing incomplete attachment"
  let alternate ← (passedNode.nativeAssociations ++ incompleteNode.nativeAssociations).mapM fun association => do
    let association ← withDifferentRange association
    return { association with realization := { association.realization with node := disagreed } }
  let alternateRequests := alternate.map fun association =>
    Capture.NativeRequest.ofAssociation association.context association
  let disagreedNode := { passedNode with sources := #[], nativeAssociations := alternate }
  let plan := Capture.plan { raw with
    nodes := #[(passed, passedNode), (incomplete, incompleteNode), (disagreed, disagreedNode)]
    registered := raw.registered.insert disagreed, authored := #[] }
  let observations ← obtain (← Capture.observe plan)
  ensure ((observations.native.filter (fun answer => alternateRequests.contains answer.request)).size == 2 &&
    observations.checks.size == 2) "The labels must share two checks and have distinct source requests"
  let changed := { observations with native := observations.native.map fun answer =>
    if !(alternateRequests.contains answer.request) then answer else
      { answer with result := answer.result.map fun prepared => { prepared with roles := #[`statement] } } }
  let snapshot ← obtain (Capture.evaluate plan changed)
  ensure ((snapshot.sourceDiagnostics.nodes.filter fun (label, issue) =>
      label == disagreed && issue.code == "native-role-disagreement").size == 2 &&
    !(snapshot.assessmentFor disagreed).nativeStatementComplete &&
    (snapshot.assessmentFor passed).requiredComplete)
    "The disagreement must reject only the sibling label's native observations"
  let panels := TraversalIndex.Nodes.capture { state with inventory := state.inventory.insert disagreed disagreedNode }
    (some snapshot)
  let checks (label : Name) := (panels.find? (·.label == label)).map (·.statementExternalChecks)
  let some checked := snapshot.nativeChecks.find? (·.declaration.native == toString ``admitted)
    | throwError "Missing genuine incomplete observation"
  ensure (checked.status.hasKnownSorry && checks passed == some #[(``complete, some .proved)] &&
    checks incomplete == some #[(``admitted, some checked.status)] &&
    (checks disagreed).any fun rows => rows.size == 2 && rows.all (·.2.isNone))
    "A disagreed label borrowed a passing or incomplete code-panel status"
  let summary ← Commands.buildSummary snapshot
  ensure (summary.incompleteDetails.any (fun row => row.label == incomplete &&
      row.decl == ``admitted && row.status == checked.status) &&
    !summary.incompleteDetails.any (·.label == disagreed))
    "A disagreed label borrowed another label's incomplete-declaration details"

-- Facet panels use the selected realization even when a label and object are shared.
run_cmd liftTermElabM do
  let state := Environment.informalExt.getState (← getEnv)
  let raw := Capture.Raw.ofState state
  let label := Name.mkSimple "storage.native"
  let some registered := state.inventory.get? label | throwError "Missing imported plain native fixture"
  let #[original] := registered.nativeAssociations | throwError "Expected one native attachment"
  ensure (original.placement == `statement) "Expected a statement panel for the original attachment"
  let alternate ← withDifferentRange { original with
    realization := { original.realization with name := `alternate }
    placement := `proof }
  let alternateRequest := Capture.NativeRequest.ofAssociation alternate.context alternate
  let node := { registered with sources := #[], uses := #[], nativeAssociations := #[original, alternate] }
  let plan := Capture.plan { raw with nodes := #[(label, node)], authored := #[] }
  let observations ← obtain (← Capture.observe plan)
  ensure (observations.native.size == 2 && observations.native.all (·.result.isOk) &&
    (observations.native.filter (·.request == alternateRequest)).size == 1 &&
    observations.checks.size == 1) "The two realizations must share a real check and have distinct source requests"
  let changed := { observations with native := observations.native.map fun answer =>
    if answer.request != alternateRequest then answer else
      { answer with result := answer.result.map fun prepared => { prepared with roles := #[`statement] } } }
  let snapshot ← obtain (Capture.evaluate plan changed)
  let name := original.reference.canonical
  let object : ObjectKey := ⟨original.context, name.toString⟩
  let accepted : RequirementKey := ⟨.declaration (original.realization.forRole `implementation) object, `implementation⟩
  let rejected : RequirementKey := ⟨.declaration (alternate.realization.forRole `statement) object, `statement⟩
  ensure ((snapshot.registry.localResult accepted).complete && (snapshot.registry.requirement? rejected).isSome &&
    !(snapshot.registry.localResult rejected).complete &&
    snapshot.sourceDiagnostics.nodes.any (fun (owner, issue) =>
      owner == label && issue.code == "native-role-disagreement" && issue.subject == name.toString))
    "The replay must reject the alternate realization while keeping the original check"
  let panels := TraversalIndex.Nodes.capture { state with inventory := state.inventory.insert label node } (some snapshot)
  let some panel := panels.find? (·.label == label) | throwError "Missing captured panels"
  ensure (panel.statementExternalChecks == #[(name, some .proved)] &&
    panel.proofExternalChecks == #[(name, none)])
    "A panel borrowed the status of another realization of the same declaration"

run_cmd liftTermElabM do
  let flat := Name.mkSimple "foo.bar»"
  let nested := Name.str (Name.mkSimple "foo") "bar»"
  let edge : Capture.SelectedUse := {
    source := `using, context := none, realization := none, role := `proof
    reference := { label := `target }, selected := .ok #[] }
  let withKey (name : Name) : Capture.SelectedUse :=
    { edge with selected := .ok #[⟨.realization ⟨`target, `lean⟩, name⟩] }
  ensure (toJson flat == toJson nested && flat != nested) "Control requires colliding display names"
  ensure ((withKey flat).bindingData != (withKey nested).bindingData)
    "Selected requirement identities must preserve typed names"
  let unresolved (code subject message : String) : Capture.SelectedUse :=
    { edge with selected := .error { code, subject, message } }
  ensure ((unresolved "missing-target" "target" "first wording").bindingData ==
      (unresolved "missing-target" "Target Display" "reworded diagnostic").bindingData)
    "Unresolved use bindings must not depend on display subject or diagnostic wording"
  ensure ((unresolved "missing-target" "target" "msg").bindingData !=
      (unresolved "ambiguous-target" "target" "msg").bindingData)
    "Unresolved use bindings must distinguish diagnostic codes"
  ensure ({ edge with reference := { edge.reference with origin := .manual } }.bindingData !=
      { edge with reference := { edge.reference with origin := .automatic } }.bindingData &&
      { edge with reference := { edge.reference with intent := .regular } }.bindingData !=
      { edge with reference := { edge.reference with intent := .auxiliary } }.bindingData)
    "Selected use bindings must distinguish origin and intent"

set_option doc.verso true in
/-- The value {Lean.Doc.lean}`x` is the owner's parameter. -/
@[blueprint "capture.bareOwnerHighlight"]
theorem bareOwnerHighlight (x : Nat) : x = x := rfl

set_option doc.verso true in
/-- The function {Lean.Doc.lean}`fun (x : Nat) => x` introduces a snippet binder. -/
@[blueprint "capture.bareSnippetHighlight"]
theorem bareSnippetHighlight (x : Nat) : x = x := rfl

set_option doc.verso true in
/-- The name {name}`x` selects the owner's parameter. -/
@[blueprint "capture.localNameDoc"]
theorem localNameDoc (x : Nat) : x = x := rfl

run_cmd liftTermElabM do
  let cases := #[
    (Name.mkSimple "capture.bareOwnerHighlight", ``bareOwnerHighlight, true),
    (Name.mkSimple "capture.bareSnippetHighlight", ``bareSnippetHighlight, true),
    (Name.mkSimple "capture.localNameDoc", ``localNameDoc, false)]
  let raw := Capture.Raw.ofState (Environment.informalExt.getState (← getEnv))
  let plan := Capture.plan { raw with
    nodes := raw.nodes.filter (fun (label, _) => cases.any (·.1 == label)), authored := #[] }
  let observations ← obtain (← Capture.observe plan)
  let snapshot ← obtain (Capture.evaluate plan observations)
  for (label, declaration, unsupported) in cases do
    let rejected := snapshot.sourceDiagnostics.nodes.any fun (owner, diagnostic) =>
      owner == label && diagnostic.subject == declaration.toString &&
        diagnostic.code == "unsupported-docstring-extension" &&
        diagnostic.message == "Compiled highlighted local variable has no captured local-context binder identity"
    let statement := (⟨label, `verso⟩ : RealizationKey).forRole `statement
    let some model := snapshot.registry.realization? statement
      | throwError "Missing compiled docstring realization for {label}"
    let #[key] := model.documents | throwError "Expected one docstring selection for {label}"
    let some document := snapshot.registry.documents.find? (·.key == key)
      | throwError "Missing compiled docstring selection for {label}"
    ensure (rejected == unsupported && document.text.isEmpty == unsupported &&
      (snapshot.assessmentFor label).requiredComplete)
      s!"Expected exact local-context identity for {label} with native checks complete"

end RealizationCaptureFixture
