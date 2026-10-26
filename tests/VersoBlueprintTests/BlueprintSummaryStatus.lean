/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Commands.Summary.Collect
import VersoBlueprintTests.BlueprintRealizationCapture

open Lean Elab Command Term
open Informal Data Graph Realizations Translations

namespace Verso.VersoBlueprintTests.BlueprintSummaryStatus

private def ensure (condition : Bool) (message : String) : TermElabM Unit :=
  unless condition do throwError message

private def obtain [Repr ε] (value : Except ε α) : TermElabM α :=
  match value with
  | .ok value => pure value
  | .error issue => throwError "Capture failed: {repr issue}"

run_cmd liftTermElabM do
  let counts : Commands.EntryStatusCounts := { completedDepsNo := 1 }
  ensure ((Commands.statusCountsText counts).contains "native checks complete, requirements incomplete: 1")
    "Summary text must not call every unfinished realization requirement a dependency gap"
  let snapshot ← obtain (← Capture.capture)
  let summary ← liftM (m := CoreM) (Commands.buildSummary snapshot)
  ensure (summary.totalEntries == snapshot.registry.nodes.size)
    "Summary inventory must come from admitted realization nodes"
  ensure (summary.pendingInformalEntries.any (·.label == Name.mkSimple "capture.complete"))
    "Optional prose assessment must not erase informational missing-prose coverage"
  ensure (summary.leanDecls > 0 && summary.incompleteDecls > 0)
    "Summary native counts should come from captured declaration requirements"
  ensure (summary.incompleteDetails.any (·.label == Name.mkSimple "capture.admitted"))
    "Detailed native debt should retain the freshly checked provider status"

  let complete := snapshot.assessmentFor (Name.mkSimple "capture.complete")
  let dependent := snapshot.assessmentFor (Name.mkSimple "capture.dependent")
  let missingProse := snapshot.registry.resultFor
    (.realization ⟨Name.mkSimple "capture.complete", `verso⟩)
  ensure (missingProse.status == .unassessed)
    "Missing prose is an unassessed optional realization, separate from coverage inventory"
  ensure (complete.nativeProofComplete && complete.requiredComplete)
    "Native proof and its own realization closure should be counted complete"
  ensure (dependent.nativeProofComplete && !dependent.requiredComplete)
    "Native proof completion should remain separate from unfinished Blueprint dependencies"

end Verso.VersoBlueprintTests.BlueprintSummaryStatus
