# UPC-0003 Wide Content Page Mode

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-verso
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: graph-specific page-shell overrides
Related cards: none

## Summary

Verso Manual pages should offer a generic page-level or section-level wide
content mode for pages whose primary content needs to escape the normal Manual
text column.

## Impact

Blueprint graph pages need a wider frame than ordinary prose pages while still
using the shared Manual shell and table-of-contents semantics. The current local
CSS/runtime behavior is specific to graph pages even though the layout need is
not graph-specific.

## Roadmap Decision

Track as an upstream Verso Manual layout capability. Keep local graph-shell
overrides until the Manual page shell offers a stable opt-in.

## Reproduction Status

Covered by generated Blueprint graph pages rather than a standalone upstream
repro.

## Preliminary Analysis

The target should be a generic Manual content-frame option, not a Blueprint
graph feature. The opt-in needs to preserve normal Manual navigation, headings,
and table-of-contents behavior.

## Scope Boundary

This card owns only the Manual content-frame opt-in. Graph layout, canvas sizing,
and graph-specific interactions remain Blueprint concerns.

## Expected Behavior

Authors or downstream extensions can opt a page or section into a wider content
frame without replacing the shared Manual shell.

## Evidence

- Local pressure point: Blueprint graph pages.
- Local workaround: graph page-shell CSS and runtime behavior.

## Current Workaround

Graph pages carry Blueprint-local page-shell CSS/runtime behavior to escape the
normal `.content-wrapper` and `main section` max-width assumptions.
