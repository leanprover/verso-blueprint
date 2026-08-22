# UPC-0010 Package Asset Resolution During Elaboration

Status: resolved
Kind: upstream-api
Priority: medium
Origin: upstream-lake
Last reviewed: 2026-08-22
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: achieved; `MathLint.lean` package-root walking was removed
Related cards: UPC-0004, UPC-0019, UPC-0020

## Summary

Blueprint no longer needs a package-asset lookup API during elaboration. Its
Node worker source is embedded in `VersoBlueprint.MathLint`, and the worker is
initialized from Verso's public embedded KaTeX string.

## Impact

The former math-lint implementation searched source and `.olean` locations for
`static-web/katex-lint.mjs` and Verso's vendored KaTeX module. Besides depending
on private Lake layout, that made linting sensitive to cache-in-place artifacts
and non-default package directories.

## Roadmap Decision

Resolve this pressure point locally instead of proposing a Lean or Lake API.
Embedding the small Blueprint worker and reusing Verso's already-embedded KaTeX
payload gives the elaborator the data it needs without interpreting source or
artifact paths. Reopen an upstream request only if a future elaborator has a
genuine need for package-owned mutable files rather than compile-time data.

## Reproduction Status

Fresh consumer smoke coverage passes for default and non-default Lake
`packagesDir` layouts with the artifact cache enabled and
`LAKE_RESTORE_ARTIFACTS=false`.

## Preliminary Analysis

Verso already exposes its compile-time KaTeX distribution as
`Verso.Output.Html.katex.js`. Blueprint can import that value and send it once
when its embedded persistent worker starts. This removes both package-root
walks and any dependence on the location of imported `.olean` files.

## Scope Boundary

This card owns filesystem lookup during Lean elaboration. It does not own how
browser assets are declared or emitted into a generated site; that is UPC-0004.

## Expected Behavior

Math linting behaves identically in root, dependency, alternate-package, and
cache-in-place builds without resolving a package source or `.olean` path.

## Evidence

- Removed workaround: source-search-path, `.olean`-path, and parent-directory
  walking in `MathLint.lean`
- Declared input: `mathLintWorkerJs` in `lakefile.lean`
- Local coverage: `scripts/check_math_lint_fresh_repo.py` exercises default and
  non-default `packagesDir` consumers with cache-in-place artifacts, exact lint
  failures, and `--wfail`.

## Current Workaround

None. The worker and its KaTeX runtime are values imported from Lean artifacts.
