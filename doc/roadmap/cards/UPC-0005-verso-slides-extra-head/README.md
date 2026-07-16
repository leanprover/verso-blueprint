# UPC-0005 Verso Slides Extra Head

Status: close-candidate
Kind: upstream-api
Priority: medium
Origin: upstream-verso-slides
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: https://github.com/leanprover/verso-slides/pull/59
Upstream timing: next compatible v4.31 release pin
Removal target: temporary `ejgallego/verso-slides` fork pin
Related cards: UPC-0004, UPC-0006

## Summary

Verso Slides needed module-script/head injection support so Blueprint slide decks
could load normal ESM preview runtime files.

## Impact

Without Slides `extraHead`, Blueprint had to carry a de-ESMified slide runtime
path. With upstream support, slide decks can use the same ESM preview runtime
shape as normal Blueprint pages.

## Roadmap Decision

The upstream API request is resolved, but this release line remains a close
candidate until Blueprint can replace its temporary v4.31-compatible fork pin
with a normal release pin.

## Reproduction Status

Covered by Blueprint slide-deck generation and browser validation.

## Preliminary Analysis

The needed API was an upstream Slides `Config.extraHead` hook. That hook lets
Blueprint inject the slide-specific ESM entrypoint without changing the Slides
writer.

## Scope Boundary

This card covers only head injection and the remaining release-pin cleanup.
Structured asset declaration remains UPC-0004, while reuse of the upstream
Slides traversal/render/output pipeline remains UPC-0006.

## Expected Behavior

Blueprint slide decks write normal preview ESM support files, load a
slide-specific runtime entrypoint, pass the preview renderer explicitly to slide
hydration, and avoid a de-ESMified `blueprint-slides.js` bundle.

## Evidence

- Upstream PR: https://github.com/leanprover/verso-slides/pull/59
- Upstream status: `Config.extraHead` is in the `verso-slides` v4.32.0 tag.
- Local release pin: `lakefile.lean` requires the v4.31-compatible fork commit
  `e6a5d54228eb21fd86b041ab786d2d03bfb46685`.

## Current Workaround

The v4.31 branch pins `ejgallego/verso-slides` to upstream PR 59 plus a
one-commit toolchain revert to Lean 4.31. The runtime itself already uses
`Config.extraHead`; only the temporary release-line pin remains.
