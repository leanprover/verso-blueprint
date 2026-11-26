/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprintTests.BlueprintAssessmentSnapshot.Owner
import VersoBlueprint.Realizations.Authoring
import VersoBlueprint.Realizations.Capture
import VersoBlueprint.Realizations.Report

/-! End-to-end consumer for an imported immutable assessment snapshot. The
owner module declares only source selections and contracts. This module performs
actual native capture and uses explicitly MOCK Alice judgments; no human reviewed
this fixture. -/

open Lean Elab Command Term Informal
open Realizations Validation Translations

namespace BlueprintAssessmentSnapshot

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error error => throwError "Capture rejected the complete fixture: {repr error}"

private def originalProseSentence := "The proposition is true. Ω 🧭 The Lean declaration provides its proof."
private def editedProseSentence := "The proposition remains true. Ω 🧭 A different proof is described here."

private def hasExactProseSelection (registry : Registry) (expected : String) : Bool := Id.run do
  let some model := registry.realization? prose | return false
  let resolved := model.documents.map fun key => registry.documents.find? (·.key == key)
  let documents := resolved.filterMap id
  return !documents.isEmpty && documents.size == model.documents.size &&
    documents.any (fun document => document.text.contains expected) &&
    documents.all (fun document => !(document.text.contains "theorem witness : True"))

private def hasExactMutualAssociations (snapshot : Realizations.Capture.Snapshot) : Bool := Id.run do
  let registry := snapshot.registry
  let some selected := registry.realization? mutualSelectedStatement | return false
  let some sibling := registry.realization? mutualSiblingStatement | return false
  let selectedChecks := snapshot.nativeChecks.filter (·.declaration == mutualSelectedObject)
  let siblingChecks := snapshot.nativeChecks.filter (·.declaration == mutualSiblingObject)
  let some selectedSource := registry.objects.find? (·.key == mutualSelectedObject) | return false
  let some siblingSource := registry.objects.find? (·.key == mutualSiblingObject) | return false
  return selected.role == `statement && sibling.role == `statement &&
    selected.declarations.size == 1 &&
    selected.declarations[0]!.object == mutualSelectedObject &&
    selected.declarations[0]!.projection == .statement &&
    sibling.declarations.size == 1 &&
    sibling.declarations[0]!.object == mutualSiblingObject &&
    sibling.declarations[0]!.projection == .statement &&
    selectedChecks.size == 1 && siblingChecks.size == 1 &&
    selectedChecks.all (·.roles.contains `statement) && siblingChecks.all (·.roles.contains `statement) &&
    selectedSource.resolution == .resolved && siblingSource.resolution == .resolved &&
    selectedSource.document.isNone && siblingSource.document.isNone

private def hasProofValuedDefinitionRoles (snapshot : Realizations.Capture.Snapshot) : Bool := Id.run do
  let registry := snapshot.registry
  let some statement := registry.realization? proofValueStatement | return false
  let some proof := registry.realization? proofValueProof | return false
  let checks := snapshot.nativeChecks.filter (·.declaration == proofValueObject)
  return statement.role == `statement && proof.role == `proof &&
    statement.declarations.size == 1 && statement.declarations[0]!.object == proofValueObject &&
    statement.declarations[0]!.projection == .statement &&
    proof.declarations.size == 1 && proof.declarations[0]!.object == proofValueObject &&
    proof.declarations[0]!.projection == .implementation && checks.size == 1 &&
    checks.all (fun checked => checked.roles.contains `statement && checked.roles.contains `proof) &&
    (registry.resultForRequirement proofValueStatementCheck).complete &&
    (registry.resultForRequirement proofValueProofCheck).complete

private def hasCustomNativeBase (snapshot : Realizations.Capture.Snapshot) : Bool := Id.run do
  let registry := snapshot.registry
  let defaultLean : RealizationKey := ⟨customNativeLabel, `lean⟩
  let some customStatement := registry.realization? customBaseStatement | return false
  let some customProof := registry.realization? customBaseProof | return false
  let some customProofRequirement := registry.requirement? customWitnessProofCheck | return false
  let some dependentProofRequirement := registry.requirement? customDependentProofCheck | return false
  let witnessChecks := snapshot.nativeChecks.filter (·.declaration == customWitnessObject)
  let selectedUses := snapshot.uses.filter fun use =>
    use.source == customDependentLabel && use.reference.label == customNativeLabel
  let selectedExactly := match selectedUses[0]? with
    | some use => match use.selected with
      | .ok keys => keys == #[customWitnessProofCheck]
      | .error _ => false
    | none => false
  return (registry.realization? defaultLean).isNone &&
    customStatement.role == `statement && customProof.role == `proof &&
    customStatement.declarations.size == 1 &&
    customStatement.declarations[0]!.object == customWitnessObject &&
    customStatement.declarations[0]!.projection == .statement &&
    customProof.declarations.size == 1 && customProof.declarations[0]!.object == customWitnessObject &&
    customProof.declarations[0]!.projection == .implementation &&
    witnessChecks.size == 1 && witnessChecks.all (fun checked =>
      checked.roles.contains `statement && checked.roles.contains `proof && checked.body.outcome == .passed) &&
    customProofRequirement.prerequisites == #[customWitnessStatementCheck] &&
    dependentProofRequirement.prerequisites.contains customWitnessProofCheck &&
    selectedUses.size == 1 && selectedExactly &&
    (registry.resultForRequirement customWitnessStatementCheck).complete &&
    (registry.resultForRequirement customWitnessProofCheck).complete &&
    (registry.resultForRequirement customDependentStatementCheck).complete &&
    (registry.resultForRequirement customDependentProofCheck).complete

private def hasDefaultUseSelection (snapshot : Realizations.Capture.Snapshot) : Bool := Id.run do
  let registry := snapshot.registry
  let selectedUses := snapshot.uses.filter fun use =>
    use.source == mainDependentLabel && use.reference.label == label
  let selectedDefault := match selectedUses[0]? with
    | some use => match use.selected with
      | .ok keys => keys.contains proofCheck && !keys.contains unfinishedAlternativeCheck
      | .error _ => false
    | none => false
  let some alternative := registry.realization? unfinishedAlternativeProof | return false
  let some alternativeRequirement := registry.requirement? unfinishedAlternativeCheck | return false
  let some alternativeDocument := registry.documents.find? (·.key == unfinishedAlternativeDocument) | return false
  let alternativeResult := registry.localResult unfinishedAlternativeCheck
  let some dependentStatementRequirement := registry.requirement? mainDependentStatementCheck | return false
  let some dependentProofRequirement := registry.requirement? mainDependentProofCheck | return false
  let defaultComplete := (registry.resultForRequirement proofCheck).complete
  let downstreamComplete := (registry.resultForRequirement mainDependentProofCheck).complete
  return selectedUses.size == 1 && selectedDefault && alternative.role == `proof &&
    alternative.required.contains unfinishedAlternativeCheck &&
    alternativeRequirement.expected == .check `blueprint.unfinishedAlternative &&
    !alternativeDocument.text.isEmpty && !alternativeResult.localComplete &&
    alternativeResult.status == .pending &&
    (registry.resultFor (.realization unfinishedAlternativeProof)).status == .pending &&
    !dependentStatementRequirement.prerequisites.contains unfinishedAlternativeCheck &&
    dependentProofRequirement.prerequisites.contains proofCheck &&
    dependentProofRequirement.prerequisites.contains mainDependentStatementCheck &&
    !dependentProofRequirement.prerequisites.contains unfinishedAlternativeCheck &&
    downstreamComplete == defaultComplete

private def defaultUseSelectionDetails (snapshot : Realizations.Capture.Snapshot) : String := Id.run do
  let registry := snapshot.registry
  let selectedUses := snapshot.uses.filter fun use =>
    use.source == mainDependentLabel && use.reference.label == label
  let selectedSummary := selectedUses.map fun use => (use.context, use.realization, use.role, use.selected)
  let alternativeSummary := match registry.realization? unfinishedAlternativeProof with
    | some alternative => s!"role={alternative.role}, required={reprStr alternative.required}, documents={reprStr alternative.documents}"
    | none => "missing"
  let alternativeRequirementSummary := match registry.requirement? unfinishedAlternativeCheck with
    | some requirement => reprStr requirement.expected
    | none => "missing"
  let alternativeDocumentSummary := match registry.documents.find? (·.key == unfinishedAlternativeDocument) with
    | some document => s!"present, bytes={document.text.utf8ByteSize}"
    | none => "missing"
  let dependentStatementPrerequisites := match registry.requirement? mainDependentStatementCheck with
    | some requirement => reprStr requirement.prerequisites
    | none => "missing"
  let dependentProofPrerequisites := match registry.requirement? mainDependentProofCheck with
    | some requirement => reprStr requirement.prerequisites
    | none => "missing"
  return s!"uses={reprStr selectedSummary}; alternative={alternativeSummary}; alternativeRequirement={alternativeRequirementSummary}; alternativeDocument={alternativeDocumentSummary}; alternativeLocal={reprStr (registry.localResult unfinishedAlternativeCheck)}; alternativeFinal={reprStr (registry.resultFor (.realization unfinishedAlternativeProof))}; defaultProof={reprStr (registry.resultForRequirement proofCheck)}; dependentStatementPrerequisites={dependentStatementPrerequisites}; dependentProofPrerequisites={dependentProofPrerequisites}; dependentFinal={reprStr (registry.resultForRequirement mainDependentProofCheck)}"

private def originalDocstring := " The attribute statement is true. Ω 🧭 "
private def editedDocstring := " The attribute statement is true. Ω 🧭  "

private def checkOwnDocstring (snapshot : Realizations.Capture.Snapshot) (swapped : Bool)
    (expectedText : String) : TermElabM Unit := do
  let registry := snapshot.registry
  let some statement := registry.realization? docstringStatement
    | throwError "Missing attribute docstring statement"
  let #[document] := statement.documents
    | throwError "Expected a single attribute docstring document"
  ensure ((registry.document? document).any (·.text == expectedText))
    "The statement must retain the exact raw own docstring bytes"
  let target := if swapped then `docDependencyB else `docDependencyA
  let other := if swapped then `docDependencyA else `docDependencyB
  let uses := snapshot.uses.filter (·.source == docstringLabel `documented)
  let #[use] := uses
    | throwError "Expected one selected use on the documented declaration, got {uses.size}"
  let selection ← obtain use.selected
  let proof := docstringProofCheck `documented
  let some contract := registry.requirement? proof
    | throwError "Missing documented declaration proof contract"
  ensure (use.role == `proof && use.reference.label == docstringLabel target &&
    selection == #[docstringProofCheck target] &&
    contract.prerequisites.contains (docstringProofCheck target) &&
    !contract.prerequisites.contains (docstringProofCheck other) &&
    (registry.resultForRequirement (docstringProofCheck target)).complete &&
    (registry.resultForRequirement (docstringProofCheck other)).complete &&
    (registry.resultForRequirement proof).complete)
    s!"Expected proof dependency on {target}, with both targets and the dependent proof complete"

private def mockJudgment (id reviewer : Name) (outcome : Outcome) (binding : ContentBinding)
    (requirement : RequirementKey := aliceReview) : ReviewJudgment := {
  id, requirement, binding
  observation := {
    criterion := `mathematicalCorrespondence, reviewer, outcome,
    explanation := "MOCK test judgment; not a human review" } }

private def captureWithAuthored (base : Lean.Environment) (id : Name)
    (batch : Environment.AuthoredBatch) : TermElabM Registry := do
  let previous ← getEnv
  try
    setEnv base
    let staged ← liftM (m := TermElabM) (α := Except (Array Diagnostic) Unit)
      (Environment.stageAuthored id batch)
    match staged with
    | .error issues => throwError "Cannot stage isolated authored review case: {repr issues}"
    | .ok _ => pure ()
    obtain ((← Realizations.Capture.capture).map (·.registry))
  finally
    setEnv previous

run_cmd liftCoreM <| Realizations.Authoring.configureProject project

run_cmd liftCoreM do
  let reference ← externalRefSnapshotAtCurrentDir (← getOptions)
    (Data.ExternalRef.ofName ``BlueprintAssessmentSnapshot.customWitness .blueprintAttr)
  unless reference.present do throwError "Custom-base control needs a real checked native declaration"
  let moduleName ← getMainModule
  let association : SourceData.NativeAssociation := {
    realization := customBase
    context := ⟨`lean, project⟩
    placement := `statement
    reference }
  let fact : Contributions.Record := {
    id := {
      moduleName
      producer := `assessment.customNativeBase
      subject := customNativeLabel
      site := 1
      slot := 0 }
    label := customNativeLabel
    nativeAssociations := #[association]
    priority := none
    source := none }
  let some _ ← Environment.contributeRecord fact {}
    | throwError "Actual custom-base native association was rejected"

run_cmd liftTermElabM do
  liftM (m := TermElabM) (α := Unit) <| Realizations.Authoring.stage `authoredAlternative {
    sources := #[unfinishedAlternativeDocument]
    realizations := #[unfinishedAlternative]
    requirements := #[unfinishedAlternativeRequirement] }
  let mode := (← IO.getEnv "VBP_SNAPSHOT_MODE").getD "smoke"
  if mode == "baseline" || mode == "capture" then
    let started ← IO.monoMsNow
    let initialSnapshot ← obtain (← Realizations.Capture.capture)
    let initial := initialSnapshot.registry
    logInfo m!"AssessmentSnapshot actual initial capture elapsedMs={(← IO.monoMsNow) - started}"
    ensure ((initial.resultForRequirement proofCheck).complete &&
      (initial.resultForRequirement nativeSupport).complete &&
      (initial.resultForRequirement sameFactSupport).complete)
      "Baseline must capture the real native proof and exact proves relation"
    ensure (hasExactProseSelection initial originalProseSentence)
      "The statement realization must own the complete Unicode prose body, not the Lean theorem"
    ensure (hasExactMutualAssociations initialSnapshot)
      "Mutual-block declarations must retain their distinct canonical owners, resolved without a source document"
    ensure (hasProofValuedDefinitionRoles initialSnapshot)
      "A proof-valued def must retain statement and proof roles from one real native check"
    ensure (hasCustomNativeBase initialSnapshot)
      "A selected non-default native base must resolve its own proof and statement prerequisites"
    ensure (hasDefaultUseSelection initialSnapshot)
      ("The native use must select its ordinary default proof while preserving the pending authored alternative: " ++
        defaultUseSelectionDetails initialSnapshot)
    checkOwnDocstring initialSnapshot false originalDocstring
    let some binding := initial.bindingFor aliceReview
      | throwError "Missing baseline correspondence binding"
    let some docstringBinding := initial.bindingFor docstringReview
      | throwError "Missing baseline attribute docstring review binding"
    let some path := (← IO.getEnv "VBP_SNAPSHOT_REVIEW_CONTROL")
      | throwError "VBP_SNAPSHOT_REVIEW_CONTROL is required in baseline mode"
    IO.FS.writeFile path binding
    IO.FS.writeFile (path ++ ".docstring") docstringBinding
    return
  if mode == "docstring-proof-use" || mode == "docstring-text" then
    let some path := (← IO.getEnv "VBP_SNAPSHOT_REVIEW_CONTROL")
      | throwError "VBP_SNAPSHOT_REVIEW_CONTROL is required in docstring source-edit modes"
    let savedBinding := (← IO.FS.readFile (path ++ ".docstring")).trimAscii.toString
    let judgmentId := `mockDocstringReview
    liftM (m := TermElabM) (α := Unit)
      (Realizations.Authoring.stage `mockDocstring {
        reviews := #[mockJudgment judgmentId `AliceMock .passed savedBinding docstringReview]
        reviewSelections := #[{ requirement := docstringReview, judgment := some judgmentId }] })
    let snapshot ← obtain (← Realizations.Capture.capture)
    let edited := mode == "docstring-text"
    checkOwnDocstring snapshot true (if edited then editedDocstring else originalDocstring)
    let registry := snapshot.registry
    let some currentBinding := registry.bindingFor docstringReview
      | throwError "Missing current attribute docstring review binding"
    let review := registry.localResult docstringReview
    if edited then
      ensure (currentBinding != savedBinding && !review.complete &&
        review.diagnostics.any (·.code == "stale-content"))
        "Editing raw docstring whitespace must stale the saved statement review"
    else
      ensure (currentBinding == savedBinding && review.complete)
        "Switching between complete proof dependencies must preserve the saved statement review"
    return
  if mode != "smoke" then
    unless ["rewrite", "hole", "statement", "mapping", "prose"].contains mode do
      throwError "Unsupported VBP_SNAPSHOT_MODE: {mode}"
    let some path := (← IO.getEnv "VBP_SNAPSHOT_REVIEW_CONTROL")
      | throwError "VBP_SNAPSHOT_REVIEW_CONTROL is required in source-edit modes"
    let savedBinding := (← IO.FS.readFile path).trimAscii.toString
    let judgmentId := `mockAliceCurrent
    let judgment := mockJudgment judgmentId `AliceMock .passed savedBinding
    liftM (m := TermElabM) (α := Unit)
      (Realizations.Authoring.stage `mockAlice {
        reviews := #[judgment]
        reviewSelections := #[{ requirement := aliceReview, judgment := some judgmentId }] })
    let started ← IO.monoMsNow
    let reviewedSnapshot ← obtain (← Realizations.Capture.capture)
    let reviewed := reviewedSnapshot.registry
    logInfo m!"AssessmentSnapshot actual reviewed capture elapsedMs={(← IO.monoMsNow) - started}"
    let expectedProse := if mode == "prose" then editedProseSentence else originalProseSentence
    ensure (hasExactProseSelection reviewed expectedProse)
      "The selected Verso source must contain the full current prose body, without native source"
    ensure (hasExactMutualAssociations reviewedSnapshot)
      "Mutual-block declarations must retain their distinct canonical owners, resolved without a source document"
    ensure (hasProofValuedDefinitionRoles reviewedSnapshot)
      "A proof-valued def must retain statement and proof roles from one real native check"
    ensure (hasCustomNativeBase reviewedSnapshot)
      "A selected non-default native base must resolve its own proof and statement prerequisites"
    ensure (hasDefaultUseSelection reviewedSnapshot)
      ("The native use must select its ordinary default proof while preserving the pending authored alternative: " ++
        defaultUseSelectionDetails reviewedSnapshot)
    let some currentBinding := reviewed.bindingFor aliceReview
      | throwError "Missing current correspondence binding"
    let proofComplete := (reviewed.resultForRequirement proofCheck).complete
    let provesComplete := (reviewed.resultForRequirement nativeSupport).complete &&
      (reviewed.resultFor (.translation proofRelation)).complete &&
      (reviewed.resultForRequirement sameFactSupport).complete &&
      (reviewed.resultFor (.translation sameFactRelation)).complete
    let alternativeIncomplete := !(reviewed.resultFor (.translation alternativeRelation)).complete
    let alice := reviewed.localResult aliceReview
    let correspondenceComplete := (reviewed.resultFor (.translation correspondence)).complete
    match mode with
    | "rewrite" =>
      ensure (currentBinding == savedBinding && alice.complete && proofComplete &&
        provesComplete && correspondenceComplete && alternativeIncomplete)
        "A proof-only rewrite must preserve the statement review and all current proof checks"
    | "hole" =>
      let correspondenceResult := reviewed.resultFor (.translation correspondence)
      ensure (currentBinding == savedBinding && alice.localComplete && !proofComplete &&
        !provesComplete && !correspondenceComplete && alternativeIncomplete &&
        correspondenceResult.diagnostics.any (·.code == "unfinished-prerequisite"))
        "A proof admission must preserve Alice's local review but leave the dependent result unfinished"
    | "statement" | "mapping" | "prose" =>
      ensure (currentBinding != savedBinding && !alice.complete &&
        alice.diagnostics.any (·.code == "stale-content") && proofComplete && provesComplete &&
        alternativeIncomplete)
        "Changing assessed statement or mapping content must stale Alice while native proof checks remain complete"
    | _ => throwError "Unsupported VBP_SNAPSHOT_MODE: {mode}"
    return

  -- First capture establishes the real current binding. This test review is
  -- explicitly mock Alice input; no human reviewed this fixture.
  let initialStarted ← IO.monoMsNow
  let unreviewedSnapshot ← obtain (← Realizations.Capture.capture)
  let unreviewed := unreviewedSnapshot.registry
  logInfo m!"AssessmentSnapshot actual initial capture elapsedMs={(← IO.monoMsNow) - initialStarted}"
  ensure ((unreviewed.resultForRequirement statementCheck).complete &&
    (unreviewed.resultForRequirement proofCheck).complete &&
    (unreviewed.resultForRequirement nativeSupport).complete &&
    (unreviewed.resultForRequirement sameFactSupport).complete)
    "Actual native capture must check the statement, proof, and exact own-type relation"
  ensure ((unreviewed.resultFor (.realization prose)).status == .unassessed &&
    (unreviewed.resultFor (.realization versoProof)).status == .unassessed &&
    !(unreviewed.resultFor (.translation alternativeRelation)).complete &&
    (unreviewed.resultFor (.translation correspondence)).status == .pending)
    "Prose statement and alternative proof stay unassessed until their explicit reviews"
  ensure (hasExactProseSelection unreviewed originalProseSentence)
    "The statement realization must own the complete Unicode prose body, not the Lean theorem"
  ensure (hasExactMutualAssociations unreviewedSnapshot)
    "Mutual-block declarations must retain their distinct canonical owners, resolved without a source document"
  ensure (hasProofValuedDefinitionRoles unreviewedSnapshot)
    "A proof-valued def must retain statement and proof roles from one real native check"
  ensure (hasCustomNativeBase unreviewedSnapshot)
    "A selected non-default native base must resolve its own proof and statement prerequisites"
  ensure (hasDefaultUseSelection unreviewedSnapshot)
    ("The native use must select its ordinary default proof while preserving the pending authored alternative: " ++
      defaultUseSelectionDetails unreviewedSnapshot)
  checkOwnDocstring unreviewedSnapshot false originalDocstring
  let some binding := unreviewed.bindingFor aliceReview
    | throwError "Missing current Alice-review binding"
  let unreviewedEnvironment ← getEnv
  -- Real native support cannot discharge an additional, unassessed claim.
  -- This isolated capture uses no mock proof or review success.
  ensure ((unreviewed.resultFor (.translation proofRelation)).complete)
    "An exact native proves relation needs no extra claim record"
  let extraClaim : ClaimKey := ⟨proofRelation, `unassessedAdditionalClaim⟩
  let withExtraClaim ← captureWithAuthored unreviewedEnvironment `extraProofClaim {
    claims := #[{
      key := extraClaim
      interpretation := "The proof's mathematical explanation has been independently reviewed." }] }
  ensure ((withExtraClaim.resultForRequirement nativeSupport).complete &&
    (withExtraClaim.resultFor (.claim extraClaim)).status == .unassessed &&
    (withExtraClaim.resultFor (.translation proofRelation)).status == .unassessed)
    "An unassessed additional claim must prevent relation completion while native support stays complete"
  let judgmentId := `mockAliceCurrent
  let judgment := mockJudgment judgmentId `AliceMock .passed binding
  liftM (m := TermElabM) (α := Unit)
    (Realizations.Authoring.stage `mockAlice {
      reviews := #[judgment]
      reviewSelections := #[{ requirement := aliceReview, judgment := some judgmentId }] })
  let reviewedStarted ← IO.monoMsNow
  let reviewedSnapshot ← obtain (← Realizations.Capture.capture)
  let reviewed := reviewedSnapshot.registry
  logInfo m!"AssessmentSnapshot actual reviewed capture elapsedMs={(← IO.monoMsNow) - reviewedStarted}"
  ensure ((reviewed.localResult aliceReview).complete &&
    (reviewed.resultForRequirement nativeSupport).complete &&
    (reviewed.resultForRequirement sameFactSupport).complete &&
    (reviewed.resultFor (.translation proofRelation)).complete &&
    (reviewed.resultFor (.translation sameFactRelation)).complete &&
    !(reviewed.resultFor (.translation alternativeRelation)).complete &&
    (reviewed.resultFor (.translation correspondence)).complete)
    "Native proofs and correspondence complete while the unreviewed informal alternative stays unfinished"
  ensure ((reviewed.realization? statement).any (fun value =>
      value.role == `statement && value.declarations.any (fun declaration =>
        declaration.object == nativeObject && declaration.projection == .statement)) &&
    (reviewed.realization? nativeProof).any (fun value =>
      value.role == `proof && value.declarations.any (fun declaration =>
        declaration.object == nativeObject && declaration.projection == .implementation)))
    "The shared declaration must have separately owned statement and proof selections"
  ensure ((reviewed.realization? prose).any (fun value =>
      value.context.language == `verso && value.role == `statement && !value.documents.isEmpty))
    "The Verso statement source must remain a separate byte-bound realization"
  ensure (hasExactProseSelection reviewed originalProseSentence)
    "The statement realization must own the complete Unicode prose body, not the Lean theorem"
  ensure (hasExactMutualAssociations reviewedSnapshot)
    "Mutual-block declarations must retain their distinct canonical owners, resolved without a source document"
  ensure (hasProofValuedDefinitionRoles reviewedSnapshot)
    "A proof-valued def must retain statement and proof roles from one real native check"
  ensure (hasCustomNativeBase reviewedSnapshot)
    "A selected non-default native base must resolve its own proof and statement prerequisites"
  ensure (hasDefaultUseSelection reviewedSnapshot)
    ("The native use must select its ordinary default proof while preserving the pending authored alternative: " ++
      defaultUseSelectionDetails reviewedSnapshot)
  ensure ((reviewed.realization? versoProof).any (fun value =>
      value.context.language == `verso && value.role == `proof && !value.documents.isEmpty))
    "The informal alternative proof must remain a separately owned source selection"
  ensure (reviewed.evidence.any fun item => item.requirement == proofCheck &&
      match item.observation with
      | .check observation => observation.validator == NativeLean.bodyValidator &&
          observation.outcome == .passed && observation.coverage == .dependencyClosure
      | _ => false)
    "The proof result must come from the real native completeness observation"
  let hasNativeSupport (requirement : RequirementKey) := reviewed.evidence.any fun item =>
    item.requirement == requirement && match item.observation with
    | .check observation => observation.validator == NativeLean.ownTypeValidator &&
        observation.declaration == some nativeObject && observation.proposition &&
        observation.outcome == .passed
    | _ => false
  ensure (hasNativeSupport nativeSupport && hasNativeSupport sameFactSupport &&
      reviewed.bindingFor nativeSupport != reviewed.bindingFor sameFactSupport)
    "One real native fact may support two edges, each with its own binding and evidence"
  let alternativeReviewUnselected := match reviewed.selectedReview alternativeProofReview with
    | .ok none => true
    | _ => false
  ensure alternativeReviewUnselected
    "No review is implicitly selected for the informal alternative proof"
  ensure (reviewed.evidence.any fun item => item.requirement == aliceReview &&
      item.id == judgmentId && item.binding == binding)
    "Source-authoring must preserve the explicit mock review binding"
  let report := Realizations.Report.ofNode reviewed label
  ensure (report.compress.contains "AliceMock" && report.compress.contains "nativeSupport" &&
      report.compress.contains "\"selectedCurrentReview\":true" &&
      !report.compress.contains binding && !report.compress.contains "The proposition is true")
    "The report should expose review/prerequisite outcomes without exporting bindings or source text"

  -- Selection is resolved before evidence freshness. An older matching approval
  -- remains stored but cannot replace a stale explicitly selected successor.
  let oldId := `mockAliceOld
  let successorId := `mockAliceSuccessor
  let staleSuccessor := mockJudgment successorId `AliceMock .passed (binding ++ ":stale")
  let staleSuccessorResult ← captureWithAuthored unreviewedEnvironment `staleSuccessor {
    reviews := #[mockJudgment oldId `AliceMock .passed binding, staleSuccessor]
    reviewSelections := #[{ requirement := aliceReview, judgment := some successorId }] }
  let staleAlice := staleSuccessorResult.localResult aliceReview
  ensure (!staleAlice.localComplete && staleAlice.diagnostics.any (·.code == "stale-content"))
    "A stale selected successor cannot fall back to an older matching approval"

  -- A withdrawal is an explicit current selection of none, even while a matching
  -- positive judgment remains in the source evidence inventory.
  let withdrawalId := `mockAliceWithdrawn
  let withdrawal := mockJudgment withdrawalId `AliceMock .passed binding
  let withdrawalResult ← captureWithAuthored unreviewedEnvironment `withdrawal {
    reviews := #[withdrawal]
    reviewSelections := #[{ requirement := aliceReview, judgment := none }] }
  let withdrawalSelectedNone := match withdrawalResult.selectedReview aliceReview with
    | .ok none => true
    | _ => false
  ensure (withdrawalSelectedNone &&
      !(withdrawalResult.localResult aliceReview).localComplete &&
      (withdrawalResult.evidence.any (·.id == withdrawalId)))
    "Withdrawal keeps the old judgment inspectable but supplies no current approval"

  -- Two current authored selections are unresolved, independent of source order.
  let firstId := `mockAliceFirst
  let secondId := `mockAliceSecond
  let conflictingEvidence := #[mockJudgment firstId `AliceMock .passed binding,
    mockJudgment secondId `AliceMock .passed binding]
  let selections := #[
    { requirement := aliceReview, judgment := some firstId },
    { requirement := aliceReview, judgment := some secondId }]
  let conflictForward ← captureWithAuthored unreviewedEnvironment `conflictingReviewsForward {
    reviews := conflictingEvidence, reviewSelections := selections }
  let conflictReverse ← captureWithAuthored unreviewedEnvironment `conflictingReviewsReverse {
    reviews := conflictingEvidence.reverse, reviewSelections := selections.reverse }
  let conflictForwardUnresolved := match conflictForward.selectedReview aliceReview with
    | .error _ => true
    | .ok _ => false
  let conflictReverseUnresolved := match conflictReverse.selectedReview aliceReview with
    | .error _ => true
    | .ok _ => false
  ensure (conflictForwardUnresolved && conflictReverseUnresolved &&
      !(conflictForward.localResult aliceReview).localComplete &&
      !(conflictReverse.localResult aliceReview).localComplete)
    "Competing current judgments remain unresolved in either input order"

  -- A positive approval by another person cannot satisfy Alice's named slot.
  let bobId := `mockBobApproval
  let bobResult ← captureWithAuthored unreviewedEnvironment `bobApproval {
    reviews := #[mockJudgment bobId `BobMock .passed binding]
    reviewSelections := #[{ requirement := aliceReview, judgment := some bobId }] }
  ensure (!(bobResult.localResult aliceReview).localComplete &&
      (bobResult.localResult aliceReview).diagnostics.any (·.code == "wrong-review"))
    "A matching Bob approval cannot discharge Alice's named obligation"

  -- A required rejection stays local assessment data and blocks the relation.
  let rejectedId := `mockAliceRejection
  let rejectionResult ← captureWithAuthored unreviewedEnvironment `requiredRejection {
    reviews := #[mockJudgment rejectedId `AliceMock .failed binding]
    reviewSelections := #[{ requirement := aliceReview, judgment := some rejectedId }] }
  ensure (!(rejectionResult.localResult aliceReview).localComplete &&
      (rejectionResult.localResult aliceReview).diagnostics.any (·.code == "review-not-accepted") &&
      !(rejectionResult.resultFor (.translation correspondence)).complete)
    "A required negative review must remain visible and prevent correspondence completion"

  -- Changing an unrelated sibling review obligation does not enter Alice's
  -- assessed binding. These captures start from the same saved authored state.
  let siblingClaim : ClaimKey := ⟨correspondence, `siblingExposition⟩
  let bobRequirement : RequirementKey := ⟨.claim siblingClaim, `expositionReview⟩
  let carolRequirement : RequirementKey := ⟨.claim siblingClaim, `expositionReview⟩
  let bobClaim : Claim := {
    key := siblingClaim
    interpretation := "Review the optional exposition"
    required := #[bobRequirement] }
  let carolClaim : Claim := {
    key := siblingClaim
    interpretation := "Review the optional exposition"
    required := #[carolRequirement] }
  let bobReviewRequirement : Requirement := {
    key := bobRequirement
    expected := .review `proseClarity `BobMock }
  let carolReviewRequirement : Requirement := {
    key := carolRequirement
    expected := .review `proseClarity `CarolMock }
  let bobBatch : Environment.AuthoredBatch := {
    reviews := #[judgment]
    reviewSelections := #[{ requirement := aliceReview, judgment := some judgmentId }]
    claims := #[bobClaim]
    requirements := #[bobReviewRequirement] }
  let carolBatch : Environment.AuthoredBatch := {
    reviews := #[judgment]
    reviewSelections := #[{ requirement := aliceReview, judgment := some judgmentId }]
    claims := #[carolClaim]
    requirements := #[carolReviewRequirement] }
  let bobSibling ← captureWithAuthored unreviewedEnvironment `siblingReviewBob bobBatch
  let carolSibling ← captureWithAuthored unreviewedEnvironment `siblingReviewCarol carolBatch
  ensure (bobSibling.bindingFor aliceReview == some binding &&
      carolSibling.bindingFor aliceReview == some binding &&
      (bobSibling.localResult aliceReview).complete && (carolSibling.localResult aliceReview).complete &&
      bobSibling.bindingFor bobRequirement != carolSibling.bindingFor carolRequirement)
    "Changing a sibling review's named reviewer preserves Alice's unchanged binding"

end BlueprintAssessmentSnapshot
