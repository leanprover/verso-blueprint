/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Graph

namespace Verso.VersoBlueprintTests.BlueprintSummaryStatus

open Lean
open Informal
open Informal.Data
open Informal.Graph

private def mkInformal (deps : Array Name := #[]) : InformalData :=
  { stx := .missing, deps := deps.map (fun label => { label }), elabStx := #[] }

private def mkDefDecl (name : Name) (typeRefs proofRefs : Nat) : LiterateDef :=
  {
    name
    provedStatus := ProvedStatus.ofRefCounts typeRefs proofRefs
  }

private def mkThmDecl (name : Name) (typeRefs proofRefs : Nat) : LiterateThm :=
  {
    name
    provedStatus := ProvedStatus.ofRefCounts typeRefs proofRefs
  }

private def mkLiterateCode (definedDefs : Array LiterateDef) (definedTheorems : Array LiterateThm)
    : CodeRef :=
  .literate { stx := .missing, definedDefs, definedTheorems }

/-- info: true -/
#guard_msgs in
#eval
  let unknownKindNode : NodeData := {
    label := `unknown_kind
    title := "Unknown kind"
    displayLabel := "Unknown kind"
    statementStatus := .ready
    visual := { fillcolor := "#ffffff" }
  }
  actionableStageForStatuses? .definition .ready .ready == some "statement" &&
    actionableStageForStatuses? .definition .blocked .incomplete == none &&
    actionableStageForStatuses? .theorem .ready .none == some "statement" &&
    actionableStageForStatuses? .theorem .ready .incomplete == some "proof" &&
    actionableStageForStatuses? .theorem .formalized .ready == some "proof" &&
    actionableStageForStatuses? .theorem .blocked .incomplete == some "proof" &&
    actionableStageForStatuses? .theorem .formalized .formalized == none &&
    unknownKindNode.actionableStage?.isNone

/-- info: true -/
#guard_msgs in
#eval
  let provedStatus := ProvedStatus.proved
  let stmtGap := ProvedStatus.ofRefCounts 1 0
  let proofGap := ProvedStatus.ofRefCounts 0 1
  let bothGap := ProvedStatus.ofRefCounts 1 1
  (!provedStatus.blocksStatementCompletion .definition) &&
  (!provedStatus.blocksStatementCompletion .proposition) &&
  (!provedStatus.blocksStatementCompletion .lemma) &&
  (!provedStatus.blocksStatementCompletion .theorem) &&
  (!provedStatus.blocksStatementCompletion .corollary) &&
  stmtGap.blocksStatementCompletion .definition &&
  stmtGap.blocksStatementCompletion .proposition &&
  stmtGap.blocksStatementCompletion .lemma &&
  stmtGap.blocksStatementCompletion .theorem &&
  stmtGap.blocksStatementCompletion .corollary &&
  proofGap.blocksStatementCompletion .definition &&
  (!proofGap.blocksStatementCompletion .proposition) &&
  (!proofGap.blocksStatementCompletion .lemma) &&
  (!proofGap.blocksStatementCompletion .theorem) &&
  (!proofGap.blocksStatementCompletion .corollary) &&
  bothGap.blocksStatementCompletion .definition &&
  bothGap.blocksStatementCompletion .proposition &&
  bothGap.blocksStatementCompletion .lemma &&
  bothGap.blocksStatementCompletion .theorem &&
  bothGap.blocksStatementCompletion .corollary &&
  stmtGap.blocksProofCompletion &&
  proofGap.blocksProofCompletion

/-- info: true -/
#guard_msgs in
#eval
  let statuses : Array ProvedStatus := #[.proved, ProvedStatus.ofRefCounts 0 1]
  ProvedStatus.anyBlocksStatementCompletion .definition statuses (fun s => s) &&
  (!ProvedStatus.anyBlocksStatementCompletion .proposition statuses (fun s => s)) &&
  (!ProvedStatus.anyBlocksStatementCompletion .theorem statuses (fun s => s)) &&
  ProvedStatus.anyBlocksProofCompletion statuses (fun s => s)

def definitionWithProofGap : Node :=
  {
    kind := .definition
    statement := some (mkInformal #[])
    leanCode := #[mkLiterateCode #[mkDefDecl `def_with_proof_gap 0 1] #[]]
  }

/-- info: true -/
#guard_msgs in
#eval
  let external : ExternalCodeStatus := {}
  nodeHasStatementSorries external definitionWithProofGap &&
  nodeHasProofSorries external definitionWithProofGap &&
  (!nodeLocalStatementFormalized external definitionWithProofGap) &&
  (!nodeLocalFormalized external definitionWithProofGap)

def theoremWithHelperDefProofGap : Node :=
  {
    kind := .theorem
    statement := some (mkInformal #[])
    leanCode := #[mkLiterateCode
      #[mkDefDecl `helper_def_with_proof_gap 0 1]
      #[mkThmDecl `main_theorem 0 0]]
  }

/-- info: true -/
#guard_msgs in
#eval
  let external : ExternalCodeStatus := {}
  nodeLocalStatementFormalized external theoremWithHelperDefProofGap &&
  nodeHasProofSorries external theoremWithHelperDefProofGap &&
  (!nodeLocalProofFormalized external theoremWithHelperDefProofGap) &&
  (!nodeLocalFormalized external theoremWithHelperDefProofGap)

def theoremWithProofGapOnly : Node :=
  {
    kind := .theorem
    statement := some (mkInformal #[])
    leanCode := #[mkLiterateCode #[] #[mkThmDecl `theorem_with_proof_gap 0 1]]
  }

/-- info: true -/
#guard_msgs in
#eval
  let external : ExternalCodeStatus := {}
  nodeLocalStatementFormalized external theoremWithProofGapOnly &&
  (!nodeLocalProofFormalized external theoremWithProofGapOnly)

end Verso.VersoBlueprintTests.BlueprintSummaryStatus
