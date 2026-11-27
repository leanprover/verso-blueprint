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
Related cards: none

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
- `findInternalDocString?` (L196) queries `inheritDocStringExt.find? (level := .server) env declName`.

## Preliminary Analysis

`Lean/DocString/Extension.lean` already persists `inheritDocStringExt` in
`.olean.server` and `.olean.private`. Exposing a read-only lookup:

```lean
def getInheritedDocStringTarget? (env : Environment) (declName : Name) : Option Name :=
  inheritDocStringExt.find? (level := .server) env declName
```

requires no serialization or elaboration changes and preserves encapsulation of
mutation (`addInheritedDocString`).

## Scope Boundary

This card covers only read-only visibility of `inheritDocStringExt`. It does
not ask Lean to retain unnormalized raw docstring source bytes.

## Expected Behavior

Downstream tools can call `Lean.getInheritedDocStringTarget? env declName` to
distinguish direct docstrings from `@[inherit_doc]` definitively, including in
the degenerate case where a declaration has both an own doc comment and
`@[inherit_doc target]` with identical text.

## Evidence

- `Lean/DocString/Extension.lean:132,196-204` (`v4.35.0`)
- `src/VersoBlueprint/Docstring/Compiled.lean`
- `src/VersoBlueprint/Realizations/NativeSource.lean` (`ownDocstringMetadata`)

## Current Workaround

`NativeSource.ownDocstringMetadata` compares `Docstring.directCompiled env name`
against `Lean.findInternalDocString? env name (includeBuiltin := false)` and
rejects any declaration whose effective docstring differs from its direct
compiled docstring (plus checks `@[inherit_doc]` in the declaration's own
modifiers). Once `getInheritedDocStringTarget?` is available in Lean, replace
the effective-vs-direct comparison with a direct `Option.isSome` check.
