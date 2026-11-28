# UPC-0022 Expose Inherited Docstring Target Query in Lean Core

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-lean
Last reviewed: 2026-11-27
Owner: none
Issue: none linked
PR: none linked
Upstream timing: as soon as possible
Removal target: `ownDocstringMetadata` effective-vs-direct comparison workaround in `src/VersoBlueprint/Realizations/NativeSource.lean`
Related cards: UPC-0023, UPC-0025

## Summary

Expose a read-only query in `Lean.DocString.Extension` (such as
`Lean.getInheritedDocStringTarget? (env : Environment) (declName : Name) : Option Name`
or `Lean.hasInheritedDocString`) for the existing `private builtin_initialize inheritDocStringExt`.

## Impact

Blueprint realization capture and other Lean documentation/verification tools
need to know whether a declaration's compiled docstring comes directly from its
own modifier doc comment or from `@[inherit_doc]`. Because `inheritDocStringExt`
is currently private, downstream packages cannot query it directly and must
either compare `findInternalDocString?` against `docStringExt` /
`versoDocStringExt` or attempt fragile syntax-level scanning.

## Roadmap Decision

Track upstream as a small, low-risk Lean core API addition. Keep the compiled
environment comparison (`Docstring.directCompiled` vs `Lean.findInternalDocString?`)
in `verso-blueprint` until the upstream query lands.

## Reproduction Status

Confirmed against Lean `v4.35.0` in `Lean/DocString/Extension.lean`:
- `docStringExt` (L126) and `versoDocStringExt` (L138) are public.
- `inheritDocStringExt` (L132) is `private`.
- `addInheritedDocString` (L183-188) rejects only 2-cycles; self-inheritance
  (`attribute [inherit_doc foo] foo`) and cycles of length ≥ 3 can be accepted,
  sometimes without a warning.
- `findInternalDocString?` (L196) is a `partial def` that queries
  `inheritDocStringExt.find? (level := .server) env declName` and recurses with
  no fuel, so any self-cycle or ≥ 3-cycle hangs `findInternalDocString?` (and
  `findDocString?`) indefinitely.

## Preliminary Analysis

`Lean/DocString/Extension.lean` already persists `inheritDocStringExt` in
`.olean.server` and `.olean.private`. Exposing a read-only, non-recursive lookup
that returns only the direct target:

```lean
def getInheritedDocStringTarget? (env : Environment) (declName : Name) : Option Name :=
  inheritDocStringExt.find? (level := .server) env declName
```

requires no serialization or elaboration changes, preserves encapsulation of
mutation (`addInheritedDocString`), and never loops on cyclic inheritance
entries. Upstream should also consider general cycle detection in
`addInheritedDocString` (not just 2-cycles).

## Scope Boundary

This card covers read-only visibility of `inheritDocStringExt` (direct target
only, non-recursive) and optionally full cycle detection in
`addInheritedDocString`. It does not ask Lean to retain unnormalized raw
docstring source bytes.

## Expected Behavior

Downstream tools can call `Lean.getInheritedDocStringTarget? env declName` to
distinguish direct docstrings from `@[inherit_doc]` definitively without
traversing inheritance chains, including when a declaration has both an own doc
comment and `@[inherit_doc target]` with identical text or a cyclic
`@[inherit_doc]` attribute.

## Evidence

- `Lean/DocString/Extension.lean:132,183-188,196-204` (`v4.35.0`)
- `src/VersoBlueprint/Docstring/Compiled.lean`
- `src/VersoBlueprint/Realizations/NativeSource.lean` (`ownDocstringMetadata`)

## Current Workaround

`NativeSource.ownDocstringMetadata` compares `Docstring.directCompiled env name`
against `Lean.findInternalDocString? env name (includeBuiltin := false)` using
pointer identity (`unsafe ptrEq`). That catches differing Markdown docstrings
as well as differing `Lean.VersoDocString` custom `Dynamic` payloads elided by
`Repr` (such as `{name}` links to different constants), while identical content
deduplicated during `.olean` compaction remains indistinguishable and cyclic
`@[inherit_doc]` entries accepted by `addInheritedDocString` can hang
`findInternalDocString?`. Once `getInheritedDocStringTarget?` is available in
Lean, replace this workaround with a direct `Option.isSome` check.
