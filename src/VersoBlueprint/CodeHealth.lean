/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.ProvedStatus
import VersoBlueprint.Informal.Block.Model

namespace Informal.Graph

open Lean

structure ExternalCodeStatus where
  isMissing : Name → Bool := fun _ => false
  provedStatus : Name → Data.ProvedStatus := fun _ => .proved

/-- Non-authoritative provider/display inventory; completion comes only from
realization capture and validation.
Each canonical declaration is counted once after conservatively merging every
captured observation. Display selection and raw facet provenance are separate.
Missing declarations have their own count; incomplete counts concern present
declarations. An empty projection cannot authorize completion. -/
structure CodeHealth where
  totalDecls : Nat := 0
  missingDecls : Nat := 0
  provedStatus : Data.ProvedStatus := .incomplete {}
  statementBlocked : Bool := true
  anyGapCount : Nat := 0
  hasAxiomLike : Bool := false
deriving Inhabited, Repr

def CodeHealth.hasAssociatedCode (health : CodeHealth) : Bool :=
  health.totalDecls > 0

def CodeHealth.presentDecls (health : CodeHealth) : Nat :=
  health.totalDecls - health.missingDecls

/-- Fold the canonical status union, never a display-filtered declaration list. -/
def CodeHealth.ofDeclarations (kind : Data.NodeKind)
    (observations : Array (Name × Data.ProvedStatus)) : CodeHealth :=
  let statuses := (Data.ProvedStatus.indexByName observations).toArray
  statuses.foldl (init := {
      totalDecls := statuses.size
      statementBlocked := false
      provedStatus := if statuses.isEmpty then .incomplete {} else .proved })
    fun health (_, status) => {
      health with
      provedStatus := health.provedStatus.mergeConservative status
      missingDecls := health.missingDecls + if status.isMissing then 1 else 0
      statementBlocked := health.statementBlocked || status.blocksStatementCompletion kind
      anyGapCount := health.anyGapCount + if !status.isMissing && status.isIncomplete then 1 else 0
      hasAxiomLike := health.hasAxiomLike || status.isAxiomLike
    }

def externalDeclMissing (external : ExternalCodeStatus) (decl : Data.ExternalRef) : Bool :=
  !decl.present || external.isMissing decl.canonical.eraseMacroScopes

def externalDeclProvedStatus (external : ExternalCodeStatus) (decl : Data.ExternalRef) : Data.ProvedStatus :=
  if externalDeclMissing external decl then .missing
  else decl.provedStatus.mergeConservative (external.provedStatus decl.canonical.eraseMacroScopes)

private def externalObservation (external : ExternalCodeStatus) (ref : Data.ExternalRef) :
    Name × Data.ProvedStatus :=
  (ref.canonical.eraseMacroScopes, externalDeclProvedStatus external ref)

def codeHealthOfExternalDecls (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (decls : Array Data.ExternalRef) : CodeHealth :=
  CodeHealth.ofDeclarations kind (decls.map (externalObservation external))

/-- Combine raw associations across any selected facets before counting.
Rows remain available to callers for per-facet provenance and rendering. -/
def codeHealthOfBlockSources (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (sources : Array Informal.BlockCodeData) : CodeHealth :=
  CodeHealth.ofDeclarations kind <| sources.flatMap fun source =>
    source.externalDecls.map (externalObservation external) ++
      source.literateDeclarations.declarations.map fun decl => (decl.name, decl.provedStatus)

def codeHealthOfBlockSource (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (source? : Option Informal.BlockCodeData) : CodeHealth :=
  codeHealthOfBlockSources kind external source?.toArray

def CodeHealth.hasMissingExternalDecls (health : CodeHealth) : Bool :=
  health.missingDecls > 0

def CodeHealth.hasStatementGaps (health : CodeHealth) : Bool :=
  health.statementBlocked

def CodeHealth.hasAnyGaps (health : CodeHealth) : Bool :=
  health.anyGapCount > 0

end Informal.Graph
