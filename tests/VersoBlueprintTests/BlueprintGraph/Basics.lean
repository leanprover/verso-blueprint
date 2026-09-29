/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintGraph.Shared

namespace Verso.VersoBlueprintTests.BlueprintGraph.Basics

open Lean
open Informal
open Informal.Data
open Informal.Environment
open Informal.Graph
open Verso.VersoBlueprintTests.BlueprintGraph.Shared

theorem statusAdmittedHelper : True := by
  sorry

theorem statusConsumer : True := statusAdmittedHelper

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let env ← getEnv
    let some helper := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusAdmittedHelper
      | return false
    let some consumer := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Basics.statusConsumer
      | return false
    let helperStatus ← ConstantInfo.blueprintProvedStatus helper.name helper
    let consumerStatus ← ConstantInfo.blueprintProvedStatus consumer.name consumer
    let some axiomInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_axiom_decl
      | return false
    let axiomFootprint ← collectAxioms axiomInfo.name
    let accessCases :=
      (match ConstantInfo.blueprintBodyAccess consumer.name consumer #[] with
        | .available _ => true
        | _ => false) &&
      (match ConstantInfo.blueprintBodyAccess axiomInfo.name axiomInfo axiomFootprint with
        | .absent => true
        | _ => false) &&
      (match ConstantInfo.blueprintBodyAccess axiomInfo.name axiomInfo #[] with
        | .unavailable => true
        | _ => false)
    let node : Data.Node := {
      kind := .theorem
      literateCodes := #[{ stx := .missing, definedTheorems :=
        #[{ name := consumer.name, provedStatus := consumerStatus }] }]
    }
    return accessCases && helperStatus.containsExplicitSorry &&
      consumerStatus.dependsOnSorry &&
      !consumerStatus.containsExplicitSorry &&
      consumerStatus.sorryRefCounts == (0, 0) &&
      !nodeLocalProofFormalized {} node

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let env ← getEnv
    let some axiomInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_axiom_decl
      | return false
    let some defInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_def_decl
      | return false
    let axiomStatus ← ConstantInfo.blueprintProvedStatus axiomInfo.name axiomInfo
    let defStatus ← ConstantInfo.blueprintProvedStatus defInfo.name defInfo
    pure (
      axiomStatus == .axiomLike &&
      defStatus == .proved
    )

/-- info: true -/
#guard_msgs in
#eval
  let status : Data.ProvedStatus :=
    .containsSorry #[{ location := .statement, refs? := some 2 }, { location := .proof, refs? := some 3 }]
  Data.NodeKind.definition.isTheoremLike = false &&
  Data.NodeKind.proposition.isTheoremLike &&
  Data.NodeKind.theorem.isTheoremLike &&
  status.sorryLocationText = "in statement and proof" &&
  status.statusLabel = "contains sorry" &&
  status.sorryRefCounts = (2, 3)

/-- info: true -/
#guard_msgs in
#eval
  let sorryStatus : Data.ProvedStatus :=
    .containsSorry #[{ location := .proof, refs? := some 1 }]
  let inheritedStatus : Data.ProvedStatus :=
    .containsSorry #[{ location := .proof, origin := .dependency }]
  let sorryView := sorryStatus.presentation
  let inheritedView := inheritedStatus.presentation
  let missingView := Data.ProvedStatus.proved.presentation (present := false)
  let axiomView := Data.ProvedStatus.axiomLike.presentation
  sorryView.summaryText == "sorry in proof" &&
    inheritedStatus.statusLabel == "depends on sorry" &&
    inheritedView.summaryText == "depends on sorry in proof" &&
    inheritedView.externalHeaderText == "depends on sorry" &&
    sorryView.externalPanelText == "contains sorry in proof" &&
    sorryView.externalHeaderText == "contains sorry" &&
    sorryView.codeDeclClass == "bp_code_decl_status_warning" &&
    sorryView.externalDeclClass == "bp_external_decl_sorry" &&
    sorryView.codeEntryClassSuffix == "warning" &&
    missingView.summaryText == "missing declaration" &&
    missingView.externalHeaderText == "missing" &&
    missingView.codeEntryClassSuffix == "missing" &&
    axiomView.summaryText == "axiom-like (no body)" &&
    axiomView.codeEntryClassSuffix == "axiom" &&
    axiomView.statusMarkSymbol == "⚠"

end Verso.VersoBlueprintTests.BlueprintGraph.Basics
