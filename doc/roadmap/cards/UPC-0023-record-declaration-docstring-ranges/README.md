# UPC-0023 Record Own Doc-Comment Source Ranges in Lean Core

Status: open
Kind: upstream-api
Priority: high
Origin: upstream-lean
Last reviewed: 2026-11-27
Owner: none
Issue: none linked
PR: none linked
Upstream timing: as soon as possible
Removal target: whole-file command replay, scope emulation, and modifier scanning in `src/VersoBlueprint/Realizations/NativeSource.lean`
Related cards: UPC-0022, UPC-0024, UPC-0025

## Summary

Record the original source range of a declaration's own modifier doc comment
alongside `DeclarationRanges` (persisted at `.server` / `.private` level during
declaration elaboration) and expose a read-only lookup such as
`Lean.findDocCommentRange? (env : Environment) (declName : Name) : Option DeclarationRange`.

## Impact

Blueprint realization capture needs the exact raw bytes of a declaration's own
doc comment (preserving original whitespace, line endings, and exact span) to
bind informal statements and reviews to the checked declaration. Because Lean
stores only the overall declaration range and identifier selection range, not
the modifier doc-comment range, `verso-blueprint` currently re-parses the
owning Lean source file without elaboration, replays `open` / `namespace` /
`section` / `end` / `set_option` parser contexts, unwraps `mutual` and `in`
command wrappers, and walks parsed modifiers.

This re-parsing machinery has been the single largest source of regressions in
realization capture (previously requiring a partial `in`-wrapper whitelist that
missed `omit ... in`, `include ... in`, `unseal ... in`, plus relative
`open scoped` interactions and parser-recovery edge cases).

## Roadmap Decision

Track upstream as a high-priority Lean core API addition. Combined with
`UPC-0022`, it lets `verso-blueprint` read a declaration's own doc comment
directly from the verified owning source bytes without re-parsing Lean files.

## Reproduction Status

Confirmed against Lean `v4.35.0`:
- `Lean.DeclarationRange` / `Lean.addDeclarationRangesFromSyntax` record only
  `range` (whole declaration including modifiers) and `selectionRange`
  (declaration identifier), discarding the `docComment` child span.
- `src/VersoBlueprint/Realizations/NativeSource.lean` (`openParserNamespaces`,
  `setParserOption`, `enterParserScopes`, `advanceParserContext`,
  `parseSourceWith`, `declarations`,
  `docCommentSyntaxAtRanges`) recovers doc-comment spans from source text
  without re-elaboration. Note that `prepareInlineBlock` also shares
  `parseSource` to verify declarations inside Verso Lean fences, so retiring the
  shared parser path depends on `UPC-0024` as well.

## Preliminary Analysis

During command elaboration (`Lean/Elab/Command.lean` /
`Lean/Elab/DeclarationRange.lean`), Lean already holds the parsed `docComment`
syntax node and the module's `FileMap` when attaching a direct docstring to
`declName`. Recording its `DeclarationRange` (or UTF-8/UTF-16 range) in a
server-level `MapDeclarationExtension` alongside `docStringExt` /
`versoDocStringExt` adds minimal metadata per documented declaration and
requires no re-parsing by downstream tools.

## Scope Boundary

- Owns recording and exposing the source range of a declaration's own modifier
  doc comment.
- Does not own `inherit_doc` target lookup (`UPC-0022`), Verso fence buffer
  mapping (`UPC-0024`), or loaded-module source verification (`UPC-0025`).

## Expected Behavior

For any declaration elaborated with a direct modifier doc comment, Lean exposes
its original `DeclarationRange` at `.server` / `.private` level so downstream
tools can slice the exact raw comment directly from the verified owning source
buffer (after confirming via `UPC-0022` that the docstring is not inherited).

## Evidence

- `src/VersoBlueprint/Realizations/NativeSource.lean` (`parseSourceWith`,
  `advanceParserContext`, `declarations`, `docCommentSyntaxAtRanges`)
- `tests/VersoBlueprintTests/BlueprintRealizationAdapter/ParserSource.lean`
- `Lean/Elab/DeclarationRange.lean` (`v4.35.0`)

## Current Workaround

`NativeSource.lean` re-parses the owning source file in the final syntax
environment while replaying standalone `open`, `namespace`, `section`, `end`,
and `set_option` commands, unwraps `mutual` and `in` command wrappers in
`declarations`, matches the declaration by `(range, selectionRange)`,
and slices the `docComment` syntax span. Once `UPC-0022` and `UPC-0023` land,
delete the ordinary-file command replay, scope replay, wrapper unwrapping, and
modifier comment scan.
