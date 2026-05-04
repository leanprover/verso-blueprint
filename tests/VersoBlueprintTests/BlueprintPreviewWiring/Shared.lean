/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

open Verso
open Verso.Genre.Manual
open Informal

set_option doc.verso true

def manualImpls : ExtensionImpls := extension_impls%

tex_prelude r#"
\newcommand{\previewmacro}{\mathsf{Preview}}
"#

#docs (Genre.Manual) previewWiringDoc "Blueprint Preview Wiring" :=
:::::::
:::definition "def:preview.base"
Base statement using $`\previewmacro` in summary and graph previews.
:::

:::lemma_ "lem:preview.next"
Depends on {uses "def:preview.base"}[].
:::

{blueprint_graph}

{blueprint_summary}
:::::::

#docs (Genre.Manual) usedByPreviewDoc "Blueprint Used-By Preview Wiring" :=
:::::::
:::definition "def:used.target"
Target statement with associated Lean code.
:::

```lean "def:used.target"
def usedByPreviewTarget : Nat := 0
```

:::lemma_ "lem:used.statement"
Statement depends on {uses "def:used.target"}[].
:::

:::theorem "thm:used.proof"
Separate theorem with a proof-only dependency.
:::

:::proof "thm:used.proof"
Proof depends on {uses "def:used.target"}[].
:::
:::::::

#docs (Genre.Manual) usedBySinglePreviewDoc "Blueprint Used-By Single Preview Wiring" :=
:::::::
:::definition "def:used.single"
Target statement with exactly one reverse dependency.
:::

:::lemma_ "lem:used.single.next"
Statement depends on {uses "def:used.single"}[].
:::
:::::::

#docs (Genre.Manual) leanStatusChipDoc "Blueprint Lean Status Chip Wiring" :=
:::::::
:::definition "def:status.proved"
Statement with proved Lean code.
:::

```lean "def:status.proved"
def previewStatusProved : Nat := 0
```

:::definition "def:status.sorry"
Statement with Lean code containing sorry.
:::

```lean "def:status.sorry"
theorem previewStatusSorry : True := by
  sorry
```

:::definition "def:status.axiom"
Statement with axiom-like Lean code.
:::

```lean "def:status.axiom"
axiom previewStatusAxiom : True
```

:::definition "def:status.none"
Statement without Lean code.
:::
:::::::

#docs (Genre.Manual) leanCodeLinkPreviewDoc "Blueprint Lean Code Link Preview Wiring" :=
:::::::
:::definition "def:code.preview" (lean := "Nat.add")
Statement with an associated Lean declaration link in the summary.
:::

{blueprint_summary}
:::::::

/-- External declaration docstring dedup marker for repeated preview refs. -/
def externalDocstringDedupDecl : Nat := 0

#docs (Genre.Manual) externalDocstringDedupDoc "External Docstring Dedup Wiring" :=
:::::::
:::definition "def:external.docstring.one" (lean := "Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.externalDocstringDedupDecl")
First statement with a repeated external declaration preview target.
:::

:::definition "def:external.docstring.two" (lean := "Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.externalDocstringDedupDecl")
Second statement with the same external declaration preview target.
:::

{blueprint_summary}
:::::::

#docs (Genre.Manual) proofFallbackSummaryDoc "Blueprint Proof Fallback Summary Wiring" :=
:::::::
:::theorem "thm:preview.proof_fallback"
:::

:::proof "thm:preview.proof_fallback"
Proof fallback body for summary wiring.
:::

{blueprint_summary}
:::::::

#docs (Genre.Manual) groupPreviewDoc "Blueprint Group Preview Wiring" :=
:::::::
:::group "grp:preview"
Preview group title.
:::

:::definition "def:group.target" (parent := "grp:preview")
Target statement in a declared group.
:::

:::lemma_ "lem:group.peer.one" (parent := "grp:preview")
First peer in the same group.
:::

:::lemma_ "lem:group.peer.two" (parent := "grp:preview")
Second peer in the same group.
:::

:::lemma_ "lem:group.user"
Statement depends on {uses "def:group.target"}[].
:::
:::::::

#docs (Genre.Manual) missingGroupPreviewDoc "Blueprint Missing Group Preview Wiring" :=
:::::::
:::definition "def:group.missing.target" (parent := "grp:missing")
Target statement in an undeclared group.
:::

:::lemma_ "lem:group.missing.peer" (parent := "grp:missing")
Peer statement sharing the undeclared parent.
:::
:::::::

#docs (Genre.Manual) singleDeclaredGroupDoc "Blueprint Single Declared Group Wiring" :=
:::::::
:::group "grp:solo"
Solo group title.
:::

:::definition "def:group.solo" (parent := "grp:solo")
Only entry in its declared group.
:::
:::::::

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared
