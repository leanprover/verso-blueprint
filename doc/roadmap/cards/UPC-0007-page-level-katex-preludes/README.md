# UPC-0007 Page-Level KaTeX Preludes

Status: candidate
Kind: upstream-api
Priority: low
Origin: upstream-verso
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: conditional; Blueprint page-level prelude injection if upstreamed
Related cards: UPC-0004

## Summary

Decide whether page-level KaTeX preludes belong in core Verso or should remain a
Blueprint-specific rendering layer.

## Impact

Blueprint owns math surfaces that need page-level math assets and prelude
injection. The ownership boundary is not yet clear enough to decide whether this
should become a reusable Verso hook.

## Roadmap Decision

Track as an upstream-boundary question, not a ready implementation request.
Defer upstream work until the generic Manual hook shape is clearer.

## Reproduction Status

No standalone upstream repro is linked.

## Preliminary Analysis

This may be covered by a more general Manual page-level prelude hook. If not,
Blueprint can continue owning the local math presentation layer.

## Scope Boundary

This card owns content-dependent prelude data attached to math rendering, not
the declaration and emission of static browser files tracked by UPC-0004.

## Expected Behavior

Either Verso exposes a generic hook for page-level math preludes, or Blueprint
documents that downstream packages should continue owning this layer locally.

## Evidence

- Local pressure points: `Math.mathHtmlAssets`,
  `Macros.texPreludeTableJs`, and preview-runtime math hydration.

## Current Workaround

Blueprint owns page-level math assets and prelude injection for Blueprint math
surfaces.
