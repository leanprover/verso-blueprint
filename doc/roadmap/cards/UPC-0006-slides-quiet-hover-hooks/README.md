# UPC-0006 Slides Quiet Hover Hooks

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-verso-slides
Last reviewed: 2026-07-08
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: copied Slides output loop and local slide asset payload code

## Summary

Verso Slides should expose hooks for quiet rendering and initial hover state so
Blueprint can reuse upstream slide output writing without copying the small
`slidesMain` output loop.

## Impact

Blueprint slide decks need Blueprint preview fragments inside Slides output and
need the generated `-verso-docs.json` to start from the rendered-fragment cache's
hover payload table. The current local path mirrors upstream output logic to
thread that data through.

## Roadmap Decision

Track as an upstream `verso-slides` API request. Keep the local wrapper until
Slides exposes the needed quiet-output and initial-hover-state parameters.

## Reproduction Status

Covered by Blueprint slide-deck generation and browser validation rather than a
standalone upstream repro.

## Preliminary Analysis

The extension point should let downstream packages call upstream `slidesMain`
with optional initial hover state and quiet-output behavior while preserving
upstream asset validation and output writing.

## Expected Behavior

Blueprint can render `{blueprint_node}` blocks into slide fragments, pass the
initial hover payload table to upstream Slides output, and keep `quiet := true`
behavior without copying the Slides output loop.

## Evidence

- Local workaround:
  `VersoBlueprint.Slides.slidesMainWithBlueprintPreviews`
- Local removal targets: `SlideAssetPayload`, `recordSlideAsset`,
  `collectSlideAssets`, and the copied output loop in `VersoBlueprint.Slides`.

## Current Workaround

`VersoBlueprint.Slides.slidesMainWithBlueprintPreviews` rewrites
`{blueprint_node}` blocks from Blueprint manifest/cache data to
`VersoSlides.BlockExt.ofHtml` during Slides traversal, then mirrors the small
`slidesMain` output loop.
