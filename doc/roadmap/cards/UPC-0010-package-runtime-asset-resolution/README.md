# UPC-0010 Package Runtime Asset Resolution

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-verso
Last reviewed: 2026-07-09
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: `MathLint.lean` package-root walking

## Summary

Verso or Lake should provide a stable way to resolve package-owned runtime
assets during elaboration.

## Impact

Blueprint math linting needs to locate package-owned assets such as
`static-web/katex-lint.mjs` and Verso's vendored KaTeX module across root
checkouts, dependency checkouts, and non-default Lake package directories. The
current local search relies on package layout details.

## Roadmap Decision

Track as an upstream API request. Prefer a Verso-owned helper if that can hide
vendored asset layout from downstream packages; otherwise track the required
package-root lookup support in Lake or Lean.

## Reproduction Status

Blueprint has fresh consumer smoke coverage for root checkouts, dependency
checkouts, and non-default Lake `packagesDir`.

## Preliminary Analysis

The local workaround walks upward from module source or `.olean` locations to
recover package roots. That is serviceable for validation, but it is too
layout-sensitive for a long-term downstream API.

## Expected Behavior

Downstream elaborators can resolve package-owned runtime assets through a stable
package-root or package-asset lookup API, or through a Verso helper that owns the
vendored asset details.

## Evidence

- Local workaround: `MathLint.lean`
- Local coverage: fresh consumer smoke tests for root checkouts, dependency
  checkouts, and non-default Lake `packagesDir`.

## Current Workaround

`MathLint.lean` walks upward from module source or `.olean` locations to recover
package roots for `static-web/katex-lint.mjs` and Verso's vendored KaTeX module.
