/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

open Verso
open Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support
open Informal

set_option doc.verso true

def hasRenderReadyBootstrap (js : String) : Bool :=
  hasSubstr js "namespace.onRenderReady = function (fn) {"

def hasRenderReadyCallback (js param : String) : Bool :=
  hasSubstr js ("window.VersoBlueprint.onRenderReady(function (" ++ param ++ ") {")

def hasRenderReadyCallbackNoParam (js : String) : Bool :=
  hasSubstr js "window.VersoBlueprint.onRenderReady(function () {"

def hasRenderReadyWiring (js param : String) : Bool :=
  hasRenderReadyBootstrap js && hasRenderReadyCallback js param

def hasRenderReadyWiringNoParam (js : String) : Bool :=
  hasRenderReadyBootstrap js && hasRenderReadyCallbackNoParam js

def hasAllSubstr (s : String) (needles : List String) : Bool :=
  needles.all fun needle => hasSubstr s needle

def lacksAllSubstr (s : String) (needles : List String) : Bool :=
  needles.all fun needle => !hasSubstr s needle

def hasTemplatePreviewDescriptor
    (html panelSelector templateSelector triggerSelector titleSelector bodySelector closeSelector : String)
    (allowHtmlCache : Bool := false) : Bool :=
  hasAllSubstr html ([
    "data-bp-template-preview-root=\"true\"",
    "data-bp-template-preview-panel-selector=\"" ++ panelSelector ++ "\"",
    "data-bp-template-preview-template-selector=\"" ++ templateSelector ++ "\"",
    "data-bp-template-preview-trigger-selector=\"" ++ triggerSelector ++ "\"",
    "data-bp-template-preview-title-selector=\"" ++ titleSelector ++ "\"",
    "data-bp-template-preview-body-selector=\"" ++ bodySelector ++ "\"",
    "data-bp-template-preview-close-selector=\"" ++ closeSelector ++ "\"",
    "data-bp-template-preview-mode=\"hover\"",
    "data-bp-template-preview-placement=\"anchored\""
  ] ++ if allowHtmlCache then [
    "data-bp-template-preview-allow-html-cache=\"true\""
  ] else [])

def findInlinePreviewJs? (st : TraverseState) : Option String :=
  findExtraJsContaining? st "const triggerSelector = \".bp_inline_preview_ref[data-bp-preview-id]\""

def findMathPreludeJs? (st : TraverseState) : Option String :=
  findExtraJsContaining? st "window.bpTexPreludeTable"

def findRemovedTemplatePreviewBinderJs? (st : TraverseState) : Option String :=
  findExtraJsContaining? st "previewUtils.bindTemplatePreviewRoots({"

def findRelationPanelJs? (st : TraverseState) : Option String :=
  findExtraJsContaining? st "previewUtils.registerPreviewHydrator(\"relationPanel\""

def findGraphPreviewJs? (st : TraverseState) : Option String :=
  findExtraJsContaining? st "document.querySelectorAll(\".bp_graph_fullwidth\")"

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
Statement depends on {uses "def:used.target" (origin := "automatic") (intent := "technical")}[].
:::

:::theorem "thm:used.proof"
Separate theorem with a proof-only dependency.
:::

:::proof "thm:used.proof"
Proof depends on {uses "def:used.target" (intent := "auxiliary")}[].
:::
:::::::

#docs (Genre.Manual) usesPreviewDoc "Blueprint Uses Preview Wiring" :=
:::::::
:::definition "def:uses.hidden"
Metadata-only dependency target.
:::

:::definition "def:uses.inline"
Inline dependency target.
:::

:::definition "def:uses.proof"
Proof dependency target.
:::

:::definition "def:uses.proof.extra"
Proof metadata-only dependency target.
:::

:::theorem "thm:uses.panel" (uses := "def:uses.hidden") (uses_origin := "automatic") (uses_intent := "technical")
Statement depends on {uses "def:uses.inline" (intent := "auxiliary")}[].
:::

:::proof "thm:uses.panel" (uses := "def:uses.proof.extra")
Proof depends on {uses "def:uses.proof"}[].
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

namespace ShortExternalPreview

def openedSummaryDecl : Nat := 0

end ShortExternalPreview

open ShortExternalPreview

#docs (Genre.Manual) shortExternalNamePreviewDoc "Blueprint Short External Name Preview Wiring" :=
:::::::
:::definition "def:code.short_external" (lean := "openedSummaryDecl")
Statement with a namespace-opened external declaration name.
:::
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
