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
      key := c, interpretation := "The prose states natural-number reflexivity"
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
    id := label ++ `nativeProof, requirement := proofKey p, binding
    observation := .proof fresh.observation }] }
  let linkedRegistry ← obtain (admit linked)
  ensure ((linkedRegistry.resultForRequirement (proofKey p)).complete) "Actual proof stays complete"
  ensure ((linkedRegistry.resultFor (.translation t)).status == .pending) "Correspondence remains pending"
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
      "adapter.verso", "adapter.inherited"] do
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
