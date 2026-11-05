# UPC-0022 Ordered Manual Inline Stylesheets

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-verso
Last reviewed: 2026-11-05
Owner: none
Issue: none linked
PR: none linked
Upstream timing: next supported-toolchain bump
Removal target: `Informal.PreviewManifest.blueprintCascadeCss` and its `extraHead` re-emission in `PreparedRendererState.emit`
Related cards: UPC-0004, BPC-0001

## Summary

Verso Manual should emit inline stylesheets in a deterministic order that
extensions can rely on, for example the order in which they were registered.

## Impact

`TraverseState.extraCss` is a `HashSet CSS`, and `Html.page` writes it with
`extraCss.toArray`. The cascade order of every inline stylesheet therefore
depends on string hashes. When rules tie in specificity, editing any stylesheet
can change which rule wins in unrelated stylesheets.

## Roadmap Decision

Track upstream. Keep the local re-emission until Verso orders `extraCss`.

## Reproduction Status

Reproduced on `feat/visual-design`. Removing the style switcher's stylesheet
moved the Blueprint block stylesheet from tenth to first among 14 inline
blocks, ahead of Verso's docstring styles. Lean declaration panels then grew
from 0.86rem to 1rem without any rule for them changing. A computed-style diff
across 21 pages showed the effect.

## Preliminary Analysis

The same `HashSet` holds styles contributed by Verso features, by Blueprint
block and command descriptors, and by downstream projects. An insertion-ordered
collection that still removes duplicates would preserve the current
deduplication. `TraverseState` has a private constructor, so extensions cannot
reorder `extraCss` before emission.

## Scope Boundary

UPC-0004 owns structured runtime asset files, including script and stylesheet
URLs and their dependency order. This card owns only the inline `extraCss`
order. The two can land independently.

## Expected Behavior

Inline stylesheets are emitted in a documented, deterministic order, and
duplicates are still removed.

## Evidence

- `feat/visual-design` commit 915dad9c: `fix: emit Blueprint styles in a fixed
  cascade order`.
- `VersoBlueprintTests.BlueprintAssets` pins the local order.

## Current Workaround

`PreparedRendererState.emit` appends one `<style>` element with every Blueprint
stylesheet, in sorted order, to `extraHead`, which Verso writes after all
`extraCss` blocks. Each page therefore carries the Blueprint rules twice: the
starter Addition page grew from 210 KB to 268 KB. Delete the re-emission and
`blueprintCascadeCss` once Verso orders `extraCss`.
