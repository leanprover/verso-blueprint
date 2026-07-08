# UPC-0008 Highlighted Docstring Performance

Status: open
Kind: performance
Priority: high
Origin: upstream-verso
Last reviewed: 2026-07-08
Owner: none
Issue: none linked
PR: none linked
Upstream timing: as soon as possible
Removal target: `PreviewManifest.patchHighlightedDocstringStartupJs`

## Summary

Verso's highlighted-code startup should read hidden docstring markdown source
with `textContent` instead of layout-sensitive `innerText`.

## Impact

Blueprint generated pages exercise hidden hover payloads heavily. Reading
docstring source with `innerText` can trigger expensive layout work and can
return empty text for hidden payloads.

## Roadmap Decision

Track as an upstream Verso performance fix. Keep the local JavaScript rewrite
until the upstream highlighted-code asset uses the cheaper source read.

## Reproduction Status

Observed on the Noperthedron reference blueprint.

## Preliminary Analysis

The affected nodes contain raw markdown source and often live under hidden
`.hover-info` containers. `textContent || ""` is enough for the source read and
does not require layout-sensitive text extraction.

## Expected Behavior

Verso highlighted-code startup reads `code.docstring, pre.docstring` source via
`textContent || ""` before `marked.parse`.

## Evidence

- Observed Blueprint impact: the Noperthedron `The-Local-Theorem` reference page
  dropped from roughly 14 seconds of highlighted-code startup work to under 0.5
  seconds after the local rewrite.
- Upstream code points at Verso commit
  `7ae82ac2ae54ae5dcc9948a701669e9b596e5cae`:
  - `src/verso/Verso/Code/Highlighted.lean#L1377-L1384`
  - `src/verso/Verso/Code/Highlighted.lean#L1460-L1467`

## Current Workaround

`PreviewManifest.patchHighlightedDocstringStartupJs` rewrites generated
highlighted-code JavaScript to read docstring source via `textContent`.
