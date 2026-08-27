# UPC-0012 Lake Update Package Overrides

Status: candidate
Kind: upstream-api
Priority: medium
Origin: upstream-lake
Last reviewed: 2026-08-27
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: harness dependency rewrite before `lake update`
Related cards: none

## Summary

Recheck whether Lake honors package overrides during the initial `lake update`
bootstrap path, and upstream a fix if the v4.29.0 behavior still reproduces.

## Impact

Blueprint's reference-project harness validates fresh external projects. On
Lean v4.29.0, `.lake/package-overrides.json` and `lake --packages ... update`
did not prevent an initial upstream clone when no manifest existed. The harness
still rewrites cloned `lakefile.lean` dependencies before running `lake update`,
but the behavior has not been rechecked on a currently supported release.

## Roadmap Decision

Keep this as a candidate until the behavior is rechecked against the current
default-development release. If it still reproduces, promote the card to
`open`; otherwise resolve it and decide whether the harness rewrite can be
simplified safely.

## Reproduction Status

Originally confirmed locally on Lean `v4.29.0`. This needs a fresh repro on the
current supported release before upstreaming.

## Preliminary Analysis

On v4.29.0, `loadWorkspace` passed `packageOverrides` only to
`materializeDeps`, while `updateManifest` called `updateAndMaterialize` without
threading overrides. Current Lake sources must be rechecked before treating
that analysis as current.

## Scope Boundary

This card owns package overrides during initial dependency resolution. It does
not own the harness's broader reference-project checkout or pinning policy.

## Expected Behavior

`lake update` applies workspace and CLI package overrides during the initial
dependency-resolution and materialization path, including fresh projects with no
manifest yet.

## Evidence

- Local workaround: the reference-project harness rewrites cloned
  `lakefile.lean` dependencies before running `lake update`.
- Historical confirmation: Lean `v4.29.0`.

## Current Workaround

The harness rewrites cloned `lakefile.lean` dependencies before running
`lake update`.
