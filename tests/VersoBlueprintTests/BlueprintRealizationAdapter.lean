/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Capture
import VersoBlueprintTests.BlueprintRealizationAdapter.ParserSource
import VersoBlueprintTests.BlueprintRealizationAdapter.Provider
import VersoBlueprintTests.SorryImport.Provider

/-! Native provider/consumer controls. Successful proof observations below are
obtained from real current Lean checks, never mocked provider success. -/

open Lean Meta Elab Term Command
open Informal.Realizations Informal.Validation Informal.Translations
open Informal.Realizations.NativeSource

namespace VersoBlueprintTests.BlueprintRealizationAdapter

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error error => throwError "Unexpected rejection: {repr error}"

private def witness (name : Name) : ObjectKey := ⟨⟨`lean, `adapterFixture⟩, name.toString⟩

private def rejected : Except ε α → Bool
  | .error _ => true
  | .ok _ => false

private def proofKey (p : PreparedModel) : RequirementKey :=
  ⟨.declaration (p.leanKey.forRole `proof) p.witness, `expectedProof⟩

private def bodyCheckKey (p : PreparedModel) : RequirementKey :=
  ⟨.declaration (p.leanKey.forRole `proof) p.witness, `proof⟩

-- Direct native preparation does not need a Blueprint node or enrollment.
-- These are actual imported declarations; native checking and model admission
-- remain separate operations, rather than facts invented by lookup. A plain
-- declaration is prepared from the environment; only doc-comment prose reads
-- the owning source bytes.
run_cmd liftTermElabM do
  let before ← Informal.Environment.stagedAuthoring
  let sourcePath := "tests/VersoBlueprintTests/BlueprintRealizationAdapter/Provider.lean"
  let request : NativeSource.Request := {
    project := `adapterFixture
    canonical := `RealizationAdapterFixture.identityInvolutive
    moduleName := `VersoBlueprintTests.BlueprintRealizationAdapter.Provider }
  ensure ((← Informal.Environment.labelsForLeanDecl request.canonical).isEmpty)
    "Direct source control must use an unenrolled declaration"
  let source ← obtain (← NativeSource.prepare request)
  let changedQueryOptions ← withOptions (fun options =>
      (options.set `maxHeartbeats (123456 : Nat)).setBool `pp.universes true) <|
    NativeLean.semanticContext .implementation request.project #[request.canonical]
  let changedQueryOptions ← obtain changedQueryOptions
  ensure (source.semanticContext == some changedQueryOptions)
    "Query-site display/budget options cannot change the meaning of an already checked declaration"
  let some ranges ← findDeclarationRanges? request.canonical | throwError "Missing actual native ranges"
  ensure (source.canonical == request.canonical && source.declaration == witness request.canonical &&
    source.moduleName == request.moduleName && source.ranges.range == ranges.range &&
    source.ranges.selectionRange == ranges.selectionRange && source.semanticContext.isSome)
    "Direct source must preserve typed identity, the environment's native ranges and current semantic inputs"
  -- Parser-boundary injection only, not successful proof/provider evidence:
  -- The later unsupported command prevents ruling out inheritance in this file.
  let text ← IO.FS.readFile sourcePath
  let tailInput := text ++ "\nsyntax \"sourceTailCommand\" : command\nsourceTailCommand\n"
  ensure (!(← NativeSource.parseSource request.canonical sourcePath tailInput).isOk)
    "Control tail must require unsupported parser context"
  let documentedRequest := { request with canonical := `RealizationAdapterFixture.number }
  let documentedTail ← NativeSource.selectDocumented documentedRequest sourcePath (fun _ => pure tailInput)
  match documentedTail with
  | .error diagnostic =>
    ensure (diagnostic.code == "source-parse-failed")
      "Docstring association must still inspect the whole source for later inheritance"
  | .ok _ => throwError "Docstring association skipped part of its owning source"
  for (result, code) in #[
      (← NativeSource.selectDocumented documentedRequest sourcePath (fun _ => pure ("\n" ++ text)),
        "source-association-unavailable"),
      (← NativeSource.selectDocumented documentedRequest sourcePath
        (fun _ => pure "import Lean\n#broken_before_declaration\n"), "source-parse-failed")] do
    match result with
    | .error diagnostic => ensure (diagnostic.code == code) s!"Wrong docstring source rejection: {diagnostic.code}"
    | .ok _ => throwError "Docstring association weakened exact owning declaration/name-range guards"
  let disagreeing ← NativeSource.prepare { request with selectionRange? := some {
    source.ranges.selectionRange with charUtf16 := source.ranges.selectionRange.charUtf16 + 1 } }
  ensure (!disagreeing.isOk) "A recorded snapshot range disagreeing with the environment was accepted"
  let nativeOrigin : Informal.Realizations.Origin := {
    id := `undocumentedSource, moduleName := request.moduleName, source := sourcePath }
  let nativeOnly ← obtain (source.realizeNative nativeOrigin
    { label := `undocumentedNative, title := "Undocumented native source" } `lean)
  let nativeOnly ← obtain (admit nativeOnly)
  ensure (nativeOnly.realizations.size == source.roles.size && nativeOnly.documents.isEmpty &&
    nativeOnly.objects.all (fun object => object.resolution == .resolved && object.document.isNone) &&
    nativeOnly.evidence.isEmpty && nativeOnly.requirements.isEmpty &&
    nativeOnly.realizations.all (fun realization =>
      realization.role != `prose && realization.role != `review &&
      (nativeOnly.resultFor (.realization realization.key)).status == .unassessed))
    "Undocumented native model records source roles only, without a source document, validation contracts or evidence"
  let noDoc ← NativeSource.prepareDocumented request sourcePath
  match noDoc with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-docstring") "Undocumented source is not prose"
  | .ok _ => throwError "Undocumented declaration borrowed a nearby docstring"
  let definition ← obtain (← NativeSource.prepare { request with canonical := `RealizationAdapterFixture.Reflexivity })
  ensure (definition.canonical == `RealizationAdapterFixture.Reflexivity &&
      definition.semanticContext.isSome && definition.roles == #[`statement])
    "A proposition definition supplies statement content without an artificial proof role"
  let documented ← obtain (← NativeSource.prepareDocumented documentedRequest sourcePath)
  ensure (documented.format == `markdown && documented.rawDocstring == " An unsupported definition. " &&
      documented.toPrepared.roles == #[`implementation] && documented.document.text == text &&
      documented.document.key == ⟨⟨`lean, request.project⟩, sourcePath⟩)
    "Direct owning documentation supports definitions without a legacy theorem-only node gate, and keeps its exact owning bytes"
  let directLabel := Name.mkSimple "native.direct.definition"
  ensure ((← Informal.Environment.getNodeInventory? directLabel).isNone)
    "Direct model control must have no old node to project"
  let origin : Informal.Realizations.Origin := {
    id := `directSource, moduleName := request.moduleName, source := sourcePath }
  let nativeKey : RealizationKey := ⟨directLabel, `lean⟩
  let nativeRole := documented.toPrepared.roles[0]!
  let nativeRoleKey := nativeKey.forRole nativeRole
  let proseKey : RealizationKey := ⟨directLabel, `description⟩
  let concept : Informal.Realizations.Node := {
    label := directLabel, title := "A direct native definition", kind := .definition }
  let model ← obtain (documented.realize origin concept nativeKey.name proseKey.name)
  let r ← obtain (admit model.input)
  ensure (model.origin == origin && model.leanKey == nativeKey && model.informalKey == proseKey &&
    r.nodes == #[concept] && r.evidence.isEmpty &&
    r.realizations.size == documented.toPrepared.roles.size + 1 &&
    r.requirements.isEmpty && (r.resultFor (.realization nativeRoleKey)).status == .unassessed &&
    (r.resultFor (.realization proseKey)).status == .unassessed)
    "Direct source preparation preserves roles and provenance without inventing assessment contracts"
  ensure (r.realizations.any (fun realization => realization.key == nativeRoleKey &&
      realization.role == `implementation &&
      realization.declarations.all (·.projection == .implementation)) &&
    !(r.realizations.any (·.role == `proof)))
    "A computational definition selects implementation content without a theorem-proof role"
  ensure (r.realizations.any (fun realization => realization.key == proseKey &&
    realization.role == `statement && realization.context.language == documented.format &&
    realization.documents.size == 1 &&
    r.documents.any (fun document => document.key == realization.documents[0]! &&
      document.text == documented.rawDocstring)))
    "The direct prose realization keeps its selected medium and exact raw docstring"
  ensure (rejected (documented.realize origin concept nativeKey.name nativeKey.name) &&
    rejected (documented.realize origin { concept with label := .anonymous } nativeKey.name proseKey.name) &&
    rejected (documented.realize { origin with moduleName := `WrongOwner } concept nativeKey.name proseKey.name))
    "Source model destinations and owning producer must be explicit and consistent"
  let neighbor ← obtain (← NativeSource.prepareDocumented
    { request with canonical := `RealizationAdapterFixture.neighboringComment } sourcePath)
  ensure (neighbor.format == `verso && neighbor.rawDocstring == " Même *texte* 😀 λ with {name}`Nat`. ")
    "Own unregistered Verso comment preserves exact supplementary Unicode bytes"
  let versoRequest := { request with canonical := `RealizationAdapterFixture.versoDocstring }
  let original ← obtain (← NativeSource.prepareDocumented versoRequest sourcePath)
  let forged := (text.replace "An own *Verso*" "An odd *Verso*").replace
    "theorem versoDocstring :" "theorem otherDocstring :"
  ensure (original.format == `verso && forged != text && forged.utf8ByteSize == text.utf8ByteSize)
    "Expected an equal-width control for the compiled Verso declaration"
  IO.FS.withTempDir fun root => do
    let wrong := root / "Provider.lean"
    IO.FS.writeFile wrong forged
    match ← NativeSource.prepareDocumented versoRequest wrong.toString with
    | .error diagnostic =>
      ensure (diagnostic.code == "source-association-unavailable") "Wrong source file must fail ownership"
    | .ok _ => throwError "Standalone preparation used source from another file and declaration"
  match ← NativeSource.prepareDocumented versoRequest sourcePath (fun _ => pure forged) with
  | .error diagnostic =>
    ensure (diagnostic.code == "source-selection-unavailable") "Edited bytes must fail the owning input hash"
  | .ok _ => throwError "Standalone preparation accepted a same-width edit at the owning path"
  match ← NativeSource.selectDocumented versoRequest sourcePath (fun _ => pure forged) with
  | .error diagnostic =>
    ensure (diagnostic.message.contains "identifier disagrees") "The selected identifier must match the compiled declaration"
  | .ok _ => throwError "Parser selection accepted a different declaration at the same ranges"
  for (bad, code) in #[
      ({ request with project := .anonymous }, "invalid-source-request"),
      ({ request with canonical := `RealizationAdapterFixture.notPresent }, "missing-declaration"),
      ({ request with moduleName := `WrongOwner }, "source-association-unavailable"),
      ({ request with canonical := Name.str `RealizationAdapterFixture "bad»name" }, "unsupported-identity"),
      ({ request with canonical := `RealizationAdapterFixture.syntheticDoc }, "source-association-unavailable"),
      ({ request with range? := some { source.ranges.range with charUtf16 := source.ranges.range.charUtf16 + 1 } },
        "source-association-unavailable")] do
    match ← NativeSource.prepare bad with
    | .error diagnostic => ensure (diagnostic.code == code) "Direct native source rejection changed"
    | .ok _ => throwError "Direct native source accepted inconsistent identity/owner/ranges"
  -- Only the doc-comment provider reads the file, so only it reports source I/O.
  let unreadable ← NativeSource.prepareDocumented documentedRequest sourcePath
    (fun _ => throw <| IO.userError "injected unavailable source")
  match unreadable with
  | .error diagnostic => ensure (diagnostic.code == "source-unavailable") "No source-I/O fallback"
  | .ok _ => throwError "Direct source manufactured readable bytes"
  match ← NativeSource.prepareDocumented documentedRequest "" with
  | .error diagnostic => ensure (diagnostic.code == "invalid-source-request") "Blank owning path must be explicit"
  | .ok _ => throwError "Doc-comment preparation accepted a blank owning path"
  ensure (decide (before = (← Informal.Environment.stagedAuthoring)))
    "Source preparation must not enroll declarations or persist semantic observations"

-- FIR's unexecuted source concern: an actual passing check of the first theorem
-- must not complete its admitted sibling merely by sharing a required key.
run_cmd liftTermElabM do
  let p ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.reflexivity") `RealizationAdapterFixture.reflexivity)
  let sibling ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.admitted") `RealizationAdapterFixture.admitted)
  let own ← obtain (← NativeLean.checkDeclaration `adapterFixture p.witness)
  let admitted ← obtain (← NativeLean.checkDeclaration `adapterFixture sibling.witness)
  ensure (own.body.outcome == .passed && admitted.body.outcome == .failed)
    "Borrowing control requires real passing and admitted declarations"
  let q := bodyCheckKey p
  let pProofKey := p.leanKey.forRole `proof
  let siblingProofKey := sibling.leanKey.forRole `proof
  let siblingKey : RequirementKey := ⟨.declaration siblingProofKey sibling.witness, `proof⟩
  let firstRealizations := p.input.realizations.map fun record =>
    if record.value.key != pProofKey then record else
      { record with value := { record.value with declarations := record.value.declarations.map fun decl =>
        { decl with required := #[q] } } }
  let borrowedSiblingRealizations := sibling.input.realizations.map fun record =>
    if record.value.key != siblingProofKey then record else
      { record with value := { record.value with declarations := record.value.declarations.map fun decl =>
        { decl with required := #[q] } } }
  let input : Input := {
    nodes := p.input.nodes ++ sibling.input.nodes
    documents := p.input.documents ++ sibling.input.documents
    objects := p.input.objects ++ sibling.input.objects
    realizations := firstRealizations ++ borrowedSiblingRealizations
    requirements := #[
      p.contribution `nativeRequirement {
        key := q, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure },
      p.contribution `siblingRequirement {
        key := siblingKey, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }]
    evidence := p.input.evidence ++ sibling.input.evidence
    bindingInputs := p.input.bindingInputs ++ sibling.input.bindingInputs }
  match admit input with
  | .error issues =>
    ensure (issues.any (·.code == "wrong-declaration-subject"))
      "Sibling requirement borrowing must be rejected at admission"
  | .ok _ => throwError "Sibling declaration borrowed another declaration's native requirement"
  let realizationCheck : RequirementKey := ⟨.realization pProofKey, `broadCheck⟩
  let broadOnly := { input with
    requirements := input.requirements.push (p.contribution `broadNativeRequirement {
      key := realizationCheck, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure })
    realizations := input.realizations.map fun record =>
      if record.value.key != pProofKey then record else
        { record with value := {
          record.value with
          required := #[realizationCheck]
          declarations := record.value.declarations.map fun decl => { decl with required := #[] }
        } } }
  match admit broadOnly with
  | .error issues => ensure (issues.any (·.code == "wrong-native-subject")) "Native checks need declaration subjects"
  | .ok _ => throwError "Native check escaped declaration identity through a realization-wide contract"
  let validInput := { input with
    realizations := input.realizations.map fun record =>
      if record.value.key == siblingProofKey then
        { record with value := { record.value with declarations := record.value.declarations.map fun decl =>
          { decl with required := #[siblingKey] } } }
      else record }
  let jointKey : RequirementKey := ⟨.realization pProofKey, `jointReview⟩
  let joint := { validInput with
    requirements := input.requirements.push (p.contribution `jointReviewRequirement {
      key := jointKey, expected := .review `jointReview `MockReviewer })
    realizations := validInput.realizations.map fun record =>
      if record.value.key != pProofKey then record else
        { record with value := { record.value with required := #[jointKey] } } }
  discard <| obtain (admit joint)
  let r ← obtain (admit validInput)
  let some firstBinding := r.bindingFor q | throwError "Missing first binding"
  let some siblingBinding := r.bindingFor siblingKey | throwError "Missing sibling binding"
  let withFirst := { validInput with evidence := #[
    p.contribution `firstNative {
      id := `actualFirstDeclaration, requirement := q, binding := firstBinding,
      observation := .check own.body },
    p.contribution `siblingNative {
      id := `actualSiblingDeclaration, requirement := siblingKey, binding := siblingBinding,
      observation := .check admitted.body }] }
  let r ← obtain (admit withFirst)
  let some statementModel := r.realization? (p.leanKey.forRole `statement)
    | throwError "The declaration lost its separate statement realization"
  ensure (statementModel.role == `statement && statementModel.declarations[0]!.projection == .statement &&
    (r.resultFor (.realization pProofKey)).complete &&
    !(r.resultFor (.declaration siblingProofKey sibling.witness)).complete)
    "One declaration keeps separate statement/proof roles without completing its sibling"
  let borrowed := { withFirst with evidence := withFirst.evidence.push (p.contribution `wrongNative {
    id := `borrowedFirstObservation, requirement := siblingKey, binding := siblingBinding
    observation := .check own.body }) }
  let r ← obtain (admit borrowed)
  ensure ((r.localResult siblingKey).diagnostics.any (·.code == "wrong-check-object") &&
    !(r.resultFor (.declaration siblingProofKey sibling.witness)).complete)
    "Fresh sibling binding cannot disguise an observation of another declaration"

-- Native validity concerns the declaration's own source statement. These real
-- observations contain no independently authored goal or correspondence claim.
run_cmd liftTermElabM do
  let before ← getMCtx
  let rawBefore ← Informal.Environment.stagedAuthoring
  for name in #[`RealizationAdapterFixture.reflexivity, `RealizationAdapterFixture.polymorphic,
      `RealizationAdapterFixture.number] do
    let checked ← obtain (← NativeLean.checkDeclaration `adapterFixture (witness name))
    ensure (checked.declaration == witness name &&
      checked.statement.outcome == .passed && checked.body.outcome == .passed &&
      checked.statement.validator == NativeLean.statementValidator &&
      checked.body.validator == NativeLean.bodyValidator &&
      checked.body.coverage == .dependencyClosure) "Actual own-declaration checking failed"
  let admitted ← obtain (← NativeLean.checkDeclaration `adapterFixture (witness `RealizationAdapterFixture.admitted))
  ensure (admitted.statement.outcome == .passed && admitted.body.outcome == .failed &&
    admitted.status.hasKnownSorry) "Native statement and proof validity must remain separate"
  let conditional ← obtain (← NativeLean.checkDeclaration `adapterFixture (witness `RealizationAdapterFixture.conditionalProof))
  ensure (conditional.body.outcome == .passed &&
    conditional.assumptions.contains "RealizationAdapterFixture.assumption") "Assumptions must remain inspectable"
  let axiomResult ← obtain (← NativeLean.checkDeclaration `adapterFixture (witness `RealizationAdapterFixture.assumption))
  ensure (axiomResult.body.outcome == .failed && axiomResult.status.isAxiomLike) "An axiom has no completed native proof"
  let missing ← obtain (← NativeLean.checkDeclaration `adapterFixture (witness `RealizationAdapterFixture.notPresent))
  ensure (missing.status.isMissing && missing.body.outcome == .unavailable) "Valid missing identity must remain unavailable"
  let unusual := Name.str `RealizationAdapterFixture "bad»name"
  match ← NativeLean.checkDeclaration `adapterFixture (witness unusual) with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-identity") "Native identity loss needs its own diagnostic"
  | .ok _ => throwError "Unsupported identity must not be silently replaced"
  ensure (rejected (← NativeLean.checkDeclaration `wrongProject (witness `RealizationAdapterFixture.reflexivity)))
    "Logical project selection cannot be ignored"
  let after ← getMCtx
  ensure (before.mvarCounter == after.mvarCounter && before.lmvarCounter == after.lmvarCounter &&
    before.eAssignment.toList == after.eAssignment.toList &&
    decide (rawBefore = (← Informal.Environment.stagedAuthoring))) "Native check leaked state or persisted observations"

-- A checked union supplies coverage for each witness. Assumptions belong to
-- individual witnesses, and expected propositions still close their own dependencies.
run_cmd liftTermElabM do
  let names := #[`RealizationAdapterFixture.groupedOne, `RealizationAdapterFixture.conditionalProof,
    `RealizationAdapterFixture.assumption, `RealizationAdapterFixture.groupedOne]
  let session ← liftM Informal.Data.newSorryInspectionSession
  NativeLean.prepareDeclarations session (names.map fun name => (`adapterFixture, witness name))
  let trueGoal ← `(term| True)
  for name in names do
    let object := witness name
    let isolated ← obtain (← NativeLean.checkDeclaration `adapterFixture object)
    let batched ← obtain (← NativeLean.checkDeclaration `adapterFixture object (some session))
    ensure (batched.status == isolated.status && batched.roles == isolated.roles &&
      batched.kind == isolated.kind && batched.statement == isolated.statement && batched.body == isolated.body)
      "Batched own-declaration observations changed root-specific roles, assumptions, or outcomes"
    let isolated ← obtain (← NativeLean.check `adapterFixture object trueGoal)
    let batched ← obtain (← NativeLean.check `adapterFixture object trueGoal (session := some session))
    ensure (batched.goal == isolated.goal && batched.status == isolated.status &&
      batched.observation == isolated.observation)
      "Batched independent-goal observation differs from an isolated check"
  let work ← session.work
  ensure (work.certificateScans == 1)
    "Covered expectations and witnesses must share the union's single certificate"
  let blockedGoal ← `(term| RealizationAdapterFixture.admittedProposition)
  match ← NativeLean.check `adapterFixture (witness names[0]!) blockedGoal (session := some session) with
  | .error issue =>
    ensure (issue.code == "unverified-expectation")
      "A new expectation dependency must be inspected independently of a clean witness"
  | .ok _ => throwError "Certified witness authorized a blocked expectation"

private def assertPendingCorrespondence (p : PreparedModel) (input : Input) (expected : Syntax)
    (interpretation : String) : TermElabM Unit := do
  -- An explicitly authored correspondence still needs its own review.
  let t : TranslationKey := ⟨`adapterFixture, `docstringToLean⟩
  let c : ClaimKey := ⟨t, `statement⟩
  let review : RequirementKey := ⟨.claim c, `review⟩
  let expectedProof := proofKey p
  let linked := { input with
    translations := #[p.contribution `translation {
      key := t
      source := #[{ realization := p.informalKey }],
      target := #[{ realization := p.leanKey.forRole `statement }],
      required := #[expectedProof] }]
    claims := #[p.contribution `claim {
      key := c, interpretation
      required := #[review] }]
    requirements := input.requirements.push (p.contribution `review {
      key := review, expected := .review `statementCorrespondence `MockReviewer }) }
  -- Recheck the native proof for the newly authored connected contract;
  -- no human review observation is supplied.
  let linkedRegistry ← obtain (admit { linked with evidence := #[] })
  let some binding := linkedRegistry.bindingFor expectedProof | throwError "missing binding"
  let fresh ← obtain (← NativeLean.check `adapterFixture p.witness expected
    (p.input.objects.filterMap (·.value.document)))
  let linked := { linked with evidence := #[p.contribution `proofEvidence {
    id := p.leanKey.node ++ `nativeProof, requirement := expectedProof, binding
    observation := .proof fresh.observation }] }
  let linkedRegistry ← obtain (admit linked)
  ensure ((linkedRegistry.resultForRequirement expectedProof).complete) "Actual proof stays complete"
  ensure ((linkedRegistry.resultFor (.translation t)).status == .pending) "Correspondence remains pending"


-- Native identity must either survive serialization or fail explicitly. These
-- are actual checked/imported declarations, not fake successful observations.
run_cmd liftTermElabM do
  let trueGoal ← `(term| True)
  let escaped := Name.str `RealizationAdapterFixture "with.dot"
  let escapedProjection ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.escaped") `RealizationAdapterFixture.«with.dot»)
  ensure (escapedProjection.witness.native.toName == escaped) "Escaped dotted name preserves typed identity"
  let escapedInput ← obtain (← escapedProjection.validate trueGoal)
  let escapedRegistry ← obtain (admit escapedInput)
  ensure ((escapedRegistry.resultForRequirement (proofKey escapedProjection)).complete)
    "Ordinary escaped dotted witness remains supported"
  let noExpectedContext ← obtain (admit { escapedInput with
    bindingInputs := escapedInput.bindingInputs.filter (·.value.name !=
      NativeLean.expectedContextFor (proofKey escapedProjection)) })
  ensure ((noExpectedContext.localResult (proofKey escapedProjection)).diagnostics.any
      (·.code == "semantic-context-unavailable")) "Selected source alone cannot bind unknown expected-goal semantics"
  let unusual := Name.str `RealizationAdapterFixture "bad»name"
  ensure (((← getEnv).checked.get.find? unusual).isSome && unusual.toString.toName != unusual)
    "Regression must use a present checked theorem whose name cannot round-trip"
  let some accepted ← Informal.Environment.getNodeInventory? (Name.mkSimple "adapter.nonroundtrip")
    | throwError "Regression requires a real accepted attribute association"
  ensure ((accepted.nativeRefsOn `statement).any (·.canonical == unusual)) "Accepted association retains original typed name"
  match ← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.nonroundtrip") (Name.str `RealizationAdapterFixture "bad»name") with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-identity") "Projection must diagnose identity loss"
  | .ok _ => throwError "Projection must not silently replace a typed Lean identity"
  match ← NativeLean.check `adapterFixture (witness unusual) trueGoal with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-identity") "Native checker must diagnose unparseable identity"
  | .ok _ => throwError "Unparseable name is not a missing declaration"

-- Real imported own-Verso source, including markup, whitespace and supplementary
-- Unicode. The consumer's own options/file map cannot supply this association.
run_cmd liftTermElabM do
  let label := Name.mkSimple "adapter.unicode"
  let before ← Informal.Environment.getNodeInventory? label
  let some accepted := before | throwError "Missing actual accepted Unicode theorem"
  let association := (accepted.nativeRefsOn `statement)[0]!
  ensure (association.range?.isNone && association.selectionRange?.isNone)
    "Ordinary attribute snapshot predates native range registration"
  let p ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture label `RealizationAdapterFixture.«état😀»)
  ensure (p.docstringFormat == `verso && p.input.documents[0]!.value.key.context.language == `verso)
    "Own native format metadata must select Verso"
  ensure (p.input.documents[0]!.value.text == " Même *texte* 😀 λ with {name}`Nat`. ")
    "Exact own source body includes authored whitespace, markup and Unicode"
  ensure (p.moduleName == `VersoBlueprintTests.BlueprintRealizationAdapter.Provider &&
    p.witness == witness (Name.str `RealizationAdapterFixture "état😀"))
    "Imported source belongs to the accepted declaration, not consumer or neighboring comment"
  let some ranges ← findDeclarationRanges? p.witness.native.toName | throwError "Missing actual native ranges"
  let reconciled ← obtain (checkedSourceRanges label association.range? association.selectionRange? (some ranges))
  ensure (reconciled.range == ranges.range && reconciled.selectionRange == ranges.selectionRange)
    "Absent snapshots must use actual native ranges for the same accepted canonical theorem"
  for (snapshot, selection) in #[(some ranges.range, none), (none, some ranges.selectionRange),
      (some ranges.range, some ranges.selectionRange)] do
    let agreed ← obtain (checkedSourceRanges label snapshot selection (some ranges))
    ensure (agreed.range == ranges.range && agreed.selectionRange == ranges.selectionRange)
      "Present agreeing snapshots retain the same owning native ranges"
  -- Negative snapshot inputs are standalone comparison values; neither the
  -- accepted association nor its producer/environment record is modified.
  let badRange := { ranges.range with charUtf16 := ranges.range.charUtf16 + 1 }
  let badSelection := { ranges.selectionRange with endCharUtf16 := ranges.selectionRange.endCharUtf16 + 1 }
  for (snapshot, selection) in #[(some badRange, none), (none, some badSelection)] do
    match checkedSourceRanges label snapshot selection (some ranges) with
    | .error diagnostic =>
      ensure (diagnostic.code == "source-association-unavailable" && diagnostic.message.endsWith "disagree")
        "Stored full/name snapshot disagreement must fail before source parsing"
    | .ok _ => throwError "Native ranges must not silently override a disagreeing stored snapshot"
  let unavailable ← findDeclarationRanges? `RealizationAdapterFixture.syntheticDoc
  ensure unavailable.isNone "Actual checked synthetic fixture has no original native ranges"
  match checkedSourceRanges label none none unavailable with
  | .error diagnostic =>
    ensure (diagnostic.code == "source-association-unavailable" && diagnostic.message.endsWith "no native source ranges")
      "Missing snapshots plus unavailable actual native ranges must fail explicitly"
  | .ok _ => throwError "Unavailable native ranges must not be synthesized"
  ensure (ranges.selectionRange.charUtf16 != ranges.selectionRange.pos.column)
    "Supplementary Unicode must distinguish Lean codepoint and UTF-16 columns"
  let text ← liftM <| IO.FS.readFile p.sourcePath
  let commands ← obtain (← parseSource label p.sourcePath text)
  let raw ← obtain (docCommentAtRanges label text ranges.range ranges.selectionRange commands)
  ensure (raw == p.input.documents[0]!.value.text) "Exact owning-source association"
  -- Explicit negative structural injections, not fabricated provider success.
  for badCommands in #[commands ++ commands, commands.map fun command =>
      command.rewriteBottomUp fun stx =>
        stx.setInfo (.synthetic (stx.getPos?.getD 0) (stx.getTailPos?.getD 0) true)] do
    ensure (rejected (docCommentAtRanges label text ranges.range ranges.selectionRange badCommands))
      "Duplicate or canonical-synthetic syntax cannot establish a unique original association"
  ensure (rejected (docCommentAtRanges label text ranges.range
    { ranges.selectionRange with charUtf16 := ranges.selectionRange.charUtf16 + 1 } commands))
    "UTF-16 disagreement is not a byte/codepoint conversion fallback"
  ensure (rejected (docCommentAtRanges label (text ++ "\n") ranges.range ranges.selectionRange commands))
    "Syntax from a different source string cannot establish original ownership"
  let other := ranges.range
  ensure (rejected (docCommentAtRanges label text ranges.range other commands))
    "Full declaration range cannot replace the selected name range"
  let trueGoal ← `(term| True)
  let input ← obtain (← p.validate trueGoal)
  assertPendingCorrespondence p input trueGoal "The own Verso source states this theorem"
  let after ← Informal.Environment.getNodeInventory? label
  ensure (reprStr before == reprStr after) "Verso projection/checking preserves accepted state"
  -- Current consumer settings must not relabel already authored own Markdown.
  let markdown ← withOptions (fun opts => opts.setBool `doc.verso true) <|
    RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.reflexivity") `RealizationAdapterFixture.reflexivity
  let markdown ← obtain markdown
  ensure (markdown.docstringFormat == `markdown &&
    markdown.input.documents[0]!.value.text == " Every natural number equals itself. Raw Markdown, with **emphasis**. ")
    "Markdown retains its exact own raw body and native format"
  let basic ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.verso") `RealizationAdapterFixture.versoDocstring)
  ensure (basic.input.documents[0]!.value.text == " An own *Verso* docstring with {name}`Nat` and é 😀. ")
    "Option-wrapped Verso source remains exact"

run_cmd liftTermElabM do
  for (label, canonical, code) in #[("adapter.inherited", `RealizationAdapterFixture.inheritedDocstring, "unsupported-docstring"),
      ("adapter.own.inherited", `RealizationAdapterFixture.ownInheritedDocstring, "inherited-docstring"),
      ("adapter.ambiguous", `RealizationAdapterFixture.ambiguousFormat, "ambiguous-docstring"),
      ("adapter.no.original.comment", `RealizationAdapterFixture.noOriginalComment, "missing-own-comment"),
      ("adapter.synthetic", `RealizationAdapterFixture.syntheticDoc, "source-association-unavailable")] do
    match ← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple label) canonical with
    | .error diagnostic =>
      ensure (diagnostic.code == code)
        s!"{label}: expected {code}, got {diagnostic.code}"
    | .ok _ => throwError "Unsupported source association must not fall back to another comment"
  -- Inspect the actual ordinary declaration with no source comment directly;
  -- late injected text cannot supply an original modifier association.
  let p ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.unicode") `RealizationAdapterFixture.«état😀»)
  let source ← liftM <| IO.FS.readFile p.sourcePath
  let commands ← obtain (← parseSource `noComment p.sourcePath source)
  let some ranges ← findDeclarationRanges? `RealizationAdapterFixture.noOriginalComment
    | throwError "Missing actual uncommented declaration ranges"
  match docCommentAtRanges `noComment source ranges.range ranges.selectionRange commands with
  | .error diagnostic => ensure (diagnostic.code == "missing-own-comment") "No adjacent-comment fallback"
  | .ok _ => throwError "Native text cannot create an original doc comment"
  -- Explicit source/parser failure injection, not replacement canonical content.
  let malformed ← NativeSource.selectDocumented {
      project := `adapterFixture, canonical := `RealizationAdapterFixture.versoDocstring
      moduleName := `VersoBlueprintTests.BlueprintRealizationAdapter.Provider }
    p.sourcePath
    (fun _ => pure "import Lean\n/-- unterminated source")
  match malformed with
  | .error diagnostic => ensure (diagnostic.code == "source-parse-failed") "Malformed source is explicit"
  | .ok _ => throwError "Malformed source must not borrow a native-rendered docstring"
  let standalone := "import Lean\n/-- own -/ theorem t : True := True.intro\nattribute [inherit_doc True.intro] t\n"
  let commands ← obtain (← parseSource `standalone "<injected-source>" standalone)
  match docCommentAtRanges `standalone standalone default default commands with
  | .error diagnostic => ensure (diagnostic.code == "inherited-docstring") "Standalone inheritance is diagnosed"
  | .ok _ => throwError "Standalone inheritance cannot silently override own-source provenance"

-- Checked alternatives can coexist under one node. Validate must admit new
-- evidence against the complete caller batch before returning that batch.
run_cmd liftTermElabM do
  let path := "tests/VersoBlueprintTests/BlueprintRealizationAdapter/Provider.lean"
  let request : NativeSource.Request := {
    project := `adapterFixture, canonical := `RealizationAdapterFixture.reflexivity
    moduleName := `VersoBlueprintTests.BlueprintRealizationAdapter.Provider }
  let source ← obtain (← NativeSource.prepareDocumented request path)
  let node : Informal.Realizations.Node := { label := `alternativeSource, title := "Checked alternatives" }
  let origin : Informal.Realizations.Origin := {
    id := `firstSource, moduleName := request.moduleName, source := path }
  let first ← obtain (source.realize origin node `first `firstDoc)
  let second ← obtain (source.realize { origin with id := `secondSource } node `second `secondDoc)
  let goal ← `(term| ∀ n : Nat, n = n)
  let a ← obtain (← first.validate goal)
  let b ← obtain (← second.validate goal)
  let #[evidence] := a.evidence | throwError "First alternative lost its proof evidence"
  let #[secondEvidence] := b.evidence | throwError "Second alternative lost its proof evidence"
  ensure (evidence.value.id != secondEvidence.value.id)
    "Separate requirements and producer origins need independent proof evidence identities"
  let registry ← obtain <| admit {
    nodes := a.nodes ++ b.nodes
    documents := a.documents ++ b.documents
    objects := a.objects ++ b.objects
    realizations := a.realizations ++ b.realizations
    requirements := a.requirements ++ b.requirements
    evidence := a.evidence ++ b.evidence
    bindingInputs := a.bindingInputs ++ b.bindingInputs }
  ensure ((registry.resultForRequirement (proofKey first)).complete &&
    (registry.resultForRequirement (proofKey second)).complete)
    "Each standalone proof alternative must retain independently bound evidence"
  let conflicting := first.contribution `alreadySuppliedEvidence { evidence.value with binding := "other-binding" }
  let input := { first.input with evidence := #[conflicting] }
  match ← ({ first with input }).validate goal with
  | .error diagnostic =>
    ensure (diagnostic.code == "semantic-conflict") "Validation must reject an existing conflicting evidence ID"
  | .ok _ => throwError "Standalone validation returned conflicting evidence for later readmission"

-- Exercise the pilot's actual involution and package-specific statements, beyond
-- reflexivity/True. These are native current-build controls, not foreign proof
-- observations, correspondence reviews, or a second mapping database.
run_cmd liftTermElabM do
  let p ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.flag.involutive") `RealizationAdapterFixture.flagInvolutive)
  let expected ← `(term| ∀ flag : RealizationAdapterFixture.Flag,
    RealizationAdapterFixture.toggle (RealizationAdapterFixture.toggle flag) = flag)
  let input ← obtain (← p.validate expected)
  let r ← obtain (admit input)
  ensure ((r.resultForRequirement (proofKey p)).complete) "Actual two-case involution must complete"
  ensure (p.docstringFormat == `verso && p.input.documents[0]!.value.text ==
    "\nToggling a *two-state* flag twice returns the original flag: é 😀.\nFor {name}`RealizationAdapterFixture.Flag.off`, toggle gives on then off;\nfor on, it gives off then on.\n")
    "Flag retains the full exact own Verso account"
  assertPendingCorrespondence p input expected "The Verso account states toggle involution by its two cases"
  ensure (input.translations.isEmpty && (r.resultFor (.realization p.informalKey)).status == .unassessed)
    "Flag proof does not invent correspondence or proofreading"
  let selectedPackage ← `(term| RealizationAdapterFixture.Involutive RealizationAdapterFixture.togglePackage)
  let packageInput ← obtain (← p.validate selectedPackage)
  let packageRegistry ← obtain (admit packageInput)
  ensure ((packageRegistry.resultForRequirement (proofKey p)).complete) "Selected package alias must match"
  for name in #[`RealizationAdapterFixture.groupedOne,
      `RealizationAdapterFixture.identityInvolutive, `RealizationAdapterFixture.conditionalInvolutive] do
    let result ← obtain (← NativeLean.check `adapterFixture (witness name) expected)
    ensure (result.observation.outcome == .failed && result.observation.actualType.isNone &&
      result.observation.explanation.startsWith "wrong-proposition:")
      "True, a different package and a conditional proof cannot satisfy unconditional involution"
  -- Neither alternative is an incomplete theorem. They are complete proofs of
  -- their own full propositions and still cannot establish the selected claim.
  let identityGoal ← `(term| RealizationAdapterFixture.Involutive RealizationAdapterFixture.identityPackage)
  let identityResult ← obtain (← NativeLean.check `adapterFixture
    (witness `RealizationAdapterFixture.identityInvolutive) identityGoal)
  ensure (identityResult.observation.outcome == .passed) "Different package proof is independently complete"
  let conditionalGoal ← `(term|
    RealizationAdapterFixture.Involutive RealizationAdapterFixture.togglePackage →
    RealizationAdapterFixture.Involutive RealizationAdapterFixture.togglePackage)
  let conditionalResult ← obtain (← NativeLean.check `adapterFixture
    (witness `RealizationAdapterFixture.conditionalInvolutive) conditionalGoal)
  ensure (conditionalResult.observation.outcome == .passed) "Conditional theorem retains its full premise"
  let wrongPackage ← obtain (← p.validate identityGoal)
  let wrongRegistry ← obtain (admit wrongPackage)
  ensure (!(wrongRegistry.resultForRequirement (proofKey p)).complete)
    "A proof for the selected toggle package cannot be relabeled as identity-package evidence"

-- The ordinary imported provider has canonical accepted Blueprint facts. Reading
-- and checking twice must not install new registrations or alter membership.
run_cmd liftTermElabM do
  let label := Name.mkSimple "adapter.reflexivity"
  let before ← Informal.Environment.getNodeInventory? label
  let labels ← Informal.Environment.labelsForLeanDecl `RealizationAdapterFixture.reflexivity
  let some accepted := before | throwError "Missing actual accepted metadata"
  let p ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture label
    `RealizationAdapterFixture.reflexivity (metadata := accepted.toNodeMetadata))
  ensure (p.input.nodes.any fun contribution => contribution.value.label == label &&
    contribution.value.toNodeMetadata == accepted.toNodeMetadata)
    "Current source model must preserve the exact accepted concept metadata"
  ensure (p.docstringFormat == `markdown &&
    (p.input.realizations.any (·.value.key == p.leanKey.forRole `statement)) &&
    (p.input.realizations.any (·.value.key == p.leanKey.forRole `proof)) &&
    (p.input.realizations.any fun contribution => contribution.value.key == p.informalKey &&
      contribution.value.role == `statement && contribution.value.context.language == p.docstringFormat))
    "Expected distinct native statement/proof and informal statement realizations"
  ensure (p.witness == witness `RealizationAdapterFixture.reflexivity &&
    p.moduleName == `VersoBlueprintTests.BlueprintRealizationAdapter.Provider &&
    p.input.documents.size == 1 && p.input.documents[0]!.value.text.contains "**emphasis**" &&
    p.input.objects.all (·.value.document.isNone))
    "Module, qualified declaration and raw Markdown must survive projection; the native object carries no source document"
  ensure (p.input.translations.isEmpty && p.input.evidence.isEmpty && p.input.requirements.isEmpty)
    "Source projection invents no validation contracts, observations, or correspondence"
  let initial ← obtain (admit p.input)
  ensure ((initial.resultFor (.realization p.informalKey)).status == .unassessed) "Prose is not proofread"
  let expected ← `(term| ∀ n : Nat, n = n)
  let semanticDiagnostic : Diagnostic := {
    code := "semantic-context-unavailable", subject := "standalone-check"
    message := "Injected standalone semantic-context failure" }
  let failingSemantics : NativeLean.SemanticContext := fun _ _ _ => pure (.error semanticDiagnostic)
  let prepared ← p.prepareValidation expected #[] failingSemantics
  let .ok (_, checked) := prepared | throwError "Standalone source validation unexpectedly failed"
  ensure (checked.semanticContext.isNone && checked.semanticDiagnostics == #[semanticDiagnostic])
    "Standalone source validation did not retain semantic-context diagnostics"
  let input ← obtain (← p.validate expected)
  let r ← obtain (admit input)
  ensure ((r.resultForRequirement (proofKey p)).complete) "Actual imported proof must complete"
  ensure ((r.resultFor (.realization (p.leanKey.forRole `proof))).complete) "Selected proof realization must complete"
  ensure ((r.resultFor (.realization p.informalKey)).status == .unassessed) "Proof is not proofreading"
  -- Definitional equality through an independently authored exposed alias.
  let alias ← `(term| RealizationAdapterFixture.Reflexivity)
  let aliasInput ← obtain (← p.validate alias)
  let aliasRegistry ← obtain (admit aliasInput)
  ensure ((aliasRegistry.resultForRequirement (proofKey p)).complete) "Definitional equality alias must pass"
  ensure (input.requirements[0]!.value != aliasInput.requirements[0]!.value)
    "Alias control must exercise different structural expectations"
  let wrong ← `(term| False)
  let wrongInput ← obtain (← p.validate wrong)
  let wrongRegistry ← obtain (admit wrongInput)
  ensure (!(wrongRegistry.resultForRequirement (proofKey p)).complete) "Wrong expected proposition must fail"
  ensure (wrongInput.evidence[0]!.value.observation.explanation.startsWith "wrong-proposition:")
    "Wrong expected proposition must fail for its actual checked type"
  let admittedProjection ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.admitted") `RealizationAdapterFixture.admitted)
  let trueGoal ← `(term| True)
  let incompleteInput ← obtain (← admittedProjection.validate trueGoal)
  let incompleteRegistry ← obtain (admit incompleteInput)
  ensure (!(incompleteRegistry.resultForRequirement (proofKey admittedProjection)).complete)
    "Admitted proof with matching goal cannot complete through pure rules"
  assertPendingCorrespondence p input expected "The prose states natural-number reflexivity"
  let _ ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture label `RealizationAdapterFixture.reflexivity)
  let after ← Informal.Environment.getNodeInventory? label
  ensure (reprStr before == reprStr after &&
    labels == (← Informal.Environment.labelsForLeanDecl `RealizationAdapterFixture.reflexivity))
    "Read/check must preserve accepted node/declaration membership"

-- Validate the selected declaration even when it follows a sibling in a
-- composed model. Keep the sibling's real evidence and the selected owner's
-- association failure, which must still block the newly attached proof.
run_cmd liftTermElabM do
  let p ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture
    (Name.mkSimple "adapter.composed") `RealizationAdapterFixture.reflexivity)
  let owner := p.leanKey.forRole `proof
  let sibling := witness `RealizationAdapterFixture.groupedOne
  let siblingKey : RequirementKey := ⟨.declaration owner sibling, `proof⟩
  let siblingCheck ← obtain (← NativeLean.checkDeclaration `adapterFixture sibling)
  let sourceIssue : Diagnostic := {
    code := "source-association-unavailable", subject := p.witness.native
    message := "Selected owner's source association is unavailable" }
  let siblingDeclaration : Informal.Realizations.Declaration := { object := sibling, required := #[siblingKey] }
  let selected : Informal.Realizations.Declaration := { object := p.witness, sourceIssues := #[sourceIssue] }
  let input := { p.input with
    objects := p.input.objects.push (p.contribution `composedSibling { key := sibling, resolution := .resolved })
    realizations := p.input.realizations.map fun record =>
      if record.value.key == owner then
        { record with value := { record.value with declarations := #[siblingDeclaration, selected] } }
      else record
    requirements := p.input.requirements.push (p.contribution `composedSiblingRequirement {
      key := siblingKey, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }) }
  let before ← obtain (admit input)
  let some binding := before.bindingFor siblingKey | throwError "Missing sibling check binding"
  let prior := p.contribution `composedSiblingEvidence {
    id := `composedSiblingEvidence, requirement := siblingKey, binding
    observation := .check siblingCheck.body }
  let composed := { p with input := { input with evidence := #[prior] } }
  let goal ← `(term| ∀ n : Nat, n = n)
  let validated ← obtain (← composed.validate goal)
  let registry ← obtain (admit validated)
  let some proof := registry.realization? owner | throwError "Missing composed proof realization"
  let expected := proofKey p
  ensure (proof.declarations == #[siblingDeclaration, { selected with required := #[expected] }] &&
    validated.evidence.size == 2 && validated.evidence[0]? == some prior &&
    (registry.resultForRequirement siblingKey).complete &&
    (registry.resultForRequirement expected).status == .blocked &&
    (registry.resultForRequirement expected).diagnostics.contains sourceIssue)
    "Expected-proof validation must preserve the exact declarations, owner issues and prior evidence"
  let wrong := { composed with witness := witness `RealizationAdapterFixture.polymorphic }
  match ← wrong.prepareValidation goal with
  | .error diagnostic => ensure (diagnostic.code == "wrong-proof-witness") "Wrong exact-owner rejection"
  | .ok _ => throwError "A proof-shaped key was accepted without its exact witness"

run_cmd liftTermElabM do
  let trueGoal ← `(term| True)
  let admitted ← obtain (← NativeLean.check `adapterFixture (witness `RealizationAdapterFixture.admitted) trueGoal)
  ensure (admitted.observation.outcome == .failed && admitted.status.any (·.hasKnownSorry))
    "Actual admitted proof must report holes"
  ensure (admitted.status.any fun s => !s.blocksStatementCompletion .theorem)
    "A proof hole does not erase clean statement coverage"
  let axiomResult ← obtain (← NativeLean.check `adapterFixture (witness `RealizationAdapterFixture.assumption) trueGoal)
  ensure (axiomResult.observation.outcome == .failed && axiomResult.status.any (·.isAxiomLike))
    "A genuine axiom is not a complete proof"
  let conditional ← obtain (← NativeLean.check `adapterFixture
    (witness `RealizationAdapterFixture.conditionalProof) trueGoal)
  ensure (conditional.observation.outcome == .passed &&
    conditional.observation.assumptions.contains "RealizationAdapterFixture.assumption")
    "Complete hole coverage does not assert absence of project axioms"
  let absent ← obtain (← NativeLean.check `adapterFixture (witness `RealizationAdapterFixture.missing) trueGoal)
  ensure (absent.observation.outcome == .unavailable && absent.status.isNone) "Missing witness stays unavailable"
  ensure (rejected (← NativeLean.check `otherProject (witness `RealizationAdapterFixture.reflexivity) trueGoal))
    "Wrong project must be rejected"
  let poly ← `(term| ∀ (α : Type) (x : α), x = x)
  let polyResult ← obtain (← NativeLean.check `adapterFixture (witness `RealizationAdapterFixture.polymorphic) poly)
  ensure (polyResult.observation.outcome == .passed) "Concrete universe and telescope must match"
  for expected in #[← `(term| (1 : Nat)), ← `(term| _), ← `(term| (by sorry : Prop)),
      ← `(term| RealizationAdapterFixture.admittedProposition)] do
    ensure (rejected (← NativeLean.check `adapterFixture (witness `RealizationAdapterFixture.admitted) expected))
      "Non-proposition/open/admitted expectations must be rejected before matching"
  withLocalDeclD `openProposition (mkSort .zero) fun _ => do
    let expected := mkIdent `openProposition
    let result ← NativeLean.check `adapterFixture (witness `RealizationAdapterFixture.admitted) expected
    match result with
    | .error diagnostic =>
      ensure (diagnostic.code == "open-expectation")
        "Actual free local assumption must be rejected before matching"
    | .ok _ => throwError "Local assumptions must not escape as closed expectations"

run_cmd liftTermElabM do
  -- Source checking takes an explicit identity; multiple declarations attached
  -- to a concept and definitions are no longer rejected by an old node-shape gate.
  for canonical in #[`RealizationAdapterFixture.groupedOne, `RealizationAdapterFixture.number] do
    let _ ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture `directSource canonical)
  for canonical in #[`RealizationAdapterFixture.undocumented,
      `RealizationAdapterFixture.notPresent, `RealizationAdapterFixture.inheritedDocstring] do
    ensure (rejected (← RealizationAdapterFixture.prepareModel `adapterFixture `directSource canonical))
      "Missing or inherited own source remains explicit"
  -- Explicitly labeled source-I/O failure injection; never a successful provider.
  let missing ← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.reflexivity") `RealizationAdapterFixture.reflexivity
    (fun _ => throw <| IO.userError "injected unavailable source")
  match missing with
  | .error diagnostic => ensure (diagnostic.code == "source-unavailable") "Missing source diagnostic"
  | .ok _ => throwError "Unreadable source must not project a resolved declaration"
  -- Explicit empty-source failure injection, not replacement successful bytes.
  let empty ← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.reflexivity") `RealizationAdapterFixture.reflexivity (fun _ => pure " \n")
  ensure (rejected empty) "Empty source must not project a resolved declaration"

open Verso Genre Manual Informal in
#docs (Manual) hiddenDeclarationsDoc "Hidden declarations" :=
:::::::
:::theorem "hidden.complete" (lean := "sorryImportComplete")
An imported theorem with a complete hidden proof.
:::

:::theorem "hidden.admitted" (lean := "sorryImportAdmitted")
An imported theorem with an admitted hidden proof.
:::

:::definition "hidden.completeSpec" (lean := "sorryImportCompleteSpec")
An imported proposition definition with a complete hidden value.
:::

:::definition "hidden.admittedSpec" (lean := "sorryImportAdmittedSpec")
An imported proposition definition with an admitted hidden value.
:::

:::theorem "hidden.axiom" (lean := "sorryImportAxiom")
An imported axiom.
:::

:::theorem "hidden.dependent" (lean := "sorryImportExposedProof")
A locally checked proof with an authored prerequisite.
:::

:::proof "hidden.dependent" (uses := "hidden.admitted")
The Blueprint proof requires the admitted theorem.
:::
:::::::

private def hiddenCapture (plan : Capture.Plan) : TermElabM Unit := do
  let observations ← obtain (← Capture.observe plan)
  let snapshot ← obtain (Capture.evaluate plan observations)
  let registry := snapshot.registry
  let key (label : String) (name role : Name) : RequirementKey :=
    ⟨.declaration ((⟨Name.mkSimple label, `lean⟩ : RealizationKey).forRole role)
      ⟨⟨`lean, `blueprintFixtures⟩, name.toString⟩, role⟩
  let checked (name : Name) : TermElabM NativeLean.CheckedDeclaration := do
    let some result := snapshot.nativeChecks.find? (·.declaration.native == name.toString)
      | throwError "Missing native check for {name}"
    return result
  for (label, name, outcome, status) in #[
      ("hidden.complete", `sorryImportComplete, Outcome.unavailable, Status.blocked),
      ("hidden.admitted", `sorryImportAdmitted, Outcome.failed, Status.pending)] do
    let native ← checked name
    let statement := key label name `statement
    let proof := key label name `proof
    let some proofRequirement := registry.requirement? proof
      | throwError "Hidden theorem lost its proof requirement: {name}"
    let assessment := snapshot.assessmentFor (Name.mkSimple label)
    ensure (native.kind == some .theorem && native.roles == #[`statement, `proof] &&
      native.statement.outcome == .passed && native.body.outcome == outcome && native.body.coverage == .subject &&
      proofRequirement.expected == .check NativeLean.bodyValidator &&
      proofRequirement.prerequisites == #[statement] && (registry.resultForRequirement statement).complete &&
      (registry.resultForRequirement proof).status == status && assessment.nativeStatementComplete &&
      assessment.hasNativeBodyRequirement && !assessment.nativeBodyComplete && !assessment.requiredComplete)
      s!"Hidden theorem must retain a passing statement and unfinished proof: {name}"
  for (label, name, outcome, status) in #[
      ("hidden.completeSpec", `sorryImportCompleteSpec, Outcome.unavailable, Status.blocked),
      ("hidden.admittedSpec", `sorryImportAdmittedSpec, Outcome.failed, Status.pending)] do
    let native ← checked name
    let assessment := snapshot.assessmentFor (Name.mkSimple label)
    ensure (native.kind == some .definition && native.roles == #[`statement] &&
      native.statement.outcome == outcome && native.statement.coverage == .subject &&
      (registry.requirement? (key label name `statement)).isSome &&
      (registry.resultForRequirement (key label name `statement)).status == status &&
      !assessment.nativeStatementComplete && !assessment.hasNativeBodyRequirement && !assessment.requiredComplete)
      s!"Hidden proposition definition must require its value for statement completion: {name}"
  let axiomCheck ← checked `sorryImportAxiom
  let axiomAssessment := snapshot.assessmentFor (Name.mkSimple "hidden.axiom")
  ensure (axiomCheck.status.isAxiomLike && axiomCheck.roles == #[`statement] && axiomCheck.body.outcome == .failed &&
    (registry.resultForRequirement (key "hidden.axiom" `sorryImportAxiom `statement)).status == .pending &&
    axiomAssessment.hasAxiomLike && !axiomAssessment.hasNativeBodyRequirement && !axiomAssessment.requiredComplete)
    "A genuine axiom must remain incomplete without a fabricated proof role"
  let admitted := key "hidden.admitted" `sorryImportAdmitted `proof
  let dependent := key "hidden.dependent" `sorryImportExposedProof `proof
  let dependentLabel := Name.mkSimple "hidden.dependent"
  let assessment := snapshot.assessmentFor dependentLabel
  let some requirement := registry.requirement? dependent | throwError "Missing dependent proof contract"
  let result := registry.resultForRequirement dependent
  ensure (snapshot.uses.any (fun use => use.source == dependentLabel && use.role == `proof &&
    use.reference.label == Name.mkSimple "hidden.admitted" &&
    match use.selected with | .ok keys => keys == #[admitted] | .error _ => false) &&
    requirement.prerequisites.contains admitted && (registry.localResult dependent).complete &&
    result.status == .blocked && result.diagnostics.any (·.code == "unfinished-prerequisite") &&
    assessment.nativeStatementComplete && assessment.nativeBodyComplete &&
    assessment.statementDependenciesComplete && !assessment.proofDependenciesComplete && !assessment.requiredComplete)
    "The authored proof use must select the hidden theorem's unfinished proof requirement"

-- A legacy import exposes bodies. Retain the actual authored source plan, then
-- observe against the same declarations at module-system server visibility.
private unsafe def hiddenChecks : CoreM Bool := do
  let raw := Capture.Raw.ofState (Informal.Environment.informalExt.getState (← getEnv))
  let isHiddenFixture (label : Name) := (label.toString (escape := false)).startsWith "hidden."
  let plan := Capture.plan { raw with
    nodes := raw.nodes.filter (isHiddenFixture ·.1)
    facts := raw.facts.filter (isHiddenFixture ·.label) }
  let visible ← Informal.Data.newSorryInspectionSession
  visible.prepare #[`sorryImportComplete]
  unless (← visible.analyzeDeclaration `sorryImportComplete).isProved do
    throwError "Legacy import failed to provide the complete theorem body"
  liftM enableInitializersExecution
  let output ← liftM <| IO.Process.output {
    cmd := "./scripts/lean-low-priority"
    args := #["lake", "-q", "query", "-J", "+VersoBlueprintTests.BlueprintRealizationAdapter:setup"] }
  unless output.exitCode == 0 do throwError "Provider setup failed: {output.stderr}"
  let setup : ModuleSetup ← ofExcept <| Json.parse output.stdout >>= fromJson?
  let env ← liftM <| importModules
    #[{ module := `VersoBlueprintTests.SorryImport.Provider, importAll := false }]
    {} (loadExts := true) (level := .server) (arts := setup.importArts)
  withEnv env <| MetaM.run' <| TermElabM.run' do
    for (name, kind) in #[(`sorryImportComplete, ConstantKind.thm), (`sorryImportAdmitted, .thm),
        (`sorryImportCompleteSpec, .defn), (`sorryImportAdmittedSpec, .defn), (`sorryImportAxiom, .axiom)] do
      let some (.axiomInfo _) := env.checked.get.find? name
        | throwError "Expected a bodyless module view for {name}"
      ensure (getOriginalConstKind? env name == some kind) s!"Missing original kind for {name}"
    let some (.axiomInfo axiomInfo) := env.checked.get.find? `sorryImportAxiom
      | throwError "Missing axiom control"
    let unknown : ConstantInfo := .axiomInfo { axiomInfo with name := `unknownOriginalKind }
    ensure ((NativeLean.rolesForDeclarationKind none true false).isEmpty &&
      (← NativeLean.declarationRoles unknown).isEmpty)
      "An unclassified axiom view must not authorize a statement-only contract"
    -- Even a successful body inspection cannot supply either check when the
    -- original kind is unavailable. Exercise the same constructor as the provider.
    let classification := NativeLean.classifyDeclarationKind none true false
    let unclassified := NativeLean.CheckedDeclaration.ofClassification (witness unknown.name) classification .proved #[]
    ensure (unclassified.kind.isNone && unclassified.roles.isEmpty && unclassified.rolesAgree &&
      unclassified.statement.outcome == .unavailable && unclassified.body.outcome == .unavailable &&
      unclassified.statement.coverage == .subject && unclassified.body.coverage == .subject)
      "Unavailable original kind must withhold both native checks"
    hiddenCapture plan
    let goal ← `(term| True)
    let reused ← NativeLean.checkDeclaration `adapterFixture (witness `sorryImportComplete) (some visible)
    ensure (rejected reused) "Changing the import view must invalidate coverage from the visible body"
    let roots := #[`sorryImportComplete, `sorryImportHiddenHelper, `sorryImportAdmitted,
      `sorryImportAxiom, `sorryImportTypeOnly]
    let unavailableExpectation ← `(term| sorryImportSpec)
    for order in #[roots, roots.reverse] do
      let session ← liftM Informal.Data.newSorryInspectionSession
      NativeLean.prepareDeclarations session (order.map fun name => (`adapterFixture, witness name))
      for name in order do
        let object := witness name
        let isolated ← obtain (← NativeLean.checkDeclaration `adapterFixture object)
        let batched ← obtain (← NativeLean.checkDeclaration `adapterFixture object (some session))
        ensure (batched.status == isolated.status && batched.roles == isolated.roles &&
          batched.statement == isolated.statement && batched.body == isolated.body)
          "Hidden bodies and positive footprints must retain root-specific native observations"
        let isolated ← obtain (← NativeLean.check `adapterFixture object goal)
        let batched ← obtain (← NativeLean.check `adapterFixture object goal (session := some session))
        ensure (batched.status == isolated.status && batched.observation == isolated.observation)
          "A blocked native union changed the independent-goal observation"
      match ← NativeLean.check `adapterFixture (witness `sorryImportComplete) unavailableExpectation
          (session := some session) with
      | .error diagnostic =>
        ensure (diagnostic.code == "unverified-expectation") "A shared session must reject a hidden expectation"
      | .ok _ => throwError "The shared session certified an unavailable expectation"
    let complete ← obtain (← NativeLean.check `adapterFixture (witness `sorryImportComplete) goal)
    let hidden ← obtain (← NativeLean.check `adapterFixture (witness `sorryImportHiddenHelper) goal)
    let admitted ← obtain (← NativeLean.check `adapterFixture (witness `sorryImportAdmitted) goal)
    let axiomResult ← obtain (← NativeLean.check `adapterFixture (witness `sorryImportAxiom) goal)
    let semantics ← NativeLean.newSemanticContext
    let hiddenStatement ← semantics .statement `adapterFixture #[`sorryImportComplete]
    let hiddenImplementation ← semantics .implementation `adapterFixture #[`sorryImportComplete]
    let hiddenDefinition ← semantics .statement `adapterFixture #[`sorryImportSpec]
    ensure (hiddenStatement.isOk && !hiddenImplementation.isOk && !hiddenDefinition.isOk)
      "Hidden proof bodies permit statement identity; hidden computational content does not"
    let ownComplete ← obtain (← NativeLean.checkDeclaration `adapterFixture (witness `sorryImportComplete))
    let ownHidden ← obtain (← NativeLean.checkDeclaration `adapterFixture (witness `sorryImportHiddenHelper))
    ensure (ownComplete.body.outcome == .unavailable && ownHidden.body.outcome == .unavailable &&
      ownComplete.body.coverage == .subject && ownHidden.body.coverage == .subject &&
      ownComplete.status.hasUnverifiedCoverage && ownHidden.status.hasUnverifiedCoverage)
      "Own-declaration checking cannot certify hidden bodies or a cached-empty footprint"
    ensure (complete.observation.outcome == .unavailable && complete.observation.coverage == .subject &&
      complete.status.any (·.isUnverified))
      "Hidden complete body is unverified and cannot claim dependency-closure coverage"
    ensure ((← collectAxioms `sorryImportHiddenHelper).isEmpty &&
      hidden.observation.outcome == .unavailable && hidden.observation.coverage == .subject &&
      hidden.status.any (·.hasUnverifiedCoverage))
      "Cached-empty hidden helper cannot authorize completion"
    ensure (admitted.observation.outcome != .passed && admitted.status.any (·.hasKnownSorry))
      "Hidden admitted body retains positive hole evidence"
    ensure (axiomResult.status.any (·.isAxiomLike) && axiomResult.observation.outcome == .failed)
      "Hidden import distinguishes genuine axiom"
    match ← NativeLean.check `adapterFixture (witness `sorryImportComplete) unavailableExpectation with
    | .error diagnostic =>
      ensure (diagnostic.code == "unverified-expectation") "Hidden expectation dependencies must be rejected"
    | .ok _ => throwError "Unavailable expected-proposition closure cannot authorize matching"
    return true

/-- info: true -/
#guard_msgs in
#eval hiddenChecks

-- Parse-only control for a later import reserving a previously valid field
-- name. The source bytes stay identical; none of these results certify a proof.
private def fieldSource : String := "def owned : Carrier where\n  map := 0\n"

run_cmd liftTermElabM do
  ensure ((← parseSource `owned "parser-control.lean" fieldSource).isOk)
    "Unreserved field-name control did not parse"

section
local syntax:max "[capture-map " "map" "]" : term

run_cmd liftTermElabM do
  match ← parseSource `owned "parser-control.lean" fieldSource with
  | .ok _ => throwError "A newly reserved field name unexpectedly parsed"
  | .error diagnostic =>
    ensure (diagnostic.code == "source-parse-failed" && diagnostic.subject == "owned" &&
      diagnostic.message.contains "2:2" && diagnostic.message.contains "current syntax environment")
      "Parser-context mismatch must retain its source position and unsupported diagnostic"
end

run_cmd liftTermElabM do
  ensure ((← parseSource `owned "parser-control.lean" fieldSource).isOk)
    "Restoring the parser context did not restore parsing of the same original bytes"

-- The imported owning module exercises parser scope independently of the
-- consumer. Every selection uses actual compiled ranges and native metadata.
run_cmd liftTermElabM do
  let path := "tests/VersoBlueprintTests/BlueprintRealizationAdapter/ParserSource.lean"
  let text ← IO.FS.readFile path
  let parse ← NativeSource.newSourceParser
  let select (name : Name) (bytes : String) := NativeSource.selectDocumented
    { project := `adapterFixture, canonical := name
      moduleName := `VersoBlueprintTests.BlueprintRealizationAdapter.ParserSource }
    path (fun _ => pure bytes) parse
  discard <| obtain (← NativeSource.parseSource `RealizationParserFixture path text)
  for (name, format, body) in #[
      (``RealizationParserFixture.Nested.Proofs.opened, `markdown,
        " The parser replays a standalone namespace opening. "),
      (``RealizationParserFixture.Nested.Proofs.scopedOpen, `markdown,
        " The parser replays a standalone scoped opening. "),
      (``RealizationParserFixture.wrappedVariable, `markdown,
        " An own comment, with Unicode 😀 before the name. "),
      (``RealizationParserFixture.sealed, `markdown,
        " The inner declaration owns the original range inside `seal`. "),
      (``RealizationParserFixture.attributed, `markdown,
        " The inner declaration owns the original range inside `attribute`. "),
      (``RealizationParserFixture.verso, `verso, " Verso syntax with *emphasis*. "),
      (``RealizationParserFixture.afterScope, `markdown,
        " The previous parser option is restored to Markdown. ")] do
    let selected ← obtain (← select name text)
    ensure (selected.format == format && selected.rawDocstring == body)
      s!"Scoped selection lost original comment bytes or format: {name}"
  let first := ``RealizationParserFixture.Nested.Proofs.opened
  let edited := text.replace "namespace opening." "namespace closing."
  ensure (edited != text && edited.utf8ByteSize == text.utf8ByteSize) "Expected same-length control"
  match ← select first edited with
  | .error issue => ensure (issue.code == "compiled-docstring-mismatch") s!"Wrong mutation diagnostic: {issue.code}"
  | .ok _ => throwError "A cached parse accepted a same-length edit of the compiled Markdown"
  discard <| obtain (← select first text)

  let malformed := text.replace "True.intro -- parser recovery control" "⦿ -- parser recovery control"
  ensure (malformed != text && !(← NativeSource.parseSource first path malformed).isOk)
    "Malformed command did not exercise parser recovery"
  let damaged := ``RealizationParserFixture.damaged
  match ← select damaged malformed with
  | .error issue =>
    ensure (issue.code == "source-parse-failed" && issue.subject == damaged.toString)
      "A cached failure must refer to its own selection"
  | .ok _ => throwError "Recovered partial command was accepted as the selected declaration"
  discard <| obtain (← select first malformed)
  discard <| obtain (← select ``RealizationParserFixture.afterRecovery malformed)

  let uncertain := malformed ++ "\nattribute [«inherit_doc» True.intro] ???\n"
  match ← select first uncertain with
  | .error issue =>
    ensure (issue.code == "source-parse-failed" && issue.message.contains "inherit_doc")
      "Malformed source with possible inheritance must fail conservatively"
  | .ok _ => throwError "Parser recovery hid a possible inheritance application"

end VersoBlueprintTests.BlueprintRealizationAdapter
