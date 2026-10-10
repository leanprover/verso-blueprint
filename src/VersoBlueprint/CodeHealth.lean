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

/-- One semantic completion projection shared by graph, headings and CLI.
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

def nodeCodeHealth (external : ExternalCodeStatus) (node : Data.Node) : CodeHealth :=
  codeHealthOfBlockSource node.kind external <| some {
    externalDecls := node.externalRefs
    literateDeclarations := Informal.LiterateDeclarations.ofCodes node.literateCodes }

def CodeHealth.hasMissingExternalDecls (health : CodeHealth) : Bool :=
  health.missingDecls > 0

def CodeHealth.hasStatementGaps (health : CodeHealth) : Bool :=
  health.statementBlocked

def CodeHealth.hasAnyGaps (health : CodeHealth) : Bool :=
  health.anyGapCount > 0

def CodeHealth.localStatementFormalized (health : CodeHealth) : Bool :=
  health.hasAssociatedCode && !health.hasStatementGaps

def CodeHealth.localProofFormalized (health : CodeHealth) : Bool :=
  health.hasAssociatedCode && health.provedStatus.isProved

def CodeHealth.verdict (health : CodeHealth) : String :=
  if health.hasAssociatedCode then health.provedStatus.verdict else "unassociated"

def CodeHealth.incompleteAssociatedCode (health : CodeHealth) : Bool :=
  health.hasAssociatedCode && !health.hasMissingExternalDecls && health.hasAnyGaps

def CodeHealth.localFormalized (health : CodeHealth) (kind : Data.NodeKind) : Bool :=
  if kind.isTheoremLike then health.localProofFormalized
  else if kind == .definition then health.localStatementFormalized
  else false

end Informal.Graph
