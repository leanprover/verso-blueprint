/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint
import VersoBlueprint.Realizations.Authoring
import VersoBlueprint.Realizations.Capture

/-! Which native contract each declared use selects. Every selection below comes
from an ordinary capture of this module's real declarations; nothing is mocked. -/

open Lean Elab Command Term Informal
open Realizations Validation Translations

namespace DependencySelectionFixture

run_cmd liftCoreM <| Realizations.Authoring.configureProject `dependencyFixtures

@[blueprint "dependencies.clean"]
theorem clean : True := True.intro

@[blueprint "dependencies.admitted"]
theorem admitted : True := by sorry

/-- A data definition is selected through its implementation contract. -/
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

/-- A proof and a data definition under one label offer no unique contract. -/
@[blueprint "dependencies.mixed"]
theorem mixedProof : True := True.intro

@[blueprint "dependencies.mixed"]
def mixedValue : Nat := 0

@[blueprint "dependencies.source"
  (uses := ["dependencies.clean", "dependencies.admitted", "dependencies.definition",
    "dependencies.proposition", "dependencies.grouped", "dependencies.mixed", "dependencies.missing"])
  (proofUses := ["dependencies.clean", "dependencies.missing"])]
theorem source : True := True.intro

@[blueprint "dependencies.consumer" (uses := ["dependencies.source"])]
theorem consumer : True := source

@[blueprint "dependencies.empty"]
theorem empty : True := True.intro

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
    unless expected.all keys.contains do
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
  let cleanProof := contract "clean" ``clean `proof
  let admittedProof := contract "admitted" ``admitted `proof
  let sourceStatement := contract "source" ``source `statement
  let sourceProof := contract "source" ``source `proof

  -- Each kind of target selects its own complete native contract.
  selects snapshot "source" `statement "clean" #[cleanProof]
  selects snapshot "source" `proof "clean" #[cleanProof]
  selects snapshot "source" `statement "definition" #[contract "definition" ``definitionTarget `implementation]
  selects snapshot "source" `statement "proposition" #[contract "proposition" ``propositionTarget `statement]
  selects snapshot "source" `statement "grouped"
    #[contract "grouped" ``groupedOne `proof, contract "grouped" ``groupedTwo `proof]
  selects snapshot "consumer" `statement "source" #[sourceProof]

  -- Selection does not depend on whether the target is finished.
  selects snapshot "source" `statement "admitted" #[admittedProof]
  ensure ((registry.resultForRequirement cleanProof).complete &&
    !(registry.resultForRequirement admittedProof).complete)
    "The clean and admitted targets were not assessed independently of their selection"

  -- Failures stay on their own edge and axis, with no invented requirement.
  fails snapshot "source" `statement "mixed" "ambiguous-native-contract"
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
      requirement.prerequisites.contains gate && requirement.prerequisites.contains cleanProof &&
      requirement.prerequisites.contains admittedProof))
    "The using statement does not require its selection check and selected contracts"
  for key in #[sourceStatement, sourceProof] do
    ensure ((registry.localResult key).complete && !(registry.resultForRequirement key).complete)
      s!"Native validity and Blueprint closure were conflated for {repr key}"
  ensure (!(registry.resultForRequirement (contract "consumer" ``consumer `proof)).complete)
    "A dependent completed through an unfinished dependency"

end DependencySelectionFixture
