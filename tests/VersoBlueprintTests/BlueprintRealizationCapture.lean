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

set_option trace.blueprint.capture true

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
  ensure (paths.size == (paths.foldl (fun seen path => if seen.contains path then seen else seen.push path) #[]).size)
    "One successful physical source read must serve every provider family"
  ensure (paths.size < plan.documents.size + plan.native.size + plan.inline.size + plan.documented.size)
    "Shared-reader control did not actually exercise repeated physical requests"
  ensure (!observations.native.isEmpty && !observations.inline.isEmpty && !observations.documented.isEmpty)
    "Native, inline and documented results must retain their separate families"
  let reversed : Capture.Observations plan := {
    documents := observations.documents.reverse, native := observations.native.reverse
    inline := observations.inline.reverse, documented := observations.documented.reverse
    checks := observations.checks.reverse, specifications := observations.specifications.reverse
    expected := observations.expected.reverse }
  let replay ← obtain (Capture.evaluate plan reversed)
  ensure (snapshot.registry.contributions == replay.registry.contributions &&
    snapshot.sourceDiagnostics == replay.sourceDiagnostics && reprStr snapshot.uses == reprStr replay.uses)
    "Observation insertion order changed exact contributions, bindings, diagnostics or selected-use metadata"
  let nativeInventory (s : Capture.Snapshot) := s.nativeChecks.map fun c =>
    (c.declaration, c.kind, c.statement, c.body, c.status)
  ensure (nativeInventory snapshot == nativeInventory replay) "Observation order changed native inventory"
  -- Fault injection only at the pure boundary; successful facts come from real
  -- providers, never mocked proof success.
  let rejects (code : String) (batch : Capture.Observations plan) : TermElabM Unit := do
    match Capture.evaluate plan batch with
    | .ok _ => throwError "Malformed observation batch was admitted: {code}"
    | .error issues => ensure (issues.any (·.code == code)) s!"Wrong batch rejection: {repr issues}"
  let some document := observations.documents[0]? | throwError "Missing actual document control"
  rejects "missing-observation" { observations with documents := observations.documents.extract 1 observations.documents.size }
  rejects "duplicate-observation" { observations with documents := observations.documents.push document }
  rejects "extraneous-observation" { observations with documents := observations.documents.push { document with handle := plan.documents.size } }
  rejects "mismatched-observation" { observations with documents := observations.documents.modify 0 fun entry =>
    { entry with result := ({ entry.result.1 with key := { entry.result.1.key with path := "wrong-document" } }, entry.result.2) } }
  for batch in #[
      { observations with native := observations.native.extract 1 observations.native.size },
      { observations with inline := observations.inline.extract 1 observations.inline.size },
      { observations with documented := observations.documented.extract 1 observations.documented.size },
      { observations with checks := observations.checks.extract 1 observations.checks.size }] do
    rejects "missing-observation" batch
  let some check := observations.checks[0]? | throwError "Missing actual check control"
  let .ok checked := check.result | throwError "Expected a real checked declaration"
  rejects "mismatched-observation" { observations with checks := observations.checks.modify 0 fun entry =>
    { entry with result := .ok { checked with declaration := { checked.declaration with native := "wrong.witness" } } } }
  logInfo m!"ordinary capture: {snapshot.registry.nodes.size} nodes in {elapsed} ms"
  let registry := snapshot.registry
  -- Public consumer projections retain native validity separately from Blueprint
  -- prerequisites, and do not borrow validity from a complete sibling.
  let completeView := snapshot.assessmentFor (Name.mkSimple "capture.complete")
  ensure (completeView.hasNativeDeclarations && completeView.nativeStatementComplete &&
    completeView.nativeProofComplete && completeView.requiredComplete &&
    completeView.proofDependenciesComplete) "Complete public assessment lost its native checks"
  let admittedView := snapshot.assessmentFor (Name.mkSimple "capture.admitted")
  ensure (admittedView.nativeStatementComplete && !admittedView.nativeProofComplete &&
    !admittedView.requiredComplete) "Public assessment hid an admitted native body"
  for label in #["capture.dependent", "capture.missing", "capture.cycleA", "capture.groupedDependent"] do
    let view := snapshot.assessmentFor (Name.mkSimple label)
    ensure (view.nativeProofComplete && !view.requiredComplete && !view.proofDependenciesComplete)
      s!"Public assessment conflated local proof and prerequisites for {label}"
  let groupedView := snapshot.assessmentFor (Name.mkSimple "capture.grouped")
  ensure (groupedView.nativeStatementComplete && !groupedView.nativeProofComplete &&
    !groupedView.requiredComplete) "Public assessment borrowed the complete sibling's proof"
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
  let foreignKey : RealizationKey := ⟨Name.mkSimple "storage.source", `rocqTranslation⟩
  let some foreign := registry.realization? foreignKey | throwError "Imported named realization disappeared"
  ensure (foreign.context.language == `rocq && foreign.facets.any (·.name == `implementation) &&
      foreign.declarations.isEmpty && (registry.resultFor (.realization foreignKey)).status == .unassessed)
    "Foreign source borrowed a native declaration or validation"
  ensure (before.data.get? (Name.mkSimple "storage.source") |>.any fun node =>
      node.sources.any fun source => source.destination == ⟨foreignKey, `implementation⟩)
    "Accepted source inventory flattened the imported named destination"
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
  let displayLeft := Name.mkSimple "foo.bar»"
  let displayRight := Name.str (Name.mkSimple "foo") "bar»"
  ensure (displayLeft != displayRight && reprStr displayLeft == reprStr displayRight)
    "Producer-identity collision fixture no longer has equal display spellings"
  let some (_, baseNode) := before.data.toArray[0]? | throwError "Missing node metadata fixture"
  let accepted : Environment.RegisteredNode := { baseNode with toNode := {
    baseNode.toNode with sources := #[], uses := #[], nativeAssociations := #[] } }
  let pending : NameSet := (({} : NameSet).insert displayLeft).insert displayRight
  let collisionRaw : Capture.Raw := {
    nodes := #[(displayLeft, accepted), (displayRight, accepted)]
    pending, facts := [], authored := #[], initialIssues := #[] }
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
    pending := (({} : NameSet).insert flat).insert hierarchical }
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
  let withUse : Environment.RegisteredNode := { accepted with toNode := {
    accepted.toNode with uses := #[{
      node := flat, facet := `statement, reference := { label := hierarchical } }] } }
  let targetPlan := Capture.plan { publicRaw with nodes := #[(flat, withUse)] }
  match Capture.evaluate targetPlan {} with
  | .ok _ => throwError "Unresolved dependency target aliased a public node label"
  | .error issues => ensure (issues.any (·.code == "ambiguous-public-label")) "Missing target alias diagnostic"
  let withGroup (parent : Name) : Environment.RegisteredNode := { accepted with toNode := {
    accepted.toNode with parent := some parent } }
  let groupRaw : Capture.Raw := { publicRaw with
    nodes := #[(`firstGroupNode, withGroup flat), (`secondGroupNode, withGroup hierarchical)]
    pending := (({} : NameSet).insert `firstGroupNode).insert `secondGroupNode }
  match Capture.evaluate (Capture.plan groupRaw) {} with
  | .ok _ => throwError "Capture accepted ambiguous parent group labels"
  | .error issues => ensure (issues.any (·.code == "ambiguous-public-label")) "Missing group alias diagnostic"
  let separateNamespaces ← obtain (Capture.evaluate
    (Capture.plan { publicRaw with nodes := #[(flat, withGroup hierarchical)] }) {})
  ensure (separateNamespaces.registry.nodes.size == 1) "Node and group label namespaces must stay independent"
  ensure (toJson displayLeft == toJson displayRight)
    "Docstring destination collision fixture must retain equal display JSON spellings"
  let some (docLabel, docNode, docSource) := plan.ordinary.findSome? fun node =>
      node.realizations.findSome? fun realization =>
        realization.sources.findSome? fun sourceStep =>
          match sourceStep.source.payload, sourceStep.documented with
          | .prose _, some (.ok _) => some (node.label, node.accepted, sourceStep.source)
          | _, _ => none
    | throwError "Missing actual attribute-owned Verso source for destination identity control"
  let docLeft := { docSource with destination := { docSource.destination with facet := displayLeft } }
  let docRight := { docSource with destination := { docSource.destination with facet := displayRight } }
  let docAccepted := { docNode with toNode := { docNode.toNode with sources := #[docLeft, docRight] } }
  let docRaw : Capture.Raw := {
    nodes := #[(docLabel, docAccepted)]
    pending := ({} : NameSet).insert docLabel
    facts := before.factRecords.filter (·.label == docLabel)
    authored := #[]
    initialIssues := #[] }
  let docPlan := Capture.plan docRaw
  let docObservations ← obtain (← Capture.observe docPlan)
  let docSnapshot ← obtain (Capture.evaluate docPlan docObservations)
  let generatedDocstrings := docSnapshot.registry.documents.filter (·.key.path.contains "#docstring:")
  ensure (generatedDocstrings.size == 2 && !generatedDocstrings[0]!.text.trimAscii.isEmpty && generatedDocstrings[0]!.key != generatedDocstrings[1]!.key &&
    generatedDocstrings[0]!.text == generatedDocstrings[1]!.text)
    "Distinct typed docstring destinations must retain separate document identities with their actual equal text"
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

-- Source-association diagnostics retain typed ownership and readable subjects. They appear
-- on the owning non-Lean node's assessment and do not leak to another node.
run_cmd liftTermElabM do
  let state := Environment.informalExt.getState (← getEnv)
  let label := Name.mkSimple "storage.source"
  let .some registered := state.data.get? label | throwError "Missing foreign-source diagnostic fixture"
  let destination : SourceData.FacetDestination := ⟨⟨label, `rocqTranslation⟩, `implementation⟩
  let .some source := registered.toNode.sources.find? (·.destination == destination)
    | throwError "Missing arbitrary non-Lean source for diagnostic fixture"
  let source := { source with source := Data.SourceLocationResult.unavailable "test source range unavailable" }
  let selected : Environment.RegisteredNode := { registered with toNode := {
    registered.toNode with sources := #[source], uses := #[], nativeAssociations := #[] } }
  let unrelatedLabel := `capture.diagnosticUnrelated
  let unrelated : Environment.RegisteredNode := { registered with toNode := {
    registered.toNode with sources := #[], uses := #[], nativeAssociations := #[] } }
  let pending := ({} : NameSet).insert label |>.insert unrelatedLabel
  let raw : Capture.Raw := {
    nodes := #[(label, selected), (unrelatedLabel, unrelated)]
    pending, facts := [], authored := #[], initialIssues := #[] }
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
  for (document, belongs) in #[(source.document, true),
      ({ source.document with context := { source.document.context with project := `unrelatedProject } }, false)] do
    let scopedSnapshot := { snapshot with sourceDiagnostics := { documents := #[(document, documentIssue)] } }
    let details := (scopedSnapshot.assessmentFor label).details
    let errors := (details.getObjValAs? (Array Json) "sourceDiagnostics").toOption.getD #[]
    ensure (errors.contains (toJson documentIssue) == belongs)
      "Document diagnostics did not use the full language/project/path identity"
    ensure (scopedSnapshot.diagnostics.contains documentIssue)
      "An unattached document error disappeared from the aggregate capture diagnostics"

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
-- capture. Scoped syntax must preserve both original declaration/name ranges.
run_cmd liftTermElabM do
  let originalEnv ← getEnv
  let text := (← getFileMap).source
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
      let commands ← obtain (← NativeSource.parseSource expected (← getFileName) text)
      let declaration ← obtain (NativeSource.declarationAtRanges expected text
        ranges.range ranges.selectionRange commands)
      for (whole, selection) in #[
          ({ ranges.range with charUtf16 := ranges.range.charUtf16 + 1 }, ranges.selectionRange),
          (ranges.range, { ranges.selectionRange with charUtf16 := ranges.selectionRange.charUtf16 + 1 })] do
        match NativeSource.declarationAtRanges expected text whole selection commands with
        | .error issue =>
          ensure (issue.code == "source-association-unavailable")
            "Scoped lookup changed range-mismatch diagnostics"
        | .ok _ => throwError "Scoped declaration bypassed exact original/name ranges"
      match NativeSource.declarationAtRanges expected text ranges.range ranges.selectionRange
          (commands ++ commands) with
      | .error issue =>
        ensure (issue.code == "ambiguous-docstring")
          "Scoped lookup lost ambiguity rejection"
      | .ok _ => throwError "Duplicated scoped declaration was accepted"
      let synthetic := declaration.rewriteBottomUp fun stx =>
        stx.setInfo (.synthetic (stx.getPos?.getD 0) (stx.getTailPos?.getD 0) true)
      ensure (!(NativeSource.declarationAtRanges expected text ranges.range ranges.selectionRange
        #[synthetic]).isOk) "Scoped declaration accepted synthetic source positions"
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
  let rejects (code : String) (batch : Capture.Observations plan) : TermElabM Unit := do
    match Capture.evaluate plan batch with
    | .ok _ => throwError "Malformed authored observation batch was admitted"
    | .error issues => ensure (issues.any (·.code == code)) s!"Wrong authored batch rejection: {repr issues}"
  rejects "missing-observation" { observations with specifications := #[] }
  rejects "missing-observation" { observations with expected := #[] }
  let some expected := observations.expected[0]? | throwError "Missing expected-goal result control"
  let originalChecked ← obtain expected.result.result
  let semanticDiagnostic : Diagnostic := {
    code := "semantic-context-unavailable"
    subject := "Unrelated.TransitiveDependency"
    message := "Injected failure for diagnostic propagation control" }
  let failingSemantics : NativeLean.SemanticContext := fun _ _ _ => pure (.error semanticDiagnostic)
  let expectedName := plan.expected[expected.handle]!.expected
  let checkedWithoutContext ← obtain (← NativeLean.check `blueprintFixtures
    originalChecked.observation.witness (mkCIdent expectedName) expected.result.documents failingSemantics)
  ensure (checkedWithoutContext.semanticContext.isNone &&
    checkedWithoutContext.semanticDiagnostics == #[semanticDiagnostic])
    "Native expected-goal check dropped its semantic-context failure"
  let failedSemantics : Capture.Observations plan := { observations with
    expected := observations.expected.modify 0 fun entry =>
      { entry with result := { entry.result with result := .ok checkedWithoutContext } } }
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
    expected := observations.expected.modify 0 fun entry =>
      { entry with result := { entry.result with result := .ok genericFailure } } })
  assertScoped generic genericDiagnostic
  let nativeFailure := { observations with native := observations.native.map fun entry =>
    if plan.native[entry.handle]!.name != ``complete then entry else
      { entry with result := entry.result.map fun prepared => { prepared with
        semanticContext := none, semanticDiagnostics := #[semanticDiagnostic] } } }
  let native ← obtain (Capture.evaluate plan nativeFailure)
  assertScoped native semanticDiagnostic
  rejects "duplicate-observation" { observations with expected := observations.expected.push expected }
  rejects "extraneous-observation" { observations with expected := observations.expected.push { expected with handle := plan.expected.size } }
  rejects "mismatched-observation" { observations with expected := observations.expected.modify 0 fun entry =>
    { entry with result := { entry.result with documents := #[] } } }
  rejects "mismatched-observation" { observations with specifications := observations.specifications.modify 0 fun entry =>
    { entry with result := { entry.result with document := { entry.result.document with text := "different specification bytes" } } } }
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
    Environment.modify fun state => Id.run do
      let target := Name.mkSimple "capture.complete"
      let some node := state.data.get? target | return state
      let associations := node.nativeAssociations.map fun association => { association with
        reference := { association.reference with provenance := .inWorkspace `VersoBlueprintTests.BlueprintRealizationCapture "/definitely/missing/blueprint-source.lean" } }
      return { state with data := state.data.insert target { node with nativeAssociations := node.nativeAssociations ++ associations } }
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
    Environment.modify fun state => Id.run do
      let target := Name.mkSimple "capture.dependent"
      let some node := state.data.get? target | return state
      let associations := node.nativeAssociations.map fun association => { association with
        reference := { association.reference with canonical := `RealizationCaptureFixture.absentNative } }
      return { state with data := state.data.insert target { node with nativeAssociations := associations } }
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


-- An independently authored false expectation does not erase a valid native
-- proof or become satisfied merely because that proof checks against its own type.
@[blueprint "capture.wrongExpected"]
theorem wrongExpected : True := True.intro
run_cmd liftCoreM <| Authoring.expectNative `wrongExpectedGoal (Name.mkSimple "capture.wrongExpected") `RealizationCaptureFixture.expectedFalse

run_cmd liftTermElabM do
  let snapshot ← obtain (← Capture.capture)
  let assessment := snapshot.assessmentFor (Name.mkSimple "capture.wrongExpected")
  ensure (assessment.nativeStatementComplete && assessment.nativeProofComplete &&
    !assessment.requiredComplete && assessment.proofDependenciesComplete)
    "Native proof success concealed an independently authored wrong proposition"
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

end RealizationCaptureFixture
