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

:::lemma_ "lem:showcase.unknown_ref"
Statement depending on {uses "def:showcase.ghost"}[].
:::

{blueprint_graph}

{blueprint_summary}
:::::::

/-- Captured in this fixture's environment before unrelated fixtures are imported. -/
def stateShowcaseDocBlueprint : Informal.BlueprintDocument := .capture stateShowcaseDoc.toPart

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls stateShowcaseDoc
    pure (
      hasSubstr out "Proof Status" &&
      hasSubstr out proofStatusNoneText &&
      hasSubstr out proofStatusReadyText &&
      hasSubstr out proofStatusIncompleteText &&
      hasSubstr out proofStatusFormalizedText &&
      hasSubstr out proofStatusFormalizedAncestorsText &&
      hasSubstr out "Unknown reference" &&
      hasSubstr out "Missing external Lean declaration" &&
      hasSubstr out "Lean code, informal statement missing" &&
      hasSubstr out "def:showcase.ghost" &&
      hasSubstr out "def:showcase.lean_only" &&
      hasSubstr out "Current blockers (2)" &&
      hasSubstr out "Declaration with sorry:"
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.StateShowcase
