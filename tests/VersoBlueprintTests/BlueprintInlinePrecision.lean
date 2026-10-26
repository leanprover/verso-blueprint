/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoManual

open Lean
open Verso Genre Manual
open Informal
open Informal.Graph

namespace Verso.VersoBlueprintTests.BlueprintInlinePrecision

#docs (Manual) inlineHelperProofGapDoc "Inline Helper Proof Gap" :=
:::::::
:::theorem "inline.theorem.helper"
Statement body.
:::

```lean "inline.theorem.helper"
def helper_inline_proof_gap : True := by
  sorry

theorem inline_main_complete : True := by
  trivial
```
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show Elab.Term.TermElabM Bool from do
    let label := Name.mkSimple "inline.theorem.helper"
    let state := Informal.Environment.informalExt.getState (← getEnv)
    match state.data.get? label with
    | none => pure false
    | some node =>
      let .ok snapshot ← Realizations.Capture.capture | pure false
      let assessment := snapshot.assessmentFor label
      let helperProofGapOnly :=
        node.literateCodes.any fun code =>
          code.definedDefs.any fun decl =>
            let (typeRefs, proofRefs) := decl.provedStatus.sorryRefCounts
            decl.provedStatus.hasProofGap &&
            !decl.provedStatus.hasTypeGap &&
            typeRefs == 0 &&
            proofRefs > 0
      pure <|
        node.kind == .theorem &&
        -- The helper is a definition: its value is part of its statement.
        -- The complete theorem cannot lend that helper a successful check.
        !assessment.nativeStatementComplete &&
        !assessment.nativeProofComplete && !assessment.requiredComplete &&
        helperProofGapOnly

#docs (Manual) inlineGeneratedDeclsDoc "Inline Generated Decls" :=
:::::::
:::definition "inline.generated.filtered"
Inline Lean code should report only source-backed declarations.
:::

```lean "inline.generated.filtered"
structure SourceFilteredStructure where
  alpha : Nat
  beta : alpha = alpha

inductive SourceFilteredStage where
  | initial
  | followup (_ : Nat)
```
:::::::

private def literateDeclNamesFor? (label : Name) : CoreM (Option (Array String)) := do
  let state := Informal.Environment.informalExt.getState (← getEnv)
  match state.data.get? label with
  | none => pure none
  | some node =>
    let names :=
      node.literateCodes.foldl (init := #[]) fun acc code =>
        acc ++ (code.definedDefs.map (·.name.toString)) ++
          (code.definedTheorems.map (·.name.toString))
    pure <| if names.isEmpty then none else some names

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let some names ← literateDeclNamesFor? (Name.mkSimple "inline.generated.filtered")
      | pure false
    let expectedSuffixes := #[
      "SourceFilteredStructure",
      "SourceFilteredStructure.alpha",
      "SourceFilteredStructure.beta",
      "SourceFilteredStage",
      "SourceFilteredStage.initial",
      "SourceFilteredStage.followup"
    ]
    let hasExactlySourceDecls :=
      names.size == expectedSuffixes.size &&
        expectedSuffixes.all (fun suffix => names.any (fun name => name.endsWith suffix))
    let generatedFragments := #[
      ".casesOn",
      ".ctorElim",
      ".ctorElimType",
      ".ctorIdx",
      ".elim",
      ".inj",
      ".injEq",
      ".mk",
      ".noConfusion",
      ".noConfusionType",
      ".rec",
      ".recOn",
      ".sizeOf_spec"
    ]
    let noGeneratedDecls :=
      names.all fun name =>
        !generatedFragments.any (fun fragment => name.contains fragment)
    pure (hasExactlySourceDecls && noGeneratedDecls)

end Verso.VersoBlueprintTests.BlueprintInlinePrecision
