/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintForeignRefs

open Lean
open Informal

private def rustTargetRange : Data.ForeignRange := {
  start := { line := 12, character := 4 }
  stop := { line := 12, character := 16 }
}

private def resolvedRustRef : Data.ForeignRef := {
  written := "collatz_step"
  status := .resolved
  targetUri? := some "file:///tmp/vbp-rust/src/lib.rs"
  targetRange? := some rustTargetRange
  sourceHref? := some "file:///tmp/vbp-rust/src/lib.rs#L13"
  sourceSnippet? := some "pub fn collatz_step(n: u64) -> u64 { n + 1 }"
}

private def unresolvedRustRef : Data.ForeignRef := {
  written := "collatz_typo"
  status := .unresolved
  message? := some "language server did not return a definition location"
}

private def rustAttachment : Data.ForeignAttachment := {
  language := .rust
  command := "rust-analyzer"
  root := "/tmp/vbp-rust"
  syntheticUri := "file:///tmp/vbp-rust/.verso-blueprint-foreign/Blueprint.rust.rs"
  refs := #[resolvedRustRef, unresolvedRustRef]
}

private def rocqAttachment : Data.ForeignAttachment := {
  language := .rocq
  command := "coq-lsp"
  root := "/tmp/vbp-rocq"
  syntheticUri := "file:///tmp/vbp-rocq/.verso-blueprint-foreign/Blueprint.rocq.v"
  preludeDiagnostics := #[
    {
      message := "Unknown logical path"
      range? := some {
        start := { line := 0, character := 0 }
        stop := { line := 0, character := 6 }
      }
    }
  ]
  refs := #[
    {
      written := "def1"
      status := .failed
      message? := some "prelude diagnostics prevented lookup"
    }
  ]
}

/-- info: true -/
#guard_msgs in
#eval
  Data.ForeignLanguage.rust.key == "rust" &&
    Data.ForeignLanguage.rust.displayName == "Rust" &&
    Data.ForeignLanguage.rust.defaultCommand == "rust-analyzer" &&
    Data.ForeignLanguage.rust.languageId == "rust" &&
    Data.ForeignLanguage.rust.sourceExtension == "rs" &&
    Data.ForeignLanguage.rocq.key == "rocq" &&
    Data.ForeignLanguage.rocq.displayName == "Rocq" &&
    Data.ForeignLanguage.rocq.defaultCommand == "coq-lsp" &&
    Data.ForeignLanguage.rocq.languageId == "coq" &&
    Data.ForeignLanguage.rocq.sourceExtension == "v"

/-- info: true -/
#guard_msgs in
#eval
  Data.ForeignLookupStatus.resolved.label == "resolved" &&
    !Data.ForeignLookupStatus.resolved.isWarning &&
    Data.ForeignLookupStatus.unresolved.isWarning &&
    Data.ForeignLookupStatus.unavailable.isWarning &&
    Data.ForeignLookupStatus.failed.isWarning

/-- info: true -/
#guard_msgs in
#eval
  rustAttachment.hasResolved &&
    rustAttachment.hasWarning &&
    resolvedRustRef.hasWarning == false &&
    unresolvedRustRef.hasWarning &&
    !rocqAttachment.hasResolved &&
    rocqAttachment.hasWarning

/-- info: true -/
#guard_msgs in
#eval
  match fromJson? (toJson rustAttachment) with
  | .ok decoded => decoded == rustAttachment
  | .error _ => false

private def foreignBlockData : BlockData := {
  kind := .statement .definition
  label := Name.mkSimple "foreign.model"
  count := 1
  foreignRefs := #[rustAttachment]
}

/-- info: true -/
#guard_msgs in
#eval
  foreignBlockData.toStoredData.toBlockData.foreignRefs == #[rustAttachment]

/-- info: true -/
#guard_msgs in
#eval
  let existing : StoredBlockData := {
    kind := .statement .definition
    label := Name.mkSimple "foreign.existing"
    count := 1
    foreignRefs := #[rocqAttachment]
  }
  let incoming : StoredBlockData := {
    kind := .statement .definition
    label := Name.mkSimple "foreign.existing"
    count := 1
    foreignRefs := #[rustAttachment]
  }
  let emptyExisting := { existing with foreignRefs := #[] }
  (mergeStoredBlockData emptyExisting incoming).foreignRefs == #[rustAttachment] &&
    (mergeStoredBlockData existing incoming).foreignRefs == #[rocqAttachment, rustAttachment] &&
    (mergeStoredBlockData existing { incoming with foreignRefs := #[rocqAttachment] }).foreignRefs == #[rocqAttachment]

end Verso.VersoBlueprintTests.BlueprintForeignRefs
