# UPC-0009 Highlighted Hover Robustness

Status: open
Kind: bug
Priority: medium
Origin: upstream-verso
Last reviewed: 2026-07-08
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: downstream patches to emitted highlighted-code assets

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

No standalone upstream repro is currently linked.

## Preliminary Analysis

This card is intentionally separate from the `innerText` performance issue:
performance and DOM-availability robustness may need different upstream tests
and fixes.

## Expected Behavior

Highlighted-code hover rendering tolerates missing or delayed DOM nodes and does
not require downstream packages to patch the emitted asset.

## Evidence

- Local pressure point: Blueprint hidden and dynamically hydrated hover payloads.

## Current Workaround

Blueprint keeps downstream robustness guards for generated highlighted-code
assets where needed.
