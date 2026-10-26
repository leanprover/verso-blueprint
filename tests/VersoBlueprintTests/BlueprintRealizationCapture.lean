/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintCanonicalSourcePersistence.Attachment
import VersoBlueprint.Realizations.Capture
import VersoBlueprint.Realizations.Authoring

open Lean Meta Elab Command Term Informal
open Realizations Validation Translations

namespace RealizationCaptureFixture

/-- Native validity does not require an independent restatement. -/
@[blueprint "capture.complete"]
theorem complete : True := True.intro

/-- An admitted native proof remains unfinished. -/
@[blueprint "capture.admitted"]
theorem admitted : True := by sorry

/-- A clean local proof with an unfinished mathematical prerequisite. -/
@[blueprint "capture.dependent" (uses := ["capture.admitted"])]
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
@[blueprint "capture.groupedDependent" (uses := ["capture.grouped"])]
theorem groupedDependent : True := True.intro

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with | .ok value => pure value | .error issues => throwError "{repr issues}"

private def key (label : String) (declaration : Name) (name : Name := `proof) : RequirementKey :=
  ⟨.declaration ⟨Name.mkSimple label, `lean⟩ ⟨⟨`lean, `blueprintFixtures⟩, declaration.toString⟩, name⟩

-- Real imported sources and fresh kernel observations; no mocked provider facts.
run_cmd liftTermElabM do
  let before := Environment.informalExt.getState (← getEnv)
  ensure before.authoringRecords.isEmpty "Control accidentally enrolled opt-in defaults"
  let start ← IO.monoMsNow
  let snapshot ← obtain (← Capture.capture)
  let elapsed := (← IO.monoMsNow) - start
  logInfo m!"ordinary capture: {snapshot.registry.nodes.size} nodes in {elapsed} ms"
  let registry := snapshot.registry
  ensure snapshot.diagnostics.isEmpty s!"Unexpected source/provider diagnostics: {repr snapshot.diagnostics}"
  ensure (registry.nodes.size == before.data.size) "Capture omitted ordinary accepted concepts"
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
  let grouped : RealizationKey := ⟨Name.mkSimple "capture.grouped", `lean⟩
  let some groupedModel := registry.realization? grouped | throwError "Missing multi-declaration realization"
  ensure (groupedModel.declarations.size == 2 && !(registry.resultFor (.realization grouped)).complete &&
    (registry.resultForRequirement (key "capture.grouped" `RealizationCaptureFixture.groupedComplete)).complete &&
    !(registry.resultForRequirement (key "capture.grouped" `RealizationCaptureFixture.groupedAdmitted)).complete)
    "Complete sibling lent its native validity to an admitted declaration"
  let inlineKey := key "storage.source" `storedInline
  ensure ((registry.localResult inlineKey).complete && !(registry.resultForRequirement inlineKey).complete)
    "Real imported inline definition must check locally despite its missing shared dependencies"
  for name in #[`verso, `rust, Name.str `tex "body.with.dot", Name.str `markdown "body.with.dot"] do
    let model : RealizationKey := ⟨Name.mkSimple "storage.source", name⟩
    ensure (registry.realization? model |>.isSome) s!"Missing ordinary realization {name}"
    ensure ((registry.resultFor (.realization model)).status == .unassessed)
      s!"Source presence invented validation for {name}"
  for document in registry.documents do
    if document.key.path.contains "#docstring:" then
      ensure (document.text.startsWith " " && document.text.endsWith " ") "Raw own-comment whitespace was lost"
    else
      ensure (document.text == (← IO.FS.readFile document.key.path)) "Canonical document is not original source bytes"
  for evidence in registry.evidence do
    ensure (registry.bindingFor evidence.requirement == some evidence.binding) "Observation belongs to another candidate"
  ensure ((registry.requirements.filter (·.key.name == `expectedProof)).isEmpty)
    "Capture invented independent expected propositions"
  let after := Environment.informalExt.getState (← getEnv)
  ensure (reprStr before == reprStr after) "Capture mutated persistent Blueprint state"

-- Original inline text, including a supplementary Unicode character before the
-- declaration, is associated through its owning FileMap and native ranges.
run_cmd liftTermElabM do
  let state := Environment.informalExt.getState (← getEnv)
  let sources := (state.pendingNodes.getD (Name.mkSimple "storage.source") {}).registrations.flatMap (·.sources)
  let some source := sources.find? (fun source => match source.payload with | .leanInline _ => true | _ => false)
    | throwError "Missing real inline source"
  let .leanInline code := source.payload | throwError "Wrong payload"
  let request : NativeSource.Request := {
    project := `blueprintFixtures, canonical := `storedInline
    moduleName := `VersoBlueprintTests.BlueprintCanonicalSourcePersistence.Owner
    sourcePath := source.document.path }
  let prepared ← obtain (← NativeSource.prepareInline request code)
  let text ← IO.FS.readFile source.document.path
  ensure (prepared.document.text == text && text.contains '𝒫') "Inline source lost original Unicode bytes"
  for result in #[
      ← NativeSource.prepareInline request { code with stx := .missing },
      ← NativeSource.prepareInline request { code with definedDefs := #[] },
      ← NativeSource.prepareInline request code (fun _ => pure (text ++ "\n-- source changed\n")),
      ← NativeSource.prepareInline { request with moduleName := `WrongOwner } code,
      ← NativeSource.prepareInline { request with range? := some { prepared.ranges.range with charUtf16 := prepared.ranges.range.charUtf16 + 1 } } code] do
    ensure (!result.isOk) "Invalid/synthetic/stale inline association was accepted"

-- Specifications remain independently authored, with all origin variants kept.
def expectedTrue : Prop := True
def expectedFalse : Prop := False
run_cmd liftCoreM <| Authoring.configureProject `blueprintFixtures
run_cmd liftCoreM <| Authoring.expectNative `expectedComplete (Name.mkSimple "capture.complete") `RealizationCaptureFixture.expectedTrue

run_cmd liftTermElabM do
  let snapshot ← obtain (← Capture.capture)
  ensure ((snapshot.registry.resultForRequirement (key "capture.complete" `RealizationCaptureFixture.complete `expectedProof)).complete)
    "Independently authored expected proposition did not check"
  let env ← getEnv
  try
    Authoring.expectNative `competingExpectation (Name.mkSimple "capture.complete") `RealizationCaptureFixture.expectedFalse
    match ← Capture.capture with
    | .ok _ => throwError "Competing specification was silently overwritten"
    | .error issues => ensure (issues.any (·.code == "semantic-conflict")) s!"Wrong specification rejection: {repr issues}"
  finally setEnv env

run_cmd liftTermElabM do
  let env ← getEnv
  try
    Authoring.expectNative `ambiguousWitness (Name.mkSimple "capture.grouped") `RealizationCaptureFixture.expectedTrue
    match ← Capture.capture with
    | .ok _ => throwError "Node-level specification silently selected one of multiple declarations"
    | .error issues => ensure (issues.any (·.code == "ambiguous-native-expectation")) "Wrong multi-witness diagnostic"
  finally setEnv env

-- Real passed native observations cannot hide an unavailable owning source.
run_cmd liftTermElabM do
  let env ← getEnv
  try
    modifyEnv fun env => Environment.informalExt.modifyState env fun state =>
      { state with factRecords := state.factRecords.map fun fact =>
        if fact.label != Name.mkSimple "capture.complete" then fact else { fact with
          nativeAssociations := fact.nativeAssociations.map fun association => { association with
            reference := { association.reference with provenance := .inWorkspace `VersoBlueprintTests.BlueprintRealizationCapture "/definitely/missing/blueprint-source.lean" } } } }
    let snapshot ← obtain (← Capture.capture)
    ensure (snapshot.diagnostics.any (·.code == "source-unavailable")) "Missing association diagnostic was lost"
    ensure (!(snapshot.registry.resultForRequirement (key "capture.complete" `RealizationCaptureFixture.complete)).complete)
      "Unavailable source completed via a passed native observation"
  finally setEnv env


-- A valid, absent native name remains a missing-declaration diagnosis, not
-- a wrong-owner/unsupported-name failure or borrowed sibling observation.
run_cmd liftTermElabM do
  let env ← getEnv
  try
    Environment.modify fun state =>
      let records := state.factRecords.map fun fact =>
        if fact.label != Name.mkSimple "capture.dependent" then fact else { fact with
          nativeAssociations := fact.nativeAssociations.map fun association => { association with
            reference := { association.reference with canonical := `RealizationCaptureFixture.absentNative } } }
      { state with factRecords := records }
    let snapshot ← obtain (← Capture.capture)
    ensure (snapshot.diagnostics.any (·.code == "missing-declaration")) "Missing native declaration diagnostic was lost"
    ensure (!(snapshot.registry.resultForRequirement (key "capture.dependent" `RealizationCaptureFixture.absentNative)).complete)
      "Missing native declaration borrowed completion"
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

end RealizationCaptureFixture
