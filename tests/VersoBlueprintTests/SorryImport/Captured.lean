/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support
import VersoBlueprintTests.SorryImport.Provider

open Lean Verso Genre Manual Informal Informal.Data

namespace Verso.VersoBlueprintTests.SorryImport.Captured

@[blueprint "sorry.capture.type-only" (autoDeps := false)]
theorem capturedTypeOnly : sorryImportSpec := True.intro

@[blueprint "sorry.capture.both" (autoDeps := false)]
theorem capturedBoth : sorryImportSpec := by sorry

@[blueprint "sorry.capture.proof-only" (autoDeps := false)]
theorem capturedProofOnly : True := sorryImportAdmitted

@[blueprint "sorry.capture.complete" (autoDeps := false)]
theorem capturedComplete : True := True.intro

#docs (Manual) statusCaptureDoc "Captured status evidence" :=
:::::::
:::theorem "sorry.capture.external" (lean := "capturedBoth")
The external attachment retains simultaneous statement and proof gaps.
:::

:::theorem "sorry.capture.inline"
A checked proof can depend on an admitted helper without a Blueprint edge.
:::

```lean "sorry.capture.inline"
theorem inlineStatusComposition : True :=
  sorryImportAdmitted
```

:::definition "sorry.capture.inline-record"
A direct hole in a constructor field belongs to the structure's statement.
:::

```lean "sorry.capture.inline-record"
structure InlineIncompleteRecord where
  payload : (by sorry : Type)
```
:::::::

def statusCaptureBlueprint : BlueprintDocument := .capture statusCaptureDoc.toPart

private def capturedStatus? (label : String) : Option ProvedStatus := do
  let node ← statusCaptureBlueprint.model.nodes.find? (·.label == Name.mkSimple label)
  let ref ← node.externalRefs[0]?
  return ref.provedStatus

/-- info: true -/
#guard_msgs in
#eval
  let statement : SorryInfo := { location := .statement, origin := .dependency }
  let proof : SorryInfo := { location := .proof }
  let inheritedProof : SorryInfo := { location := .proof, origin := .dependency }
  capturedStatus? "sorry.capture.type-only" == some (.incomplete { knownSorry := #[statement] }) &&
    capturedStatus? "sorry.capture.both" == some (.incomplete { knownSorry := #[statement, proof, inheritedProof] }) &&
    capturedStatus? "sorry.capture.proof-only" == some (.incomplete { knownSorry := #[inheritedProof] }) &&
    capturedStatus? "sorry.capture.complete" == some .proved &&
    capturedStatus? "sorry.capture.external" == capturedStatus? "sorry.capture.both"

/-- info: true -/
#guard_msgs in
#eval
  let model := statusCaptureBlueprint.model
  let graphStatus (label : String) :=
    model.graph.nodes.find? (·.label == Name.mkSimple label) |>.map (·.proofStatus)
  let summaryStatus (label : String) :=
    model.summary.incompleteDetails.find? (·.label == Name.mkSimple label) |>.map (·.status)
  graphStatus "sorry.capture.type-only" == some .incomplete &&
    graphStatus "sorry.capture.both" == some .incomplete &&
    graphStatus "sorry.capture.proof-only" == some .incomplete &&
    graphStatus "sorry.capture.inline" == some .incomplete &&
    (graphStatus "sorry.capture.complete" == some .formalized ||
      graphStatus "sorry.capture.complete" == some .formalizedWithAncestors) &&
    (summaryStatus "sorry.capture.type-only").any (fun status => status.hasTypeGap && !status.hasProofGap) &&
    (summaryStatus "sorry.capture.both").any (fun status => status.hasTypeGap && status.hasProofGap) &&
    (summaryStatus "sorry.capture.inline").any (fun status => status.dependsOnSorry && !status.containsExplicitSorry) &&
    (summaryStatus "sorry.capture.complete").isNone &&
    (summaryStatus "sorry.capture.inline-record").any (fun status =>
      status.hasTypeGap && status.containsExplicitSorry && status.sorryRefCounts.1 > 0) &&
    model.summary.incompleteDecls > 5

-- Captured producer evidence survives duplicate snapshot merging, including a
-- later consumer whose neutral lookup contributes no additional evidence.
/-- info: true -/
#guard_msgs in
#eval
  match capturedStatus? "sorry.capture.both" with
  | none => false
  | some status =>
    let merged := status.mergeConservative .proved
    merged == status && merged.mergeConservative status == status &&
      merged.hasTypeGap && merged.hasProofGap && merged.containsExplicitSorry && merged.dependsOnSorry

end Verso.VersoBlueprintTests.SorryImport.Captured
