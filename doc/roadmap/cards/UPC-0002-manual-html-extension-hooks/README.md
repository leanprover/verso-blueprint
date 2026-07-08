# UPC-0002 Manual HTML Extension Hooks

Status: open
Kind: upstream-api
Priority: high
Origin: upstream-verso
Last reviewed: 2026-07-08
Owner: none
Issue: none linked
PR: https://github.com/ejgallego/verso/pull/new/verso-manual-extra-step-upstream-20260313
Upstream timing: as soon as possible
Removal target: `PreviewManifest.blueprintMain`

## Summary

Verso Manual HTML should expose extension hooks around traversal and emission so
Blueprint can add preview data and xref filtering without mirroring Verso's
top-level Manual dispatcher.

## Impact

Blueprint currently delegates to Verso traversal and HTML emitters, but it still
mirrors the single-page and multi-page dispatcher to insert Blueprint-specific
steps. That creates release-line churn whenever the upstream dispatcher changes.

## Roadmap Decision

Track this as an upstream Verso API request. Keep the local dispatcher mirror
until Verso exposes a stable hook boundary.

## Reproduction Status

No standalone upstream repro is currently linked. The preserved branch records a
candidate upstream shape.

## Preliminary Analysis

The most useful hook is a post-traversal, pre-HTML-emission transform for
`TraverseState` and `HtmlAssets`. A lower-priority post-emit hook would still be
useful for downstream files such as Blueprint preview data.

## Expected Behavior

Downstream packages can transform traversal state and HTML assets, customize the
xref payload used by both `xref.json` and the find page, and optionally write
extra downstream files without copying the upstream Manual dispatcher.

## Evidence

- Preserved branch: `ejgallego/verso-manual-extra-step-upstream-20260313`
- PR shortcut:
  https://github.com/ejgallego/verso/pull/new/verso-manual-extra-step-upstream-20260313
- Local workaround: `PreviewManifest.blueprintMain`

## Current Workaround

`PreviewManifest.blueprintMain` mirrors Verso's top-level single-page and
multi-page dispatcher while still delegating traversal and HTML emission back to
Verso.
