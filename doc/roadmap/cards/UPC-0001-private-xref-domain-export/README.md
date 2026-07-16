# UPC-0001 Private Xref Domain Export

Status: open
Kind: upstream-api
Priority: high
Origin: upstream-verso
Last reviewed: 2026-07-16
Owner: none
Issue: https://github.com/leanprover/verso/issues/840
PR: none linked
Upstream timing: as soon as possible
Removal target: `PreviewManifest.buildPublicXrefJson` and `emitPublicXref`
Related cards: UPC-0002

## Summary

Verso Manual HTML should let extensions mark cross-reference domains as public
output or traversal-private data before `xref.json` and the generated find page
are emitted.

## Impact

Blueprint needs traversal-local domains for preview, graph, and generated-data
work, but not every domain should become public search or xref payload. The
current post-processing path makes Blueprint depend on Verso's emitted output
shape.

## Roadmap Decision

Track this as an upstream Verso API request. Keep the local filter until Verso
offers an extension-level way to control public xref export.

## Reproduction Status

Covered by Blueprint generated-output validation rather than a standalone
upstream repro.

## Preliminary Analysis

The filtering decision belongs before Manual HTML writes public xref artifacts.
Filtering after emission works, but it forces downstream packages to rewrite
both `xref.json` and the find page consistently.

## Scope Boundary

This card owns the policy for choosing public domains and the xref payload that
implements it. [`UPC-0002`](../UPC-0002-manual-html-extension-hooks/README.md)
owns the Manual pipeline hooks that would let Blueprint stop copying the
top-level dispatcher; either upstream change is useful without the other.

## Expected Behavior

Extensions can declare whether traversal domains are public xref data or
private traversal storage. The same decision controls both `xref.json` and the
find page. Verso can also choose whether to emit compressed or minified xref
payloads.

## Evidence

- Upstream issue: https://github.com/leanprover/verso/issues/840
- Local workaround: `PreviewManifest.buildPublicXrefJson`
- Local workaround: `PreviewManifest.emitPublicXref`

## Current Workaround

Blueprint filters traversal domains after traversal, writes the filtered
`xref.json`, and replaces the xref payload embedded in the generated find page
after Verso HTML emission.
