# UPC-0023 Record Own Doc-Comment Source Ranges

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-lean
Last reviewed: 2026-11-28
Owner: none
Issue: none linked
PR: none linked
Related cards: UPC-0022, UPC-0026

## Summary

Expose the original modifier doc-comment range alongside Lean's compiled declaration ranges.

## Impact

Editors and generated source links can use this range to navigate directly to a declaration's comment. Capture uses compiled Markdown or Verso metadata, so this range is optional presentation metadata.

## Roadmap Decision

Track as an upstream improvement. Current compiled-artifact capture is independent
of this API.
