# UPC-0025 Supported Loaded-Module Source-Input Verification Query in Lean/Lake

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-lake
Last reviewed: 2026-11-27
Owner: none
Issue: none linked
PR: none linked
Upstream timing: as soon as possible
Removal target: compacted-region adjacency and `.trace` JSON parsing in `src/VersoBlueprint/ExternalModuleSource.lean`
Related cards: UPC-0020, UPC-0022, UPC-0023, UPC-0024

## Summary

Provide a supported Lean/Lake query that connects a loaded `Environment`
module (including both its `.olean` and `.olean.server` artifacts) to the
verified owning source file path and compiler-input digest.

## Impact

When multiple checkouts, worktrees, or cache-in-place artifacts share
`LEAN_PATH`, looking up a module name on the search path can resolve to a
different checkout's `.lean` file than the compiled artifact actually loaded
into `Environment`. To avoid binding declarations to stale or wrong-checkout
source files, `verso-blueprint` currently inspects `env.header.regions`
ordering for adjacent `.olean` and `.olean.server` compacted regions, locates
and parses Lake's internal `.trace` JSON files (`Module.name:`,
`Package.id?:`, `outputs.o`), and re-hashes files with `Lake.computeBinFileHash`
and `Lake.Hash.ofText`.

That logic depends directly on Lean's `env.header.regions` adjacency convention
and Lake's internal `.trace` schema, both of which are undocumented
implementation details that can break across toolchain upgrades.

## Roadmap Decision

Track upstream at the Lean/Lake boundary. Keep `ExternalModuleSource.lean` as a
contained local adapter until Lean/Lake exposes a supported loaded-artifact
source query.

## Reproduction Status

Confirmed against Lean/Lake `v4.35.0`:
- `src/VersoBlueprint/ExternalModuleSource.lean:32–95` implements
  `matchesArtifact`, `matchesArtifacts`, `ownerFromTrace?`, and `find?` by
  scanning `searchPathRef`, parsing `Lake.BuildMetadata`, checking
  `env.header.regions` adjacency for `.olean` and `.olean.server`, and
  comparing `Lake.Hash.ofText`.
- Tested across normal builds, cache-in-place builds, and restored builds in
  `tests/VersoBlueprintTests/BlueprintRealizationAdapter.lean` and
  `tests/test-realization-semantic-binding.py`.

## Preliminary Analysis

Lean already records the loaded compacted-region paths (`env.header.regions`)
and module package metadata (`env.getModulePackageByIdx?`), while Lake already
computes the source path, input text hash, and output artifact hashes in its
build trace. Exposing a supported query (either via Lake's trace/artifact API
keyed by loaded region paths, or via module-level source provenance metadata
stored alongside `.olean.server`) removes downstream reliance on `.trace` key
formatting and compacted-region adjacency.

## Scope Boundary

- Owns mapping a loaded module's compiled artifacts (`.olean` +
  `.olean.server`) to its verified owning source file and input digest.
- Does not own general cache-in-place external path restoration (`UPC-0020`),
  Blueprint realization assessment policy, or doc-comment span extraction
  (`UPC-0023`).

## Expected Behavior

Given a loaded `Environment` and `ModuleIdx`, a single supported Lean/Lake API
returns the owning source `FilePath` and verifiable input digest (matching both
the loaded public `.olean` and server `.olean.server` artifacts, in both
cache-in-place and restored modes), or `none` when provenance cannot be
established.

## Evidence

- `src/VersoBlueprint/ExternalModuleSource.lean:32–115`
- `src/VersoBlueprint/Realizations/NativeSource.lean` (`owningSource`)
- `tests/test-realization-semantic-binding.py`

## Current Workaround

`ExternalModuleSource.lean` scans `searchPathRef` for `.trace` files, parses
`Lake.BuildMetadata` inputs/outputs, checks `env.header.regions` adjacency for
`.olean` and `.olean.server`, and verifies `Lake.Hash.ofText`. Delete
`matchesArtifact`, `matchesArtifacts`, and `ownerFromTrace?` once Lean/Lake
provides a supported loaded-module source-input query.
