/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

import VersoBlueprint.Source.Data
meta import VersoBlueprint.Source.Data

namespace VersoBlueprintModuleTests.SourceData

open Lean
open Informal.Source

local macro "sourceRefContract" : term => do
  let sourceRef : Ref := {
    document := "paper"
    spans := #[{
      page := "12"
      text := some {
        path := "paper.tex"
        startLine := 10
        endLine := 12
      }
    }]
  }
  return quote sourceRef

/-- info: true -/
#guard_msgs in
#eval
  let sourceRef : Ref := sourceRefContract
  let jsonRoundtripOk :=
    match Lean.fromJson? (α := Ref) (Lean.toJson sourceRef) with
    | .ok decoded => decoded == sourceRef
    | .error _ => false
  let documentErrors :=
    Document.validationErrors ({ id := "", kind := .pdf } : Document)
  let rangeErrors :=
    TextRange.validationErrors {
      path := "paper.tex"
      startLine := 3
      endLine := 2
    }
  let emptySourceOmitted := (NodeMetadataInput.source? {}).isNone
  let presentSourceRetained :=
    (NodeMetadataInput.source? { source := { document := "paper" } }).isSome
  jsonRoundtripOk &&
    documentErrors == #[
      .emptyField "source document id",
      .pdfDocumentMissingPath
    ] &&
    rangeErrors == #[.textStartLineAfterEndLine] &&
    emptySourceOmitted &&
    presentSourceRetained

end VersoBlueprintModuleTests.SourceData
