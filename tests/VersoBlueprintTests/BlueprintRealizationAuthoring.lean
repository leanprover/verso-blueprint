/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintNativeFixture
import VersoBlueprintTests.BlueprintRealizationAuthoring.Owner
import VersoBlueprintTests.BlueprintRealizationAuthoring.Attachment
import VersoBlueprint.Realizations.Report
import VersoBlueprint.Realizations.Dependencies

open Lean Meta Elab Command Term Informal
open Realizations Validation Translations

namespace VersoBlueprintTests.BlueprintRealizationAuthoring

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error issues => throwError "Unexpected rejection: {repr issues}"

/-- info: Authoring/import: native proof complete; prose unassessed; Verso link pending; Rocq link blocked -/
#guard_msgs in
run_cmd liftTermElabM do
  let before := Environment.informalExt.getState (← getEnv)
  ensure before.authoringProject?.isNone "Imports must not configure the consumer"
  let r ← obtain ((← Realizations.Capture.capture).map (·.registry))
  ensure ((r.resultForRequirement Owner.proof).complete &&
    (r.resultFor (.realization Owner.proseKey)).status == .unassessed &&
    (r.resultFor (.translation Owner.versoLink)).status == .pending &&
    (r.resultFor (.translation Owner.rocqLink)).status == .blocked)
    "Actual imported contracts retain independent native/prose/correspondence outcomes"
  ensure ((r.resultFor (.realization ⟨Name.mkSimple "authoring.unassessed", `lean⟩)).complete)
    "A real native check supplies proof validity without a duplicate independent specification"
  ensure (r.nodes.size == 5 && r.realizations.size == 11 && r.translations.size == 2 && r.evidence.size == 15)
    "Actual diamond imports and exact replay duplicate no semantic values or evidence"
  for (consumer, target, complete) in #[("authoring.nativeDependent", "authoring.unassessed", true),
      ("authoring.admittedDependent", "authoring.nativeAdmitted", false)] do
    let uses ← obtain (← Realizations.Dependencies.selectUses r ⟨`lean, Owner.projectName⟩ (Name.mkSimple consumer))
    let some (_, selected) := uses.1.find? (fun edge => edge.1.label == Name.mkSimple target)
      | throwError "Missing native-only ordinary dependency"
    let selected ← obtain selected
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
  let uses ← obtain (← Realizations.Dependencies.selectUses alternatives witness.context (Name.mkSimple "authoring.admittedDependent"))
  let some (_, .ok selected) := uses.1.find? (fun entry => entry.1.label == Name.mkSimple "authoring.nativeAdmitted")
    | throwError "Missing admitted native default"
  ensure ((alternatives.resultForRequirement alternativeKey).complete &&
    !(alternatives.resultForRequirement selected).complete &&
    selected.subject != alternativeKey.subject) "A complete native alternative cannot rescue the selected admitted default"
  let after := Environment.informalExt.getState (← getEnv)
  ensure (decide (before.authoringRecords = after.authoringRecords) &&
    decide (before.localAuthoringRecords = after.localAuthoringRecords) &&
    before.authoringProject? == after.authoringProject?) "Query persists no evidence or authoring changes"
  ensure ((← obtain (Json.parse (Report.ofRegistry r).compress)) == Report.ofRegistry r)
    "Normal consumer reports its combined imported model without assembling Input/admit"
  logInfo "Authoring/import: native proof complete; prose unassessed; Verso link pending; Rocq link blocked"

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
  ensure (before.data.toArray.map (·.1) == after.data.toArray.map (·.1)) "Accepted labels changed"
  for (label, a) in before.data.toArray do
    let some b := after.data.get? label | throwError "Accepted node disappeared"
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
  ensure (before.pendingNodes.toArray.map (·.1) == after.pendingNodes.toArray.map (·.1)) "Pending labels changed"
  for (label, a) in before.pendingNodes.toArray do
    let some b := after.pendingNodes.get? label | throwError "Pending node disappeared"
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

private def query : TermElabM (Except (Array Diagnostic) Registry) := do
  let before := Environment.informalExt.getState (← getEnv)
  let sentinel ← mkFreshExprMVar (mkConst ``True)
  let metaBefore ← getMCtx
  let result := (← Realizations.Capture.capture).map (·.registry)
  let metaAfter ← getMCtx
  unchanged before (Environment.informalExt.getState (← getEnv))
  ensure (!(← sentinel.mvarId!.isAssigned) && metaBefore.mvarCounter == metaAfter.mvarCounter &&
    metaBefore.lmvarCounter == metaAfter.lmvarCounter &&
    metaBefore.eAssignment.toList == metaAfter.eAssignment.toList &&
    metaBefore.lAssignment.toList == metaAfter.lAssignment.toList &&
    metaBefore.decls.toList.map (·.1) == metaAfter.decls.toList.map (·.1))
    "Materialization leaked elaborator changes"
  return result

private def rejected (code : String) (result : Except (Array Diagnostic) α) : TermElabM (Array Diagnostic) :=
  match result with
  | .ok _ => throwError "Unexpected partial/successful model; expected {code}"
  | .error issues => do
    ensure (issues.any (·.code == code)) s!"Wrong rejection: {repr issues}"
    return issues

run_cmd liftCoreM <| Realizations.Authoring.configureProject Owner.projectName
-- Distinct module/site boundaries must not falsely collide with Owner/prefixSite.
run_cmd liftCoreM <| Realizations.Authoring.stage `Owner.prefixSite {}
run_cmd liftCoreM <| Realizations.Authoring.expectNative `consumerProof (Name.mkSimple "authoring.unassessed") `VersoBlueprintTests.BlueprintRealizationAuthoring.expectedTrue

run_cmd liftTermElabM do
  let r ← obtain (← query)
  let key : RealizationKey := ⟨Name.mkSimple "authoring.unassessed", `lean⟩
  ensure ((r.resultFor (.realization key)).complete && r.evidence.size == 16)
    "A separately authored consumer specification can validate an imported default"
  let some requirement := r.requirements.find? (fun requirement => requirement.key.name == `expectedProof &&
      requirement.key.subject == .declaration key
        ⟨⟨`lean, Owner.projectName⟩, "VersoBlueprintTests.BlueprintRealizationAuthoring.Owner.withoutContract"⟩)
    | throwError "Missing consumer-owned native requirement"
  let .proof goal _ := requirement.expected | throwError "Wrong requirement"
  ensure (goal.documents.any (·.path.endsWith "/Owner.lean") &&
    goal.documents.any (·.path.endsWith "/BlueprintRealizationAuthoring.lean"))
    "Binding must include both canonical witness and independently authored specification source"
  for key in goal.documents do
    let some document := r.documents.find? (·.key == key) | throwError "Missing bound source"
    ensure (document.text == (← IO.FS.readFile key.path)) "Bound source is not the original canonical bytes"
  for evidence in r.evidence do
    ensure (r.bindingFor evidence.requirement == some evidence.binding) "Observation bound to another snapshot"
    match evidence.observation with
    | .proof observation => ensure (observation.outcome == .passed) "Actual independent-goal proof did not pass"
    | .check observation =>
      ensure (observation.validator == `blueprint.dependencySelection || observation.declaration.isSome) "A native check must retain its own declaration identity"
    | .review _ => throwError "Unexpected manufactured review evidence"
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
    let r ← obtain (← query)
    let uses ← obtain (← Realizations.Dependencies.selectUses r ⟨`lean, Owner.projectName⟩
      (Name.mkSimple "authoring.admittedDependent"))
    let some (_, .ok key) := uses.1.find? (fun entry => entry.1.label == Name.mkSimple "authoring.nativeDependent")
      | throwError "Missing exact native prerequisite"
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
    ensure (specs.size == 2 && specs[0]!.origin.id != specs[1]!.origin.id && r.evidence.size == 17)
      "Equivalent expectations must retain both specification origins and current observations"
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
    Environment.modify fun state => { state with data := state.data.modify Owner.node fun node =>
      { node with nativeAssociations := node.nativeAssociations.map fun association =>
        { association with reference := { association.reference with canonical := `Wrong.subject } } } }
    discard <| rejected "unknown-requirement" (← query)
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
  return ({ id, label, nativeAssociations := BlueprintNativeFixture.associations label #[`statement] #[reference] Owner.projectName, priority := none, source := none },
    { count := state.nextCount + 100, tags := #["synthetic candidate"]
      sources := #[BlueprintNativeFixture.source label `verso `statement `verso
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
    let result ← Environment.withDirective (pure { label := `outerFailure, kind := .statement .lemma }) .missing do
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
      discard <| Environment.withDirective (pure { label := `outerException, kind := .statement .lemma }) .missing do
        insideDirective
        throwError "Synthetic enclosing directive exception"
        pure ((), #[])
    catch exception =>
      caught := (← exception.toMessageData.toString) == "Synthetic enclosing directive exception"
    ensure caught "Expected directive exception"
    unchanged before (Environment.informalExt.getState (← getEnv))

end VersoBlueprintTests.BlueprintRealizationAuthoring
