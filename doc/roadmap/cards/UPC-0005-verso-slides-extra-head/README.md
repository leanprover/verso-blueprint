# UPC-0005 Verso Slides Extra Head

Status: close-candidate
Kind: upstream-api
Priority: medium
Origin: upstream-verso-slides
Last reviewed: 2026-07-08
Owner: none
Issue: none linked
PR: https://github.com/leanprover/verso-slides/pull/59
Upstream timing: next supported-toolchain bump
Removal target: post-rc1 `verso-slides` commit pin once release support exists

## Summary

Verso Slides needed module-script/head injection support so Blueprint slide decks
could load normal ESM preview runtime files.

## Impact

Without Slides `extraHead`, Blueprint had to carry a de-ESMified slide runtime
path. With upstream support, slide decks can use the same ESM preview runtime
shape as normal Blueprint pages.

## Roadmap Decision

Treat the upstream request as landed. Keep the card open as a close candidate
until a supported `verso-slides` release includes `Config.extraHead` and
Blueprint no longer needs the post-rc1 commit pin.

## Reproduction Status

Covered by Blueprint slide-deck generation and browser validation.

## Preliminary Analysis

The needed API was an upstream Slides `Config.extraHead` hook. That hook lets
Blueprint inject the slide-specific ESM entrypoint without changing the Slides
writer.

## Expected Behavior

Blueprint slide decks write normal preview ESM support files, load a
slide-specific runtime entrypoint, pass the preview renderer explicitly to slide
hydration, and avoid a de-ESMified `blueprint-slides.js` bundle.

## Evidence

- Upstream PR: https://github.com/leanprover/verso-slides/pull/59
- Upstream status: `Config.extraHead` landed on the `verso-slides` main line.

## Current Workaround

This checkout's Lean toolchain is `v4.32.0-rc1`, and `lakefile.lean` pins
`leanprover/verso-slides` to the upstream post-rc1 commit that merged PR 59
until the next `verso-slides` tag includes `Config.extraHead`. Once a supported
`verso-slides` release line contains `extraHead`, replace the commit pin with
the normal upstream release pin.
