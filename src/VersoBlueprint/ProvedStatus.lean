/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.SorryAnalysis

namespace Informal.Data

open Lean

/-!
`ProvedStatus` API surface for blueprint completeness.

The API is organized into:
- state predicates (`isProved`, `isMissing`, `isIncomplete`, ...),
- axis predicates (`hasTypeGap`, `hasProofGap`),
- completion policy (`blocksStatementCompletion`, `blocksProofCompletion`),
- rendering helpers (`statusLabel`, `sorryLocationText`, `sorryRefCounts`,
  `presentation`),
- collection helpers (`any*`),
- constructors/merging (`of*`, `mergeConservative`),
- Lean environment bridge (`analyzeDeclaration`).
-/

/-- True only when the declaration is fully proved. -/
def ProvedStatus.isProved : ProvedStatus → Bool
  | .proved => true
  | _ => false

/-- True when the declaration is intentionally axiom-like (no body). -/
def ProvedStatus.isAxiomLike : ProvedStatus → Bool
  | .axiomLike => true
  | _ => false

/-- True when the declaration is missing from the captured environment snapshot. -/
def ProvedStatus.isMissing : ProvedStatus → Bool
  | .missing => true
  | _ => false

/-- Conservative incompleteness predicate: anything non-`proved` is incomplete. -/
def ProvedStatus.isIncomplete (status : ProvedStatus) : Bool :=
  !status.isProved

/-- Observed sorry evidence, independent of verification coverage. -/
def ProvedStatus.sorryEvidence : ProvedStatus → Array SorryInfo
  | .incomplete info => info.knownSorry
  | _ => #[]

/-- An empty incomplete payload represents unknown coverage, never a known hole. -/
def ProvedStatus.verificationGaps : ProvedStatus → Array VerificationGap
  | .incomplete info =>
    info.withCoverageFallback.unverified
  | _ => #[]

def ProvedStatus.hasKnownSorry (status : ProvedStatus) : Bool :=
  !status.sorryEvidence.isEmpty

def ProvedStatus.hasUnverifiedCoverage (status : ProvedStatus) : Bool :=
  !status.verificationGaps.isEmpty

/-- Coverage failure without an observed hole. -/
def ProvedStatus.isUnverified (status : ProvedStatus) : Bool :=
  status.hasUnverifiedCoverage && !status.hasKnownSorry

/-- Statement/type-side blockers whose existence is observed. -/
def ProvedStatus.hasTypeGap (status : ProvedStatus) : Bool :=
  status.isMissing || status.isAxiomLike || status.sorryEvidence.any (·.location == .statement)

/-- Proof/body-side blockers whose existence is observed. -/
def ProvedStatus.hasProofGap (status : ProvedStatus) : Bool :=
  status.isMissing || status.isAxiomLike || status.sorryEvidence.any (·.location == .proof)

def ProvedStatus.hasUnlocalizedSorry (status : ProvedStatus) : Bool :=
  status.sorryEvidence.any (·.location == .unknown)

def ProvedStatus.hasUnverifiedType (status : ProvedStatus) : Bool :=
  status.verificationGaps.any fun gap => gap.location == .statement || gap.location == .unknown

def ProvedStatus.hasUnverifiedProof (status : ProvedStatus) : Bool :=
  status.verificationGaps.any fun gap => gap.location == .proof || gap.location == .unknown

/-- Theorem statements require a verified statement closure. Definitions also
require a verified body closure. Unlocalized holes block both tracks. -/
def ProvedStatus.blocksStatementCompletion (status : ProvedStatus) (kind : NodeKind) : Bool :=
  status.hasUnlocalizedSorry || status.hasTypeGap || status.hasUnverifiedType ||
    (kind == .definition && (status.hasProofGap || status.hasUnverifiedProof))

def ProvedStatus.blocksProofCompletion (status : ProvedStatus) : Bool :=
  status.isIncomplete

def ProvedStatus.containsExplicitSorry (status : ProvedStatus) : Bool :=
  status.sorryEvidence.any (·.origin == .direct)

def ProvedStatus.dependsOnSorry (status : ProvedStatus) : Bool :=
  status.sorryEvidence.any (·.origin == .dependency)

/-- Human-readable evidence location; uncertainty is reported separately. -/
def ProvedStatus.sorryLocationText (status : ProvedStatus) : String :=
  if status.isMissing then "missing declaration"
  else if status.isAxiomLike then "axiom-like (no body)"
  else if !status.hasKnownSorry then
    if status.hasUnverifiedCoverage then "coverage unverified" else "location unknown"
  else
    let hasType := status.sorryEvidence.any (·.location == .statement)
    let hasProof := status.sorryEvidence.any (·.location == .proof)
    let known := if hasType && hasProof then "in statement and proof"
      else if hasType then "in statement"
      else if hasProof then "in proof" else "location unknown"
    let known := if (hasType || hasProof) && status.hasUnlocalizedSorry then
      known ++ "; other locations unknown" else known
    if status.hasUnverifiedCoverage then known ++ "; coverage unverified" else known

def ProvedStatus.statusLabel (status : ProvedStatus) : String :=
  if status.isProved then "proved"
  else if status.isMissing then "missing"
  else if status.isAxiomLike then "axiom-like"
  else if status.containsExplicitSorry then "contains sorry"
  else if status.dependsOnSorry then "depends on sorry"
  else if status.hasKnownSorry then "sorry detected"
  else "unverified"

/-- Machine verdict derived from the semantic status, without presentation parsing. -/
def ProvedStatus.verdict (status : ProvedStatus) : String :=
  if status.isProved then "complete"
  else if status.isMissing then "missing"
  else if status.isAxiomLike then "axiom-like"
  else if status.hasKnownSorry then "incomplete" else "unverified"

/-- Agent-facing evidence report. Verification gaps and known holes may coexist.
Source reference counts are observations, not completion certificates. -/
def ProvedStatus.reportJson (status : ProvedStatus) : Json :=
  Json.mkObj [
    ("verdict", toJson status.verdict),
    ("complete", toJson status.isProved),
    ("knownSorry", toJson status.sorryEvidence),
    ("unverified", toJson status.verificationGaps)
  ]

/--
Presentation data shared by the renderers that show declaration-level Lean
status. The semantic source remains `ProvedStatus`; this structure keeps the
small visual vocabulary from being reconstructed independently by each renderer.
-/
structure ProvedStatusPresentation where
  /-- Bracketed status text used in compact declaration-summary rows. -/
  summaryText : String
  /-- Status text used in expanded external-code panel rows. -/
  externalPanelText : String
  /-- Short status text used in rendered external declaration headers. -/
  externalHeaderText : String
  /-- CSS class used by compact declaration-summary rows. -/
  codeDeclClass : String
  /-- CSS class used by external declaration badges. -/
  externalDeclClass : String
  /-- CSS class suffix used by heading-level code-entry icons. -/
  codeEntryClassSuffix : String
  /-- Symbol used by heading-level code-entry icons. -/
  codeEntrySymbol : String
  /-- Default symbol used by statement-heading status marks. -/
  statusMarkSymbol : String
deriving Repr, Inhabited

/--
Declaration-level status presentation.

`present := false` handles unresolved external references even when their
stored semantic status has not already been normalized to `.missing`.
-/
def ProvedStatus.presentation (status : ProvedStatus) (present : Bool := true) :
    ProvedStatusPresentation :=
  let missingView : ProvedStatusPresentation := {
    summaryText := "missing declaration"
    externalPanelText := "missing declaration"
    externalHeaderText := "missing"
    codeDeclClass := "bp_code_decl_status_missing"
    externalDeclClass := "bp_external_decl_missing"
    codeEntryClassSuffix := "missing"
    codeEntrySymbol := "!"
    statusMarkSymbol := "✗"
  }
  if !present || status.isMissing then
    missingView
  else
    match status with
    | .proved =>
      {
        summaryText := "complete"
        externalPanelText := "complete"
        externalHeaderText := "complete"
        codeDeclClass := "bp_code_decl_status_ok"
        externalDeclClass := "bp_external_decl_ok"
        codeEntryClassSuffix := "proved"
        codeEntrySymbol := "✓"
        statusMarkSymbol := "✓"
      }
    | .missing =>
      missingView
    | .axiomLike =>
      {
        summaryText := "axiom-like (no body)"
        externalPanelText := "axiom-like (no body)"
        externalHeaderText := "axiom-like"
        codeDeclClass := "bp_code_decl_status_axiom"
        externalDeclClass := "bp_external_decl_sorry"
        codeEntryClassSuffix := "axiom"
        codeEntrySymbol := "A"
        statusMarkSymbol := "⚠"
      }
    | .incomplete _ =>
      let locationText := status.sorryLocationText
      let direct := status.containsExplicitSorry
      let dependency := status.dependsOnSorry
      let compact := if direct then "sorry" else status.statusLabel
      {
        summaryText := if status.isUnverified then "unverified" else s!"{compact} {locationText}"
        externalPanelText := if status.isUnverified then "unverified" else s!"{status.statusLabel} {locationText}"
        externalHeaderText := if direct then "contains sorry" else if dependency then "depends on sorry" else status.statusLabel
        codeDeclClass := "bp_code_decl_status_warning"
        externalDeclClass := "bp_external_decl_sorry"
        codeEntryClassSuffix := "warning"
        codeEntrySymbol := "⚠"
        statusMarkSymbol := "✗"
      }

/-- Aggregate observed per-axis source counts. Zero alone never certifies absence. -/
def ProvedStatus.sorryRefCounts (status : ProvedStatus) : Nat × Nat :=
  status.sorryEvidence.foldl (init := (0, 0)) fun (typeRefs, proofRefs) item =>
    match item.location with
    | .statement => (typeRefs + item.refs?.getD 0, proofRefs)
    | .proof => (typeRefs, proofRefs + item.refs?.getD 0)
    | .unknown => (typeRefs, proofRefs)

def ProvedStatus.withDirectRefCounts (status : ProvedStatus) (typeRefs proofRefs : Nat) : ProvedStatus :=
  match status with
  | .incomplete info => .incomplete { info with knownSorry := info.knownSorry.map fun item =>
      if item.origin != .direct then item else
        match item.location with
        | .statement => { item with refs? := some typeRefs }
        | .proof => { item with refs? := some proofRefs }
        | .unknown => item }
  | other => other

/-- True when any declaration in a collection is incomplete. -/
def ProvedStatus.anyIncomplete (decls : Array α) (statusOf : α → ProvedStatus) : Bool :=
  decls.any fun decl => (statusOf decl).isIncomplete

/-- True when any declaration blocks statement completion for the given node kind. -/
def ProvedStatus.anyBlocksStatementCompletion (kind : NodeKind) (decls : Array α)
    (statusOf : α → ProvedStatus) : Bool :=
  decls.any fun decl => (statusOf decl).blocksStatementCompletion kind

/-- True when any declaration blocks proof completion. -/
def ProvedStatus.anyBlocksProofCompletion (decls : Array α) (statusOf : α → ProvedStatus) : Bool :=
  decls.any fun decl => (statusOf decl).blocksProofCompletion

@[simp] theorem ProvedStatus.mergeConservative_proved_left (status : ProvedStatus) :
    ProvedStatus.mergeConservative .proved status = status := by
  cases status <;> rfl

@[simp] theorem ProvedStatus.mergeConservative_proved_right (status : ProvedStatus) :
    ProvedStatus.mergeConservative status .proved = status := by
  cases status <;> rfl

/-- The only production completion boundary: actual closed inspection, no
conflicting observed hole, and no remaining axis coverage gaps. -/
def ProvedStatus.ofInspection (inspection : SorryInspection) (info : IncompletenessInfo) : ProvedStatus :=
  if inspection.isComplete && info.knownSorry.isEmpty && info.unverified.isEmpty then .proved
  else .incomplete info

theorem ProvedStatus.ofInspection_complete (inspection : SorryInspection) (info : IncompletenessInfo)
    (h : (ofInspection inspection info).isProved = true) : inspection.isComplete = true := by
  unfold ofInspection at h
  split at h
  · rename_i hcert
    exact (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp hcert).1).1
  · contradiction

/-- Production completion cannot reach a sorryAx in its inspected closure. -/
theorem ProvedStatus.ofInspection_not_reachable (inspection : SorryInspection) (info : IncompletenessInfo)
    (h : (ofInspection inspection info).isProved = true) (root : Name)
    (hroot : root ∈ inspection.roots.toList) :
    ¬inspection.declarations.reachable root ``sorryAx :=
  certifiedNoSorry_not_reachable inspection.roots inspection.declarations
    (ofInspection_complete inspection info h) root hroot

/-- Remove outer body binder types already observed in the declaration telescope. -/
private def proofBody (type value : Expr) : Expr :=
  match type, value with
  | .forallE _ domain typeBody _, .lam _ valueDomain valueBody _ =>
    -- The declaration telescope is already statement evidence. Remove only
    -- syntactically identical outer binder types, not arbitrary annotations or
    -- constants shared by the statement and proof.
    if domain == valueDomain then proofBody typeBody valueBody else value
  | _, _ => value

/-- Axis roots are actual expression references. Remove the declaration itself
from axis attribution, while the whole-declaration certificate still covers it. -/
private def axisRoots (name : Name) (expressions : Array Expr) : Array Name :=
  (expressions.foldl (fun deps expr => deps ++ expr.getUsedConstants) #[]).filter
    fun dep => dep != name && dep != ``sorryAx

/-- Analyze a canonical checked declaration with full transitive inspection.
Ordinary hidden imports remain unverified even when cached footprints are empty.
`collectAxioms` is used only for positive evidence and genuine-axiom kind evidence. -/
def analyzeDeclaration [Monad m] [MonadEnv m] (name : Name) : m ProvedStatus := do
  let some info := (← getEnv).checked.get.find? name
    | return .incomplete { unverified := #[{ declaration := name }] }
  let axioms ← match info with
    | .axiomInfo _ => collectAxioms name
    | _ => pure #[]
  let body := ConstantInfo.blueprintBodyAccess name info axioms
  if let .axiomInfo _ := info then
    if let .absent := body then return .axiomLike
  let computation : SorryInspectionM m ProvedStatus := do
    let whole ← inspectSorryDependencies #[name] (stopAtBlocker := true)
    let completion := ProvedStatus.ofInspection whole {}
    if completion.isProved then return completion
    let mut statements := #[info.type]
    if let .inductInfo induct := info then
      for ctor in induct.ctors do
        if let some ctorInfo := (← getEnv).checked.get.find? ctor then
          statements := statements.push ctorInfo.type
    let statement ← inspectSorryDependencies (axisRoots name statements) (stopAtBlocker := true)
    let proofs := match body with
      | .available value => #[(proofBody info.type value)]
      | _ => match info with
        | .recInfo rec => rec.rules.toArray.map (·.rhs)
        | _ => #[]
    let proof ← inspectSorryDependencies (axisRoots name proofs) (stopAtBlocker := true)
    let mut evidence : Array SorryInfo := #[]
    if statements.any (·.hasSorry) then evidence := evidence.push { location := .statement }
    if statement.hasSorry then evidence := evidence.push { location := .statement, origin := .dependency }
    if proofs.any (·.hasSorry) then evidence := evidence.push { location := .proof }
    if proof.hasSorry then evidence := evidence.push { location := .proof, origin := .dependency }
    if axioms.contains ``sorryAx then
      if let .unavailable := body then
        evidence := evidence.push {
          location := if statement.isComplete && !statements.any (·.hasSorry) then .proof else .unknown
          origin := .unknown }
    let mut gaps := statement.verificationGaps .statement ++ proof.verificationGaps .proof
    if let .unavailable := body then
      gaps := gaps.push { location := .proof, declaration := name, reason := .bodyUnavailable }
    -- A witnessed blocker is enough for an incomplete verdict. Each clean axis
    -- still underwent closed inspection; only completion needs the whole graph.
    if !evidence.isEmpty || !gaps.isEmpty then
      return .incomplete { knownSorry := evidence, unverified := gaps }
    if evidence.isEmpty && whole.hasSorry then
      evidence := evidence.push { location := .unknown, origin := .unknown }
    for gap in whole.verificationGaps .unknown do
      if !gaps.any (fun known => known.declaration == gap.declaration) then
        let location := if gap.declaration == name && gap.reason == .bodyUnavailable then
          .proof else .unknown
        gaps := gaps.push { gap with location }
    return ProvedStatus.ofInspection whole { knownSorry := evidence, unverified := gaps }
  return (← computation.run {}).1

end Informal.Data
