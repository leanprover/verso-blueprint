# UPC-0012 Lake Update Package Overrides

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-lake
Last reviewed: 2026-07-09
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: harness dependency rewrite before `lake update`

## Summary

Lake should honor package overrides during the initial `lake update` bootstrap
path.

## Impact

Blueprint's reference-project harness validates fresh external projects. When a
fresh checkout has no manifest yet, `.lake/package-overrides.json` and
`lake --packages ... update` do not currently prevent an initial upstream clone
in the confirmed local scenario. The harness therefore rewrites cloned
`lakefile.lean` dependencies before running `lake update`.

## Roadmap Decision

Track as an upstream Lake behavior request. Re-check the behavior against the
active supported Lean release before opening upstream work.

## Reproduction Status

Originally confirmed locally on Lean `v4.29.0`. This needs a fresh repro on the
current supported release before upstreaming.

## Preliminary Analysis

The observed limitation was that `loadWorkspace` passed `packageOverrides` only
to `materializeDeps`, while `updateManifest` called `updateAndMaterialize`
without threading overrides.

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
