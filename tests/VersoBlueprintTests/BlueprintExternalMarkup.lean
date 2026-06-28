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
A markup-only witness can introduce a Blueprint node while porting.
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
      ({ mode := .none } : Informal.PreviewManifest.ExternalMarkupRenderConfig)
    let witnessFilesNoNotice ← Informal.PreviewManifest.buildPreviewDataFiles extension_impls% (fun _ => pure ()) witnessState
      ({ showSourceNotice := false } : Informal.PreviewManifest.ExternalMarkupRenderConfig)
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
    pure <|
      hasSubstr traversedTex "\\begin{theorem}" &&
      hasSubstr traversedMd "Imported **Markdown** proof witness." &&
      externalBlockEntry.externalMarkup.size == 2 &&
      !externalFiles.manifest.previews.any (fun entry => entry.key == externalMarkupOnlyKey) &&
      (match witnessEntry.targetKind with | .externalMarkup => true | _ => false) &&
      witnessEntry.label == Name.mkSimple "external.witness" &&
      witnessEntry.authoredLabel == "external.witness" &&
      witnessEntry.externalMarkup.size == 1 &&
      hasSubstr witnessHtml "bp_external_markup_notice" &&
      hasSubstr witnessHtml "Rendered from external TeX source" &&
      hasSubstr witnessHtml "\\begin{theorem}" &&
      (witnessFilesNoRender.htmlCache.findHtml? witnessKey).isNone &&
      !hasSubstr witnessHtmlNoNotice "bp_external_markup_notice" &&
      hasSubstr witnessHtmlNoNotice "\\begin{theorem}" &&
      hasSubstr markdownHtml "bp_external_markdown_body" &&
      hasSubstr markdownHtml "<h1>Markdown witness</h1>" &&
      hasSubstr markdownHtml "<strong>source</strong>" &&
      hasSubstr markdownHtml "<li>Review imported source</li>" &&
      hasSubstr markdownHtml "<blockquote>" &&
      hasSubstr markdownHtml "<table>" &&
      hasSubstr markdownHtml "<pre><code>#check Nat.add" &&
      hasSubstr markdownHtml "&lt;span&gt;raw HTML stays text&lt;/span&gt;" &&
      hasSubstr markdownHtml "For every $n$" &&
      (match bodylessEntry.targetKind with | .externalMarkup => true | _ => false) &&
      bodylessEntry.authoredLabel == "external.bodyless.lean" &&
      bodylessEntry.leanCodePreviewKeys.any (hasSubstr · "Nat.add") &&
      bodylessEntry.leanCodePreviewKeys.any (hasSubstr · "Nat.mul") &&
      bodylessExternalRefs.contains `Nat.add &&
      bodylessExternalRefs.contains `Nat.mul &&
      (match punctuationEntry.targetKind with | .externalMarkup => true | _ => false) &&
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
      !hasSubstr externalOut "\\begin{theorem}" &&
      !hasSubstr externalOut "thm:external-markup" &&
      !hasSubstr externalOut "Imported **Markdown** proof witness" &&
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
