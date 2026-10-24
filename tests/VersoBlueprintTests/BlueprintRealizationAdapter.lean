/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations.Existing
import VersoBlueprintTests.BlueprintRealizationAdapter.Provider
import VersoBlueprintTests.SorryImport.Provider

/-! Native provider/consumer controls. Successful proof observations below are
obtained from real current Lean checks, never mocked provider success. -/

open Lean Meta Elab Term Command
open Informal.Realizations Informal.Validation Informal.Translations
open Informal.Realizations.Existing

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

private def proofKey (p : Projection) : RequirementKey := ⟨.declaration p.leanKey p.witness, `proof⟩

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

private def assertPendingCorrespondence (p : Projection) (input : Input) (expected : Syntax)
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
  let escapedProjection ← obtain (← project `adapterFixture (Name.mkSimple "adapter.escaped"))
  ensure (escapedProjection.witness.native.toName == escaped) "Escaped dotted name preserves typed identity"
  let escapedInput ← obtain (← escapedProjection.validate trueGoal)
  let escapedRegistry ← obtain (admit escapedInput)
  ensure ((escapedRegistry.resultForRequirement (proofKey escapedProjection)).complete)
    "Ordinary escaped dotted witness remains supported"
  let unusual := Name.str `RealizationAdapterFixture "bad»name"
  ensure (((← getEnv).checked.get.find? unusual).isSome && unusual.toString.toName != unusual)
    "Regression must use a present checked theorem whose name cannot round-trip"
  let some accepted ← Informal.Environment.getNode? (Name.mkSimple "adapter.nonroundtrip")
    | throwError "Regression requires a real accepted attribute association"
  ensure (accepted.externalRefs.any (·.canonical == unusual)) "Accepted association retains original typed name"
  match ← project `adapterFixture (Name.mkSimple "adapter.nonroundtrip") with
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
  let association := accepted.externalRefs[0]!
  ensure (association.range?.isNone && association.selectionRange?.isNone)
    "Ordinary attribute snapshot predates native range registration"
  let p ← obtain (← project `adapterFixture label)
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
    project `adapterFixture (Name.mkSimple "adapter.reflexivity")
  let markdown ← obtain markdown
  ensure (markdown.docstringFormat == `markdown &&
    markdown.input.documents[1]!.value.text == " Every natural number equals itself. Raw Markdown, with **emphasis**. ")
    "Markdown retains its exact own raw body and native format"
  let basic ← obtain (← project `adapterFixture (Name.mkSimple "adapter.verso"))
  ensure (basic.input.documents[1]!.value.text == " An own *Verso* docstring with {name}`Nat` and é 😀. ")
    "Option-wrapped Verso source remains exact"

run_cmd liftTermElabM do
  for (label, code) in #[("adapter.inherited", "unsupported-docstring"),
      ("adapter.own.inherited", "inherited-docstring"),
      ("adapter.ambiguous", "ambiguous-docstring"),
      ("adapter.no.original.comment", "missing-docstring"),
      ("adapter.synthetic", "source-association-unavailable")] do
    match ← project `adapterFixture (Name.mkSimple label) with
    | .error diagnostic =>
      ensure (diagnostic.code == code)
        s!"{label}: expected {code}, got {diagnostic.code}"
    | .ok _ => throwError "Unsupported source association must not fall back to another comment"
  -- Inspect the actual ordinary declaration with no source comment directly;
  -- late injected text cannot supply an original modifier association.
  let p ← obtain (← project `adapterFixture (Name.mkSimple "adapter.unicode"))
  let source ← liftM <| IO.FS.readFile p.sourcePath
  let commands ← obtain (← parseSource `noComment p.sourcePath source)
  let some ranges ← findDeclarationRanges? `RealizationAdapterFixture.noOriginalComment
    | throwError "Missing actual uncommented declaration ranges"
  match docCommentAtRanges `noComment source ranges.range ranges.selectionRange commands with
  | .error diagnostic => ensure (diagnostic.code == "missing-own-comment") "No adjacent-comment fallback"
  | .ok _ => throwError "Native text cannot create an original doc comment"
  -- Explicit source/parser failure injection, not replacement canonical content.
  let malformed ← project `adapterFixture (Name.mkSimple "adapter.verso")
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
  let p ← obtain (← project `adapterFixture (Name.mkSimple "adapter.flag.involutive"))
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
  let p ← obtain (← project `adapterFixture label)
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
  let admittedProjection ← obtain (← project `adapterFixture (Name.mkSimple "adapter.admitted"))
  let trueGoal ← `(term| True)
  let incompleteInput ← obtain (← admittedProjection.validate trueGoal)
  let incompleteRegistry ← obtain (admit incompleteInput)
  ensure (!(incompleteRegistry.resultForRequirement (proofKey admittedProjection)).complete)
    "Admitted proof with matching goal cannot complete through pure rules"
  assertPendingCorrespondence p input expected "The prose states natural-number reflexivity"
  let _ ← obtain (← project `adapterFixture label)
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
  for label in #["adapter.grouped", "adapter.definition", "adapter.undocumented", "adapter.missing",
      "adapter.inherited"] do
    ensure (rejected (← project `adapterFixture (Name.mkSimple label))) "Unsupported input must be explicit"
  -- Explicitly labeled source-I/O failure injection; never a successful provider.
  let missing ← project `adapterFixture (Name.mkSimple "adapter.reflexivity")
    (fun _ => throw <| IO.userError "injected unavailable source")
  match missing with
  | .error diagnostic => ensure (diagnostic.code == "source-unavailable") "Missing source diagnostic"
  | .ok _ => throwError "Unreadable source must not project a resolved declaration"
  -- Explicit empty-source failure injection, not replacement successful bytes.
  let empty ← project `adapterFixture (Name.mkSimple "adapter.reflexivity") (fun _ => pure " \n")
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

end VersoBlueprintTests.BlueprintRealizationAdapter
