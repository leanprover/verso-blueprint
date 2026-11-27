# UPC-0024 Expose Owning Source Range and Buffer Mapping for Verso Lean Fences

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-verso
Last reviewed: 2026-11-27
Owner: none
Issue: none linked
PR: none linked
Upstream timing: as soon as possible
Removal target: fence scanning, re-padding, and incremental `#doc` re-parsing in `src/VersoBlueprint/Realizations/NativeSource.lean` and buffer reconstruction in `src/VersoBlueprint/SourceData.lean`
Related cards: UPC-0023, UPC-0025

## Summary

Expose the owning physical source range and padded-to-original buffer mapping
when Verso elaborates a Lean code block or `#doc` / `#docs` fence, rather than
only supplying a space/newline-padded string via `Verso.SyntaxUtils.parserInputString`.

## Impact

When `@[blueprint]` or an inline Lean block elaborates inside a Verso `#doc` or
`#docs` document, `Core.Context.fileMap.source` is the padded fence buffer
produced by `Verso.SyntaxUtils.parserInputString`. To verify that a compiled
declaration or attribute docstring came from the unchanged physical source file
(preserving raw bytes and line endings), `verso-blueprint` currently has to
re-parse the containing Verso document (including custom `#doc` incremental term
parsing), scan syntax trees for a hardcoded whitelist of Lean fence expander
names, re-pad every matching string literal, and map padded positions back to
raw file bytes.

## Roadmap Decision

Track upstream in Verso. Blueprint retains policy ownership over which
realization owns a selected block, while Verso should own the mechanical
mapping between an elaborated fence's padded parser input and its original
source span.

## Reproduction Status

Confirmed against current pinned Verso on `v4.35.0`:
- `src/VersoBlueprint/Realizations/NativeSource.lean` (`parseIncrementalDocument`,
  `leanFenceContents`, `documentFenceContents`, `documentFences`,
  `paddedFenceInput`, `attributeFenceInput`) reconstructs the padded buffer
  from the physical file for `#docs` and incremental `#doc` fences.
- `src/VersoBlueprint/SourceData.lean` (`syntaxRange`, `FencedSelection.ofSyntax`)
  similarly recovers owning spans from syntax head/tail info.
- Covered by `tests/VersoBlueprintTests/BlueprintRealizationCapture.lean`
  (`capture.fencedAttribute`, `capture.incrementalFencedAttribute`).

## Preliminary Analysis

At fence elaboration time, Verso already holds the enclosing document's
`FileMap`, the original `StrLit` syntax range, and the exact padded input passed
to Lean's elaborator. Attaching a lightweight source-mapping record (owning
file path, original UTF-8/UTF-16 literal span, and padded-prefix byte offset or
origin metadata) to the elaborated context or block data removes the need for
downstream packages to re-parse Verso documents or whitelist expander names.

## Scope Boundary

- Owns Verso's fence-to-source span and buffer mapping metadata.
- Does not own Blueprint realization ownership policy, Lean core doc-comment
  ranges (`UPC-0023`), or Lake module artifact verification (`UPC-0025`).

## Expected Behavior

Elaboration inside a Verso Lean fence makes the fence's owning document span
and padded-to-original mapping directly queryable so Blueprint can verify the
fence against the physical file in one direct slice without re-parsing the
Verso file or maintaining a fence-expander name list.

## Evidence

- `src/VersoBlueprint/Realizations/NativeSource.lean` (`parseIncrementalDocument`,
  `leanFenceContents`, `documentFenceContents`, `documentFences`,
  `paddedFenceInput`, `attributeFenceInput`)
- `src/VersoBlueprint/SourceData.lean` (`syntaxRange`, `FencedSelection.ofSyntax`)
- `tests/VersoBlueprintTests/BlueprintRealizationCapture.lean`

## Current Workaround

`NativeSource.attributeFenceInput` re-parses the owning `.lean` file (using
`parseIncrementalDocument` for `#doc`), collects `StrLit` nodes under a fixed
list of Lean expander names (`lean`, `Informal.lean`,
`Verso.Genre.Manual.InlineLean.lean`, `internal`, `Informal.internal`),
re-runs `Verso.SyntaxUtils.parserInputString` until a literal reproduces the
registered padded buffer, and splices raw bytes back in. Delete those helpers
once Verso exposes the fence source mapping directly.
