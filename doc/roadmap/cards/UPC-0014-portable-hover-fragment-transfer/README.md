# UPC-0014 Portable Hover Fragment Transfer

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-verso
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: `ExternalDeclRenderedHtml` marker/rewrite machinery and `renderedHtmlWithHoverTable`
Related cards: none

## Summary

Verso should expose a portable highlighted-fragment API that carries local
hover ids and payloads until a downstream renderer can register them in its
destination hover table and rewrite the fragment to final `data-verso-hover`
ids.

## Impact

Blueprint renders external declaration snippets before a final Manual page or
preview-cache hover table exists. Reusing normal highlighted-code hovers
therefore requires a local transfer representation and separate registration
paths for page HTML, generated cache fragments, and isolated self-contained
previews.

## Roadmap Decision

Track this as an upstream Verso highlighted-fragment API request. Keep the local
portable-fragment bridge until Verso can transfer hover payloads between an
isolated render and a destination hover table without downstream marker
rewrites.

## Reproduction Status

Covered by external-declaration page, preview-cache, and slide rendering tests.
The current bridge exercises both destination-table registration and isolated
self-contained rendering.

## Preliminary Analysis

Highlighted snippets rendered outside the final page cannot allocate stable
page hover ids. The reusable boundary is a fragment with local ids plus an
ordered payload table, followed by a helper that registers each payload in the
destination dedup table and substitutes the returned ids into the fragment.

## Scope Boundary

This card owns server-side transfer of highlighted hover payloads between
rendering contexts. It does not own highlighted-code startup performance or DOM
robustness (UPC-0008 and UPC-0009), nor static browser asset declaration
(UPC-0004); those changes can land and be removed independently.

## Expected Behavior

Verso can render a highlighted snippet as a portable fragment, inline its hover
payloads for an isolated consumer, or register those payloads in a destination
hover state and emit the fragment with final `data-verso-hover` ids.

## Evidence

- Local representation and rewrite layer:
  `Informal.ExternalDeclRenderedHtml` in `ExternalDeclRender.lean`.
- Local destination-table bridge:
  `Informal.ExternalCode.renderedHtmlWithHoverTable`.
- Local coverage: `tests/VersoBlueprintTests/ExternalDeclRender.lean` and
  Blueprint Slides rendering tests.

## Current Workaround

Blueprint templates isolated hover ids into custom marker attributes, carries
the hover payloads beside the rendered HTML, and later rewrites those markers
either to destination-table `data-verso-hover` ids or to inline hover HTML.
