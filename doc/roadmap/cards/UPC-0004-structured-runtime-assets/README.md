# UPC-0004 Structured Runtime Assets

Status: open
Kind: upstream-api
Priority: high
Origin: upstream-verso
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: none linked
Upstream timing: as soon as possible
Removal target: Blueprint-local runtime asset writers and asset-kind/head assembly
Related cards: UPC-0005, UPC-0006, UPC-0007, UPC-0010

## Summary

Verso should expose first-class structured runtime assets, including ESM module
scripts, so downstream packages can declare emitted browser assets without
string-concatenated bundles or package-specific writers.

## Impact

Blueprint owns several browser runtimes for previews, graph pages, summaries,
citations, math, and slide hydration. Without structured upstream asset support,
Blueprint must assemble asset bundles, write package-owned files, and inject
entrypoints through feature-specific code.

## Roadmap Decision

Track as an upstream Verso asset API request. Keep local package-asset embedding
until downstream packages can declare asset kinds, output URLs, ordering, and
module-script entries directly.

## Reproduction Status

Covered by Blueprint generated-output and browser-regression flows rather than
a standalone upstream repro.

## Preliminary Analysis

The API needs stable output URLs, explicit asset kinds such as stylesheet,
classic script, and `type="module"` script, plus dependency/order metadata for
ESM entrypoints.

## Scope Boundary

This card owns declaration and emission of static browser assets. It does not
own Slides pipeline lifecycle hooks (UPC-0006), content-dependent KaTeX prelude
data (UPC-0007), or locating package files during Lean elaboration (UPC-0010).
UPC-0005 is the landed, narrower Slides head-injection prerequisite and tracks
the remaining v4.31 release-pin cleanup. Durable Lean/Lake rebuild edges for
`include_str` inputs remain a repository-local Asset and Build Reliability
workstream in [`ROADMAP.md`](../../../ROADMAP.md).

## Expected Behavior

Downstream packages declare runtime assets in structured form. Verso emits them
at predictable URLs and lets ESM entrypoints import package-owned modules
without de-ESMified compatibility bundles.

## Evidence

- Local pressure points: Blueprint `-verso-data/` writers and browser runtime
  entrypoints.
- Local workaround: package-owned Lean modules plus feature-specific asset
  plans, writers, and head injection.

## Current Workaround

Blueprint package assets are embedded through package-owned Lean modules and
emitted through Blueprint-local `-verso-data/` writers. Regular Manual pages and
slide decks inject their ESM entrypoints with `extraHead`.
