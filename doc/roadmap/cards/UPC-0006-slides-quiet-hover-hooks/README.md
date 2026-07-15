# UPC-0006 Verso Slides Pipeline Hooks

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-verso-slides
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: copied Slides output loop and local slide asset payload code
Related cards: UPC-0004, UPC-0005

## Summary

Verso Slides should expose a reusable render/output pipeline so Blueprint can
render extension blocks with its own HTML handler, seed the initial hover state,
and suppress the success message without copying `slidesMain`.

## Impact

Blueprint slide decks need Blueprint preview fragments inside Slides output and
need the generated `-verso-docs.json` to start from the rendered-fragment cache's
hover payload table. The current local path mirrors upstream output logic to
thread that data through.

## Roadmap Decision

Track as an upstream `verso-slides` API request. Keep the local wrapper until
Slides exposes the downstream render transform, initial-hover-state, and
quiet-output hooks needed to reuse its output writer.

## Reproduction Status

Covered by Blueprint slide-deck generation and browser validation rather than a
standalone upstream repro.

## Preliminary Analysis

The extension point should let downstream packages customize block rendering,
provide an initial hover state, and choose quiet output while preserving
upstream asset validation and output writing.

## Scope Boundary

These hooks form one card because they are all needed to remove the same copied
`slidesMain` loop. Static runtime asset declaration belongs to UPC-0004, and
head injection and its v4.30 release-pin follow-up belong to UPC-0005.

## Expected Behavior

Blueprint can render `{blueprint_node}` blocks into slide fragments through a
downstream HTML handler, pass the initial hover payload table to upstream
rendering, and keep `quiet := true` behavior while delegating asset validation
and all output writing to Slides.

## Evidence

- Local workaround:
  `VersoBlueprint.Slides.slidesMainWithBlueprintPreviews`
- Local removal targets: `SlideAssetPayload`, `recordSlideAsset`,
  `collectSlideAssets`, and the copied output loop in `VersoBlueprint.Slides`.

## Current Workaround

`VersoBlueprint.Slides.slidesMainWithBlueprintPreviews` installs a local
`GenreHtml Slides IO` handler that renders `{blueprint_node}` blocks from
Blueprint manifest/cache data, then mirrors the small `slidesMain` output loop.
