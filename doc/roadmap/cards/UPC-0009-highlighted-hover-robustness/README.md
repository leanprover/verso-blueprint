# UPC-0009 Highlighted Hover Robustness

Status: candidate
Kind: bug
Priority: medium
Origin: upstream-verso
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: optional tactic-state guards in `patchHighlightedStartupJs`
Related cards: UPC-0008

## Summary

Verso highlighted-code hover rendering should tolerate missing or delayed DOM
nodes without downstream packages patching emitted assets.

## Impact

Blueprint generated pages exercise hidden and dynamically hydrated hover
payloads more heavily than normal pages. Fragile hover startup behavior becomes
a downstream maintenance burden.

## Roadmap Decision

Track as a separate upstream robustness item from the docstring startup
performance fix.

## Reproduction Status

The local patch guards two missing `.tactic-state` lookups, but no standalone
fixture currently demonstrates the unpatched failure. Isolate that case before
promoting this card to `open`.

## Preliminary Analysis

The local substitutions return early when a hover reference has no direct
`.tactic-state`, and preserve the existing content when the target has no state
to clone. Those are concrete defensive changes, but the triggering DOM shape
still needs a focused test.

## Scope Boundary

This card owns only the two missing-tactic-state guards. The required docstring
source-read performance rewrite in the same local patch function is tracked by
UPC-0008 and can be upstreamed and removed independently.

## Expected Behavior

Highlighted-code hover rendering tolerates missing or delayed DOM nodes and does
not require downstream packages to patch the emitted asset.

## Evidence

- Local implementation: `highlightedTacticShowGuardedToggleRead` and
  `highlightedTacticContentGuardedCloneRead` in `PreviewManifest.lean`.
- Missing evidence: a focused fixture that fails without those guards.

## Current Workaround

`PreviewManifest.patchHighlightedStartupJs` optionally inserts guards before
reading or cloning a direct child `.tactic-state` node.
