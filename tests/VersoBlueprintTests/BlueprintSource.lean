/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprint.PreviewManifest
import VersoBlueprintTests.Blueprint.Support
import VersoManual

open Lean
open Verso Genre Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintSource

private def sourcedLabel : Name := Name.mkSimple "source.lemma"
private def secondSourcedLabel : Name := Name.mkSimple "source.second"

private def sourceRefHasPage (document page : String) (sourceRef : Informal.Source.Ref) : Bool :=
  sourceRef.document == document && sourceRef.spans.any (fun span => span.page == page)

private def entryHasSourcePage
    (document page : String) (entry : Informal.PreviewManifest.Entry) : Bool :=
  entry.hasSourceDocument document && entry.sources.any (sourceRefHasPage document page)

private def entryOptionHasSourcePage
    (document page : String) (entry? : Option Informal.PreviewManifest.Entry) : Bool :=
  entry?.any fun entry => entryHasSourcePage document page entry

private def sourceRefHasRepresentationTheorySpan (sourceRef : Informal.Source.Ref) : Bool :=
  sourceRef.document == "paper" &&
    sourceRef.spans.any fun span =>
      let boxXMax := (span.pdf.bind (·.box)).map (·.xMax)
      span.page == "12" &&
        span.text.map (·.path) == some "source/pages/page-12.md" &&
        span.text.map (·.startLine) == some 41 &&
        span.text.map (·.endLine) == some 45 &&
        span.pdf.map (·.path) == some "source/pages/page-12.pdf" &&
        span.pdf.bind (·.image) == some "source/pages/images/page-12.png" &&
        boxXMax == some 980

#docs (Manual) sourceProvenanceDoc "Source Provenance" :=
:::::::
:::source_document "paper"
%%%
title := "Representation Theory"
kind := .pdf
pdf := "source/paper.pdf"
pageRoot := "source/pages"
imageRoot := "source/pages/images"
%%%
:::

:::source_document "notes"
%%%
title := "Lecture Notes"
kind := .text
pageRoot := "source/notes"
%%%
:::

:::lemma_ "source.lemma" (lean := "Nat.add")
%%%
source := {
  document := "paper"
  spans := #[
    {
      page := "12"
      text := some {
        path := "source/pages/page-12.md"
        startLine := 41
        endLine := 45
      }
      pdf := some {
        path := "source/pages/page-12.pdf"
        image := "source/pages/images/page-12.png"
        box := some {
          scale := 2
          pageWidth := 1600
          pageHeight := 2200
          xMin := 120
          yMin := 240
          xMax := 980
          yMax := 520
        }
      }
    }
  ]
}
%%%

A sourced statement.
:::

:::lemma_ "source.second" (lean := "Nat.add")
%%%
source := {
  document := "notes"
  spans := #[
    {
      page := "A"
      text := some {
        path := "source/notes/addition.md"
        startLine := 1
        endLine := 3
      }
    }
  ]
}
%%%

A second sourced statement using the same Lean declaration.
:::
:::::::

#docs (Manual) missingSourceProvenanceDoc "Missing Source Provenance" :=
:::::::
:::lemma_ "source.missing"
%%%
source := {
  document := "missing-paper"
  spans := #[
    {
      page := "1"
      pdf := some { path := "source/pages/missing-1.pdf" }
    }
  ]
}
%%%

This source document is intentionally not declared.
:::
:::::::

#docs (Manual) conflictingSourceDocumentDoc "Conflicting Source Document" :=
:::::::
:::source_document "paper"
%%%
title := "Representation Theory"
kind := .pdf
pdf := "source/paper.pdf"
%%%
:::

:::source_document "paper"
%%%
title := "Different Metadata"
kind := .pdf
pdf := "source/other-paper.pdf"
%%%
:::
:::::::

/--
error: Source document 'paper' has unexpected body content; source_document directives accept exactly one metadata block and no visible body
-/
#guard_msgs in
#docs (Manual) sourceDocumentBodyDoc "Source Document Body" :=
:::::::
:::source_document "paper"
%%%
title := "Representation Theory"
kind := .pdf
pdf := "source/paper.pdf"
%%%

Source document declarations do not render visible body content.
:::
:::::::

/--
error: Source document 'paper' has an extra metadata block; source_document directives accept exactly one leading metadata block
-/
#guard_msgs in
#docs (Manual) sourceDocumentExtraMetadataDoc "Source Document Extra Metadata" :=
:::::::
:::source_document "paper"
%%%
title := "Representation Theory"
kind := .pdf
pdf := "source/paper.pdf"
%%%

%%%
title := "Duplicate Metadata"
%%%
:::
:::::::

/--
error: Label late_source has a metadata block after visible content; Blueprint source metadata must be the first block inside the directive
-/
#guard_msgs in
#docs (Manual) lateSourceMetadataDoc "Late Source Metadata" :=
:::::::
:::lemma_ "late_source"
Visible content comes first.

%%%
source := {
  document := "paper"
}
%%%
:::
:::::::

/--
error: Source document '' is invalid: source document id must be non-empty
---
error: Source document '' is invalid: PDF source documents require a pdf path
-/
#guard_msgs in
#docs (Manual) invalidSourceDocumentDoc "Invalid Source Document" :=
:::::::
:::source_document ""
%%%
title := "Invalid"
kind := .pdf
%%%
:::
:::::::

/--
error: Label invalid_source has invalid source metadata: source metadata must include at least one source span
-/
#guard_msgs in
#docs (Manual) invalidSourceMetadataDoc "Invalid Source Metadata" :=
:::::::
:::lemma_ "invalid_source"
%%%
source := {
  document := "paper"
}
%%%

Invalid source metadata.
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let documentErrors :=
      Informal.Source.Document.validationErrors
        ({ id := "", kind := .pdf } : Informal.Source.Document)
    let refErrors :=
      Informal.Source.Ref.validationErrors
        ({ document := "paper" } : Informal.Source.Ref)
    let expectedDocumentErrors : Array Informal.Source.ValidationError := #[
      .emptyField "source document id",
      .pdfDocumentMissingPath
    ]
    let expectedRefErrors : Array Informal.Source.ValidationError := #[.refMissingSpan]
    documentErrors == expectedDocumentErrors &&
      refErrors == expectedRefErrors

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (html, st) ← renderManualDocHtmlStringAndState extension_impls% sourceProvenanceDoc
    let sourceDocument? := Informal.TraversalIndex.SourceDocuments.data? st "paper"
    let sourceRef? := Informal.TraversalIndex.SourceRefs.data? st sourcedLabel
    let storageOk :=
      match sourceDocument?, sourceRef? with
      | some sourceDocument, some sourceRef =>
          sourceDocument.id == "paper" &&
            sourceDocument.title == "Representation Theory" &&
            sourceDocument.kind == .pdf &&
            sourceDocument.pdf == some "source/paper.pdf" &&
            sourceDocument.pageRoot == some "source/pages" &&
            sourceDocument.imageRoot == some "source/pages/images" &&
            sourceRefHasRepresentationTheorySpan sourceRef
      | _, _ => false
    pure <|
      hasSubstr html "A sourced statement." &&
      !hasSubstr html "source/paper.pdf" &&
      storageOk

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let files ← buildManualPreviewDataFiles extension_impls% sourceProvenanceDoc
    let entry? := files.manifest.previews.find? fun entry => entry.label == sourcedLabel
    let secondEntry? := files.manifest.previews.find? fun entry => entry.label == secondSourcedLabel
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey `Nat.add
    let codeEntry? := files.manifest.previews.find? fun entry => entry.key == codeKey
    let sourceDocument? := files.manifest.sourceDocument? "paper"
    let notesDocument? := files.manifest.sourceDocument? "notes"
    let entriesWithSource := files.manifest.entriesWithSource
    let paperEntries := files.manifest.entriesForSourceDocument "paper"
    let notesEntries := files.manifest.entriesForSourceDocument "notes"
    pure <|
      sourceDocument?.map (·.pdf) == some (some "source/paper.pdf") &&
      notesDocument?.map (·.kind) == some .text &&
      entriesWithSource.any (fun entry =>
        entry.label == sourcedLabel && entry.hasSourceDocument "paper") &&
      entriesWithSource.any (fun entry =>
        entry.label == secondSourcedLabel && entry.hasSourceDocument "notes") &&
      paperEntries.any (fun entry => entry.label == sourcedLabel) &&
      paperEntries.any (fun entry => entry.key == codeKey) &&
      notesEntries.any (fun entry => entry.label == secondSourcedLabel) &&
      notesEntries.any (fun entry => entry.key == codeKey) &&
      entry?.any (fun entry => entry.leanCodePreviewKeys.contains codeKey) &&
      secondEntry?.any (fun entry => entry.leanCodePreviewKeys.contains codeKey) &&
      codeEntry?.any (fun entry =>
        entry.targetKind == .leanDecl &&
          entry.sources.size == 2 &&
          entryHasSourcePage "paper" "12" entry &&
          entryHasSourcePage "notes" "A" entry) &&
      entryOptionHasSourcePage "paper" "12" entry? &&
      entryOptionHasSourcePage "notes" "A" secondEntry?

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let logged ← IO.mkRef #[]
    let _ ← traverseManualDocBlocksAndState extension_impls% conflictingSourceDocumentDoc
      (fun message => logged.modify (·.push message))
    let messages ← logged.get
    pure <|
      messages.any fun message =>
        hasSubstr message "Source document 'paper' was declared more than once with conflicting metadata"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let logged ← IO.mkRef #[]
    let _files ← buildManualPreviewDataFiles extension_impls% missingSourceProvenanceDoc
      (fun message => logged.modify (·.push message))
    let messages ← logged.get
    pure <|
      messages.any fun message =>
        hasSubstr message "source ref for label «source.missing» references unknown source document 'missing-paper'"

end Verso.VersoBlueprintTests.BlueprintSource
