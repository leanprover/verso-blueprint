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

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let env ← getEnv
    let some axiomInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_axiom_decl
      | return false
    let some defInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_def_decl
      | return false
    let axiomStatus := ConstantInfo.blueprintProvedStatus axiomInfo (allowOpaque := true)
    let defStatus := ConstantInfo.blueprintProvedStatus defInfo (allowOpaque := true)
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
  let sorryView := sorryStatus.presentation
  let missingView := Data.ProvedStatus.proved.presentation (present := false)
  let axiomView := Data.ProvedStatus.axiomLike.presentation
  sorryView.summaryText == "sorry in proof" &&
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
