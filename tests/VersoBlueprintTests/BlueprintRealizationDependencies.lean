/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint
import VersoBlueprint.Realizations.Authoring
import VersoBlueprint.Realizations.Capture

/-! Which native contracts each declared use selects. Every selection below comes
from an ordinary capture of this module's real declarations; nothing is mocked.

A label's ordinary Lean declarations form one development, and a use requires
all of them. The use's axis decides the contract of each declaration: a
proof-axis use requires each theorem's proof, a statement-axis use only each
theorem's statement; both require each data definition's implementation and
each proposition definition's statement. -/

open Lean Elab Command Term Informal
open Realizations Validation Translations

namespace DependencySelectionFixture

run_cmd liftCoreM <| Realizations.Authoring.configureProject `dependencyFixtures

@[blueprint "dependencies.clean"]
theorem clean : True := True.intro

@[blueprint "dependencies.admitted"]
theorem admitted : True := by sorry

/-- A data definition is selected through its implementation contract on both axes. -/
@[blueprint "dependencies.definition"]
def definitionTarget : Nat := 1

/-- A proposition definition has a statement and no proof to select. -/
@[blueprint "dependencies.proposition"]
def propositionTarget : Prop := True

/-- Declarations sharing one label are required together. -/
@[blueprint "dependencies.grouped"]
theorem groupedOne : True := True.intro

@[blueprint "dependencies.grouped"]
theorem groupedTwo : True := True.intro

/-- A data definition and the theorems about it form one development. -/
@[blueprint "dependencies.mixed"]
def mixedValue : Nat := 0

@[blueprint "dependencies.mixed"]
theorem mixedValueZero : mixedValue = 0 := rfl

@[blueprint "dependencies.mixed"]
theorem mixedValueSmall : mixedValue ≤ 1 := Nat.zero_le 1

/-- A data definition whose body is admitted. -/
@[blueprint "dependencies.admittedDefinition"]
def admittedValue : Nat := sorry

@[blueprint "dependencies.source"
  (uses := ["dependencies.clean", "dependencies.admitted", "dependencies.definition",
    "dependencies.proposition", "dependencies.grouped", "dependencies.mixed", "dependencies.missing"])
  (proofUses := ["dependencies.clean", "dependencies.admitted", "dependencies.definition",
    "dependencies.proposition", "dependencies.grouped", "dependencies.mixed", "dependencies.missing"])]
theorem source : True := True.intro

/-- A statement mentioning an admitted theorem is meaningful once it is stated. -/
@[blueprint "dependencies.statementUser" (uses := ["dependencies.admitted"])]
theorem statementUser : True := True.intro

/-- A proof using an admitted theorem is not done. -/
@[blueprint "dependencies.proofUser" (proofUses := ["dependencies.admitted"])]
theorem proofUser : True := True.intro

/-- A proof using a mixed development requires all of it. -/
@[blueprint "dependencies.mixedUser" (proofUses := ["dependencies.mixed"])]
theorem mixedUser : True := True.intro

/-- A definition's body is part of its meaning, so it gates a statement using it. -/
@[blueprint "dependencies.admittedDefinitionUser" (uses := ["dependencies.admittedDefinition"])]
theorem admittedDefinitionUser : True := True.intro

@[blueprint "dependencies.consumer" (uses := ["dependencies.source"])]
theorem consumer : True := source

@[blueprint "dependencies.empty"]
theorem empty : True := True.intro

/-- The only use names a missing target; nothing else leaves this node unfinished. -/
@[blueprint "dependencies.unresolved" (uses := ["dependencies.missing"])]
theorem unresolved : True := True.intro

@[blueprint "dependencies.unresolvedConsumer" (uses := ["dependencies.unresolved"])]
theorem unresolvedConsumer : True := unresolved

@[blueprint "dependencies.unfinishedTarget" (proofUses := ["dependencies.missing"])]
theorem unfinishedTarget : True := True.intro

@[blueprint "dependencies.autoBoth" (autoDeps := true)]
theorem autoBoth : True ∧ unfinishedTarget = unfinishedTarget := ⟨unfinishedTarget, rfl⟩

@[blueprint "dependencies.explicitBoth" (uses := ["dependencies.unfinishedTarget"])
    (proofUses := ["dependencies.unfinishedTarget"])]
theorem explicitBoth : True ∧ unfinishedTarget = unfinishedTarget := ⟨unfinishedTarget, rfl⟩

@[blueprint "dependencies.derived" (autoDeps := true)]
def derived : Prop := propositionTarget ∧ True

-- Exercise the checked role of a proof written with the def command.
set_option linter.defProp false in
@[blueprint "dependencies.witness" (autoDeps := true)]
def witness : propositionTarget := unfinishedTarget

@[blueprint "dependencies.orphan" (proofUses := ["dependencies.clean"])]
def orphan : Prop := True

@[blueprint "dependencies.lateOwner" (proofUses := ["dependencies.clean"])]
def lateOwner : Prop := True

theorem externalBoth : True ∧ unfinishedTarget = unfinishedTarget := ⟨unfinishedTarget, rfl⟩

open Verso Verso.Genre.Manual in
#docs (Genre.Manual) dependencyOwnersDoc "Dependency owners" :=
:::::::
:::definition "dependencies.lateOwner"
A proposition with an informal proof.
:::
:::proof "dependencies.lateOwner"
Use the clean theorem.
:::
:::lemma_ "dependencies.externalBoth"
The external theorem mentions its prerequisite twice.
:::
:::proof "dependencies.externalBoth" (lean := "externalBoth") (autoDeps := true)
The proof placement supplies the whole Lean declaration.
:::
:::lemma_ "dependencies.inlineBoth"
The inline theorem mentions its prerequisite twice.
:::
```lean "dependencies.inlineBoth" (autoDeps := true)
theorem inlineBoth :
    True ∧ unfinishedTarget = unfinishedTarget :=
  ⟨unfinishedTarget, rfl⟩
```

:::definition "dependencies.inlineGroup"
A proposition, a proof, and a number share a label.
:::
```lean "dependencies.inlineGroup" (autoDeps := true)
def inlineProp : Prop := propositionTarget ∧ True
theorem inlineProof : True := unfinishedTarget
def inlineNumber : Nat := definitionTarget
```
:::::::

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def context : Realizations.Context := ⟨`lean, `dependencyFixtures⟩

private def contract (label : String) (declaration : Name) (role : Name) : RequirementKey :=
  ⟨.declaration ((⟨Name.mkSimple ("dependencies." ++ label), `lean⟩ : RealizationKey).forRole role)
    ⟨context, declaration.toString⟩, role⟩

private def selection (snapshot : Capture.Snapshot) (source : String) (role : Name) (target : String) :
    TermElabM (Except Diagnostic (Array RequirementKey)) := do
  let matching := snapshot.uses.filter fun use => use.source == Name.mkSimple ("dependencies." ++ source) &&
    use.role == role && use.reference.label == Name.mkSimple ("dependencies." ++ target)
  let #[use] := matching | throwError "Expected one {role} use {source} -> {target}, found {matching.size}"
  ensure (use.context == some context) "A use was selected outside its source project context"
  return use.selected

private def selects (snapshot : Capture.Snapshot) (source : String) (role : Name) (target : String)
    (expected : Array RequirementKey) : TermElabM Unit := do
  match ← selection snapshot source role target with
  | .ok keys =>
    unless canonical keys == canonical expected do
      throwError "{source} -> {target} ({role}) selected {repr keys}, expected {repr expected}"
  | .error diagnostic => throwError "{source} -> {target} ({role}) failed: {repr diagnostic}"

private def fails (snapshot : Capture.Snapshot) (source : String) (role : Name) (target code : String) :
    TermElabM Unit := do
  match ← selection snapshot source role target with
  | .ok keys => throwError "{source} -> {target} ({role}) selected {repr keys}, expected {code}"
  | .error diagnostic =>
    unless diagnostic.code == code do
      throwError "{source} -> {target} ({role}) failed with {diagnostic.code}, expected {code}"

run_cmd liftTermElabM do
  let snapshot ← match ← Realizations.Capture.capture with
    | .ok snapshot => pure snapshot
    | .error diagnostics => throwError "Capture rejected the fixture: {repr diagnostics}"
  let registry := snapshot.registry
  let cleanStatement := contract "clean" ``clean `statement
  let cleanProof := contract "clean" ``clean `proof
  let admittedStatement := contract "admitted" ``admitted `statement
  let admittedProof := contract "admitted" ``admitted `proof
  let sourceStatement := contract "source" ``source `statement
  let sourceProof := contract "source" ``source `proof
  let definition := contract "definition" ``definitionTarget `implementation
  let proposition := contract "proposition" ``propositionTarget `statement
  let mixedImplementation := contract "mixed" ``mixedValue `implementation

  let assessment (label : String) := snapshot.assessmentFor (Name.mkSimple ("dependencies." ++ label))
  let unfinishedStatement := contract "unfinishedTarget" ``unfinishedTarget `statement
  let unfinishedProof := contract "unfinishedTarget" ``unfinishedTarget `proof
  for label in #["autoBoth", "explicitBoth", "inlineBoth", "externalBoth"] do
    selects snapshot label `statement "unfinishedTarget" #[unfinishedStatement]
    selects snapshot label `proof "unfinishedTarget" #[unfinishedProof]
    let result := assessment label
    ensure (result.selectedLeanUseCount == 2 && result.nativeLocallyComplete &&
      result.nativeBodyComplete && result.statementDependenciesComplete &&
      !result.proofDependenciesComplete && !result.requiredComplete)
      s!"{label} lost a dependency or conflated a local proof with Blueprint completion"

  selects snapshot "derived" `statement "proposition" #[proposition]
  selects snapshot "witness" `statement "proposition" #[proposition]
  selects snapshot "witness" `proof "unfinishedTarget" #[unfinishedProof]
  selects snapshot "inlineGroup" `statement "proposition" #[proposition]
  selects snapshot "inlineGroup" `proof "unfinishedTarget" #[unfinishedProof]
  selects snapshot "inlineGroup" `proof "definition" #[definition]
  -- Even with several possible owners on one label, each inferred edge belongs
  -- to the declaration role whose checked content supplied the reference.
  let group := Name.mkSimple "dependencies.inlineGroup"
  let edges := snapshot.uses.filter (·.source == group)
  ensure (edges.size == 3) "Unexpected inferred dependency in the mixed inline block"
  for (target, owner) in #[("proposition", `statement), ("unfinishedTarget", `proof), ("definition", `implementation)] do
    let key := (⟨group, `lean⟩ : RealizationKey).forRole owner
    ensure (edges.any fun edge => edge.reference.label == Name.mkSimple ("dependencies." ++ target) &&
      edge.realization == some key.name) s!"Wrong source realization for {target}"

  -- Authored proofUses may acquire an informal owner later. A genuinely
  -- ownerless edge stays visible without opening a native proof work item.
  selects snapshot "lateOwner" `proof "clean" #[cleanProof]
  let orphanEdges := snapshot.uses.filter (·.source == Name.mkSimple "dependencies.orphan")
  let #[edge] := orphanEdges | throwError "Expected one ownerless proof dependency"
  let .error diagnostic := edge.selected | throwError "An ownerless use acquired a target contract"
  ensure (edge.context.isNone && edge.role == `proof && diagnostic.code == "missing-use-owner" &&
    diagnostic.message.contains "dependencies.orphan" && diagnostic.message.contains "dependencies.clean" &&
    diagnostic.message.contains "proof") "Missing author-facing proof owner diagnostic"
  for label in #["derived", "proposition", "orphan", "lateOwner"] do
    let result := assessment label
    ensure (result.nativeStatementComplete && result.requiredComplete && result.nativeLocallyComplete &&
      !result.hasNativeBodyRequirement && !result.nativeBodyComplete &&
      (Graph.actionableStageForAssessment? result).isNone)
      s!"Statement-only {label} acquired native proof work"
  ensure ((assessment "lateOwner").selectedLeanUseCount == 0 &&
      (assessment "orphan").selectedLeanUseCount == 0)
    "A shared proof dependency was attributed to a native proposition definition"
  ensure (Graph.actionableStageForAssessment? (assessment "admitted") == some "proof")
    "An actual unfinished proof disappeared from the work queue"

  -- A proof-axis use requires each target declaration to be done.
  selects snapshot "source" `proof "clean" #[cleanProof]
  selects snapshot "source" `proof "definition" #[definition]
  selects snapshot "source" `proof "proposition" #[proposition]
  selects snapshot "source" `proof "grouped"
    #[contract "grouped" ``groupedOne `proof, contract "grouped" ``groupedTwo `proof]
  selects snapshot "source" `proof "mixed" #[mixedImplementation,
    contract "mixed" ``mixedValueZero `proof, contract "mixed" ``mixedValueSmall `proof]

  -- A statement-axis use requires a theorem's statement, not its proof; a
  -- definition's body is part of its meaning on either axis.
  selects snapshot "source" `statement "clean" #[cleanStatement]
  selects snapshot "source" `statement "definition" #[definition]
  selects snapshot "source" `statement "proposition" #[proposition]
  selects snapshot "source" `statement "grouped"
    #[contract "grouped" ``groupedOne `statement, contract "grouped" ``groupedTwo `statement]
  selects snapshot "source" `statement "mixed" #[mixedImplementation,
    contract "mixed" ``mixedValueZero `statement, contract "mixed" ``mixedValueSmall `statement]
  selects snapshot "consumer" `statement "source" #[sourceStatement]

  -- Selection does not depend on whether the target is finished.
  selects snapshot "source" `statement "admitted" #[admittedStatement]
  selects snapshot "source" `proof "admitted" #[admittedProof]
  ensure ((registry.resultForRequirement cleanProof).complete &&
    (registry.resultForRequirement admittedStatement).complete &&
    !(registry.resultForRequirement admittedProof).complete)
    "The clean and admitted targets were not assessed independently of their selection"

  -- A statement using an admitted theorem is complete; a proof using it is not.
  let statementUser := contract "statementUser" ``statementUser `statement
  ensure ((registry.requirement? statementUser).any (·.prerequisites.contains admittedStatement) &&
      (registry.resultForRequirement statementUser).complete &&
      (registry.resultForRequirement (contract "statementUser" ``statementUser `proof)).complete)
    "A statement-axis use of an admitted theorem gated the using node"
  let proofUser := contract "proofUser" ``proofUser `proof
  ensure ((registry.requirement? proofUser).any (·.prerequisites.contains admittedProof) &&
      (registry.resultForRequirement (contract "proofUser" ``proofUser `statement)).complete &&
      (registry.localResult proofUser).complete && !(registry.resultForRequirement proofUser).complete)
    "A proof-axis use of an admitted theorem did not gate the using proof"

  -- A proof using a mixed development requires all of it and completes with it.
  let mixedUser := contract "mixedUser" ``mixedUser `proof
  selects snapshot "mixedUser" `proof "mixed" #[mixedImplementation,
    contract "mixed" ``mixedValueZero `proof, contract "mixed" ``mixedValueSmall `proof]
  ensure ((registry.resultForRequirement mixedImplementation).complete &&
      (registry.resultForRequirement mixedUser).complete)
    "A proof using a complete mixed development did not complete"

  -- A statement using an admitted data definition requires its implementation.
  let admittedValue := contract "admittedDefinition" ``admittedValue `implementation
  let admittedDefinitionUser := contract "admittedDefinitionUser" ``admittedDefinitionUser `statement
  selects snapshot "admittedDefinitionUser" `statement "admittedDefinition" #[admittedValue]
  ensure (!(registry.resultForRequirement admittedValue).complete &&
      (registry.localResult admittedDefinitionUser).complete &&
      !(registry.resultForRequirement admittedDefinitionUser).complete)
    "A statement using an admitted data definition was not gated by its body"

  -- Failures stay on their own edge and axis, with no invented requirement.
  fails snapshot "source" `statement "missing" "missing-target"
  fails snapshot "source" `proof "missing" "missing-target"
  ensure (!(snapshot.uses.any (·.source == Name.mkSimple "dependencies.empty")))
    "A node declaring no uses acquired a dependency edge"

  -- A failed selection gates the Blueprint closure; it does not erase the
  -- native result of the using declaration, and it reaches its own dependents.
  let gate : RequirementKey := ⟨sourceStatement.subject, `statement ++ `dependencySelection⟩
  ensure ((registry.requirement? gate).any (·.expected == .check dependencySelectionValidator) &&
    !(registry.resultForRequirement gate).complete)
    "An unresolved dependency did not leave its selection check unfinished"
  ensure ((registry.requirement? sourceStatement).any (fun requirement =>
      requirement.prerequisites.contains gate && requirement.prerequisites.contains cleanStatement &&
      requirement.prerequisites.contains admittedStatement && !requirement.prerequisites.contains admittedProof))
    "The using statement does not require its selection check and only its targets' statements"
  for key in #[sourceStatement, sourceProof] do
    ensure ((registry.localResult key).complete && !(registry.resultForRequirement key).complete)
      s!"Native validity and Blueprint closure were conflated for {repr key}"
  ensure (!(registry.resultForRequirement (contract "consumer" ``consumer `proof)).complete)
    "A dependent completed through an unfinished dependency"

  -- The failed selection alone gates a node with no admitted dependency.
  let unresolvedStatement := contract "unresolved" ``unresolved `statement
  let unresolvedGate : RequirementKey := ⟨unresolvedStatement.subject, `statement ++ `dependencySelection⟩
  fails snapshot "unresolved" `statement "missing" "missing-target"
  ensure ((registry.requirement? unresolvedStatement).any (·.prerequisites == #[unresolvedGate]))
    "The unresolved statement requires something other than its selection check"
  ensure (!(registry.resultForRequirement unresolvedGate).complete)
    "A missing target did not leave its selection check unfinished"
  for key in #[unresolvedStatement, contract "unresolved" ``unresolved `proof,
      contract "unresolvedConsumer" ``unresolvedConsumer `statement,
      contract "unresolvedConsumer" ``unresolvedConsumer `proof] do
    ensure ((registry.localResult key).complete && !(registry.resultForRequirement key).complete)
      s!"A failed selection alone did not gate the closure of {repr key}"

  -- The selection record is attached under its own check's name. Every other
  -- binding input on a using declaration is a native descriptor or names one of
  -- that subject's own contracts.
  let selectionChecks := registry.requirements.filter (·.expected == .check dependencySelectionValidator)
  ensure (selectionChecks.any (·.key == gate) && selectionChecks.any (·.key == unresolvedGate))
    "Capture did not create the expected selection checks"
  for check in selectionChecks do
    let subjectInputs := registry.bindingInputs.filter (·.subject == check.key.subject)
    ensure (subjectInputs.any (·.name == selectedUsesFor check.key))
      s!"The selection record of {repr check.key} is not attached under its check's name"
    let contractScoped := (registry.requirements.filter (·.key.subject == check.key.subject)).flatMap
      fun requirement => #[NativeLean.expectedContextFor requirement.key,
        NativeLean.expectedStatementContextFor requirement.key, selectedUsesFor requirement.key]
    ensure (subjectInputs.all fun input => input.name == NativeLean.sourceContext ||
        input.name == NativeLean.statementContext || contractScoped.contains input.name)
      s!"A declaration-wide binding input on {repr check.key.subject} may carry its selection record"

  -- Changing what the uses selected re-binds the selection check only, never a
  -- review of the using statement or its native statement check.
  let review : RequirementKey := ⟨sourceStatement.subject, `mockStatementReview⟩
  let captured := registry.contributions
  let withReview : Input := { captured with requirements := captured.requirements.push {
    origin := { id := `mockStatementReview, moduleName := `MockProvider, source := "synthetic-test-input" }
    value := { key := review, expected := .review `statementCorrespondence `MockReviewer } } }
  let selectionRecord (input : BindingInput) : Bool := input.subject == sourceStatement.subject &&
    input.name != NativeLean.sourceContext && input.name != NativeLean.statementContext
  ensure (withReview.bindingInputs.any (selectionRecord ·.value))
    "The using statement carries no selection record to change"
  let reselect (input : Contribution BindingInput) : Contribution BindingInput :=
    if selectionRecord input.value then
      { input with value := { input.value with content := input.value.content ++ " reselected" } }
    else input
  let reselected : Input := { withReview with bindingInputs := withReview.bindingInputs.map reselect }
  let readmit (input : Input) : TermElabM Registry := match admit input with
    | .ok registry => pure registry
    | .error diagnostics => throwError "Re-admission rejected the captured input: {repr diagnostics}"
  let before ← readmit withReview
  let after ← readmit reselected
  ensure (after.bindingFor review == before.bindingFor review &&
      after.bindingFor sourceStatement == before.bindingFor sourceStatement)
    "A changed dependency selection re-bound the using statement"
  ensure (after.bindingFor gate != before.bindingFor gate)
    "A changed dependency selection did not re-bind its selection check"

end DependencySelectionFixture
