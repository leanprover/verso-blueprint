/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.NativeSource
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

private def proofKey (p : PreparedModel) : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩

-- Direct owning-source preparation does not need a Blueprint node or enrollment.
-- These are actual imported declarations/source bytes; native checking and model
-- admission remain separate operations, rather than facts invented by lookup.
run_cmd liftTermElabM do
  let before ← Informal.Environment.stagedAuthoring
  let request : NativeSource.Request := {
    project := `adapterFixture
    canonical := `RealizationAdapterFixture.identityInvolutive
    moduleName := `VersoBlueprintTests.BlueprintRealizationAdapter.Provider
    sourcePath := "tests/VersoBlueprintTests/BlueprintRealizationAdapter/Provider.lean" }
  ensure ((← Informal.Environment.labelsForLeanDecl request.canonical).isEmpty)
    "Direct source control must use an unenrolled declaration"
  let source ← obtain (← NativeSource.prepare request)
  let changedQueryOptions ← withOptions (fun options =>
      (options.set `maxHeartbeats (123456 : Nat)).setBool `pp.universes true) <|
    NativeLean.semanticContext request.project #[request.canonical]
  let changedQueryOptions ← obtain changedQueryOptions
  ensure (source.semanticContext == some changedQueryOptions)
    "Query-site display/budget options cannot change the meaning of an already checked declaration"
  ensure (source.canonical == request.canonical && source.declaration == witness request.canonical &&
    source.moduleName == request.moduleName && source.document.key.path == request.sourcePath &&
    source.document.text == (← IO.FS.readFile request.sourcePath) && source.semanticContext.isSome)
    "Direct source must preserve typed identity, exact owning bytes and current semantic inputs"
  -- Parser-boundary injection only, not successful proof/provider evidence:
  -- unrelated later syntax need not parse to locate an already checked native
  -- declaration. The original whole text is retained, and both ranges still bind.
  let tailInput := source.document.text ++ "\nsyntax \"sourceTailCommand\" : command\nsourceTailCommand\n"
  let boundedSource ← obtain (← NativeSource.prepare request (fun _ => pure tailInput))
  ensure (boundedSource.document.text == tailInput && boundedSource.ranges.range == source.ranges.range &&
    boundedSource.ranges.selectionRange == source.ranges.selectionRange)
    "Native prefix association must preserve whole source bytes and exact checked ranges"
  ensure (!(← NativeSource.parseSource request.canonical request.sourcePath tailInput).isOk)
    "Control tail must require unsupported parser context"
  let documentedTail ← NativeSource.prepareDocumented
    { request with canonical := `RealizationAdapterFixture.number } (fun _ => pure tailInput)
  match documentedTail with
  | .error diagnostic =>
    ensure (diagnostic.code == "source-parse-failed")
      "Docstring association must still inspect the whole source for later inheritance"
  | .ok _ => throwError "Native prefix shortcut leaked into docstring association"
  for result in #[
      ← NativeSource.prepare request (fun _ => pure ("\n" ++ source.document.text)),
      ← NativeSource.prepare { request with selectionRange? := some {
        source.ranges.selectionRange with charUtf16 := source.ranges.selectionRange.charUtf16 + 1 } },
      ← NativeSource.prepare request (fun _ => pure "import Lean\n#broken_before_declaration\n")] do
    ensure (!result.isOk) "Prefix parsing weakened exact owning declaration/name-range guards"
  let nativeOrigin : Informal.Realizations.Origin := {
    id := `undocumentedSource, moduleName := request.moduleName, source := request.sourcePath }
  let nativeOnly ← obtain (source.realizeNative nativeOrigin
    { label := `undocumentedNative, title := "Undocumented native source" } `implementation)
  let nativeOnly ← obtain (admit nativeOnly)
  ensure (nativeOnly.realizations.size == 1 && nativeOnly.documents.size == 1 &&
    nativeOnly.evidence.isEmpty && nativeOnly.requirements.isEmpty)
    "Undocumented native model must not fabricate a prose realization or proof contract"
  let noDoc ← NativeSource.prepareDocumented request
  match noDoc with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-docstring") "Undocumented source is not prose"
  | .ok _ => throwError "Undocumented declaration borrowed a nearby docstring"
  let definition ← obtain (← NativeSource.prepare { request with canonical := `RealizationAdapterFixture.Reflexivity })
  ensure (definition.canonical == `RealizationAdapterFixture.Reflexivity && definition.semanticContext.isSome)
    "A checked definition has native source without an artificial theorem/prose contract"
  let documented ← obtain (← NativeSource.prepareDocumented { request with canonical := `RealizationAdapterFixture.number })
  ensure (documented.format == `markdown && documented.rawDocstring == " An unsupported definition. ")
    "Direct owning documentation supports definitions without a legacy theorem-only node gate"
  let directLabel := Name.mkSimple "native.direct.definition"
  ensure ((← Informal.Environment.getNode? directLabel).isNone)
    "Direct model control must have no old node to project"
  let origin : Informal.Realizations.Origin := {
    id := `directSource, moduleName := request.moduleName, source := request.sourcePath }
  let nativeKey : RealizationKey := ⟨directLabel, `implementation⟩
  let proseKey : RealizationKey := ⟨directLabel, `description⟩
  let concept : Informal.Realizations.Node := {
    label := directLabel, title := "A direct native definition", kind := .definition }
  let model ← obtain (documented.realize origin concept nativeKey.name proseKey.name)
  let r ← obtain (admit model.input)
  ensure (model.origin == origin && model.leanKey == nativeKey && model.informalKey == proseKey &&
    r.nodes == #[concept] && r.evidence.isEmpty && r.requirements.isEmpty && r.realizations.size == 2 &&
    (r.resultFor (.realization nativeKey)).status == .unassessed &&
    (r.resultFor (.realization proseKey)).status == .unassessed)
    "Direct model preparation preserves explicit destinations/origin and invents no checking or prose assessment"
  ensure (r.realizations.any (fun realization => realization.key == nativeKey &&
    realization.facets.any (·.name == `body) && !realization.facets.any (·.name == `proof)))
    "A definition's native body must not be presented as a theorem proof"
  ensure (rejected (documented.realize origin concept nativeKey.name nativeKey.name) &&
    rejected (documented.realize origin { concept with label := .anonymous } nativeKey.name proseKey.name) &&
    rejected (documented.realize { origin with moduleName := `WrongOwner } concept nativeKey.name proseKey.name))
    "Source model destinations and owning producer must be explicit and consistent"
  let neighbor ← obtain (← NativeSource.prepareDocumented { request with canonical := `RealizationAdapterFixture.neighboringComment })
  ensure (neighbor.format == `verso && neighbor.rawDocstring == " Même *texte* 😀 λ with {name}`Nat`. ")
    "Own unregistered Verso comment preserves exact supplementary Unicode bytes"
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
  let unreadable ← NativeSource.prepare request (fun _ => throw <| IO.userError "injected unavailable source")
  match unreadable with
  | .error diagnostic => ensure (diagnostic.code == "source-unavailable") "No source-I/O fallback"
  | .ok _ => throwError "Direct source manufactured readable bytes"
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
  let q := proofKey p
  let input : Input := { p.input with
    objects := p.input.objects ++ sibling.input.objects
    realizations := p.input.realizations.map fun record =>
      if record.value.key != p.leanKey then record else
        { record with value := { record.value with declarations := #[
          { object := p.witness, required := #[q] },
          { object := sibling.witness, required := #[q] }] } }
    requirements := #[p.contribution `nativeRequirement {
      key := q, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }] }
  match admit input with
  | .error issues =>
    ensure (issues.any (·.code == "wrong-declaration-subject"))
      "Sibling requirement borrowing must be rejected at admission"
  | .ok _ => throwError "Sibling declaration borrowed another declaration's native requirement"
  let facetKey : RequirementKey := ⟨.facet p.leanKey `proof, `proof⟩
  let facetOnly := { input with
    requirements := #[p.contribution `facetNativeRequirement {
      key := facetKey, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }]
    realizations := input.realizations.map fun record =>
      if record.value.key != p.leanKey then record else
        { record with value := { record.value with declarations := record.value.declarations.map fun decl =>
          { decl with required := #[facetKey] } } } }
  match admit facetOnly with
  | .error issues => ensure (issues.any (·.code == "wrong-native-subject")) "Native checks need declaration subjects"
  | .ok _ => throwError "Native check escaped declaration identity through a broad facet contract"
  let jointKey : RequirementKey := ⟨.realization p.leanKey, `jointReview⟩
  let joint := { input with
    requirements := #[p.contribution `jointReviewRequirement { key := jointKey, expected := .review `jointReview }]
    realizations := input.realizations.map fun record =>
      if record.value.key != p.leanKey then record else
        { record with value := { record.value with declarations := record.value.declarations.map fun decl =>
          { decl with required := #[jointKey] } } } }
  discard <| obtain (admit joint)
  let siblingKey : RequirementKey := ⟨.declaration p.leanKey sibling.witness, `proof⟩
  let input := { input with
    realizations := input.realizations.map fun record =>
      if record.value.key != p.leanKey then record else
        { record with value := { record.value with
          declarations := #[{ object := p.witness, required := #[q] },
            { object := sibling.witness, required := #[siblingKey] }]
          facets := record.value.facets.map fun facet => { facet with required := #[q] } } }
    requirements := input.requirements.push (p.contribution `siblingRequirement {
      key := siblingKey, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }) }
  let r ← obtain (admit input)
  let some firstBinding := r.bindingFor q | throwError "Missing first binding"
  let some siblingBinding := r.bindingFor siblingKey | throwError "Missing sibling binding"
  let withFirst := { input with evidence := #[p.contribution `firstNative {
    id := `actualFirstDeclaration, requirement := q, binding := firstBinding, observation := .check own.body }] }
  let r ← obtain (admit withFirst)
  ensure ((r.resultFor (.facet p.leanKey `statement)).complete &&
    (r.resultFor (.facet p.leanKey `proof)).complete &&
    !(r.resultFor (.declaration p.leanKey sibling.witness)).complete &&
    !(r.resultFor (.realization p.leanKey)).complete)
    "One declaration can serve its own facets, without completing its sibling or the group"
  let borrowed := { withFirst with evidence := withFirst.evidence.push (p.contribution `wrongNative {
    id := `borrowedFirstObservation, requirement := siblingKey, binding := siblingBinding
    observation := .check own.body }) }
  let r ← obtain (admit borrowed)
  ensure ((r.localResult siblingKey).diagnostics.any (·.code == "wrong-check-object") &&
    !(r.resultFor (.declaration p.leanKey sibling.witness)).complete)
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

private def assertPendingCorrespondence (p : PreparedModel) (input : Input) (expected : Syntax)
    (interpretation : String) : TermElabM Unit := do
  -- An explicitly authored correspondence still needs its own review.
  let t : TranslationKey := ⟨`adapterFixture, `docstringToLean⟩
  let c : ClaimKey := ⟨t, `statement⟩
  let review : RequirementKey := ⟨.claim c, `review⟩
  let linked := { input with
    translations := #[p.contribution `translation {
      key := t
      source := #[{ realization := p.informalKey, facets := #[`statement] }],
      target := #[{ realization := p.leanKey, facets := #[`statement] }],
      required := #[proofKey p] }]
    claims := #[p.contribution `claim {
      key := c, interpretation
      required := #[review] }]
    requirements := input.requirements.push (p.contribution `review {
      key := review, expected := .review `statementCorrespondence }) }
  -- Recheck the native proof for the newly authored connected contract;
  -- no human review observation is supplied.
  let linkedRegistry ← obtain (admit { linked with evidence := #[] })
  let some binding := linkedRegistry.bindingFor (proofKey p) | throwError "missing binding"
  let fresh ← obtain (← NativeLean.check `adapterFixture p.witness expected
    (p.input.objects.filterMap (·.value.document)))
  let linked := { linked with evidence := #[p.contribution `proofEvidence {
    id := p.leanKey.node ++ `nativeProof, requirement := proofKey p, binding
    observation := .proof fresh.observation }] }
  let linkedRegistry ← obtain (admit linked)
  ensure ((linkedRegistry.resultForRequirement (proofKey p)).complete) "Actual proof stays complete"
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
  let some accepted ← Informal.Environment.getNode? (Name.mkSimple "adapter.nonroundtrip")
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
  let before ← Informal.Environment.getNode? label
  let some accepted := before | throwError "Missing actual accepted Unicode theorem"
  let association := (accepted.nativeRefsOn `statement)[0]!
  ensure (association.range?.isNone && association.selectionRange?.isNone)
    "Ordinary attribute snapshot predates native range registration"
  let p ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture label `RealizationAdapterFixture.«état😀»)
  ensure (p.docstringFormat == `verso && p.input.documents[1]!.value.key.context.language == `verso)
    "Own native format metadata must select Verso"
  ensure (p.input.documents[1]!.value.text == " Même *texte* 😀 λ with {name}`Nat`. ")
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
  ensure (raw == p.input.documents[1]!.value.text) "Exact owning-source association"
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
  let after ← Informal.Environment.getNode? label
  ensure (reprStr before == reprStr after) "Verso projection/checking preserves accepted state"
  -- Current consumer settings must not relabel already authored own Markdown.
  let markdown ← withOptions (fun opts => opts.setBool `doc.verso true) <|
    RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.reflexivity") `RealizationAdapterFixture.reflexivity
  let markdown ← obtain markdown
  ensure (markdown.docstringFormat == `markdown &&
    markdown.input.documents[1]!.value.text == " Every natural number equals itself. Raw Markdown, with **emphasis**. ")
    "Markdown retains its exact own raw body and native format"
  let basic ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.verso") `RealizationAdapterFixture.versoDocstring)
  ensure (basic.input.documents[1]!.value.text == " An own *Verso* docstring with {name}`Nat` and é 😀. ")
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
  let malformed ← RealizationAdapterFixture.prepareModel `adapterFixture (Name.mkSimple "adapter.verso") `RealizationAdapterFixture.versoDocstring
    (fun _ => pure "import Lean\n/-- unterminated source")
  match malformed with
  | .error diagnostic => ensure (diagnostic.code == "source-parse-failed") "Malformed source is explicit"
  | .ok _ => throwError "Malformed source must not borrow a native-rendered docstring"
  let standalone := "import Lean\n/-- own -/ theorem t : True := True.intro\nattribute [inherit_doc True.intro] t\n"
  let commands ← obtain (← parseSource `standalone "<injected-source>" standalone)
  match docCommentAtRanges `standalone standalone default default commands with
  | .error diagnostic => ensure (diagnostic.code == "inherited-docstring") "Standalone inheritance is diagnosed"
  | .ok _ => throwError "Standalone inheritance cannot silently override own-source provenance"

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
  ensure (p.docstringFormat == `verso && p.input.documents[1]!.value.text ==
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
  let before ← Informal.Environment.getNode? label
  let labels ← Informal.Environment.labelsForLeanDecl `RealizationAdapterFixture.reflexivity
  let some accepted := before | throwError "Missing actual accepted metadata"
  let p ← obtain (← RealizationAdapterFixture.prepareModel `adapterFixture label
    `RealizationAdapterFixture.reflexivity (metadata := accepted.toNodeMetadata))
  ensure (p.input.nodes.any fun contribution => contribution.value.label == label &&
    contribution.value.toNodeMetadata == accepted.toNodeMetadata)
    "Current source model must preserve the exact accepted concept metadata"
  ensure (p.docstringFormat == `markdown && p.input.realizations.size == 2) "Expected raw Markdown and Lean realizations"
  let source ← liftM <| IO.FS.readFile p.sourcePath
  ensure (p.witness == witness `RealizationAdapterFixture.reflexivity &&
    p.moduleName == `VersoBlueprintTests.BlueprintRealizationAdapter.Provider &&
    p.input.documents[0]!.value.text == source &&
    p.input.documents[1]!.value.text.contains "**emphasis**")
    "Canonical source, module, qualified declaration and raw Markdown must survive projection"
  ensure (p.input.translations.isEmpty && p.input.evidence.isEmpty && p.input.requirements.isEmpty)
    "Projection must not invent validation or correspondence"
  let initial ← obtain (admit p.input)
  ensure ((initial.resultFor (.realization p.informalKey)).status == .unassessed) "Prose is not proofread"
  let expected ← `(term| ∀ n : Nat, n = n)
  let semanticDiagnostic : Diagnostic := {
    code := "semantic-context-unavailable", subject := "standalone-check"
    message := "Injected standalone semantic-context failure" }
  let failingSemantics : NativeLean.SemanticContext := fun _ _ => pure (.error semanticDiagnostic)
  let prepared ← p.prepareValidation expected #[] failingSemantics
  let .ok (_, checked) := prepared | throwError "Standalone source validation unexpectedly failed"
  ensure (checked.semanticContext.isNone && checked.semanticDiagnostics == #[semanticDiagnostic])
    "Standalone source validation did not retain semantic-context diagnostics"
  let input ← obtain (← p.validate expected)
  let r ← obtain (admit input)
  ensure ((r.resultForRequirement (proofKey p)).complete) "Actual imported proof must complete"
  ensure ((r.resultFor (.facet p.leanKey `proof)).complete) "Shared proof facet must complete"
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
  let after ← Informal.Environment.getNode? label
  ensure (reprStr before == reprStr after &&
    labels == (← Informal.Environment.labelsForLeanDecl `RealizationAdapterFixture.reflexivity))
    "Read/check must preserve accepted node/declaration membership"

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

-- Reuse #497's actual module-system fixture. A legacy import exposes bodies;
-- dynamically import the same module at ordinary visibility to test unavailable
-- coverage through this provider, including a cached-empty-footprint control.
private unsafe def hiddenChecks : CoreM Bool := do
  liftM enableInitializersExecution
  let output ← liftM <| IO.Process.output {
    cmd := "./scripts/lean-low-priority"
    args := #["lake", "-q", "query", "-J", "+VersoBlueprintTests.BlueprintRealizationAdapter:setup"] }
  unless output.exitCode == 0 do throwError "Provider setup failed: {output.stderr}"
  let setup : ModuleSetup ← ofExcept <| Json.parse output.stdout >>= fromJson?
  let env ← liftM <| importModules
    #[{ module := `VersoBlueprintTests.SorryImport.Provider, importAll := false }]
    {} (loadExts := true) (level := .exported) (arts := setup.importArts)
  withEnv env <| MetaM.run' <| TermElabM.run' do
    let goal ← `(term| True)
    let complete ← obtain (← NativeLean.check `adapterFixture (witness `sorryImportComplete) goal)
    let hidden ← obtain (← NativeLean.check `adapterFixture (witness `sorryImportHiddenHelper) goal)
    let admitted ← obtain (← NativeLean.check `adapterFixture (witness `sorryImportAdmitted) goal)
    let axiomResult ← obtain (← NativeLean.check `adapterFixture (witness `sorryImportAxiom) goal)
    let ownComplete ← obtain (← NativeLean.checkDeclaration `adapterFixture (witness `sorryImportComplete))
    let ownHidden ← obtain (← NativeLean.checkDeclaration `adapterFixture (witness `sorryImportHiddenHelper))
    ensure (ownComplete.body.outcome == .unavailable && ownHidden.body.outcome == .unavailable &&
      ownComplete.body.coverage == .subject && ownHidden.body.coverage == .subject &&
      ownComplete.status.hasUnverifiedCoverage && ownHidden.status.hasUnverifiedCoverage)
      "Own-declaration checking cannot certify hidden bodies or a cached-empty footprint"
    ensure (complete.observation.outcome == .unavailable && complete.status.any (·.isUnverified))
      "Hidden complete body is unverified, not a certificate"
    ensure ((← collectAxioms `sorryImportHiddenHelper).isEmpty &&
      hidden.observation.outcome == .unavailable && hidden.status.any (·.hasUnverifiedCoverage))
      "Cached-empty hidden helper cannot authorize completion"
    ensure (admitted.observation.outcome != .passed && admitted.status.any (·.hasKnownSorry))
      "Hidden admitted body retains positive hole evidence"
    ensure (axiomResult.status.any (·.isAxiomLike) && axiomResult.observation.outcome == .failed)
      "Hidden import distinguishes genuine axiom"
    let unavailableExpectation ← `(term| sorryImportSpec)
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

end VersoBlueprintTests.BlueprintRealizationAdapter
