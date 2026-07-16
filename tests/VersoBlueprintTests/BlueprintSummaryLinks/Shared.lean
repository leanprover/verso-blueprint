/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared

open Verso
open Verso.Genre.Manual
open Informal

set_option doc.verso true

def manualImpls : ExtensionImpls := extension_impls%

private def syntheticSummaryDoc (summary : Informal.Commands.Summary) : Doc.VersoDoc Genre.Manual :=
  .mk
    (fun _ =>
      Doc.Part.mk
        #[]
        "Synthetic Summary"
        none
        #[Doc.Block.other (Informal.Commands.Block.summary summary) #[]]
        #[])
    "{}"

def summaryDiagnosticsSyntheticDoc (showDebugDiagnostics : Bool) : Doc.VersoDoc Genre.Manual :=
  syntheticSummaryDoc {
    showDebugDiagnostics
    totalEntries := 1
    renderFailures := [{
      label := `diag.render
      kind := "definition"
      written := `Diag.renderFail
      canonical := `Diag.renderFail
      message := "synthetic render failure"
    }]
  }

#docs (Genre.Manual) externalSummaryLinksDoc "External Summary Links" :=
:::::::
:::definition "def:external.summary" (lean := "Nat.add")
External declaration wiring test.
:::

{blueprint_summary}
:::::::

/--
warning: Label «def:blocker.missing»: external Lean name 'Nat.nope' could not be resolved in current namespace/open declarations; keeping parsed name
-/
#guard_msgs in
#docs (Genre.Manual) summaryBlockersDoc "Summary Blockers" :=
:::::::
:::definition "def:blocker.missing" (lean := "Nat.nope")
Missing external declaration sample.
:::

:::definition "def:blocker.sorry"
Inline sorry sample.
:::

```lean "def:blocker.sorry"
theorem summaryBlockerSorry : True := by
  sorry
```

{blueprint_summary}
:::::::

#docs (Genre.Manual) summaryTriageDoc "Summary Triage" :=
:::::::
:::author "alice" (name := "Alice Example")
:::

:::author "bob" (name := "Bob Example")
:::

:::group "triage.group"
Triage group heading.
:::

:::definition "def:triage.01" (parent := "triage.group") (owner := "alice") (tags := "foundation, local") (effort := "small") (priority := "low") (pr_url := "https://example.com/pr/1")
Definition 01.
:::

:::definition "def:triage.02" (parent := "triage.group")
Definition 02.
:::

:::definition "def:triage.03" (parent := "triage.group")
Definition 03.
:::

:::definition "def:triage.04" (parent := "triage.group")
Definition 04.
:::

:::definition "def:triage.05" (parent := "triage.group")
Definition 05.
:::

:::definition "def:triage.06" (parent := "triage.group")
Definition 06.
:::

:::definition "def:triage.07" (parent := "triage.group")
Definition 07.
:::

:::definition "def:triage.08" (parent := "triage.group")
Definition 08.
:::

:::definition "def:triage.09" (parent := "triage.group")
Definition 09.
:::

:::definition "def:triage.10" (parent := "triage.group")
Definition 10.
:::

:::definition "def:triage.11" (parent := "triage.group")
Definition 11.
:::

:::definition "def:triage.12" (parent := "triage.group") (owner := "bob") (tags := "critical, quick-win") (effort := "small") (priority := "high") (pr_url := "https://example.com/pr/12")
Definition 12.
:::

:::definition "def:triage.leaf" (parent := "triage.group") (owner := "bob") (tags := "critical, leaf-quick-win") (effort := "small") (priority := "high")
Actionable leaf definition with no downstream users.
:::

:::theorem "thm:triage.main" (parent := "triage.group") (owner := "alice") (tags := "critical") (effort := "large")
Depends on
{uses "def:triage.01"}[],
{uses "def:triage.02"}[],
{uses "def:triage.03"}[],
{uses "def:triage.04"}[],
{uses "def:triage.05"}[],
{uses "def:triage.06"}[],
{uses "def:triage.07"}[],
{uses "def:triage.08"}[],
{uses "def:triage.09"}[],
{uses "def:triage.10"}[],
{uses "def:triage.11"}[],
and {uses "def:triage.12"}[].
:::

:::theorem "thm:triage.proof" (parent := "triage.group")
Proof-only dependency sample.
:::

:::proof "thm:triage.proof"
Proof uses {uses "def:triage.01"}[] and {uses "def:triage.02"}[].
:::

{blueprint_summary}
:::::::

end Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared
