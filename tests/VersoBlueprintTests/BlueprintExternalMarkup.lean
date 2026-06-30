/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprintTests.Blueprint.Support
import VersoManual

open Lean
open Verso Genre Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintExternalMarkup

private def externalMarkupRaw?
    (sources : Informal.Data.ExternalMarkupSet)
    (language : Informal.Data.ExternalMarkupLanguage)
    (slot : String) : Option String :=
  sources.find? language slot |>.map (·.raw.trimAscii.toString)

private def externalMarkupLocation?
    (sources : Informal.Data.ExternalMarkupSet)
    (language : Informal.Data.ExternalMarkupLanguage)
    (slot : String) : Option Informal.Data.ExternalMarkupLocation :=
  sources.find? language slot |>.bind (·.location)

private def previewEntry?
    (manifest : Informal.PreviewManifest.File) (key : String) :
    Option Informal.PreviewManifest.Entry :=
  manifest.previews.find? (fun entry => entry.key == key)

private def entryExternalDeclNames (entry : Informal.PreviewManifest.Entry) : Array Name :=
  match entry.codeData with
  | some (.external refs) => refs.map (·.canonical)
  | _ => #[]

private def entryHasExternalMarkup
    (entry : Informal.PreviewManifest.Entry)
    (language : Informal.Data.ExternalMarkupLanguage)
    (slot : String) : Bool :=
  entry.externalMarkup.any fun markup =>
    markup.language == language && markup.slot == slot

private def entryHasSourcePage
    (entry : Informal.PreviewManifest.Entry) (document page : String) : Bool :=
  entry.sources.any fun sourceRef =>
    sourceRef.document == document &&
      sourceRef.spans.any (fun span => span.page == page)

private def htmlHasSourceBadge (html document pageText : String) : Bool :=
  hasSubstr html "bp_extra_slot_source" &&
    hasSubstr html "bp_source_ref_badge" &&
    hasSubstr html document &&
    hasSubstr html pageText

private def failedCheckLabels (checks : Array (String × Bool)) : Array String :=
  checks.filterMap fun (label, ok) =>
    if ok then none else some label

private def entryIsExternalMarkup (entry : Informal.PreviewManifest.Entry) : Bool :=
  match entry.targetKind with
  | .externalMarkup => true
  | _ => false

#docs (Manual) externalMarkupDoc "External Markup" :=
:::::::
:::theorem "external.markup"
Statement body.
:::

```tex "external.markup" (slot := statement) (path := "imports/source.tex") (start_line := 4) (start_character := 2) (end_line := 8) (end_character := 0)
\begin{theorem}\label{thm:external-markup}
For every natural number $n$, adding zero on the right leaves it unchanged.
\end{theorem}
```

```md "external.markup" (slot := proof)
Imported **Markdown** proof witness.
```
:::::::

#docs (Manual) unlabeledExternalMarkupDoc "Unlabeled External Markup" :=
:::::::
:::theorem "external.unlabeled.anchor"
Anchor statement.
:::

```tex
\begin{theorem}
An unlabeled witness should stay hidden and should not create a Blueprint node.
\end{theorem}
```
:::::::

#docs (Manual) externalMarkupWitnessDoc "External Markup Witness" :=
:::::::
```tex "external.witness"
\begin{theorem}\label{thm:external-witness}
A source-backed witness can introduce a Blueprint node while porting.
\end{theorem}
```
:::::::

#docs (Manual) externalMarkdownWitnessDoc "External Markdown Witness" :=
:::::::
```md "external.markdown.witness" (slot := statement)
# Markdown witness

For every $n$, **source** text can back a Blueprint node.

- Review imported source

> Standard Markdown blockquote.

| Term | Meaning |
| --- | --- |
| `n` | natural number |

    #check Nat.add

<span>raw HTML stays text</span>
```
:::::::

#docs (Manual) externalBodylessLeanWitnessDoc "External Bodyless Lean Witness" :=
:::::::
:::theorem "external.bodyless.lean" (lean := "Nat.add, Nat.mul")
:::

```md "external.bodyless.lean" (slot := statement)
# Bodyless Lean-backed witness

The source body is imported from Markdown.
```
:::::::

#docs (Manual) externalPunctuationBodylessLeanWitnessDoc "External Punctuation Bodyless Lean Witness" :=
:::::::
:::theorem "Chapter4:Theorem4.2.1" (lean := "Nat.add")
:::

```md "Chapter4:Theorem4.2.1" (slot := statement)
# Punctuation-label witness

The source body is imported from Markdown.
```
:::::::

#docs (Manual) sourcedExternalMarkupWitnessDoc "Sourced External Markup Witness" :=
:::::::
:::source_document "external-paper"
%%%
title := "External Paper"
kind := .pdf
pdf := "source/external-paper.pdf"
%%%
:::

:::theorem "external.sourced.witness"
%%%
source := {
  document := "external-paper"
  spans := #[
    {
      page := "7"
      pdf := some { path := "source/external-paper-page-7.pdf" }
    }
  ]
}
%%%
:::

```md "external.sourced.witness" (slot := statement)
Imported Markdown statement with source provenance.
```
:::::::

#docs (Manual) externalMarkupMultiLanguageDoc "External Markup Multi-language Slots" :=
:::::::
```tex "external.multi" (slot := statement)
TeX statement witness.
```

```md "external.multi" (slot := statement)
Markdown statement witness.
```
:::::::

/--
error: Label «external.duplicate» already has associated tex external markup in slot 'proof'
-/
#guard_msgs in
#docs (Manual) duplicateExternalMarkupSlotDoc "Duplicate External Markup Slot" :=
:::::::
```tex "external.duplicate" (slot := proof)
First proof witness.
```

```tex "external.duplicate" (slot := "proof")
Second proof witness.
```
:::::::

/--
error: External markup location requires all of '(path := ...)', '(start_line := ...)', '(start_character := ...)', '(end_line := ...)', and '(end_character := ...)'
-/
#guard_msgs in
#docs (Manual) incompleteExternalMarkupLocationDoc "Incomplete External Markup Location" :=
:::::::
```md "external.incomplete" (path := "imports/source.md") (start_line := 1)
Incomplete source location.
```
:::::::

/--
error: External markup location range must be non-empty and end-exclusive
-/
#guard_msgs in
#docs (Manual) emptyExternalMarkupLocationDoc "Empty External Markup Location" :=
:::::::
```md "external.empty.range" (path := "imports/source.md") (start_line := 1) (start_character := 2) (end_line := 1) (end_character := 2)
Empty source location.
```
:::::::

#docs (Manual) externalMarkupSummaryDisplayDoc "External Markup Summary Display" :=
:::::::
```md "external.summary" (slot := statement) (path := "imports/source.md") (start_line := 0) (start_character := 0) (end_line := 1) (end_character := 0) (display := summary)
Summary-only content should stay hidden.
```
:::::::

#docs (Manual) externalMarkupSourceDisplayDoc "External Markup Source Display" :=
:::::::
```md "external.source" (display := source)
<raw & source>
```
:::::::

#docs (Manual) externalMarkupShowcaseDoc "External Markup Source Showcase" :=
:::::::
This showcase models a Blueprint that is being migrated from an imported paper.
The visible text is the current informal Blueprint layer. The MD and TeX badges
in Blueprint headers mark original source markup that is attached to the same
label, even when that source is not shown inline.

There are three layers in play:

- the original source pages and extracted markup;
- the informal Blueprint node, which may already be native Verso or may still be
  bodyless;
- the Lean declarations attached with `(lean := ...)`.

:::source_document "imported-paper"
%%%
title := "Imported Paper"
kind := .pdf
pdf := "source/imported-paper.pdf"
pageRoot := "source/pages"
imageRoot := "source/pages/images"
%%%
:::

# Native Blueprint text with imported witnesses

This first node has a normal Verso body. The source witnesses are review data:
the header advertises that Markdown and TeX are attached, while the body remains
the curated Blueprint text.

:::definition "showcase.visible.attachments" (lean := "Nat.add") (tags := "external-source,mixed-markup,native-body")
A native Verso Blueprint node can carry external Markdown and TeX witnesses. The
source markup remains available to the manifest and preview cache, but it does
not replace the authored Blueprint body.
:::

```md "showcase.visible.attachments" (slot := statement) (path := "source/pages/page-12.md") (start_line := 4) (start_character := 0) (end_line := 9) (end_character := 0)
**Imported statement.** This Markdown witness is attached to a native Blueprint
node, so the rendered header shows an MD badge while the visible body remains
the curated Verso text.
```

```tex "showcase.visible.attachments" (slot := proof) (path := "source/imported-paper.tex") (start_line := 42) (start_character := 0) (end_line := 46) (end_character := 0)
\begin{proof}
This proof witness is kept as imported TeX while the Blueprint statement is
being reviewed.
\end{proof}
```

# Bodyless Markdown statement with Lean declarations

This theorem is not native Verso yet. The theorem directive intentionally has no
body, but it still has source provenance, imported Markdown, and Lean
declarations. The preview manifest must therefore keep the source and Lean data
on the external-markup entry.

:::theorem "ImportedPaper:Theorem2.1" (lean := "Nat.add, Nat.mul") (tags := "external-source,markdown-only,bodyless")
%%%
source := {
  document := "imported-paper"
  spans := #[
    {
      page := "12"
      text := some {
        path := "source/pages/page-12.md"
        startLine := 4
        endLine := 15
      }
      pdf := some {
        path := "source/pages/page-12.pdf"
        image := some "source/pages/images/page-12.png"
      }
    }
  ]
}
%%%
:::

```md "ImportedPaper:Theorem2.1" (slot := statement) (path := "source/pages/page-12.md") (start_line := 4) (start_character := 0) (end_line := 15) (end_character := 0)
# Theorem 2.1

For every natural number $n$, the imported source states that addition and
multiplication have canonical recursive behavior.

- Source text is Markdown, not Verso.
- The Blueprint node is intentionally bodyless.
- Lean declarations are still attached to the manifest entry.
```

# Selected Markdown preview with TeX alongside

When a bodyless node has more than one source witness, the generator must choose
one witness for the rendered preview body. This example carries both Markdown
and TeX statement witnesses. The default render preference chooses Markdown for
the preview body, while the header badges still show that both source formats
are attached.

:::theorem "ImportedPaper:Theorem2.1.SelectedMarkdown" (lean := "Nat.add") (tags := "external-source,mixed-markup,selected-markdown,bodyless")
%%%
source := {
  document := "imported-paper"
  spans := #[
    {
      page := "12"
      text := some {
        path := "source/pages/page-12.md"
        startLine := 16
        endLine := 26
      }
      pdf := some {
        path := "source/pages/page-12.pdf"
        image := some "source/pages/images/page-12.png"
      }
    }
  ]
}
%%%
:::

```tex "ImportedPaper:Theorem2.1.SelectedMarkdown" (slot := statement) (path := "source/imported-paper.tex") (start_line := 52) (start_character := 0) (end_line := 58) (end_character := 0)
\begin{theorem}\label{thm:selected-markdown}
This TeX statement is attached, but it is not the selected rendered preview body
when Markdown is also available in the statement slot.
\end{theorem}
```

```md "ImportedPaper:Theorem2.1.SelectedMarkdown" (slot := statement) (path := "source/pages/page-12.md") (start_line := 16) (start_character := 0) (end_line := 26) (end_character := 0)
## Selected Markdown statement

This Markdown witness is selected for the rendered preview body even though a
TeX statement witness is attached to the same node.
```

# Authored labels with punctuation

Imported papers often carry labels such as `Chapter4:Theorem4.2.1` or
`ImportedPaper:Theorem2.2`. The canonical Lean `Name` is useful internally, but
the manifest also preserves the raw authored label for user interfaces.

:::theorem "ImportedPaper:Theorem2.2" (lean := "Nat.add") (tags := "external-source,markdown-only,raw-label")
%%%
source := {
  document := "imported-paper"
  spans := #[
    {
      page := "13"
      text := some {
        path := "source/pages/page-13.md"
        startLine := 1
        endLine := 8
      }
      pdf := some {
        path := "source/pages/page-13.pdf"
        image := some "source/pages/images/page-13.png"
      }
    }
  ]
}
%%%
:::

```md "ImportedPaper:Theorem2.2" (slot := statement) (path := "source/pages/page-13.md") (start_line := 1) (start_character := 0) (end_line := 8) (end_character := 0)
## Theorem 2.2

This second bodyless node uses a punctuation-heavy authored label. The manifest
keeps the raw label and the external Markdown source separately from the Lean
name used for generated declaration previews.
```

# Bodyless TeX statement

Some imports start from TeX rather than Markdown. This node has no native Verso
body and no Markdown witness, but it still gets a TeX badge, source provenance,
and a Lean declaration preview.

:::definition "ImportedPaper:Definition2.3" (lean := "Nat.mul") (tags := "external-source,tex-only,bodyless")
%%%
source := {
  document := "imported-paper"
  spans := #[
    {
      page := "14"
      text := some {
        path := "source/imported-paper.tex"
        startLine := 88
        endLine := 96
      }
      pdf := some {
        path := "source/pages/page-14.pdf"
        image := some "source/pages/images/page-14.png"
      }
    }
  ]
}
%%%
:::

```tex "ImportedPaper:Definition2.3" (slot := statement) (path := "source/imported-paper.tex") (start_line := 88) (start_character := 0) (end_line := 96) (end_character := 0)
\begin{definition}\label{def:imported-multiplication}
The imported TeX source defines the multiplication operation used by the later
results in this section.
\end{definition}
```

# Multi-page source provenance

Source provenance may point at more than one page. The external markup witness
is a compact Markdown extraction, while the source metadata records both PDF
pages that reviewers should inspect.

:::theorem "ImportedPaper:Proposition2.4" (lean := "Nat.add, Nat.mul") (uses := "ImportedPaper:Theorem2.1") (tags := "external-source,multi-page,bodyless")
%%%
source := {
  document := "imported-paper"
  spans := #[
    {
      page := "15"
      text := some {
        path := "source/pages/page-15.md"
        startLine := 20
        endLine := 39
      }
      pdf := some {
        path := "source/pages/page-15.pdf"
        image := some "source/pages/images/page-15.png"
      }
    },
    {
      page := "16"
      text := some {
        path := "source/pages/page-16.md"
        startLine := 1
        endLine := 8
      }
      pdf := some {
        path := "source/pages/page-16.pdf"
        image := some "source/pages/images/page-16.png"
      }
    }
  ]
}
%%%
:::

```md "ImportedPaper:Proposition2.4" (slot := statement) (path := "source/pages/page-15.md") (start_line := 20) (start_character := 0) (end_line := 39) (end_character := 0)
### Proposition 2.4

The imported Markdown extraction summarizes a result whose source spans two
pages. The manifest keeps both source spans, while this witness records the
textual extraction used for review.
```

# Native rewrite after review

After review, an imported item can be rewritten as normal Blueprint prose while
keeping the original source witness attached for auditability.

:::theorem "showcase.native.rewrite" (lean := "Nat.add") (uses := "ImportedPaper:Theorem2.1") (tags := "external-source,native-body,reviewed")
%%%
source := {
  document := "imported-paper"
  spans := #[
    {
      page := "17"
      text := some {
        path := "source/pages/page-17.md"
        startLine := 11
        endLine := 20
      }
      pdf := some {
        path := "source/pages/page-17.pdf"
        image := some "source/pages/images/page-17.png"
      }
    }
  ]
}
%%%

The reviewed theorem is now expressed directly in Verso. Its Markdown badge
shows that the imported source is still connected to the node for comparison and
future audits.
:::

```md "showcase.native.rewrite" (slot := statement) (path := "source/pages/page-17.md") (start_line := 11) (start_character := 0) (end_line := 20) (end_character := 0)
## Reviewed theorem

This is the original Markdown extraction for a theorem that now has native
Blueprint prose.
```

# Summary surface

The summary below is included so the showcase has a review surface as well as
individual node headers. It should retain labels, source-backed nodes, Lean
status, and relationships for nodes whose visible body still comes from
external markup.

{blueprint_summary}
:::::::

/-- info: #[] -/
#guard_msgs in
#eval
  show IO (Array String) from do
    let (showcaseHtml, showcaseState) ←
      renderManualDocHtmlStringAndState extension_impls% externalMarkupShowcaseDoc
    let showcaseFiles ←
      Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) showcaseState
    let manifest := showcaseFiles.manifest
    let nativeKey := Informal.PreviewCache.statementKey (Name.mkSimple "showcase.visible.attachments")
    let theorem21Key :=
      Informal.PreviewManifest.externalMarkupEntryKey (Name.mkSimple "ImportedPaper:Theorem2.1")
    let selectedMarkdownKey :=
      Informal.PreviewManifest.externalMarkupEntryKey
        (Name.mkSimple "ImportedPaper:Theorem2.1.SelectedMarkdown")
    let theorem22Key :=
      Informal.PreviewManifest.externalMarkupEntryKey (Name.mkSimple "ImportedPaper:Theorem2.2")
    let definition23Key :=
      Informal.PreviewManifest.externalMarkupEntryKey (Name.mkSimple "ImportedPaper:Definition2.3")
    let proposition24Key :=
      Informal.PreviewManifest.externalMarkupEntryKey (Name.mkSimple "ImportedPaper:Proposition2.4")
    let rewriteKey := Informal.PreviewCache.statementKey (Name.mkSimple "showcase.native.rewrite")
    let some nativeEntry := previewEntry? manifest nativeKey
      | return #["missing native entry"]
    let some theorem21Entry := previewEntry? manifest theorem21Key
      | return #["missing theorem 2.1 entry"]
    let some selectedMarkdownEntry := previewEntry? manifest selectedMarkdownKey
      | return #["missing selected Markdown entry"]
    let some theorem22Entry := previewEntry? manifest theorem22Key
      | return #["missing theorem 2.2 entry"]
    let some definition23Entry := previewEntry? manifest definition23Key
      | return #["missing definition 2.3 entry"]
    let some proposition24Entry := previewEntry? manifest proposition24Key
      | return #["missing proposition 2.4 entry"]
    let some rewriteEntry := previewEntry? manifest rewriteKey
      | return #["missing native rewrite entry"]
    let some nativeHtml := showcaseFiles.htmlCache.findHtml? nativeKey
      | return #["missing native HTML"]
    let some theorem21Html := showcaseFiles.htmlCache.findHtml? theorem21Key
      | return #["missing theorem 2.1 HTML"]
    let some selectedMarkdownHtml := showcaseFiles.htmlCache.findHtml? selectedMarkdownKey
      | return #["missing selected Markdown HTML"]
    let some definition23Html := showcaseFiles.htmlCache.findHtml? definition23Key
      | return #["missing definition 2.3 HTML"]
    let some proposition24Html := showcaseFiles.htmlCache.findHtml? proposition24Key
      | return #["missing proposition 2.4 HTML"]
    let theorem21Refs := entryExternalDeclNames theorem21Entry
    let selectedMarkdownRefs := entryExternalDeclNames selectedMarkdownEntry
    let theorem22Refs := entryExternalDeclNames theorem22Entry
    let definition23Refs := entryExternalDeclNames definition23Entry
    let proposition24Refs := entryExternalDeclNames proposition24Entry
    let rewriteRefs := entryExternalDeclNames rewriteEntry
    let showcaseLosses :=
      Informal.PreviewManifest.previewMetadataLosses showcaseState manifest
    let selectedMarkup? :=
      Informal.ExternalMarkupRender.selected?
        ({} : Informal.ExternalMarkupRender.Config)
        selectedMarkdownEntry.externalMarkup
    let narrativeChecks : Array (String × Bool) := #[
      ("visible intro", hasSubstr showcaseHtml "This showcase models a Blueprint that is being migrated"),
      ("native scenario text", hasSubstr showcaseHtml "The source witnesses are review data"),
      ("bodyless markdown scenario text", hasSubstr showcaseHtml "This theorem is not native Verso yet"),
      ("selected markdown scenario text", hasSubstr showcaseHtml "more than one source witness"),
      ("selected Markdown page rendered body", hasSubstr showcaseHtml "<h2>Selected Markdown statement</h2>"),
      ("selected Markdown page did not render tex body", !hasSubstr showcaseHtml "thm:selected-markdown"),
      ("bodyless tex scenario text", hasSubstr showcaseHtml "Some imports start from TeX rather than Markdown"),
      ("multi-page scenario text", hasSubstr showcaseHtml "Source provenance may point at more than one page"),
      ("summary scenario text", hasSubstr showcaseHtml "The summary below is included"),
      ("source document", manifest.sourceDocuments.any (fun document =>
        document.id == "imported-paper" &&
          document.title == "Imported Paper" &&
          document.kind == .pdf &&
          document.pdf == some "source/imported-paper.pdf" &&
          document.pageRoot == some "source/pages" &&
          document.imageRoot == some "source/pages/images"))
    ]
    let nativeChecks : Array (String × Bool) := #[
      ("native entry is block", nativeEntry.targetKind == .block),
      ("native authored label", nativeEntry.authoredLabel == "showcase.visible.attachments"),
      ("native markdown attachment", entryHasExternalMarkup nativeEntry .markdown "statement"),
      ("native tex attachment", entryHasExternalMarkup nativeEntry .tex "proof"),
      ("native Lean preview", nativeEntry.leanCodePreviewKeys.any (hasSubstr · "Nat.add")),
      ("page markdown badge", hasSubstr showcaseHtml "bp_external_markup_badge_markdown"),
      ("page tex badge", hasSubstr showcaseHtml "bp_external_markup_badge_tex"),
      ("native rendered body", hasSubstr nativeHtml "source markup remains available")
    ]
    let theorem21Checks : Array (String × Bool) := #[
      ("theorem 2.1 external entry", entryIsExternalMarkup theorem21Entry),
      ("theorem 2.1 authored label", theorem21Entry.authoredLabel == "ImportedPaper:Theorem2.1"),
      ("theorem 2.1 markdown attachment", entryHasExternalMarkup theorem21Entry .markdown "statement"),
      ("theorem 2.1 Nat.add key", theorem21Entry.leanCodePreviewKeys.any (hasSubstr · "Nat.add")),
      ("theorem 2.1 Nat.mul key", theorem21Entry.leanCodePreviewKeys.any (hasSubstr · "Nat.mul")),
      ("theorem 2.1 Nat.add data", theorem21Refs.contains `Nat.add),
      ("theorem 2.1 Nat.mul data", theorem21Refs.contains `Nat.mul),
      ("theorem 2.1 source page", entryHasSourcePage theorem21Entry "imported-paper" "12"),
      ("theorem 2.1 markdown badge", hasSubstr theorem21Html "bp_external_markup_badge_markdown"),
      ("theorem 2.1 source badge", htmlHasSourceBadge theorem21Html "imported-paper" "p. 12"),
      ("theorem 2.1 rendered markdown", hasSubstr theorem21Html "<h1>Theorem 2.1</h1>")
    ]
    let selectedMarkdownChecks : Array (String × Bool) := #[
      ("selected Markdown external entry", entryIsExternalMarkup selectedMarkdownEntry),
      ("selected Markdown authored label", selectedMarkdownEntry.authoredLabel == "ImportedPaper:Theorem2.1.SelectedMarkdown"),
      ("selected Markdown markdown attachment", entryHasExternalMarkup selectedMarkdownEntry .markdown "statement"),
      ("selected Markdown tex attachment", entryHasExternalMarkup selectedMarkdownEntry .tex "statement"),
      ("selected Markdown selected by preference",
        selectedMarkup?.any fun markup =>
          markup.language == .markdown &&
            markup.slot == "statement" &&
            hasSubstr markup.raw "Selected Markdown statement"),
      ("selected Markdown Nat.add data", selectedMarkdownRefs.contains `Nat.add),
      ("selected Markdown source page", entryHasSourcePage selectedMarkdownEntry "imported-paper" "12"),
      ("selected Markdown markdown badge", hasSubstr selectedMarkdownHtml "bp_external_markup_badge_markdown"),
      ("selected Markdown tex badge", hasSubstr selectedMarkdownHtml "bp_external_markup_badge_tex"),
      ("selected Markdown source badge", htmlHasSourceBadge selectedMarkdownHtml "imported-paper" "p. 12"),
      ("selected Markdown rendered body", hasSubstr selectedMarkdownHtml "<h2>Selected Markdown statement</h2>"),
      ("selected Markdown did not render tex body", !hasSubstr selectedMarkdownHtml "thm:selected-markdown")
    ]
    let theorem22Checks : Array (String × Bool) := #[
      ("theorem 2.2 external entry", entryIsExternalMarkup theorem22Entry),
      ("theorem 2.2 authored label", theorem22Entry.authoredLabel == "ImportedPaper:Theorem2.2"),
      ("theorem 2.2 Nat.add data", theorem22Refs.contains `Nat.add),
      ("theorem 2.2 source page", entryHasSourcePage theorem22Entry "imported-paper" "13")
    ]
    let definition23Checks : Array (String × Bool) := #[
      ("definition 2.3 external entry", entryIsExternalMarkup definition23Entry),
      ("definition 2.3 kind", definition23Entry.kind == some .definition),
      ("definition 2.3 authored label", definition23Entry.authoredLabel == "ImportedPaper:Definition2.3"),
      ("definition 2.3 tex attachment", entryHasExternalMarkup definition23Entry .tex "statement"),
      ("definition 2.3 Nat.mul data", definition23Refs.contains `Nat.mul),
      ("definition 2.3 source page", entryHasSourcePage definition23Entry "imported-paper" "14"),
      ("definition 2.3 tex badge", hasSubstr definition23Html "bp_external_markup_badge_tex"),
      ("definition 2.3 rendered tex", hasSubstr definition23Html "\\begin{definition}")
    ]
    let proposition24Checks : Array (String × Bool) := #[
      ("proposition 2.4 external entry", entryIsExternalMarkup proposition24Entry),
      ("proposition 2.4 authored label", proposition24Entry.authoredLabel == "ImportedPaper:Proposition2.4"),
      ("proposition 2.4 markdown attachment", entryHasExternalMarkup proposition24Entry .markdown "statement"),
      ("proposition 2.4 Nat.add data", proposition24Refs.contains `Nat.add),
      ("proposition 2.4 Nat.mul data", proposition24Refs.contains `Nat.mul),
      ("proposition 2.4 source page 15", entryHasSourcePage proposition24Entry "imported-paper" "15"),
      ("proposition 2.4 source page 16", entryHasSourcePage proposition24Entry "imported-paper" "16"),
      ("proposition 2.4 source badge", htmlHasSourceBadge proposition24Html "imported-paper" "pp. 15, 16"),
      ("proposition 2.4 statement use", proposition24Entry.statementUses.any (fun use => use.label == Name.mkSimple "ImportedPaper:Theorem2.1")),
      ("proposition 2.4 rendered markdown", hasSubstr proposition24Html "<h3>Proposition 2.4</h3>")
    ]
    let rewriteChecks : Array (String × Bool) := #[
      ("rewrite entry is block", rewriteEntry.targetKind == .block),
      ("rewrite authored label", rewriteEntry.authoredLabel == "showcase.native.rewrite"),
      ("rewrite markdown attachment", entryHasExternalMarkup rewriteEntry .markdown "statement"),
      ("rewrite Nat.add data", rewriteRefs.contains `Nat.add),
      ("rewrite source page", entryHasSourcePage rewriteEntry "imported-paper" "17"),
      ("rewrite source badge", htmlHasSourceBadge showcaseHtml "imported-paper" "p. 17"),
      ("rewrite statement use", rewriteEntry.statementUses.any (fun use => use.label == Name.mkSimple "ImportedPaper:Theorem2.1")),
      ("metadata losses", showcaseLosses.isEmpty)
    ]
    pure <| failedCheckLabels <|
      narrativeChecks ++ nativeChecks ++ theorem21Checks ++ selectedMarkdownChecks ++ theorem22Checks ++
        definition23Checks ++ proposition24Checks ++ rewriteChecks

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let some node := state.data.get? (Name.mkSimple "external.markup")
      | pure false
    let some unlabeledAnchor := state.data.get? (Name.mkSimple "external.unlabeled.anchor")
      | pure false
    let some witness := state.data.get? (Name.mkSimple "external.witness")
      | pure false
    let some multi := state.data.get? (Name.mkSimple "external.multi")
      | pure false
    let texStatement := externalMarkupRaw? node.externalMarkup .tex "statement" |>.getD ""
    let mdProof := externalMarkupRaw? node.externalMarkup .markdown "proof" |>.getD ""
    let witnessSource := externalMarkupRaw? witness.externalMarkup .tex Informal.Data.defaultExternalMarkupSlot |>.getD ""
    let multiTex := externalMarkupRaw? multi.externalMarkup .tex "statement" |>.getD ""
    let multiMd := externalMarkupRaw? multi.externalMarkup .markdown "statement" |>.getD ""
    let some loc := externalMarkupLocation? node.externalMarkup .tex "statement"
      | pure false
    pure <|
      node.kind == .theorem &&
      node.statement.isSome &&
      hasSubstr texStatement "\\begin{theorem}" &&
      hasSubstr texStatement "\\label{thm:external-markup}" &&
      hasSubstr mdProof "Imported **Markdown** proof witness." &&
      loc.path == "imports/source.tex" &&
      loc.range.start.line == 4 &&
      loc.range.start.character == 2 &&
      loc.range.«end».line == 8 &&
      loc.range.«end».character == 0 &&
      unlabeledAnchor.kind == .theorem &&
      unlabeledAnchor.statement.isSome &&
      unlabeledAnchor.externalMarkup.isEmpty &&
      witness.statement.isNone &&
      witness.proof.isNone &&
      hasSubstr witnessSource "\\begin{theorem}" &&
      hasSubstr witnessSource "\\label{thm:external-witness}" &&
      multi.statement.isNone &&
      multi.proof.isNone &&
      hasSubstr multiTex "TeX statement witness." &&
      hasSubstr multiMd "Markdown statement witness."

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (externalOut, externalState) ← renderManualDocHtmlStringAndState extension_impls% externalMarkupDoc
    let unlabeledOut ← renderManualDocHtmlString extension_impls% unlabeledExternalMarkupDoc
    let witnessOut ← renderManualDocHtmlString extension_impls% externalMarkupWitnessDoc
    let multiOut ← renderManualDocHtmlString extension_impls% externalMarkupMultiLanguageDoc
    let summaryOut ← renderManualDocHtmlString extension_impls% externalMarkupSummaryDisplayDoc
    let sourceOut ← renderManualDocHtmlString extension_impls% externalMarkupSourceDisplayDoc
    let traversed := (Informal.TraversalIndex.ExternalMarkup.data? externalState (Name.mkSimple "external.markup")).map (·.markup) |>.getD {}
    let traversedTex := externalMarkupRaw? traversed .tex "statement" |>.getD ""
    let traversedMd := externalMarkupRaw? traversed .markdown "proof" |>.getD ""
    let externalFiles ← Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) externalState
    let externalBlockKey := Informal.PreviewCache.statementKey (Name.mkSimple "external.markup")
    let externalMarkupOnlyKey := Informal.PreviewManifest.externalMarkupEntryKey (Name.mkSimple "external.markup")
    let some externalBlockEntry := externalFiles.manifest.previews.find? (fun entry => entry.key == externalBlockKey)
      | return false
    let (_witnessOut, witnessState) ← renderManualDocHtmlStringAndState extension_impls% externalMarkupWitnessDoc
    let witnessFiles ← Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) witnessState
    let witnessFilesNoRender ← Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) witnessState
      ({ mode := .none } : Informal.ExternalMarkupRender.Config)
    let witnessFilesNoNotice ← Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) witnessState
      ({ showSourceNotice := false } : Informal.ExternalMarkupRender.Config)
    let witnessKey := Informal.PreviewManifest.externalMarkupEntryKey (Name.mkSimple "external.witness")
    let some witnessEntry := witnessFiles.manifest.previews.find? (fun entry => entry.key == witnessKey)
      | return false
    let some witnessHtml := witnessFiles.htmlCache.findHtml? witnessKey
      | return false
    let some witnessHtmlNoNotice := witnessFilesNoNotice.htmlCache.findHtml? witnessKey
      | return false
    let (_markdownOut, markdownState) ← renderManualDocHtmlStringAndState extension_impls% externalMarkdownWitnessDoc
    let markdownFiles ← Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) markdownState
    let markdownKey := Informal.PreviewManifest.externalMarkupEntryKey (Name.mkSimple "external.markdown.witness")
    let some markdownHtml := markdownFiles.htmlCache.findHtml? markdownKey
      | return false
    let (_bodylessOut, bodylessState) ← renderManualDocHtmlStringAndState extension_impls% externalBodylessLeanWitnessDoc
    let bodylessFiles ← Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) bodylessState
    let bodylessKey := Informal.PreviewManifest.externalMarkupEntryKey (Name.mkSimple "external.bodyless.lean")
    let some bodylessEntry := bodylessFiles.manifest.previews.find? (fun entry => entry.key == bodylessKey)
      | return false
    let some bodylessHtml := bodylessFiles.htmlCache.findHtml? bodylessKey
      | return false
    let (_punctuationOut, punctuationState) ←
      renderManualDocHtmlStringAndState extension_impls% externalPunctuationBodylessLeanWitnessDoc
    let punctuationFiles ←
      Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) punctuationState
    let punctuationLabel := Name.mkSimple "Chapter4:Theorem4.2.1"
    let punctuationKey := Informal.PreviewManifest.externalMarkupEntryKey punctuationLabel
    let some punctuationEntry := punctuationFiles.manifest.previews.find? (fun entry => entry.key == punctuationKey)
      | return false
    let bodylessLosses :=
      Informal.PreviewManifest.previewMetadataLosses bodylessState bodylessFiles.manifest
    let bodylessExternalRefs : Array Name :=
      match bodylessEntry.codeData with
      | some (.external refs) => refs.map (fun ref => ref.canonical)
      | _ => #[]
    let punctuationExternalRefs : Array Name :=
      match punctuationEntry.codeData with
      | some (.external refs) => refs.map (fun ref => ref.canonical)
      | _ => #[]
    let brokenBodylessManifest : Informal.PreviewManifest.File := {
      bodylessFiles.manifest with
      previews := bodylessFiles.manifest.previews.map fun entry =>
        if entry.key == bodylessKey then
          { entry with leanCodePreviewKeys := #[], codeData := none }
        else
          entry
    }
    let brokenBodylessLosses :=
      Informal.PreviewManifest.previewMetadataLosses bodylessState brokenBodylessManifest
    let some brokenBodylessLoss := brokenBodylessLosses[0]?
      | return false
    let brokenBodylessLossMessage := brokenBodylessLoss.warningMessage
    let (_sourcedWitnessOut, sourcedWitnessState) ← renderManualDocHtmlStringAndState extension_impls% sourcedExternalMarkupWitnessDoc
    let sourcedWitnessFiles ← Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) sourcedWitnessState
    let sourcedWitnessKey :=
      Informal.PreviewManifest.externalMarkupEntryKey (Name.mkSimple "external.sourced.witness")
    let some sourcedWitnessEntry :=
        sourcedWitnessFiles.manifest.previews.find? (fun entry => entry.key == sourcedWitnessKey)
      | return false
    pure <|
      hasSubstr traversedTex "\\begin{theorem}" &&
      hasSubstr traversedMd "Imported **Markdown** proof witness." &&
      externalBlockEntry.externalMarkup.size == 2 &&
      !externalFiles.manifest.previews.any (fun entry => entry.key == externalMarkupOnlyKey) &&
      entryIsExternalMarkup witnessEntry &&
      witnessEntry.label == Name.mkSimple "external.witness" &&
      witnessEntry.authoredLabel == "external.witness" &&
      witnessEntry.externalMarkup.size == 1 &&
      hasSubstr witnessHtml "bp_external_markup_notice" &&
      hasSubstr witnessHtml "Rendered from external TeX source" &&
      hasSubstr witnessHtml "bp_extra_slot_markup" &&
      hasSubstr witnessHtml "bp_external_markup_badge_tex" &&
      hasSubstr witnessHtml "bp_external_markup_badge_prefix" &&
      hasSubstr witnessHtml "External TeX source markup attached" &&
      hasSubstr witnessHtml "\\begin{theorem}" &&
      (witnessFilesNoRender.htmlCache.findHtml? witnessKey).isNone &&
      !hasSubstr witnessHtmlNoNotice "bp_external_markup_notice" &&
      hasSubstr witnessHtmlNoNotice "\\begin{theorem}" &&
      hasSubstr markdownHtml "bp_external_markdown_body" &&
      hasSubstr markdownHtml "bp_external_markup_badge_markdown" &&
      hasSubstr markdownHtml "<h1>Markdown witness</h1>" &&
      hasSubstr markdownHtml "<strong>source</strong>" &&
      hasSubstr markdownHtml "<li>Review imported source</li>" &&
      hasSubstr markdownHtml "<blockquote>" &&
      hasSubstr markdownHtml "<table>" &&
      hasSubstr markdownHtml "<pre><code>#check Nat.add" &&
      hasSubstr markdownHtml "&lt;span&gt;raw HTML stays text&lt;/span&gt;" &&
      hasSubstr markdownHtml "For every $n$" &&
      entryIsExternalMarkup bodylessEntry &&
      bodylessEntry.authoredLabel == "external.bodyless.lean" &&
      bodylessEntry.leanCodePreviewKeys.any (hasSubstr · "Nat.add") &&
      bodylessEntry.leanCodePreviewKeys.any (hasSubstr · "Nat.mul") &&
      bodylessExternalRefs.contains `Nat.add &&
      bodylessExternalRefs.contains `Nat.mul &&
      entryIsExternalMarkup punctuationEntry &&
      punctuationEntry.label == punctuationLabel &&
      punctuationEntry.authoredLabel == "Chapter4:Theorem4.2.1" &&
      punctuationEntry.leanCodePreviewKeys.any (hasSubstr · "Nat.add") &&
      punctuationExternalRefs.contains `Nat.add &&
      bodylessLosses.isEmpty &&
      brokenBodylessLosses.size == 1 &&
      brokenBodylessLoss.manifestEntryKey? == some bodylessKey &&
      brokenBodylessLoss.missingLeanCodePreviewKeys.any (hasSubstr · "Nat.add") &&
      brokenBodylessLoss.missingLeanCodePreviewKeys.any (hasSubstr · "Nat.mul") &&
      hasSubstr brokenBodylessLossMessage "lost Lean preview keys" &&
      hasSubstr brokenBodylessLossMessage s!"manifest entry {bodylessKey}" &&
      hasSubstr bodylessHtml "Bodyless Lean-backed witness" &&
      hasSubstr bodylessHtml "bp_external_markup_badge_markdown" &&
      sourcedWitnessEntry.targetKind == .externalMarkup &&
      sourcedWitnessEntry.externalMarkup.size == 1 &&
      sourcedWitnessEntry.sources.any (fun sourceRef =>
        sourceRef.document == "external-paper" &&
          sourceRef.spans.size == 1 &&
          sourceRef.spans[0]!.page == "7") &&
      hasSubstr externalOut "bp_extra_slot_markup" &&
      hasSubstr externalOut "bp_external_markup_badge_markdown" &&
      hasSubstr externalOut "bp_external_markup_badge_tex" &&
      hasSubstr externalOut "External Markdown source markup attached (proof)" &&
      hasSubstr externalOut "External TeX source markup attached (statement)" &&
      !hasSubstr externalOut "\\begin{theorem}" &&
      !hasSubstr externalOut "thm:external-markup" &&
      !hasSubstr externalOut "Imported **Markdown** proof witness" &&
      !hasSubstr unlabeledOut "bp_extra_slot_markup" &&
      !hasSubstr unlabeledOut "\\begin{theorem}" &&
      !hasSubstr unlabeledOut "unlabeled witness should stay hidden" &&
      !hasSubstr witnessOut "\\begin{theorem}" &&
      !hasSubstr witnessOut "thm:external-witness" &&
      !hasSubstr multiOut "TeX statement witness." &&
      !hasSubstr multiOut "Markdown statement witness." &&
      hasSubstr summaryOut "External Markdown markup (statement): imports/source.md:0:0-1:0" &&
      !hasSubstr summaryOut "Summary-only content should stay hidden" &&
      hasSubstr sourceOut "External Markdown markup (default)" &&
      hasSubstr sourceOut "&lt;raw &amp; source&gt;"

end Verso.VersoBlueprintTests.BlueprintExternalMarkup
