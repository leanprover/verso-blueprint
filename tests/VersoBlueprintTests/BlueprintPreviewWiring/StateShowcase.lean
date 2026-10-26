/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.StateShowcase

open Verso
open Verso.Genre.Manual
open Informal
open Informal.Graph
open Verso.VersoBlueprintTests.Blueprint.Support

set_option doc.verso true

def manualImpls : ExtensionImpls := extension_impls%

@[blueprint "def:showcase.lean_only"]
def previewShowcaseLeanOnly : Nat := 11

/--
warning: Label «def:showcase.external_missing»: external Lean name 'Nat.nope' could not be resolved in current namespace/open declarations; keeping parsed name
-/
#guard_msgs in
#docs (Genre.Manual) stateShowcaseDoc "Blueprint Graph State Showcase" :=
:::::::
:::definition "def:showcase.base"
Base definition with complete local Lean code.
:::

```lean "def:showcase.base"
def showcaseBase : Nat := 1
```

:::definition "def:showcase.ready"
Ready statement depending on {uses "def:showcase.base"}[].
:::

:::definition "def:showcase.blocked"
Blocked statement depending on {uses "def:showcase.ready"}[].
:::

:::theorem "thm:showcase.proof_ready"
Statement depends on {uses "def:showcase.base"}[].
:::

:::proof "thm:showcase.proof_ready"
Proof also depends on {uses "def:showcase.base"}[].
:::

:::theorem "thm:showcase.not_ready"
Statement depends on {uses "def:showcase.base"}[].
:::

:::proof "thm:showcase.not_ready"
Proof depends on {uses "def:showcase.ready"}[].
:::

:::theorem "thm:showcase.incomplete"
Locally started theorem depending on {uses "def:showcase.base"}[].
:::

```lean "thm:showcase.incomplete"
theorem showcaseIncomplete : True := by
  sorry
```

:::theorem "thm:showcase.local_done"
Locally complete theorem depending on {uses "def:showcase.ready"}[].
:::

```lean "thm:showcase.local_done"
theorem showcaseLocalDone : True := by
  trivial
```

:::theorem "thm:showcase.full_done"
Fully complete theorem depending on {uses "def:showcase.base"}[].
:::

```lean "thm:showcase.full_done"
theorem showcaseFullDone : True := by
  trivial
```

:::definition "def:showcase.external_missing" (lean := "Nat.nope")
Missing external declaration sample.
:::

:::lemma_ "lem:showcase.lean_only_user"
Statement depending on {uses "def:showcase.lean_only"}[].
:::

:::lemma_ "lem:showcase.unknown_ref" (uses := "def:showcase.ghost")
Statement with an intentionally unresolved graph dependency, `def:showcase.ghost`.
:::

{blueprint_graph}

{blueprint_summary}
:::::::

/-- Captured in this fixture's environment before unrelated fixtures are imported. -/
def stateShowcaseDocBlueprint : Informal.BlueprintDocument := .capture stateShowcaseDoc.toPart

/-- info: #[] -/
#guard_msgs in
#eval
  show IO (Array String) from do
    let model := stateShowcaseDocBlueprint.model
    let out ← renderManualDocHtmlString manualImpls stateShowcaseDoc (model := model)
    let assessmentFor? (label : String) :=
      (model.nodes.find? (·.label == Lean.Name.mkSimple label)).bind (·.assessment)
    let graphNode? (label : String) :=
      model.graph.nodes.find? (·.label == Lean.Name.mkSimple label)
    let nativeBase := (assessmentFor? "def:showcase.base").any fun assessment =>
      assessment.hasNativeDeclarations && assessment.nativeStatementComplete &&
        assessment.nativeProofComplete && assessment.requiredComplete
    let incompleteTheorem := (assessmentFor? "thm:showcase.incomplete").any fun assessment =>
      assessment.hasNativeDeclarations && !assessment.nativeProofComplete
    let proseOnly := (assessmentFor? "thm:showcase.proof_ready").any fun assessment =>
      !assessment.hasNativeDeclarations
    let unresolvedUse := (graphNode? "lem:showcase.unknown_ref").any fun node =>
      node.statementUses.any (·.label == Lean.Name.mkSimple "def:showcase.ghost")
    let ghostIsUnresolved := (graphNode? "def:showcase.ghost").any fun node =>
      node.assessment.isNone && node.warnings.unknownRef
    let checks : Array (String × Bool) := #[
      ("proof status legend", hasSubstr out "Proof Status"),
      ("unassessed status legend", hasSubstr out proofStatusUnassessedText),
      ("not ready status legend", hasSubstr out proofStatusNoneText),
      ("ready status legend", hasSubstr out proofStatusReadyText),
      ("incomplete status legend", hasSubstr out proofStatusIncompleteText),
      ("formalized status legend", hasSubstr out proofStatusFormalizedText),
      ("formalized with dependencies legend", hasSubstr out proofStatusFormalizedAncestorsText),
      ("unknown reference from selected uses", hasSubstr out "Unknown reference"),
      ("missing external native declaration", hasSubstr out "Missing external Lean declaration"),
      ("missing informal coverage is reported separately", hasSubstr out "Missing informal coverage"),
      ("unknown target label", hasSubstr out "def:showcase.ghost"),
      ("native-only captured label", hasSubstr out "def:showcase.lean_only"),
      ("current blocker section", hasSubstr out "Current blockers ("),
      ("sorry source display", hasSubstr out "Declaration with sorry:"),
      ("inline declaration has a current native check", nativeBase),
      ("incomplete theorem keeps its native proof unfinished", incompleteTheorem),
      ("native-free prose remains unassessed", proseOnly),
      ("ordinary selected use remains in canonical graph", unresolvedUse),
      ("unresolved target is not fabricated as a node", ghostIsUnresolved)]
    pure <| checks.filterMap fun (name, ok) => if ok then none else some name

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.StateShowcase
