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

-- Direct native preparation does not need a Blueprint node or enrollment.
-- These are actual imported declarations; native checking and model admission
-- remain separate operations, rather than facts invented by lookup. A plain
-- declaration and its own documentation are prepared from the environment.
run_cmd liftTermElabM do
  let before ← Informal.Environment.stagedAuthoring
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
  let disagreeing ← NativeSource.prepare { request with selectionRange? := some {
    source.ranges.selectionRange with charUtf16 := source.ranges.selectionRange.charUtf16 + 1 } }
  ensure (!disagreeing.isOk) "A recorded snapshot range disagreeing with the environment was accepted"
  ensure (source.roles == #[`statement, `proof])
    "Undocumented theorem must retain its intrinsic statement and proof roles"
  let noDoc ← NativeSource.prepareDocumented request
  match noDoc with
  | .error diagnostic => ensure (diagnostic.code == "unsupported-docstring") "Undocumented source is not prose"
  | .ok _ => throwError "Undocumented declaration borrowed a nearby docstring"
  let definition ← obtain (← NativeSource.prepare { request with canonical := `RealizationAdapterFixture.Reflexivity })
  ensure (definition.canonical == `RealizationAdapterFixture.Reflexivity &&
      definition.semanticContext.isSome && definition.roles == #[`statement])
    "A proposition definition supplies statement content without an artificial proof role"
  let documented ← obtain (← NativeSource.prepareDocumented
    { request with canonical := `RealizationAdapterFixture.number })
  ensure (documented.format == `markdown && documented.content == "An unsupported definition. " &&
      documented.toPrepared.roles == #[`implementation])
    "Compiled Markdown source must support definitions"
  let moduleIdx ← match (← getEnv).getModuleIdxFor? request.canonical with
    | some index => pure index
    | none => throwError "Missing imported package identity"
  let some package := (← getEnv).getModulePackageByIdx? moduleIdx
    | throwError "Missing imported package identity"
  let documentedRequest := { request with canonical := `RealizationAdapterFixture.versoDocstring }
  let verso ← obtain (← NativeSource.prepareDocumented { documentedRequest with package? := some package })
  ensure (verso.format == `verso && verso.content.contains "é 😀" &&
    verso.content.contains (Vir.nameKey ``Lean.Doc.Data.Const) && verso.content.contains (Vir.nameKey ``Lean.Doc.Data.LeanTerm) &&
    verso.content.contains (Vir.nameKey ``Lean.Doc.Data.Atom))
    "Compiled Verso must retain the name, term and keyword payloads"
  match ← NativeSource.prepareDocumented { documentedRequest with package? := some "wrong-package" } with
  | .error diagnostic => ensure (diagnostic.code == "source-association-unavailable") "Wrong package diagnostic"
  | .ok _ => throwError "Docstring preparation accepted an unrelated compiled package"
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
  ensure (decide (before = (← Informal.Environment.stagedAuthoring)))
    "Source preparation must not enroll declarations or persist semantic observations"

-- A real passing check of the first theorem must not complete its admitted
-- sibling merely by sharing a required key.
run_cmd liftTermElabM do
  let first ← obtain (← RealizationAdapterFixture.prepareOwnDocstring
    `adapterFixture `RealizationAdapterFixture.reflexivity)
  let sibling ← obtain (← RealizationAdapterFixture.prepareOwnDocstring
    `adapterFixture `RealizationAdapterFixture.admitted)
  let own ← obtain (← NativeLean.checkDeclaration `adapterFixture first.declaration)
  let admitted ← obtain (← NativeLean.checkDeclaration `adapterFixture sibling.declaration)
  ensure (own.body.outcome == .passed && admitted.body.outcome == .failed)
    "Borrowing control requires real passing and admitted declarations"
  let firstKey : RealizationKey := ⟨`first, `lean⟩
  let siblingKey : RealizationKey := ⟨`sibling, `lean⟩
  let firstProof := firstKey.forRole `proof
  let siblingProof := siblingKey.forRole `proof
  let q : RequirementKey := ⟨.declaration firstProof first.declaration, `proof⟩
  let siblingCheck : RequirementKey := ⟨.declaration siblingProof sibling.declaration, `proof⟩
  let record {α : Type} (id : Name) (value : α) : Contribution α :=
    { origin := { id, moduleName := first.moduleName, source := s!"module:{first.moduleName}" }, value }
  let input : Input := {
    nodes := #[record `firstNode { label := firstKey.node, title := "First" },
      record `siblingNode { label := siblingKey.node, title := "Sibling" }]
    objects := #[record `firstObject { key := first.declaration, resolution := .resolved },
      record `siblingObject { key := sibling.declaration, resolution := .resolved }]
    realizations := #[
      record `firstStatement {
        key := firstKey.forRole `statement, context := first.declaration.context, role := `statement
        declarations := #[{ object := first.declaration, projection := .statement }] },
      record `firstProof {
        key := firstProof, context := first.declaration.context, role := `proof
        declarations := #[{ object := first.declaration, required := #[q] }] },
      record `siblingProof {
        key := siblingProof, context := sibling.declaration.context, role := `proof
        declarations := #[{ object := sibling.declaration, required := #[q] }] }]
    requirements := #[
      record `nativeRequirement {
        key := q, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure },
      record `siblingRequirement {
        key := siblingCheck, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure }]
    bindingInputs := first.semanticContext.toArray.map (fun content => record `firstContext {
      subject := q.subject, name := NativeLean.sourceContext, content }) ++
      sibling.semanticContext.toArray.map (fun content => record `siblingContext {
        subject := siblingCheck.subject, name := NativeLean.sourceContext, content }) }
  match admit input with
  | .error issues =>
    ensure (issues.any (·.code == "wrong-declaration-subject"))
      "Sibling requirement borrowing must be rejected at admission"
  | .ok _ => throwError "Sibling declaration borrowed another declaration's native requirement"
  let realizationCheck : RequirementKey := ⟨.realization firstProof, `broadCheck⟩
  let broadOnly := { input with
    requirements := input.requirements.push (record `broadNativeRequirement {
      key := realizationCheck, expected := .check NativeLean.bodyValidator, coverage := .dependencyClosure })
    realizations := input.realizations.map fun entry =>
      if entry.value.key != firstProof then entry else
        { entry with value := {
          entry.value with
          required := #[realizationCheck]
          declarations := entry.value.declarations.map fun decl => { decl with required := #[] }
        } } }
  match admit broadOnly with
  | .error issues => ensure (issues.any (·.code == "wrong-native-subject")) "Native checks need declaration subjects"
  | .ok _ => throwError "Native check escaped declaration identity through a realization-wide contract"
  let validInput := { input with
    realizations := input.realizations.map fun entry =>
      if entry.value.key == siblingProof then
        { entry with value := { entry.value with declarations := entry.value.declarations.map fun decl =>
          { decl with required := #[siblingCheck] } } }
      else entry }
  let jointKey : RequirementKey := ⟨.realization firstProof, `jointReview⟩
  let joint := { validInput with
    requirements := input.requirements.push (record `jointReviewRequirement {
      key := jointKey, expected := .review `jointReview `MockReviewer })
    realizations := validInput.realizations.map fun entry =>
      if entry.value.key != firstProof then entry else
        { entry with value := { entry.value with required := #[jointKey] } } }
  discard <| obtain (admit joint)
  let r ← obtain (admit validInput)
  let some firstBinding := r.bindingFor q | throwError "Missing first binding"
  let some siblingBinding := r.bindingFor siblingCheck | throwError "Missing sibling binding"
  let withFirst := { validInput with evidence := #[
    record `firstNative {
      id := `actualFirstDeclaration, requirement := q, binding := firstBinding,
      observation := .check own.body },
    record `siblingNative {
      id := `actualSiblingDeclaration, requirement := siblingCheck, binding := siblingBinding,
      observation := .check admitted.body }] }
  let r ← obtain (admit withFirst)
  let some statementModel := r.realization? (firstKey.forRole `statement)
    | throwError "The declaration lost its separate statement realization"
  ensure (statementModel.role == `statement && statementModel.declarations[0]!.projection == .statement &&
    (r.resultFor (.realization firstProof)).complete &&
    !(r.resultFor (.declaration siblingProof sibling.declaration)).complete)
    "One declaration keeps separate statement/proof roles without completing its sibling"
  let borrowed := { withFirst with evidence := withFirst.evidence.push (record `wrongNative {
    id := `borrowedFirstObservation, requirement := siblingCheck, binding := siblingBinding
    observation := .check own.body }) }
  let r ← obtain (admit borrowed)
  ensure ((r.localResult siblingCheck).diagnostics.any (·.code == "wrong-check-object") &&
    !(r.resultFor (.declaration siblingProof sibling.declaration)).complete)
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

-- Native identity must either survive serialization or fail explicitly. These
-- are actual checked/imported declarations, not fake successful observations.
run_cmd liftTermElabM do
  let trueGoal ← `(term| True)
  let escaped := Name.str `RealizationAdapterFixture "with.dot"
  let documented ← obtain (← RealizationAdapterFixture.prepareOwnDocstring `adapterFixture escaped)
  ensure (documented.declaration.native.toName == escaped) "Escaped dotted name preserves typed identity"
  let checked ← obtain (← NativeLean.check `adapterFixture documented.declaration trueGoal)
  ensure (checked.observation.outcome == .passed) "Ordinary escaped dotted witness remains supported"
  let unusual := Name.str `RealizationAdapterFixture "bad»name"
  ensure (((← getEnv).checked.get.find? unusual).isSome && unusual.toString.toName != unusual)
    "Regression must use a present checked theorem whose name cannot round-trip"
  let some accepted ← Informal.Environment.getNodeInventory? (Name.mkSimple "adapter.nonroundtrip")
    | throwError "Regression requires a real accepted attribute association"
  ensure ((accepted.nativeRefsOn `statement).any (·.canonical == unusual)) "Accepted association retains original typed name"
  match ← RealizationAdapterFixture.prepareOwnDocstring `adapterFixture unusual with
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
  let documented ← obtain (← RealizationAdapterFixture.prepareOwnDocstring
    `adapterFixture `RealizationAdapterFixture.«état😀»)
  ensure (documented.format == `verso)
    "Own native format metadata must select Verso"
  ensure (documented.content.contains "texte" && documented.content.contains "😀 λ" &&
    documented.content.contains (Vir.nameKey ``Lean.Doc.Data.Const))
    "Exact own source body includes authored whitespace, markup and Unicode"
  ensure (documented.moduleName == `VersoBlueprintTests.BlueprintRealizationAdapter.Provider &&
    documented.declaration == witness (Name.str `RealizationAdapterFixture "état😀"))
    "Imported source belongs to the accepted declaration, not consumer or neighboring comment"
  let some ranges ← findDeclarationRanges? documented.canonical | throwError "Missing actual native ranges"
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
  let after ← Informal.Environment.getNodeInventory? label
  ensure (reprStr before == reprStr after) "Verso source selection preserves accepted state"
  -- Current consumer settings do not relabel already authored docstrings.
  let markdown ← withOptions (fun opts => opts.setBool `doc.verso true) <|
    RealizationAdapterFixture.prepareOwnDocstring `adapterFixture `RealizationAdapterFixture.reflexivity
  let markdown ← obtain markdown
  ensure (markdown.format == `markdown &&
    markdown.content == "Every natural number equals itself. Raw Markdown, with **emphasis**. ")
    "Markdown retains its exact own raw body and native format"

run_cmd liftTermElabM do
  for (label, canonical, code) in #[("adapter.inherited", `RealizationAdapterFixture.inheritedDocstring, "unsupported-docstring"),
      ("adapter.own.inherited", `RealizationAdapterFixture.ownInheritedDocstring, "inherited-docstring"),
      ("adapter.ambiguous", `RealizationAdapterFixture.ambiguousFormat, "ambiguous-docstring"),
      ("adapter.synthetic", `RealizationAdapterFixture.syntheticDoc, "source-association-unavailable")] do
    match ← RealizationAdapterFixture.prepareOwnDocstring `adapterFixture canonical with
    | .error diagnostic =>
      ensure (diagnostic.code == code)
        s!"{label}: expected {code}, got {diagnostic.code}"
    | .ok _ => throwError "Unsupported source association must not fall back to another comment"
run_cmd liftTermElabM do
  let documented ← obtain (← RealizationAdapterFixture.prepareOwnDocstring
    `adapterFixture `RealizationAdapterFixture.noOriginalComment)
  ensure (documented.format == `markdown &&
    documented.content == "Injected metadata is not an original modifier comment.")
    "A direct compiled docstring needs no literal source comment"

-- Exercise the pilot's actual involution and package-specific statements, beyond
-- reflexivity/True. These are native current-build controls, not foreign proof
-- observations, correspondence reviews, or a second mapping database.
run_cmd liftTermElabM do
  let documented ← obtain (← RealizationAdapterFixture.prepareOwnDocstring
    `adapterFixture `RealizationAdapterFixture.flagInvolutive)
  let expected ← `(term| ∀ flag : RealizationAdapterFixture.Flag,
    RealizationAdapterFixture.toggle (RealizationAdapterFixture.toggle flag) = flag)
  let checked ← obtain (← NativeLean.check `adapterFixture documented.declaration expected)
  ensure (checked.observation.outcome == .passed) "Actual two-case involution must complete"
  ensure (documented.format == `verso && documented.content.contains "two-state" &&
    documented.content.contains "é 😀" && documented.content.contains "Flag")
    "The compiled Flag account retains its structure, Unicode and name link"
  let selectedPackage ← `(term| RealizationAdapterFixture.Involutive RealizationAdapterFixture.togglePackage)
  let selected ← obtain (← NativeLean.check `adapterFixture documented.declaration selectedPackage)
  ensure (selected.observation.outcome == .passed) "Selected package alias must match"
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
  let wrongPackage ← obtain (← NativeLean.check `adapterFixture documented.declaration identityGoal)
  ensure (wrongPackage.observation.outcome == .failed)
    "A proof for the selected toggle package cannot be relabeled as identity-package evidence"

-- Standalone owned-source reads and native checks preserve accepted membership.
run_cmd liftTermElabM do
  let label := Name.mkSimple "adapter.reflexivity"
  let before ← Informal.Environment.getNodeInventory? label
  let labels ← Informal.Environment.labelsForLeanDecl `RealizationAdapterFixture.reflexivity
  ensure before.isSome "Missing actual accepted metadata"
  let documented ← obtain (← RealizationAdapterFixture.prepareOwnDocstring
    `adapterFixture `RealizationAdapterFixture.reflexivity)
  ensure (documented.format == `markdown && documented.roles == #[`statement, `proof] &&
    documented.declaration == witness `RealizationAdapterFixture.reflexivity &&
    documented.moduleName == `VersoBlueprintTests.BlueprintRealizationAdapter.Provider &&
    documented.content.contains "**emphasis**")
    "Standalone source preserves the exact roles, owner and Markdown"
  let expected ← `(term| ∀ n : Nat, n = n)
  let semanticDiagnostic : Diagnostic := {
    code := "semantic-context-unavailable", subject := "standalone-check"
    message := "Injected standalone semantic-context failure" }
  let scopes ← IO.mkRef (#[] : Array ContentScope)
  let failingSemantics : NativeLean.SemanticContext := fun scope _ _ => do
    scopes.modify (·.push scope)
    return .error semanticDiagnostic
  let checked ← obtain (← NativeLean.check `adapterFixture documented.declaration expected #[] failingSemantics)
  ensure ((← scopes.get) == #[.implementation] &&
    checked.semanticContext.isNone && checked.semanticDiagnostics == #[semanticDiagnostic])
    "Independent proof checking must retain only its requested implementation descriptor diagnostics"
  let checked ← obtain (← NativeLean.check `adapterFixture documented.declaration expected)
  ensure (checked.observation.outcome == .passed) "Actual imported proof must complete"
  let alias ← `(term| RealizationAdapterFixture.Reflexivity)
  let aliasChecked ← obtain (← NativeLean.check `adapterFixture documented.declaration alias)
  ensure (aliasChecked.observation.outcome == .passed && aliasChecked.goal != checked.goal)
    "Definitionally equal expected propositions can have distinct structural identities"
  let wrong ← `(term| False)
  let wrongChecked ← obtain (← NativeLean.check `adapterFixture documented.declaration wrong)
  ensure (wrongChecked.observation.outcome == .failed &&
    wrongChecked.observation.explanation.startsWith "wrong-proposition:")
    "Wrong expected proposition must fail for its actual checked type"
  let _ ← obtain (← RealizationAdapterFixture.prepareOwnDocstring
    `adapterFixture `RealizationAdapterFixture.reflexivity)
  let after ← Informal.Environment.getNodeInventory? label
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
    let _ ← obtain (← RealizationAdapterFixture.prepareOwnDocstring `adapterFixture canonical)
  for canonical in #[`RealizationAdapterFixture.undocumented,
      `RealizationAdapterFixture.notPresent, `RealizationAdapterFixture.inheritedDocstring] do
    ensure (rejected (← RealizationAdapterFixture.prepareOwnDocstring `adapterFixture canonical))
      "Missing or inherited own source remains explicit"
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

private structure UnknownDocstringData where
  value : Nat
  deriving TypeName

-- Identical link text can resolve to distinct compiled declarations.
run_cmd liftTermElabM do
  let select (canonical : Name) := NativeSource.prepareDocumented {
    project := `adapterFixture, canonical
    moduleName := `VersoBlueprintTests.BlueprintRealizationAdapter.ParserSource }
  let nat ← obtain (← select ``RealizationParserFixture.versoLinkNat)
  let int ← obtain (← select ``RealizationParserFixture.versoLinkDirect)
  ensure (nat.content != int.content && nat.format == `verso && int.format == `verso)
    "Compiled docstrings must bind the distinct targets of identical link text"
  for inherited in #[``RealizationParserFixture.standaloneInherited,
      ``RealizationParserFixture.renamedInherited,
      ``RealizationParserFixture.ExportShadow.Before.target,
      ``RealizationParserFixture.versoLinkInherited] do
    match ← select inherited with
    | .error diagnostic =>
      ensure (diagnostic.code == "inherited-docstring") s!"Expected inheritance diagnostic for {inherited}"
    | .ok _ => throwError "Inherited docstring accepted as an own comment"
  let unknown : Lean.VersoDocString := {
    text := #[.para #[.other (.custom (Dynamic.mk (⟨37⟩ : UnknownDocstringData))) #[.text "fallback"]]]
    subsections := #[] }
  match Informal.Docstring.canonicalVersoDocstring unknown with
  | .error diagnostic =>
    ensure (diagnostic.code == "unsupported-docstring-extension") "Unknown extension must fail closed"
  | .ok _ => throwError "Opaque Dynamic payload silently bound as fallback text"

end VersoBlueprintTests.BlueprintRealizationAdapter
