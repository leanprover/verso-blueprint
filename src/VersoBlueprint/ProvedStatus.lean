/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Data

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
- Lean environment bridge (`ConstantInfo.blueprint*`).
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

/-- True when the declaration has statement/type-side incompleteness. -/
def ProvedStatus.hasTypeGap : ProvedStatus → Bool
  | .proved => false
  | .missing => true
  | .axiomLike => true
  | .containsSorry info => info.any (·.location == .statement)

/-- True when the declaration has proof/body-side incompleteness. -/
def ProvedStatus.hasProofGap : ProvedStatus → Bool
  | .proved => false
  | .missing => true
  | .axiomLike => true
  | .containsSorry info => info.any (·.location == .proof)

/-- A sorry footprint is known, but its axis is not fully localized. -/
def ProvedStatus.hasUnlocalizedSorry : ProvedStatus → Bool
  | .containsSorry info => info.isEmpty || info.any (·.location == .unknown)
  | _ => false

/--
Whether this status blocks statement-track completion for a node kind.

Definitions are blocked by either statement or proof gaps.
Theorem-like statements are blocked only by statement gaps.
-/
def ProvedStatus.blocksStatementCompletion (status : ProvedStatus) (kind : NodeKind) : Bool :=
  status.hasUnlocalizedSorry || match kind with
  | .definition => status.hasTypeGap || status.hasProofGap
  | .proposition | .lemma | .theorem | .corollary => status.hasTypeGap

/-- Conservative proof-track blocker predicate. -/
def ProvedStatus.blocksProofCompletion (status : ProvedStatus) : Bool :=
  status.isIncomplete

/-- True only when explicit `sorry` markers were observed. -/
def ProvedStatus.containsExplicitSorry : ProvedStatus → Bool
  | .containsSorry info => info.any (·.origin == .direct)
  | _ => false

/-- True when a declaration depends on a `sorry` in another declaration. -/
def ProvedStatus.dependsOnSorry : ProvedStatus → Bool
  | .containsSorry info => info.any (·.origin == .dependency)
  | _ => false

/-- Human-readable location text used in summary/tooltip rendering. -/
def ProvedStatus.sorryLocationText : ProvedStatus → String
  | .missing => "missing declaration"
  | .axiomLike => "axiom-like (no body)"
  | .containsSorry info =>
    let hasType := info.any (·.location == .statement)
    let hasProof := info.any (·.location == .proof)
    let known := if hasType && hasProof then
      "in statement and proof"
    else if hasType then
      "in statement"
    else if hasProof then
      "in proof"
    else
      "location unknown"
    if (hasType || hasProof) && info.any (·.location == .unknown) then
      known ++ "; other locations unknown"
    else known
  | .proved => "location unknown"

/-- Compact label used in textual reports. -/
def ProvedStatus.statusLabel : ProvedStatus → String
  | .missing => "missing"
  | .axiomLike => "axiom-like"
  | .containsSorry info =>
    if info.any (·.origin == .direct) then "contains sorry"
    else if info.any (·.origin == .dependency) then "depends on sorry"
    else "sorry detected"
  | .proved => "proved"

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
    | .containsSorry info =>
      let locationText := status.sorryLocationText
      let direct := info.any (·.origin == .direct)
      let dependency := info.any (·.origin == .dependency)
      let compact := if direct then "sorry" else status.statusLabel
      {
        summaryText := s!"{compact} {locationText}"
        externalPanelText := s!"{status.statusLabel} {locationText}"
        externalHeaderText := if direct then "contains sorry" else if dependency then "depends on sorry" else "sorry detected"
        codeDeclClass := "bp_code_decl_status_warning"
        externalDeclClass := "bp_external_decl_sorry"
        codeEntryClassSuffix := "warning"
        codeEntrySymbol := "⚠"
        statusMarkSymbol := "✗"
      }

/-- Aggregate per-axis sorry reference counts `(statementRefs, proofRefs)`. -/
def ProvedStatus.sorryRefCounts : ProvedStatus → Nat × Nat
  | .containsSorry info =>
    info.foldl (init := (0, 0)) fun (typeRefs, proofRefs) item =>
      match item.location with
      | .statement => (typeRefs + item.refs?.getD 0, proofRefs)
      | .proof => (typeRefs, proofRefs + item.refs?.getD 0)
      | .unknown => (typeRefs, proofRefs)
  | _ => (0, 0)

/-- Supply source reference counts without inventing locations for inherited gaps. -/
def ProvedStatus.withDirectRefCounts (status : ProvedStatus) (typeRefs proofRefs : Nat) : ProvedStatus :=
  match status with
  | .containsSorry info => .containsSorry <| info.map fun item =>
      if item.origin != .direct then item else
        match item.location with
        | .statement => { item with refs? := some typeRefs }
        | .proof => { item with refs? := some proofRefs }
        | .unknown => item
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

/-- Build a status from per-axis incompleteness flags and optional ref counts. -/
def ProvedStatus.ofSorryFlags (hasType hasProof : Bool)
    (typeRefs? : Option Nat := none) (proofRefs? : Option Nat := none) : ProvedStatus :=
  let statementInfo : Array SorryInfo :=
    if hasType then #[{ location := .statement, refs? := typeRefs? }] else #[]
  let proofInfo : Array SorryInfo :=
    if hasProof then #[{ location := .proof, refs? := proofRefs? }] else #[]
  let info := statementInfo ++ proofInfo
  if info.isEmpty then .proved else .containsSorry info

/-- Build a status from per-axis reference counts. -/
def ProvedStatus.ofRefCounts (typeRefs proofRefs : Nat) : ProvedStatus :=
  ProvedStatus.ofSorryFlags
    (typeRefs > 0)
    (proofRefs > 0)
    (if typeRefs > 0 then some typeRefs else none)
    (if proofRefs > 0 then some proofRefs else none)

/-- Merge duplicate observations by axis *and* origin. Counts are lower bounds
from overlapping snapshots, so take their maximum instead of adding them. -/
def SorryInfo.mergeEvidence (items : Array SorryInfo) : Array SorryInfo :=
  items.foldl (init := #[]) fun acc item =>
    match acc.findIdx? (fun old => old.location == item.location && old.origin == item.origin) with
    | none => acc.push item
    | some index => acc.modify index fun old =>
      { old with refs? := max old.refs? item.refs? }

/-- An empty sorry payload still observes incompleteness with no attribution. -/
def SorryInfo.withUnlocalizedFallback (items : Array SorryInfo) : Array SorryInfo :=
  if items.isEmpty then #[{ location := .unknown, origin := .unknown }] else items

/--
Conservative merge for duplicated snapshots of the same declaration/revision.
`missing` and then `axiomLike` dominate; `proved` is neutral. Sorry snapshots
retain every observed axis/origin and the maximum known reference count.
An empty sorry payload remains incomplete rather than becoming `proved`.
-/
def ProvedStatus.mergeConservative : ProvedStatus → ProvedStatus → ProvedStatus
  | .missing, _ | _, .missing => .missing
  | .axiomLike, _ | _, .axiomLike => .axiomLike
  | .proved, b => b
  | a, .proved => a
  | .containsSorry a, .containsSorry b => .containsSorry <| SorryInfo.mergeEvidence
      (SorryInfo.withUnlocalizedFallback a ++ SorryInfo.withUnlocalizedFallback b)

@[simp] theorem ProvedStatus.mergeConservative_proved_left (status : ProvedStatus) :
    ProvedStatus.mergeConservative .proved status = status := by
  cases status <;> rfl

@[simp] theorem ProvedStatus.mergeConservative_proved_right (status : ProvedStatus) :
    ProvedStatus.mergeConservative status .proved = status := by
  cases status <;> rfl

/-- Pure boundary between observed sorry evidence and the declaration status.
A known footprint with no localized evidence keeps both axis and origin unknown.
Visible evidence is retained even if the combined footprint was incomplete. -/
def ProvedStatus.ofSorryEvidence (knownSorry : Bool) (evidence : Array SorryInfo) : ProvedStatus :=
  if evidence.isEmpty then
    if knownSorry then .containsSorry (SorryInfo.withUnlocalizedFallback evidence) else .proved
  else .containsSorry evidence

theorem ProvedStatus.ofSorryEvidence_known_incomplete (evidence : Array SorryInfo) :
    (ProvedStatus.ofSorryEvidence true evidence).isIncomplete = true := by
  simp only [ofSorryEvidence]
  split <;> rfl

/-- Definition shorthand for statement/type-side incompleteness checks. -/
def LiterateDef.hasTypeSorry (d : LiterateDef) : Bool :=
  d.provedStatus.hasTypeGap

/-- Definition shorthand for any incompleteness checks. -/
def LiterateDef.hasSorry (d : LiterateDef) : Bool :=
  d.provedStatus.isIncomplete

/-- Theorem shorthand for statement/type-side incompleteness checks. -/
def LiterateThm.hasTypeSorry (d : LiterateThm) : Bool :=
  d.provedStatus.hasTypeGap

/-- Theorem shorthand for proof/body-side incompleteness checks. -/
def LiterateThm.hasProofSorry (d : LiterateThm) : Bool :=
  d.provedStatus.hasProofGap

/-- Theorem shorthand for any incompleteness checks. -/
def LiterateThm.hasSorry (d : LiterateThm) : Bool :=
  d.provedStatus.isIncomplete

/--
Blueprint incompleteness treats axioms like synthetic sorries because they
lack executable/provable bodies.
-/
def ConstantInfo.blueprintIsAxiomLike (info : ConstantInfo) : Bool :=
  match info with
  | .axiomInfo _ => true
  | _ => false

/-- Whether a declaration has an inspectable body, no body, or a body hidden by import. -/
inductive BodyAccess where
  | available (value : Expr)
  | unavailable
  | absent

/-- The imported public view represents hidden theorems as axioms. Their cached
axiom footprint omits their own name; an actual axiom includes its own name. -/
def ConstantInfo.blueprintBodyAccess (name : Name) (info : ConstantInfo)
    (axioms : Array Name) : BodyAccess :=
  match info.value? (allowOpaque := true) with
  | some value => .available value
  | none =>
    match info with
    | .axiomInfo _ => if axioms.contains name then .absent else .unavailable
    | _ => .absent

/-- Remove outer body binder types already observed in the declaration telescope. -/
private def proofBody (type value : Expr) : Expr :=
  match type, value with
  | .forallE _ domain typeBody _, .lam _ valueDomain valueBody _ =>
    -- The declaration telescope is already statement evidence. Remove only
    -- syntactically identical outer binder types, not arbitrary annotations or
    -- constants shared by the statement and proof.
    if domain == valueDomain then proofBody typeBody valueBody else value
  | _, _ => value

/-- Read cached sorry footprints and visible inductive/constructor types.
Cached aggregates can omit nested constructor gaps. The visited worklist follows
only those type/constructor links, never arbitrary definition or proof bodies. -/
partial def declarationHasSorryFootprint [Monad m] [MonadEnv m] (name : Name) : m Bool :=
  visit [name] {}
where
  visit (pending : List Name) (visited : NameSet) : m Bool := do
    match pending with
    | [] => return false
    | name :: pending =>
      if visited.contains name then return ← visit pending visited
      let visited := visited.insert name
      if (← collectAxioms name).contains ``sorryAx then return true
      let mut pending := pending
      match (← getEnv).find? name with
      | some (.inductInfo info) =>
        if info.type.hasSorry then return true
        pending := info.ctors ++ info.type.getUsedConstants.toList ++ pending
      | some (.ctorInfo info) =>
        if info.type.hasSorry then return true
        pending := info.type.getUsedConstants.toList ++ pending
      | _ => pure ()
      visit pending visited

/-- Classify observed expressions and the combined cached sorry footprint. -/
def ConstantInfo.blueprintProvedStatus [Monad m] [MonadEnv m]
    (name : Name) (info : ConstantInfo) : m ProvedStatus := do
  let axioms ← collectAxioms name
  let knownSorry ← declarationHasSorryFootprint name
  let body := ConstantInfo.blueprintBodyAccess name info axioms
  if let .absent := body then
    if ConstantInfo.blueprintIsAxiomLike info then return .axiomLike
  let mut typeDirect := info.type.hasSorry
  let mut typeInherited := false
  for dep in info.type.getUsedConstants do
    if dep != name && dep != ``sorryAx && (← declarationHasSorryFootprint dep) then
      typeInherited := true
      break
  let proofDirect := match body with
    | .available value => (proofBody info.type value).hasSorry
    | _ => false
  let mut proofInherited := false
  match body with
  | .available value =>
    for dep in (proofBody info.type value).getUsedConstants do
      if dep != name && dep != ``sorryAx && (← declarationHasSorryFootprint dep) then
        proofInherited := true
        break
  | _ => pure ()
  -- The inductive's own type omits its fields. Constructor types are statement
  -- evidence, not a reason to invent an axis for an otherwise unlocalized gap.
  if let .inductInfo induct := info then
    for ctor in induct.ctors do
      if let some ctorInfo := (← getEnv).find? ctor then
        if ctorInfo.type.hasSorry then typeDirect := true
        for dep in ctorInfo.type.getUsedConstants do
          if dep != name && dep != ctor && dep != ``sorryAx && (← declarationHasSorryFootprint dep) then
            typeInherited := true
  let mut evidence : Array SorryInfo := #[]
  if typeDirect then evidence := evidence.push { location := .statement }
  if typeInherited then evidence := evidence.push { location := .statement, origin := .dependency }
  if proofDirect then evidence := evidence.push { location := .proof }
  if proofInherited then evidence := evidence.push { location := .proof, origin := .dependency }
  if let .unavailable := body then
    if knownSorry || typeDirect || typeInherited then
      -- A clean visible type localizes the remaining footprint to the body,
      -- but does not reveal whether it has a direct hole or admitted helper.
      -- When the type already explains the footprint, the body may be complete.
      evidence := evidence.push {
        location := if typeDirect || typeInherited then .unknown else .proof
        origin := .unknown
      }
  return ProvedStatus.ofSorryEvidence knownSorry evidence

end Informal.Data
