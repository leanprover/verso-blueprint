# UPC-0010 Package Asset Resolution During Elaboration

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-lake
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: `MathLint.lean` package-root walking
Related cards: UPC-0004

## Summary

Lake should provide a stable way for elaborators to resolve package-owned files
from a module and package-relative path. A Verso helper may additionally hide
the location of Verso's vendored KaTeX module.

## Impact

Blueprint math linting needs to locate package-owned assets such as
`static-web/katex-lint.mjs` and Verso's vendored KaTeX module across root
checkouts, dependency checkouts, and non-default Lake package directories. The
current local search relies on package layout details.

## Roadmap Decision

Track the general package/module lookup as an upstream Lake API request. A
separate Verso convenience wrapper is useful only for the Verso-owned KaTeX
path and does not replace lookup of Blueprint's own lint script.

## Reproduction Status

Blueprint has fresh consumer smoke coverage for root checkouts, dependency
checkouts, and non-default Lake `packagesDir`.

## Preliminary Analysis

The local workaround walks upward from module source or `.olean` locations to
recover package roots. That is serviceable for validation, but it is too
layout-sensitive for a long-term downstream API.

## Scope Boundary

This card owns filesystem lookup during Lean elaboration. It does not own how
browser assets are declared or emitted into a generated site; that is UPC-0004.

## Expected Behavior

Downstream elaborators can resolve a package-owned file through a stable
module-to-package-root or package-asset lookup API without walking parent
directories. Verso may wrap that API for its own vendored assets.

## Evidence

- Local workaround: `MathLint.lean`
- Local coverage: fresh consumer smoke tests for root checkouts, dependency
  checkouts, and non-default Lake `packagesDir`.

## Current Workaround

`MathLint.lean` walks upward from module source or `.olean` locations to recover
package roots for `static-web/katex-lint.mjs` and Verso's vendored KaTeX module.
