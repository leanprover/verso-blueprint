/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoBlueprint.Realizations

/-! Subject-specific requirements and observations. These records describe the
boundary to trusted language tools; constructing a record does not run a checker.
In particular, equality of goal descriptions below is not Lean type checking. -/

namespace Informal.Validation

open Lean Realizations

/-- An independently authored expected proposition in a selected formal context.
The provider must elaborate it, check the witness's actual type against it, and
report completeness. `fingerprint` is an opaque provider-owned structural identity
including binders and selected package arguments. It is neither readable proposition
text nor a theorem-name shortcut. Native Lean uses a SHA-256 structural digest. -/
structure Goal where
  context : Context
  fingerprint : String
  documents : Array DocumentKey := #[]
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Source documents are provenance, not part of proposition equality. Actual
definitional equality must be established by the provider before this boundary. -/
def Goal.sameProposition (a b : Goal) : Bool :=
  a.context == b.context && a.fingerprint == b.fingerprint

/-- Proof checking, human review, and named executable checks remain distinct. -/
inductive Expectation where
  | proof (goal : Goal) (witness : ObjectKey)
  /-- Exact own-type support; the registry checks the receiving P/S selections. -/
  | proves (witness : ObjectKey)
  | review (criterion : Name) (reviewer : Name)
  | check (validator : Name)
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

namespace NativeLean

/-- Shared contract identities; native completeness is not an arbitrary check
named `proof`, or a proof of an independently specified proposition. -/
def statementValidator : Name := `lean.declarationStatement
def bodyValidator : Name := `lean.declarationCompleteness
def ownTypeValidator : Name := `lean.ownTypeProof
def sourceContext : Name := `source.semanticContext
def statementContext : Name := `source.statementContext
def expectedContext : Name := `lean.expectedContext
def expectedContextFor (key : RequirementKey) : Name := expectedContext ++ key.name

/-- Single source of truth for ordinary Lean declaration roles: which content
scope they project, which native check validator they require, and which
semantic context input they bind. -/
structure RoleSpec where
  projection : ContentScope
  validator : Name
  contextName : Name
  deriving Repr, Inhabited, BEq, DecidableEq

def roleSpec? : Name → Option RoleSpec
  | `statement => some ⟨.statement, statementValidator, statementContext⟩
  | `proof => some ⟨.implementation, bodyValidator, sourceContext⟩
  | `implementation => some ⟨.implementation, bodyValidator, sourceContext⟩
  | _ => none

def isNativeRole (role : Name) : Bool := (roleSpec? role).isSome

end NativeLean

/-- The mechanical dependency-selection check and the descriptor of what it
selected. The descriptor records other nodes' target selection, so it binds
only its own selection contract, never the declaration it is attached to. -/
def dependencySelectionValidator : Name := `blueprint.dependencySelection
def selectedUses : Name := `blueprint.selectedUses
def selectedUsesFor (key : RequirementKey) : Name := selectedUses ++ key.name

def Expectation.isNativeDeclarationCheck : Expectation → Bool
  | .check validator => validator == NativeLean.statementValidator || validator == NativeLean.bodyValidator
  | _ => false

inductive Coverage where
  | subject
  | dependencyClosure
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

structure Requirement where
  key : RequirementKey
  expected : Expectation
  coverage : Coverage := .subject
  prerequisites : Array RequirementKey := #[]
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

inductive Outcome where
  | passed
  | failed
  | unavailable
  | notApplicable
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Input from the owning checker, not an unchecked success flag on a realization.
`actualType` must be obtained from the checked witness. Complete proof evidence
requires dependency-closure coverage, including absence of holes/verification gaps.
Project-specific axiom policies belong to separately named requirements. -/
structure ProofObservation where
  witness : ObjectKey
  actualType : Option Goal := none
  outcome : Outcome
  coverage : Coverage := .subject
  assumptions : Array String := #[]
  explanation : String := ""
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

structure ReviewObservation where
  criterion : Name
  reviewer : Name
  outcome : Outcome
  coverage : Coverage := .subject
  explanation : String := ""
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

structure CheckObservation where
  validator : Name
  /-- Required for native declaration checks; generic joint tests may omit it. -/
  declaration : Option ObjectKey := none
  /-- The checked declaration type is a proposition, not merely a well-typed value. -/
  proposition : Bool := false
  outcome : Outcome
  coverage : Coverage := .subject
  /-- Declared native assumptions remain inspectable; this is not an axiom policy. -/
  assumptions : Array String := #[]
  explanation : String := ""
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

inductive Observation where
  | proof (observation : ProofObservation)
  | review (observation : ReviewObservation)
  | check (observation : CheckObservation)
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

def Observation.explanation : Observation → String
  | .proof o => o.explanation
  | .review o => o.explanation
  | .check o => o.explanation

/-- Versioned SHA-256 Merkle identity of the selected current inputs.
Freshness assumes collision resistance; this string does not authenticate evidence. -/
abbrev ContentBinding := String

structure Evidence where
  id : Name
  requirement : RequirementKey
  binding : ContentBinding
  observation : Observation
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Authored current selection, distinct from assessed content. Multiple distinct
selections for one slot are unresolved; none explicitly withdraws approval. -/
structure ReviewSelection where
  requirement : RequirementKey
  judgment : Option Name := none
  deriving Ord, Repr, Inhabited, BEq, DecidableEq, ToJson

/-- Only human review observations may be source-authored. Native facts enter
through fresh capture, never through this persisted record. -/
structure ReviewJudgment where
  id : Name
  requirement : RequirementKey
  binding : ContentBinding
  observation : ReviewObservation
  deriving Repr, Inhabited, BEq, DecidableEq

def Expectation.valid : Expectation → Bool
  | .proof goal witness =>
    goal.context.valid && !blank goal.fingerprint && witness.valid && witness.context == goal.context
  | .proves witness => witness.valid && witness.context.language == `lean
  | .review criterion reviewer => !criterion.isAnonymous && !reviewer.isAnonymous
  | .check validator => !validator.isAnonymous

def Coverage.covers (actual required : Coverage) : Bool :=
  actual == .dependencyClosure || actual == required

/-- Explain unsuitable evidence; successful output only means the supplied
provider observation fits this contract, not that this function checked a proof. -/
def Evidence.mismatch? (evidence : Evidence) (requirement : Requirement)
    (currentBinding : ContentBinding) : Option String := do
  if evidence.requirement != requirement.key then return "wrong-subject"
  if blank evidence.binding || evidence.binding != currentBinding then return "stale-content"
  match requirement.expected, evidence.observation with
  | .proof goal witness, .proof observation =>
    if observation.witness != witness then return "wrong-proof"
    if observation.outcome == .unavailable then return "validation-unavailable"
    if observation.outcome == .notApplicable then return "not-applicable"
    if !observation.actualType.any (·.sameProposition goal) then return "wrong-proof"
    if observation.coverage != .dependencyClosure then return "insufficient-coverage"
    if observation.outcome != .passed then return "proof-not-complete"
    none
  | .proves witness, .check observation =>
    if observation.validator != NativeLean.ownTypeValidator || observation.declaration != some witness then
      return "wrong-proof"
    if observation.outcome == .unavailable then return "validation-unavailable"
    if observation.outcome != .passed then return "proof-not-complete"
    if !observation.proposition then return "non-proposition"
    if observation.coverage != .dependencyClosure then return "insufficient-coverage"
    none
  | .review criterion reviewer, .review observation =>
    if observation.criterion != criterion || observation.reviewer != reviewer then return "wrong-review"
    if observation.outcome == .unavailable then return "validation-unavailable"
    if !observation.coverage.covers requirement.coverage then return "insufficient-coverage"
    if observation.outcome != .passed then return "review-not-accepted"
    none
  | .check validator, .check observation =>
    if observation.validator != validator then return "wrong-validator"
    if requirement.expected.isNativeDeclarationCheck then
      let .declaration _ object := requirement.key.subject | return "wrong-native-subject"
      if observation.declaration != some object then return "wrong-check-object"
    if observation.outcome == .unavailable then return "validation-unavailable"
    if !observation.coverage.covers requirement.coverage then return "insufficient-coverage"
    if observation.outcome != .passed then return "check-not-passed"
    none
  | _, _ => return "wrong-evidence-kind"

inductive Status where
  | unassessed
  | pending
  | blocked
  | complete
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

structure Result where
  status : Status
  /-- Independent local evidence survives failure of prerequisite closure. -/
  localComplete : Bool := false
  diagnostics : Array Diagnostic := #[]
  deriving Repr, Inhabited, BEq, DecidableEq, ToJson

def Result.complete (result : Result) : Bool := result.status == .complete

def Result.actionable (result : Result) : Bool := result.status == .pending

end Informal.Validation
