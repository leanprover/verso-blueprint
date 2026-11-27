/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintNativeFixture
import VersoBlueprintTests.BlueprintRealizationAuthoring.Owner
import VersoBlueprintTests.BlueprintRealizationAuthoring.Attachment
import VersoBlueprint.Realizations.Report

open Lean Meta Elab Command Term Informal
open Realizations Validation Translations

namespace VersoBlueprintTests.BlueprintRealizationAuthoring

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error issues => throwError "Unexpected rejection: {repr issues}"

/-- The native proof contract that the production capture selected for one
proof-axis dependency. -/
private def selectedProof (snapshot : Capture.Snapshot) (consumer target : String) : TermElabM RequirementKey := do
  let some use := snapshot.uses.find? fun use => use.source == Name.mkSimple consumer &&
      use.role == `proof && use.reference.label == Name.mkSimple target
    | throwError "Missing captured dependency {consumer} -> {target}"
  let some key := (← obtain use.selected).find? (·.name == `proof)
    | throwError "Dependency {consumer} -> {target} selected no native proof contract"
  return key

private def unassessedProofKey : RealizationKey :=
  (⟨Name.mkSimple "authoring.unassessed", `lean⟩ : RealizationKey).forRole `proof

private def unassessedWitness : ObjectKey := ⟨⟨`lean, Owner.projectName⟩,
  "VersoBlueprintTests.BlueprintRealizationAuthoring.Owner.withoutContract"⟩

private def unassessedProofKeyRequirement : RequirementKey :=
  ⟨.declaration unassessedProofKey
    ⟨⟨`lean, Owner.projectName⟩, "VersoBlueprintTests.BlueprintRealizationAuthoring.Owner.withoutContract"⟩,
    `proof⟩

/-- info: Authoring/import: native proof complete; prose unassessed; Verso link complete under explicit MOCK review; Rocq link blocked -/
#guard_msgs in
run_cmd liftTermElabM do
  let before := Environment.informalExt.getState (← getEnv)
  ensure before.authoringProject?.isNone "Imports must not configure the consumer"
  let snapshot ← obtain (← Realizations.Capture.capture)
  let r := snapshot.registry
  ensure ((r.resultForRequirement Owner.proof).complete &&
    (r.resultFor (.realization Owner.proseKey)).status == .unassessed &&
    (r.resultFor (.translation Owner.versoLink)).complete &&
    (r.resultFor (.translation Owner.rocqLink)).status == .blocked)
    s!"Imported outcomes: native={repr (r.resultForRequirement Owner.proof)}, prose={repr (r.resultFor (.realization Owner.proseKey))}, Verso={repr (r.resultFor (.translation Owner.versoLink))}, Rocq={repr (r.resultFor (.translation Owner.rocqLink))}"
  ensure ((r.resultFor (.realization unassessedProofKey)).complete)
    "A real native check supplies proof validity without a duplicate independent specification"
  ensure (r.nodes.size == 5 && r.realizations.size == 16 && r.translations.size == 2)
    s!"Imported diamond inventory has unexpected cardinality: nodes={r.nodes.size}, realizations={r.realizations.size}, translations={r.translations.size}"
  ensure (r.evidence.any (fun evidence => evidence.requirement == Owner.proof &&
      r.bindingFor Owner.proof == some evidence.binding &&
      (match evidence.observation with
      | .check observation => observation.outcome == .passed
      | _ => false)) &&
    r.evidence.any (fun evidence => evidence.requirement == unassessedProofKeyRequirement &&
      r.bindingFor unassessedProofKeyRequirement == some evidence.binding &&
      (match evidence.observation with
      | .check observation => observation.outcome == .passed
      | _ => false)))
    "Imported theorem bodies retain current, actual native proof checks"
  ensure (r.reviewSelections.any (fun selection => selection.requirement == Owner.versoReview &&
      selection.judgment == some `mockVersoCorrespondence) &&
    (r.evidence.filter fun evidence => evidence.requirement == Owner.versoReview).size == 1 &&
    r.evidence.any (fun evidence => evidence.requirement == Owner.versoReview &&
      r.bindingFor Owner.versoReview == some evidence.binding &&
      (match evidence.observation with
      | .review judgment => judgment.criterion == `statementCorrespondence &&
          judgment.reviewer == `MockReviewer && judgment.outcome == .passed
      | _ => false)))
    "The completed Verso link must be supported by the explicitly selected, current MOCK review"
  for (consumer, target, complete) in #[("authoring.nativeDependent", "authoring.unassessed", true),
      ("authoring.admittedDependent", "authoring.nativeAdmitted", false)] do
    let selected ← selectedProof snapshot consumer target
    let some requirement := r.requirement? selected | throwError "Missing native contract"
    ensure (selected.name == `proof && requirement.expected == .check NativeLean.bodyValidator &&
      (r.resultForRequirement selected).complete == complete)
      "Native prerequisites select exact complete-body checks without expected-goal duplication"
  -- A real complete native alternative is an explicitly constructed control;
  -- it must not donate completion to the ordinary admitted default.
  let alternative : RealizationKey := ⟨Name.mkSimple "authoring.nativeAdmitted", `alternative⟩
  let witness : ObjectKey := ⟨⟨`lean, Owner.projectName⟩,
    "VersoBlueprintTests.BlueprintRealizationAuthoring.Owner.withoutContract"⟩
  let fresh ← obtain (← NativeLean.checkDeclaration Owner.projectName witness)
  let alternativeKey : RequirementKey := ⟨.declaration alternative witness, `proof⟩
  let moduleName ← getMainModule
  let extended := { r.contributions with
    realizations := r.contributions.realizations.push {
      origin := { id := `nativeAlternative, moduleName }
      value := {
        key := alternative, context := witness.context
        declarations := #[{ object := witness, required := #[alternativeKey] }] } }
    requirements := r.contributions.requirements.push {
      origin := { id := `nativeAlternativeRequirement, moduleName }
      value := { key := alternativeKey, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure } } }
  let candidate ← obtain (admit extended)
  let some binding := candidate.bindingFor alternativeKey | throwError "Missing alternative binding"
  let alternatives ← obtain (admit { extended with evidence := extended.evidence.push {
    origin := { id := `nativeAlternativeEvidence, moduleName }
    value := {
      id := `nativeAlternativeCheck, requirement := alternativeKey, binding
      observation := .check fresh.body } } })
  let selected ← selectedProof snapshot "authoring.admittedDependent" "authoring.nativeAdmitted"
  ensure ((alternatives.resultForRequirement alternativeKey).complete &&
    !(alternatives.resultForRequirement selected).complete &&
    selected.subject != alternativeKey.subject) "A complete native alternative cannot rescue the selected admitted default"
  let after := Environment.informalExt.getState (← getEnv)
  ensure (decide (before.authoringRecords = after.authoringRecords) &&
    decide (before.localAuthoringRecords = after.localAuthoringRecords) &&
    before.authoringProject? == after.authoringProject?) "Query persists no evidence or authoring changes"
  ensure ((← obtain (Json.parse (Report.ofRegistry r).compress)) == Report.ofRegistry r)
    "Normal consumer reports its combined imported model without assembling Input/admit"
  logInfo "Authoring/import: native proof complete; prose unassessed; Verso link complete under explicit MOCK review; Rocq link blocked"

-- Independent consumer-owned contracts. The axiom is deliberately not a
-- definition and must never supply a validated expected proposition.
def expectedTrue : Prop := True
def wrongExpected : Prop := False
def nonProposition : Nat := 0
axiom assumedExpected : Prop
theorem rollbackDeclaration : True := True.intro

-- Assert semantic fields, evidence buffers, indexes, catalogs and counters
-- directly. No debug rendering is used as a substitute for state assertions.
private def unchanged (before after : Environment.State) : TermElabM Unit := do
  ensure (before.inventory.toArray.map (·.1) == after.inventory.toArray.map (·.1)) "Accepted labels changed"
  for (label, a) in before.inventory.toArray do
    let some b := after.inventory.get? label | throwError "Accepted node disappeared"
    ensure (a.kind == b.kind && a.kindIsExplicit == b.kindIsExplicit && a.count == b.count &&
      reprStr a.sources == reprStr b.sources && a.uses == b.uses &&
      a.nativeAssociations == b.nativeAssociations &&
      a.parent == b.parent && a.priority == b.priority && a.owner == b.owner && a.tags == b.tags &&
      a.effort == b.effort && a.prUrl == b.prUrl && a.issueUrl == b.issueUrl &&
      a.origin == b.origin && a.modules == b.modules) "Accepted node fields changed"
  ensure (before.nextCount == after.nextCount &&
    decide (before.factRecords = after.factRecords) &&
    decide (before.localFactRecords = after.localFactRecords) &&
    before.leanNameLabels.toArray == after.leanNameLabels.toArray) "Evidence/index/counter changed"
  ensure (before.nodeRegistrations.toArray.map (·.1) == after.nodeRegistrations.toArray.map (·.1)) "Pending labels changed"
  for (label, a) in before.nodeRegistrations.toArray do
    let some b := after.nodeRegistrations.get? label | throwError "Pending node disappeared"
    ensure (a.registrations.size == b.registrations.size && a.localRegistrations.size == b.localRegistrations.size &&
      a.origin == b.origin && a.contributors == b.contributors && a.authoredOrigin? == b.authoredOrigin? &&
      a.authoredOriginConflict == b.authoredOriginConflict) "Pending payload/export/provenance changed"
  for (a, b) in #[(before.blueprintAttributeLabelsByModule, after.blueprintAttributeLabelsByModule),
      (before.localBlueprintAttributeLabelsByModule, after.localBlueprintAttributeLabelsByModule)] do
    ensure (a.toArray.map (·.1) == b.toArray.map (·.1)) "Catalog modules changed"
    for (moduleName, x) in a.toArray do
      let some y := b.get? moduleName | throwError "Catalog disappeared"
      ensure (x.labels == y.labels && x.members.toArray == y.members.toArray) "Catalog content changed"
  ensure (before.groups.toArray == after.groups.toArray && before.localGroups.toArray == after.localGroups.toArray &&
    decide (before.authors.toArray = after.authors.toArray) &&
    decide (before.localAuthors.toArray = after.localAuthors.toArray) &&
    decide (before.importedConflicts = after.importedConflicts) &&
    before.activeDirective.map (·.label) == after.activeDirective.map (·.label) &&
    before.authoringProject? == after.authoringProject? &&
    decide (before.authoringRecords = after.authoringRecords) &&
    decide (before.localAuthoringRecords = after.localAuthoringRecords)) "Scope/raw/export state changed"

private def isolated (action : TermElabM α) : TermElabM α := do
  let env ← getEnv
  try action finally setEnv env

private def capturePlanned : TermElabM (Except (Array Diagnostic) Capture.Snapshot) := do
  let raw := Capture.Raw.ofState (Environment.informalExt.getState (← getEnv))
  let plan := Capture.plan raw
  match ← Capture.observe plan with
  | .error issues => pure (.error issues)
  | .ok observations => pure (Capture.evaluate plan observations)

private def querySnapshot : TermElabM (Except (Array Diagnostic) Capture.Snapshot) := do
  let before := Environment.informalExt.getState (← getEnv)
  let sentinel ← mkFreshExprMVar (mkConst ``True)
  let metaBefore ← getMCtx
  let result ← capturePlanned
  let metaAfter ← getMCtx
  unchanged before (Environment.informalExt.getState (← getEnv))
  ensure (!(← sentinel.mvarId!.isAssigned) && metaBefore.mvarCounter == metaAfter.mvarCounter &&
    metaBefore.lmvarCounter == metaAfter.lmvarCounter &&
    metaBefore.eAssignment.toList == metaAfter.eAssignment.toList &&
    metaBefore.lAssignment.toList == metaAfter.lAssignment.toList &&
    metaBefore.decls.toList.map (·.1) == metaAfter.decls.toList.map (·.1))
    "Materialization leaked elaborator changes"
  return result

private def query : TermElabM (Except (Array Diagnostic) Registry) :=
  return (← querySnapshot).map (·.registry)

private def rejected (code : String) (result : Except (Array Diagnostic) α) : TermElabM (Array Diagnostic) :=
  match result with
  | .ok _ => throwError "Unexpected partial/successful model; expected {code}"
  | .error issues => do
    ensure (issues.any (·.code == code)) s!"Expected rejection {code}, got: {repr issues}"
    return issues

run_cmd liftCoreM <| Realizations.Authoring.configureProject Owner.projectName
-- Distinct module/site boundaries must not falsely collide with Owner/prefixSite.
run_cmd liftCoreM <| Realizations.Authoring.stage `Owner.prefixSite {}
run_cmd liftCoreM <| Realizations.Authoring.expectNative `consumerProof (Name.mkSimple "authoring.unassessed") `VersoBlueprintTests.BlueprintRealizationAuthoring.expectedTrue

run_cmd liftTermElabM do
  let r ← obtain (← query)
  let key := unassessedProofKey
  ensure ((r.resultFor (.realization key)).complete)
    s!"A separately authored consumer specification can validate an imported default: {repr (r.resultFor (.realization key))}"
  let some requirement := r.requirements.find? (fun requirement => requirement.key.name == `expectedProof &&
      requirement.key.subject == .declaration key unassessedWitness)
    | throwError "Missing consumer-owned native requirement"
  let .proof goal _ := requirement.expected | throwError "Wrong requirement"
  ensure ((r.resultForRequirement requirement.key).complete &&
    r.evidence.any (fun evidence => evidence.requirement == requirement.key &&
      r.bindingFor requirement.key == some evidence.binding &&
      (match evidence.observation with
      | .proof observation => observation.outcome == .passed
      | _ => false)))
    "The independently authored proposition must have a current passing native proof observation"
  ensure (goal.documents.size == 1 && goal.documents.any (·.path.endsWith "/BlueprintRealizationAuthoring.lean"))
    "Binding must include the independently authored specification source and no native witness file"
  for key in goal.documents do
    let some document := r.documents.find? (·.key == key) | throwError "Missing bound source"
    ensure (document.text == (← IO.FS.readFile key.path)) "Bound source is not the original canonical bytes"
  for evidence in r.evidence do
    ensure (r.bindingFor evidence.requirement == some evidence.binding) "Observation bound to another snapshot"
    match evidence.observation with
    | .proof observation => ensure (observation.outcome == .passed) "Actual independent-goal proof did not pass"
    | .check observation =>
      ensure (observation.validator == Validation.dependencySelectionValidator || observation.declaration.isSome) "A native check must retain its own declaration identity"
    | .review observation =>
      ensure (evidence.requirement == Owner.versoReview &&
        observation.criterion == `statementCorrespondence && observation.reviewer == `MockReviewer &&
        observation.outcome == .passed)
        "The only review evidence in this imported model must be its explicit MOCK correspondence control"
  let env ← getEnv
  ensure (((Environment.informalExt.getState env).authoringRecords.filter
      (fun record => record.origin.moduleName == env.mainModule)).size == 2)
    "Consumer/Owner prefix site collided or query persisted observations"

-- This combined command runs many complete current-source admissions. Its
-- budget is local to these regression controls, not a production query setting.
set_option maxHeartbeats 800000 in
run_cmd liftTermElabM do
  isolated do
    Realizations.Authoring.expectNative `wrongIndependentGoal (Name.mkSimple "authoring.nativeDependent")
      `VersoBlueprintTests.BlueprintRealizationAuthoring.wrongExpected
    let snapshot ← obtain (← querySnapshot)
    let r := snapshot.registry
    let key ← selectedProof snapshot "authoring.admittedDependent" "authoring.nativeDependent"
    let expected := { key with name := `expectedProof }
    ensure ((r.resultForRequirement key).complete && !(r.resultForRequirement expected).complete &&
      (r.localResult key).complete)
      "Wrong independently expected goal must not erase native validity or change native prerequisite selection"
  isolated do
    Realizations.Authoring.expectNative `secondConsumerSpec (Name.mkSimple "authoring.unassessed")
      `VersoBlueprintTests.BlueprintRealizationAuthoring.expectedTrue
    let r ← obtain (← query)
    let specs := r.contributions.requirements.filter (fun record =>
      record.origin.moduleName == `VersoBlueprintTests.BlueprintRealizationAuthoring)
    let expectedKey : RequirementKey := ⟨.declaration unassessedProofKey unassessedWitness, `expectedProof⟩
    let authoredSpecs := r.requirements.filter fun requirement =>
      requirement.key == expectedKey &&
        (match requirement.expected with
        | .proof _ witness => witness == unassessedWitness
        | _ => false)
    let currentSpecs := r.evidence.filter fun evidence =>
        evidence.requirement == expectedKey && r.bindingFor expectedKey == some evidence.binding &&
        (match evidence.observation with
        | .proof observation => observation.outcome == .passed && observation.witness == unassessedWitness
        | _ => false)
    ensure (specs.size == 2 && specs[0]!.origin.id != specs[1]!.origin.id &&
      specs.all (·.value.key == expectedKey) && authoredSpecs.size == 1 &&
      (r.resultForRequirement expectedKey).complete && currentSpecs.size == 2 &&
      currentSpecs[0]!.id != currentSpecs[1]!.id)
      s!"Equivalent expectations must retain both specification origins and current observations: origins={repr (specs.map (·.origin))}, requirements={repr authoredSpecs}, current={repr currentSpecs}"
  isolated do
    Realizations.Authoring.stage `sameProducer {}
    let before := Environment.informalExt.getState (← getEnv)
    discard <| rejected "producer-collision" (← Environment.stageAuthored `sameProducer {
      realizations := #[{ key := ⟨Owner.node, `newFacet⟩, context := ⟨`lean, Owner.projectName⟩ }] })
    unchanged before (Environment.informalExt.getState (← getEnv))
  isolated do
    Realizations.Authoring.expectNative `competing Owner.node
      `VersoBlueprintTests.BlueprintRealizationAuthoring.wrongExpected
    let issues ← rejected "semantic-conflict" (← query)
    ensure (issues.any fun issue => issue.origins.any (·.moduleName ==
      `VersoBlueprintTests.BlueprintRealizationAuthoring.Owner) && issue.origins.any (·.moduleName ==
      `VersoBlueprintTests.BlueprintRealizationAuthoring)) "Both competing specification origins must survive"
  isolated do
    Realizations.Authoring.expectNative `assumed Owner.node
      `VersoBlueprintTests.BlueprintRealizationAuthoring.assumedExpected
    discard <| rejected "invalid-expectation" (← query)
  isolated do
    Realizations.Authoring.expectNative `wrongOwner Owner.node
      `VersoBlueprintTests.BlueprintRealizationAuthoring.Owner.expected
    discard <| rejected "wrong-expectation-owner" (← query)
  isolated do
    Realizations.Authoring.expectNative `nonProposition Owner.node
      `VersoBlueprintTests.BlueprintRealizationAuthoring.nonProposition
    discard <| rejected "invalid-expectation-or-witness" (← query)
  isolated do
    let state := Environment.informalExt.getState (← getEnv)
    let some fact := state.factRecords.find? (·.label == Owner.node) | throwError "Missing actual fact"
    -- Isolated raw corruption: conflicting complete fact with the same identity.
    Environment.modify fun state => { state with factRecords := { fact with priority := some "synthetic" } :: state.factRecords }
    discard <| rejected "producer-collision" (← query)
  isolated do
    Environment.modify fun state => { state with inventory := state.inventory.modify Owner.node fun node =>
      { node with nativeAssociations := node.nativeAssociations.map fun association =>
        { association with reference := { association.reference with canonical := `Wrong.subject } } } }
    -- The expectation cannot borrow the original theorem after its accepted
    -- source association changes: exact proof selection fails before admission.
    let issues ← rejected "ambiguous-native-expectation" (← query)
    ensure (issues.any (fun issue => issue.code == "ambiguous-native-expectation" &&
      issue.subject == Owner.node.toString)) "Wrong native expectation subject"
  let conflict (reverse : Bool) := isolated do
    let a : Environment.AuthoredBatch := {
      realizations := #[{ key := ⟨Owner.node, `conflict⟩, context := ⟨`lean, Owner.projectName⟩ }] }
    let b : Environment.AuthoredBatch := {
      realizations := #[{ key := ⟨Owner.node, `conflict⟩, context := ⟨`rocq, Owner.projectName⟩ }] }
    if reverse then
      Realizations.Authoring.stage `variantB b
      Realizations.Authoring.stage `variantA a
    else
      Realizations.Authoring.stage `variantA a
      Realizations.Authoring.stage `variantB b
    rejected "semantic-conflict" (← query)
  let forward ← conflict false
  let backward ← conflict true
  ensure (decide (forward = backward)) "Whole-batch conflict diagnostics depend on producer order"

-- Synthetic transaction inputs are used only to test rejection/rollback, never
-- as provider facts or evidence. The native identity is a real checked theorem.
private def rollbackInput (label : Name) : CoreM (Contributions.Record × SourceData.Registration) := do
  let state := Environment.informalExt.getState (← getEnv)
  let moduleName ← getMainModule
  let id : Contributions.ContributionId := {
    moduleName, producer := `blueprint.attribute
    subject := `VersoBlueprintTests.BlueprintRealizationAuthoring.rollbackDeclaration, site := 8001, slot := 0 }
  let reference : Data.ExternalRef := {
    canonical := `VersoBlueprintTests.BlueprintRealizationAuthoring.rollbackDeclaration
    written := `rollbackDeclaration, present := true, origin := .blueprintAttr, kind := .theorem }
  return ({ id, label, nativeAssociations := BlueprintNativeFixture.associations label `statement #[reference] Owner.projectName, priority := none, source := none },
    { count := state.nextCount + 100, tags := #["synthetic candidate"]
      sources := #[BlueprintNativeFixture.source label `verso (some `statement) `verso
        (.prose { stx := .missing, previewBlocks := #[.para #[.text "Synthetic transaction body"]] }) Owner.projectName] })

-- Ordinary capture has no default-enrollment phase or theorem/docstring gate.
-- Supplemental attributes still publish the admitted candidate and catalog once.
run_cmd liftTermElabM do
  isolated do
    ensure (← Environment.contribute `preExistingDefault { tags := #["earlier"] }).isSome
      "Test must start with an accepted metadata-only concept"
    let (fact, payload) ← rollbackInput `preExistingDefault
    ensure (← Environment.contributeAttribute fact payload).isSome
      "Ordinary attribute was incorrectly restricted to opt-in new defaults"
    let state := Environment.informalExt.getState (← getEnv)
    ensure ((state.localBlueprintAttributeLabelsByModule.getD (← getMainModule) {}).labels.contains `preExistingDefault)
      "Successful ordinary attribute did not publish its catalog entry"

/-- error: Duplicate imported blueprint group label 'syntheticImport' -/
#guard_msgs in
run_cmd liftTermElabM do
  isolated do
    -- Diagnostic-only imported corruption: planning otherwise succeeds, but a
    -- newly logged error must prevent the final candidate publication.
    Environment.modify fun state => { state with importedConflicts := #[{
      kind := .group, label := `syntheticImport }], importedConflictsReported := false }
    let (fact, payload) ← rollbackInput `loggedPlanningFailure
    let before := Environment.informalExt.getState (← getEnv)
    ensure (← Environment.contributeAttribute fact payload).isNone "New logged error published the candidate"
    let after := Environment.informalExt.getState (← getEnv)
    unchanged before after
    ensure after.importedConflictsReported "Expected diagnostic-reporting flag to be retained"

private def insideDirective : TermElabM Unit := do
  Realizations.Authoring.stage `insideDirective {}
  let (fact, payload) ← rollbackInput `insideDirectiveDefault
  ensure (← Environment.contributeAttribute fact payload).isSome "Inner candidate must succeed before outer rollback"

/-- error: Synthetic enclosing directive failure -/
#guard_msgs in
run_cmd liftTermElabM do
  isolated do
    let before := Environment.informalExt.getState (← getEnv)
    let result ← Environment.withDirective (pure { label := `outerFailure, kind := some .lemma }) .missing do
      insideDirective
      logError "Synthetic enclosing directive failure"
      pure ((), #[])
    ensure result.isNone "Logged directive failure committed"
    unchanged before (Environment.informalExt.getState (← getEnv))

run_cmd liftTermElabM do
  isolated do
    let before := Environment.informalExt.getState (← getEnv)
    let mut caught := false
    try
      discard <| Environment.withDirective (pure { label := `outerException, kind := some .lemma }) .missing do
        insideDirective
        throwError "Synthetic enclosing directive exception"
        pure ((), #[])
    catch exception =>
      caught := (← exception.toMessageData.toString) == "Synthetic enclosing directive exception"
    ensure caught "Expected directive exception"
    unchanged before (Environment.informalExt.getState (← getEnv))

-- Two real declarations form a later ambiguous native witness for the ordered
-- authored-failure regression below.
@[blueprint "authoring.ambiguous"]
theorem ambiguousFirst : True := True.intro

@[blueprint "authoring.ambiguous"]
theorem ambiguousSecond : True := True.intro

run_cmd liftTermElabM do
  isolated do
    -- The first record fails only after its specification document has been
    -- observed. Planning must not report the later multi-witness ambiguity first.
    Realizations.Authoring.expectNative `earlierInvalid Owner.node
      `VersoBlueprintTests.BlueprintRealizationAuthoring.assumedExpected
    Realizations.Authoring.expectNative `laterAmbiguous (Name.mkSimple "authoring.ambiguous")
      `VersoBlueprintTests.BlueprintRealizationAuthoring.expectedTrue
    let raw := Capture.Raw.ofState (Environment.informalExt.getState (← getEnv))
    let plan := Capture.plan raw
    match ← Capture.observe plan with
    | .error issues =>
      ensure (issues.size == 1 && issues[0]!.code == "invalid-expectation" &&
        issues[0]!.subject == "VersoBlueprintTests.BlueprintRealizationAuthoring.assumedExpected")
        s!"Earlier invalid owned definition must win over later ambiguous witness: {repr issues}"
    | .ok _ => throwError "Invalid first specification was accepted before the later ambiguity"

run_cmd liftTermElabM do
  isolated do
    let target := Name.mkSimple "authoring.unassessed"
    let env ← getEnv
    let raw := Capture.Raw.ofState (Environment.informalExt.getState env)
    -- Keep this request's actual consumer-owned proposition, while avoiding
    -- unrelated imported specification jobs in this focused source-failure case.
    let raw := { raw with authored := raw.authored.filter fun record =>
      record.origin.moduleName == env.mainModule &&
        record.nativeGoals.any (fun goal => goal.1 == target) }
    let plan := Capture.plan raw
    let ownerPath ← liftM <| IO.FS.realPath
      "tests/VersoBlueprintTests/BlueprintRealizationAuthoring/Owner.lean"
    let reader (path : System.FilePath) : IO String := do
      if path == ownerPath then throw <| IO.userError "injected owning-source read failure"
      IO.FS.readFile path
    let before := Environment.informalExt.getState (← getEnv)
    let sentinel ← mkFreshExprMVar (mkConst ``True)
    let metaBefore ← getMCtx
    let observed ← Capture.observe plan reader
    let metaAfter ← getMCtx
    unchanged before (Environment.informalExt.getState (← getEnv))
    ensure (!(← sentinel.mvarId!.isAssigned) && metaBefore.mvarCounter == metaAfter.mvarCounter &&
      metaBefore.lmvarCounter == metaAfter.lmvarCounter &&
      metaBefore.eAssignment.toList == metaAfter.eAssignment.toList &&
      metaBefore.lAssignment.toList == metaAfter.lAssignment.toList &&
      metaBefore.decls.toList.map (·.1) == metaAfter.decls.toList.map (·.1))
      "Normal observation return must restore elaboration state"
    let observations ← obtain observed
    let some expectedRequest := plan.expected.find? (·.node == target)
      | throwError "Missing focused independent expected-goal request"
    let witness : ObjectKey := ⟨⟨`lean, Owner.projectName⟩,
      "VersoBlueprintTests.BlueprintRealizationAuthoring.Owner.withoutContract"⟩
    let some expectedResult := observations.expected.find? fun entry =>
        entry.request.project == expectedRequest.project && entry.request.expected == expectedRequest.expected
      | throwError "Expected-goal observation disappeared"
    let specification := plan.specifications[expectedRequest.specification]!
    let specificationDocument := plan.documents[specification.document]!
    -- A plain native declaration is prepared from the environment, so its
    -- unreadable owning file does not make it unavailable.
    ensure (observations.native.any fun result => result.request.name.toString == witness.native &&
        match result.result with
        | .error _ => false
        | .ok prepared => prepared.declaration == witness)
      "A plain native declaration must not depend on reading its owning source file"
    ensure (expectedResult.request.documents == #[specificationDocument] &&
      expectedResult.request.witness == witness)
      "Expected-goal documents must be the authored spec only, never the witness's owning file"
    let .ok checked := expectedResult.result
      | throwError "Independent expected goal did not run with an unreadable owning file"
    ensure (checked.observation.outcome == .passed && checked.goal.documents == #[specificationDocument])
      "The independently authored goal must be checked against its exact spec-only documents"
    let some checkRequest := plan.checks.find? (·.witness == witness)
      | throwError "Missing actual own-native check request"
    let some checkedResult := observations.checks.find? (·.request == checkRequest)
      | throwError "Own-native observation disappeared with an unreadable owning file"
    let .ok nativeCheck := checkedResult.result | throwError "Own-native check did not run"
    ensure (nativeCheck.body.outcome == .passed)
      "An unreadable owning file must not suppress the real own-native check"
    let snapshot ← obtain (Capture.evaluate plan observations)
    -- Doc-comment prose still reads the file and keeps its diagnostic; the
    -- native declaration's checks and expected goal complete without it.
    ensure (snapshot.diagnostics.any (·.code == "source-unavailable") &&
      snapshot.nativeChecks.any (fun result => result.declaration == witness && result.body.outcome == .passed) &&
      (snapshot.registry.resultFor (.realization unassessedProofKey)).complete)
      "Evaluated snapshot must keep the doc-comment diagnostic and complete the native proof without the owning file"

-- F1: authored alternatives own their contracts. Conventional names do not
-- opt a review (or an authored native check) into ordinary dependency wiring.
run_cmd liftTermElabM do
  let initialEnv ← getEnv
  try
    let baseline ← obtain (← Realizations.Capture.capture)
    let base := baseline.registry.contributions
    let moduleName ← getMainModule
    for (contractName, expectation) in #[
        (`proof, Expectation.review `independentReview `MockReviewer),
        (`proofReview, Expectation.review `independentReview `MockReviewer),
        (`proof, Expectation.check NativeLean.bodyValidator)] do
      setEnv initialEnv
      let alternative : RealizationKey := (⟨Owner.node, `reviewAlternative⟩ : RealizationKey).forRole `proof
      let key : RequirementKey := ⟨.declaration alternative Owner.native, contractName⟩
      let model : Realization := {
        key := alternative, context := Owner.native.context, role := `proof
        declarations := #[{ object := Owner.native, projection := .implementation, required := #[key] }] }
      let requirement : Requirement := {
        key, expected := expectation, coverage := .dependencyClosure }
      let pureInput := { base with
        realizations := base.realizations.push {
          origin := { id := `alternativeModelControl, moduleName }, value := model }
        requirements := base.requirements.push {
          origin := { id := `alternativeRequirementControl, moduleName }, value := requirement } }
      let pureRegistry ← obtain (admit pureInput)
      let isReview := match expectation with
        | .review .. => true
        | _ => false
      let expectedStatus := if isReview then Status.blocked else Status.pending
      ensure ((pureRegistry.resultForRequirement key).status == expectedStatus)
        s!"Authored alternative contract must retain its pre-capture status: {repr (pureRegistry.resultForRequirement key)}"
      if isReview then
        ensure ((pureRegistry.resultForRequirement key).diagnostics.any
          (·.code == "semantic-context-unavailable"))
          "A review alternative without its own semantic descriptor must report unavailable context"
      Authoring.configureProject Owner.projectName
      Authoring.stage `alternativeContractControl {
        realizations := #[model], requirements := #[requirement] }
      let snapshot ← obtain (← Realizations.Capture.capture)
      ensure (snapshot.registry.requirement? key == some requirement)
        "Capture rewrote an authored alternative contract based on its name or validator"
      ensure ((snapshot.registry.resultForRequirement key).status == expectedStatus)
        s!"A valid authored alternative contract must retain its selected-evidence state after capture: {repr (snapshot.registry.resultForRequirement key)}"
      if isReview then
        ensure ((snapshot.registry.resultForRequirement key).diagnostics.any
          (·.code == "semantic-context-unavailable"))
          "Capture must not borrow another realization's descriptor for this review"
      else
        ensure ((snapshot.registry.resultForRequirement key).diagnostics.isEmpty)
          "An authored native check without an observation remains pending without invented diagnostics"
      ensure (!(snapshot.registry.requirements.any fun value =>
        value.key.subject == key.subject && value.key != key))
        "Capture invented sibling contracts or dependency-selection gates for an authored alternative"
      let defaultAssessment := snapshot.assessmentFor Owner.node
      ensure (defaultAssessment.nativeProofComplete && defaultAssessment.requiredComplete)
        "An unfinished authored alternative must not change the default proof summary"
  finally
    setEnv initialEnv

end VersoBlueprintTests.BlueprintRealizationAuthoring
