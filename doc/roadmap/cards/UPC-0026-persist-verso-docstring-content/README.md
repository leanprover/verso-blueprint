# UPC-0026 Persist Raw Text or a Canonical Hash for Verso Docstrings

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-lean
Last reviewed: 2026-11-28
Owner: none
Issue: none linked
PR: none linked
Related cards: UPC-0022, UPC-0023

## Summary

Persist original docstring text or a versioned canonical content hash alongside `versoDocStringExt` in `.olean.server`.

## Impact

The compiled docstring tree holds custom payloads in `Dynamic`. Blueprint encodes supported payloads structurally and leaves opaque extensions unavailable. A compiler-provided representation could bind arbitrary compiled documentation without adding a decoder for each extension. A canonical hash should cover the document tree and all resolved extension identities, including name-link destinations. If only raw text is stored, consumers still need an explicit identity for changes in name resolution.

`DocHighlight.var` carries a name, free-variable ID and formatted type, with no
`LocalContext`. Blueprint reports `unsupported-docstring-extension` for a
highlighted local unless a `Lean.Doc.Data.Local` payload in the same docstring
supplies an unambiguous position for that exact ID. Upstream binder metadata
or a canonical hash that preserves resolved binder identities could cover
docstrings without a separate local name link.

## Roadmap Decision

Track as an upstream improvement. Current compiled-artifact capture is independent
of this API.
