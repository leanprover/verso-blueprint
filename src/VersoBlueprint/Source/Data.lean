/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import Lean.Data.Json.FromToJson.Basic
meta import Verso.Instances.Deriving

public section

namespace Informal.Source

open Lean

/-- Broad kind of an original source document. -/
inductive DocumentKind where
  | pdf
  | text
deriving Inhabited, Repr, BEq, DecidableEq, FromJson, ToJson, Quote

/-- Metadata written in a `:::source_document` directive. -/
structure DocumentMetadata where
  title : String := ""
  kind : DocumentKind := .pdf
  pdf : Option String := none
  pageRoot : Option String := none
  imageRoot : Option String := none
deriving Inhabited, Repr, BEq, DecidableEq, FromJson, ToJson, Quote

/-- A source document known to the Blueprint. -/
structure Document extends DocumentMetadata where
  id : String
deriving Inhabited, Repr, BEq, DecidableEq, FromJson, ToJson, Quote

def DocumentMetadata.toDocument (id : String) (metadata : DocumentMetadata) : Document := {
  metadata with
  id
}

/-- Structured validation errors for source-document and source-span metadata. -/
inductive ValidationError where
  | emptyField (field : String)
  | pdfDocumentMissingPath
  | textStartLineNotOneBased
  | textEndLineNotOneBased
  | textStartLineAfterEndLine
  | textCharacterRangeEmpty
  | textCharacterRangeIncomplete
  | pdfBoxScaleNonPositive
  | pdfBoxPageWidthNonPositive
  | pdfBoxPageHeightNonPositive
  | pdfBoxInvalidXRange
  | pdfBoxInvalidYRange
  | pdfBoxXMaxBeyondPageWidth
  | pdfBoxYMaxBeyondPageHeight
  | spanMissingLocation
  | refMissingSpan
deriving Inhabited, Repr, BEq, DecidableEq

def ValidationError.message : ValidationError → String
  | .emptyField field => s!"{field} must be non-empty"
  | .pdfDocumentMissingPath => "PDF source documents require a pdf path"
  | .textStartLineNotOneBased => "source text startLine must be 1-based"
  | .textEndLineNotOneBased => "source text endLine must be 1-based"
  | .textStartLineAfterEndLine => "source text startLine must be less than or equal to endLine"
  | .textCharacterRangeEmpty => "source text character range must be non-empty"
  | .textCharacterRangeIncomplete => "source text character range requires both startCharacter and endCharacter"
  | .pdfBoxScaleNonPositive => "source PDF box scale must be positive"
  | .pdfBoxPageWidthNonPositive => "source PDF box pageWidth must be positive"
  | .pdfBoxPageHeightNonPositive => "source PDF box pageHeight must be positive"
  | .pdfBoxInvalidXRange => "source PDF box xMin must be less than xMax"
  | .pdfBoxInvalidYRange => "source PDF box yMin must be less than yMax"
  | .pdfBoxXMaxBeyondPageWidth => "source PDF box xMax must be within pageWidth"
  | .pdfBoxYMaxBeyondPageHeight => "source PDF box yMax must be within pageHeight"
  | .spanMissingLocation => "source spans require text or PDF location data"
  | .refMissingSpan => "source metadata must include at least one source span"

instance : ToString ValidationError where
  toString := ValidationError.message

private def nonEmptyField (field value : String) : Array ValidationError :=
  if value.trimAscii.isEmpty then #[.emptyField field] else #[]

private def addIf (errors : Array ValidationError) (condition : Bool)
    (error : ValidationError) : Array ValidationError :=
  if condition then errors.push error else errors

private def addOptional {α : Type} (errors : Array ValidationError) (value? : Option α)
    (validationErrors : α → Array ValidationError) : Array ValidationError :=
  match value? with
  | some value => errors ++ validationErrors value
  | none => errors

private def addMany {α : Type} (errors : Array ValidationError) (values : Array α)
    (validationErrors : α → Array ValidationError) : Array ValidationError :=
  values.foldl (fun errors value => errors ++ validationErrors value) errors

def Document.validationErrors (document : Document) : Array ValidationError :=
  let errors := nonEmptyField "source document id" document.id
  let errors := addOptional errors document.pdf (nonEmptyField "source document pdf")
  let errors := addIf errors (document.kind == .pdf && document.pdf.isNone) .pdfDocumentMissingPath
  let errors := addOptional errors document.pageRoot (nonEmptyField "source document pageRoot")
  addOptional errors document.imageRoot (nonEmptyField "source document imageRoot")

/-- Text-line range for a source span. Lines are 1-based and inclusive. -/
structure TextRange where
  path : String
  startLine : Nat
  endLine : Nat
  startCharacter : Option Nat := none
  endCharacter : Option Nat := none
deriving Inhabited, Repr, BEq, DecidableEq, FromJson, ToJson, Quote

def TextRange.validationErrors (range : TextRange) : Array ValidationError :=
  let errors := nonEmptyField "source text path" range.path
  let errors := addIf errors (range.startLine == 0) .textStartLineNotOneBased
  let errors := addIf errors (range.endLine == 0) .textEndLineNotOneBased
  let errors := addIf errors (range.startLine > range.endLine) .textStartLineAfterEndLine
  match range.startCharacter, range.endCharacter with
  | some startCharacter, some endCharacter =>
      addIf errors (range.startLine == range.endLine && startCharacter >= endCharacter)
        .textCharacterRangeEmpty
  | some _, none | none, some _ =>
      errors.push .textCharacterRangeIncomplete
  | none, none =>
      errors

/-- Scaled source-PDF crop box in top-left page coordinates. -/
structure PdfBox where
  scale : Nat
  pageWidth : Nat
  pageHeight : Nat
  xMin : Nat
  yMin : Nat
  xMax : Nat
  yMax : Nat
deriving Inhabited, Repr, BEq, DecidableEq, FromJson, ToJson, Quote

def PdfBox.validationErrors (box : PdfBox) : Array ValidationError :=
  let errors : Array ValidationError := #[]
  let errors := addIf errors (box.scale == 0) .pdfBoxScaleNonPositive
  let errors := addIf errors (box.pageWidth == 0) .pdfBoxPageWidthNonPositive
  let errors := addIf errors (box.pageHeight == 0) .pdfBoxPageHeightNonPositive
  let errors := addIf errors (box.xMin >= box.xMax) .pdfBoxInvalidXRange
  let errors := addIf errors (box.yMin >= box.yMax) .pdfBoxInvalidYRange
  let errors := addIf errors (box.pageWidth != 0 && box.xMax > box.pageWidth)
    .pdfBoxXMaxBeyondPageWidth
  addIf errors (box.pageHeight != 0 && box.yMax > box.pageHeight)
    .pdfBoxYMaxBeyondPageHeight

/-- PDF/page-image data for a source span. -/
structure PdfSpan where
  path : String
  image : Option String := none
  box : Option PdfBox := none
deriving Inhabited, Repr, BEq, DecidableEq, FromJson, ToJson, Quote

def PdfSpan.validationErrors (span : PdfSpan) : Array ValidationError :=
  let errors := nonEmptyField "source PDF path" span.path
  let errors := addOptional errors span.image (nonEmptyField "source PDF image")
  addOptional errors span.box PdfBox.validationErrors

/-- One source span attached to a Blueprint node. -/
structure Span where
  page : String
  text : Option TextRange := none
  pdf : Option PdfSpan := none
deriving Inhabited, Repr, BEq, DecidableEq, FromJson, ToJson, Quote

def Span.validationErrors (span : Span) : Array ValidationError :=
  let errors := nonEmptyField "source span page" span.page
  let errors := addIf errors (span.text.isNone && span.pdf.isNone) .spanMissingLocation
  let errors := addOptional errors span.text TextRange.validationErrors
  addOptional errors span.pdf PdfSpan.validationErrors

/-- Source provenance for a Blueprint node. -/
structure Ref where
  document : String := ""
  spans : Array Span := #[]
deriving Inhabited, Repr, BEq, DecidableEq, FromJson, ToJson, Quote

def Ref.isEmpty (ref : Ref) : Bool :=
  ref.document.trimAscii.isEmpty && ref.spans.isEmpty

def Ref.validationErrors (ref : Ref) : Array ValidationError :=
  let errors := nonEmptyField "source document reference" ref.document
  let errors := addIf errors ref.spans.isEmpty .refMissingSpan
  addMany errors ref.spans Span.validationErrors

/--
Input-only metadata shape accepted at the beginning of Blueprint node directives.

The default empty `source` lets authors omit source metadata without writing
`some { ... }`; `source?` converts the input sentinel to the semantic optional
reference stored by Blueprint.
-/
structure NodeMetadataInput where
  source : Ref := {}
deriving Inhabited, Repr, BEq, DecidableEq, FromJson, ToJson, Quote

def NodeMetadataInput.source? (metadata : NodeMetadataInput) : Option Ref :=
  if metadata.source.isEmpty then none else some metadata.source

end Informal.Source
