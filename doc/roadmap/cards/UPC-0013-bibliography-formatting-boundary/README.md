# UPC-0013 Bibliography Formatting Boundary

Status: open
Kind: cleanup
Priority: low
Origin: upstream-verso
Last reviewed: 2026-07-09
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: none until ownership is decided

## Summary

Decide whether the bibliography formatting cleanup in
`VersoManual/Bibliography.lean` belongs upstream or should remain
Blueprint-specific presentation code.

## Impact

Bibliography presentation affects generated Manual output, but this item is not
yet a concrete upstream API request. Keeping the ownership question explicit
prevents the cleanup from becoming stale inline roadmap clutter.

## Roadmap Decision

Track as an upstream-boundary question. Do not open upstream work until the
formatting change is reviewed as either a general Verso Manual improvement or a
Blueprint-only presentation choice.

## Reproduction Status

No standalone upstream repro is linked.

## Preliminary Analysis

The useful decision is ownership, not implementation mechanics. If the cleanup
is general Manual behavior, it belongs upstream. If it is specific to Blueprint
presentation, it should remain local and documented as such.

## Expected Behavior

Maintainers decide whether to upstream a general bibliography formatting
improvement or document why Blueprint keeps a local presentation layer.

## Evidence

- Local question: `VersoManual/Bibliography.lean`

## Current Workaround

Blueprint keeps the local bibliography presentation behavior while the upstream
boundary remains undecided.
