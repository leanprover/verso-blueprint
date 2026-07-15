# UPC-0005 Verso Slides Extra Head

Status: close-candidate
Kind: upstream-api
Priority: medium
Origin: upstream-verso-slides
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: https://github.com/leanprover/verso-slides/pull/59
Upstream timing: next compatible v4.30 release pin
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
candidate until Blueprint can replace its temporary v4.30-compatible fork pin
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
Slides render/output pipeline remains UPC-0006.

## Expected Behavior

Blueprint slide decks write normal preview ESM support files, load a
slide-specific runtime entrypoint, pass the preview renderer explicitly to slide
hydration, and avoid a de-ESMified `blueprint-slides.js` bundle.

## Evidence

- Upstream PR: https://github.com/leanprover/verso-slides/pull/59
- Upstream status: `Config.extraHead` is in the `verso-slides` v4.32.0 tag.
- Local release pin: `lakefile.lean` requires the v4.30-compatible fork commit
  `7bcedddced33ab0c955972e22be01f192aa1dc05`.

## Current Workaround

The v4.30 branch pins `ejgallego/verso-slides` to its v4.30-compatible base
plus the minimal `Config.extraHead` change. The runtime itself already uses
`extraHead`; only the temporary release-line pin remains.
