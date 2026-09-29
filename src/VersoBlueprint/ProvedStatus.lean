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

/--
Whether this status blocks statement-track completion for a node kind.

Definitions are blocked by either statement or proof gaps.
Theorem-like statements are blocked only by statement gaps.
-/
def ProvedStatus.blocksStatementCompletion (status : ProvedStatus) (kind : NodeKind) : Bool :=
  match kind with
  | .definition => status.hasTypeGap || status.hasProofGap
  | .proposition | .lemma | .theorem | .corollary => status.hasTypeGap

/-- Conservative proof-track blocker predicate. -/
def ProvedStatus.blocksProofCompletion (status : ProvedStatus) : Bool :=
  status.hasTypeGap || status.hasProofGap

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
    if hasType && hasProof then
      "in statement and proof"
    else if hasType then
      "in statement"
    else if hasProof then
      "in proof"
    else
      "location unknown"
  | .proved => "location unknown"

/-- Compact label used in textual reports. -/
def ProvedStatus.statusLabel : ProvedStatus → String
  | .missing => "missing"
  | .axiomLike => "axiom-like"
  | .containsSorry info =>
    if info.any (·.origin == .direct) then "contains sorry" else "depends on sorry"
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
      {
        summaryText := s!"{if direct then "sorry" else "depends on sorry"} {locationText}"
        externalPanelText := s!"{if direct then "contains sorry" else "depends on sorry"} {locationText}"
        externalHeaderText := if direct then "contains sorry" else "depends on sorry"
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
  | _ => (0, 0)

/-- Supply source reference counts without inventing locations for inherited gaps. -/
def ProvedStatus.withDirectRefCounts (status : ProvedStatus) (typeRefs proofRefs : Nat) : ProvedStatus :=
  match status with
  | .containsSorry info => .containsSorry <| info.map fun item =>
      if item.origin == .dependency then item else
        { item with refs? := some <| if item.location == .statement then typeRefs else proofRefs }
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
  let info : Array SorryInfo :=
    (#[]
      |> fun acc => if hasType then acc.push { location := .statement, refs? := typeRefs? } else acc
      |> fun acc => if hasProof then acc.push { location := .proof, refs? := proofRefs? } else acc)
  if info.isEmpty then .proved else .containsSorry info

/-- Build a status from per-axis reference counts. -/
def ProvedStatus.ofRefCounts (typeRefs proofRefs : Nat) : ProvedStatus :=
  ProvedStatus.ofSorryFlags
    (typeRefs > 0)
    (proofRefs > 0)
    (if typeRefs > 0 then some typeRefs else none)
    (if proofRefs > 0 then some proofRefs else none)

/--
Conservative merge for duplicated status snapshots:
- `missing` dominates,
- `axiomLike` dominates,
- otherwise preserve any observed axis incompleteness.
-/
def ProvedStatus.mergeConservative (a b : ProvedStatus) : ProvedStatus :=
  if a.isMissing || b.isMissing then
    .missing
  else if a.isAxiomLike || b.isAxiomLike then
    .axiomLike
  else
    let evidence := fun (location : SorryWhere) =>
      let matching := fun (status : ProvedStatus) => match status with
        | .containsSorry info => info.filter fun (item : SorryInfo) => item.location == location
        | _ => (#[] : Array SorryInfo)
      let items : Array SorryInfo := matching a ++ matching b
      if items.isEmpty then (#[] : Array SorryInfo) else
        #[({ location,
             origin := if items.any (fun (item : SorryInfo) => item.origin == .direct)
                       then .direct else .dependency } : SorryInfo)]
    let info := evidence .statement ++ evidence .proof
    if info.isEmpty then .proved else .containsSorry info

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

/-- Analyze both visible `sorry` terms and transitive `sorryAx` dependencies.
`collectAxioms` reads cached footprints across module boundaries. -/
def ConstantInfo.blueprintProvedStatus [Monad m] [MonadEnv m]
    (name : Name) (info : ConstantInfo) : m ProvedStatus := do
  let axioms ← collectAxioms name
  let body := ConstantInfo.blueprintBodyAccess name info axioms
  if let .absent := body then
    if ConstantInfo.blueprintIsAxiomLike info then return .axiomLike
  if !axioms.contains ``sorryAx then return .proved
  let typeDirect := info.type.hasSorry
  let mut typeInherited := false
  for dep in info.type.getUsedConstants do
    if (← collectAxioms dep).contains ``sorryAx then
      typeInherited := true
      break
  let proofDirect := match body with
    | .available value => value.hasSorry
    | _ => false
  let mut proofInherited := false
  match body with
  | .available value =>
    for dep in value.getUsedConstants do
      if (← collectAxioms dep).contains ``sorryAx then
        proofInherited := true
        break
  | .unavailable =>
    -- The proof is hidden, but the cached footprint still records `sorryAx`.
    proofInherited := axioms.contains ``sorryAx
  | .absent => pure ()
  let info : Array SorryInfo :=
    (#[]
      |> fun acc => if typeDirect || typeInherited then
          acc.push { location := .statement,
                     origin := if typeDirect then .direct else .dependency }
        else acc
      |> fun acc => if proofDirect || proofInherited then
          acc.push { location := .proof,
                     origin := if proofDirect then .direct else .dependency }
        else acc)
  return if info.isEmpty then .proved else .containsSorry info

end Informal.Data
