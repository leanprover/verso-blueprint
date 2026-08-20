# UPC-0020 Cache-in-Place External Consumer Compatibility

Status: candidate
Kind: bug
Priority: low
Origin: upstream-lake
Last reviewed: 2026-08-20
Owner: none
Issue: https://github.com/leanprover/lean4/issues/14435
PR: none linked
Upstream timing: none
Removal target: none; the local canonical-output fallback was removed after maintained-release validation
Related cards: UPC-0019

## Summary

Lake's artifact cache intentionally supports cache-in-place outputs when
`LAKE_RESTORE_ARTIFACTS=false`. Lake-backed consumers receive the cached
artifact path, while filesystem consumers that independently expect every
output under `.lake/build` may require restoration or additional integration.

## Impact

No failure remains in Blueprint's supported generation paths or its tested
Lean Beam integration. `lake lean`, `lake exe vbp build`, and a held Beam
language-server session all consumed cached modules whose canonical `.olean`
files were absent. Lean issue #14435 records a related editor failure after a
clean artifact-cache build, so other editor and direct-filesystem consumers
remain worth checking upstream.

## Roadmap Decision

Ship Blueprint generation with Lake's default cache-in-place behavior and
remove the canonical-output fallback. Do not force
`LAKE_RESTORE_ARTIFACTS=true` for supported VBP or Lean Beam commands. Keep this
card as a candidate for the narrower editor or direct-filesystem-consumer
boundary and use restoration as the documented opt-in when such a consumer
requires it.

## Reproduction Status

Validated on Lean v4.32 and v4.33 with `VersoBlueprint.Commands.Graph`.
Starting from a dedicated warm artifact cache, remove `Graph.olean` and
`Graph.olean.hash` while leaving `Graph.trace`, then build and generate with
restoration disabled.

- `lake build PreviewRuntimeShowcase` completed while the canonical `.olean`
  remained absent.
- The raw `lake lean ... --run ...` generator completed and passed `vbp check`
  with 90 manifest and 90 HTML-cache entries; the `.olean` remained absent.
- `lake exe vbp build` also completed and passed the same 90/90 check while the
  `.olean` remained absent.
- With restoration enabled, Lake restored the five embedded-asset owner modules
  used by this fixture. The unused slides owner remained absent, as expected.
- A fresh project-template package and consumer, with private `.lake`
  directories, built in 162.78 seconds cold and 7.30 seconds warm. The warm VBP
  package had 87 traces and no canonical VBP `.olean` files; its generated site
  matched the cold site apart from the compiled timestamp and passed the 20/20
  `vbp check`.
- The real FLT v4.33 reference target (`v4.33.0-rc1`) built 4,394 Lake jobs in
  231.33 seconds cold and 31.90 seconds warm. The warm package and project trees
  retained cache traces without canonical `.olean` files, and the generated
  site passed the 586/586 `vbp check`.
- Lean Beam 0.2.0-beta opened and synchronized
  `VersoBlueprint.Commands.Graph` against the warm cache, reported zero
  diagnostics and `saveReady: true`, and returned semantic hover information
  from `VersoBlueprint.Graph`. The target and imported VBP modules still had
  traces but no canonical `.olean` files after the session.
- On the v4.32 backport, a cold `lake test`, a build-tree-free warm replay, a
  fresh downstream project-template generation, and the same Beam workflow all
  passed with artifact caching enabled and restoration disabled. Changing only
  `graph.css` rebuilt the expected 24-module closure and embedded the marker;
  restoring the CSS selected the byte-identical original synthetic trace and
  removed the canonical `Graph.olean` again.

## Preliminary Analysis

Lean's package configuration documents that restore-all defaults to `false`
and exists for external consumers that expect build-directory outputs. Module
cache reuse restores only the artifacts Lake requires in place, such as the
`.ilean`, and propagates other cache paths through Lake jobs. This behavior is
independent of whether an external `include_str` input participates in the
trace; UPC-0019 owns that dependency question.

Lean issue #14435 reports a user-visible `missing data file` failure after a
clean artifact-cache rebuild on v4.34 nightly and v4.33.0-rc1. Beam's held
language-server path does not reproduce it on v4.32 or final v4.33, so the
remaining question is narrower: which editor/server entry paths bypass Lake's
resolved artifact locations, and whether those paths should request
restoration automatically.

## Scope Boundary

This card owns compatibility between cache-in-place artifacts and consumers
outside Lake's job graph. It does not own external-input declaration or
module-level dependency granularity, which remains UPC-0019, and it does not own
remote artifact transport policy.

## Expected Behavior

Lake-backed tools should consume the artifact paths returned by Lake without
requiring canonical copies. External consumers that require `.lake/build`
paths should either opt into `LAKE_RESTORE_ARTIFACTS=true` or have an integrated
entry path that requests the necessary restoration.

## Evidence

- Existing Lean issue: https://github.com/leanprover/lean4/issues/14435
- Local v4.32 and v4.33 target: `VersoBlueprint.Commands.Graph`
- Preserved trace: `.lake/build/lib/lean/VersoBlueprint/Commands/Graph.trace`
- Removed outputs: `Graph.olean` and `Graph.olean.hash`
- Consumers: standalone `lake lean` generation and public `lake exe vbp build`
- Observed result: both consumers exited successfully while canonical
  `Graph.olean` remained absent
- Generated-data validation: both sites passed `vbp check` with 90 manifest and
  90 HTML-cache entries
- Restoration control: `LAKE_RESTORE_ARTIFACTS=true` restored the cache-backed
  owner outputs required by the fixture
- Isolated downstream benchmark: project-template `vbp build`, 162.78 seconds
  cold versus 7.30 seconds warm (22.3x); 20/20 `vbp check`
- Real v4.33 integration: FLT's 4,394-job build, 231.33 seconds cold versus
  31.90 seconds warm (7.25x); 586/586 `vbp check`
- Beam integration: `update`, `sync`, and `hover` succeeded on final v4.33 with
  restoration disabled and canonical dependency outputs absent
- v4.32 backport: cold and cache-in-place `lake test`, fresh project-template
  generation, Beam, and asset-change/restore selection all succeeded without a
  release-specific cache disable

## Current Workaround

None for supported VBP generation. Set `LAKE_RESTORE_ARTIFACTS=true` only when
using an external tool that requires canonical build-directory artifacts.
