# Performance research

These are experimental evidence reports, not published package benchmarks.
Start with the current comparison below; older captures may use different
renderers, codecs, runtime policies or timing boundaries.

The [widget benchmarking guide](../../tests/vir_preview/README.md#choose-the-question-before-comparing-timings)
separates shared rendering-algorithm changes, VIR/FIR execution costs, and input
construction. Each comparison changes one declared axis while retaining the
same input, options and output checks.

## Current widget evidence

| Question | Authoritative report | Scope |
| --- | --- | --- |
| How do VIR and FIR compare on matching input/source/codec? | [Checked-codec comparison](VIR_FIR_CHECKED_COMPARISON_20260917.md) | Unsampled AB/BA, frozen pre-style renderer, default view |
| Where does FIR spend time? | [Frozen FIR profile](FIR_FROZEN_REPLAY_20260917.md) | Separate sampled session/content callbacks; internal symbols pending |
| What changed in the renderer? | [Component-owned styles](STYLE_REUSE_20260917.md) | VIR-only source candidate; small provisional gain, not yet the FIR comparator |
| What is the faster decoding prototype? | [Direct typed decoder](DIRECT_TYPED_DECODER_20260917.md) | VIR-specific constructor path, not a matched FIR result |
| Which upstream base and SDK are used? | [VIR refresh](VIR_UPSTREAM_REFRESH_20260917.md) | Exact source/SDK identities and qualification |
| Where is the refreshed live matched demo? | [Matched 4.34 demo](MATCHED_DEMO_V434.md) | New interpreter/SDK, frozen paired renderer; startup VIR/FIR toggle |
| Can FIR string construction avoid per-string temporary arrays? | [FIR UTF-8 pool](FIR_UTF8_POOL_20260922.md) | Consumer prototype; retained full-FLT replay and separate sampled attribution |
| Which browser renderer change should be tested next? | [Retained section rendering](RETAINED_RENDER_TARGET_20260923.md) | Accepted FIR package, current sampled cost, symbol limit and next experiment |

Do not compare an inner content callback with an entire render-to-DOM interval.
Do not compare FIR's checked Lean.Json/FromJson path with VIR's direct typed
constructor and call the difference backend overhead. Independent phase medians
are not additive. MutationObserver acceptance after DOM commit is not paint.

The checked comparison deliberately excludes later style reuse and direct-codec
optimizations. Matching output qualifies the tested default-view slice, not every
math/extension/options branch. Session age is matched; retention policies differ.
Each report records its own input/source/package hashes and raw capture names.

## Consolidation and next steps

1. Test retained section rendering on the frozen edit, with the shared Lean
   renderer and separate before/after pairs for VIR and FIR. The current FIR
   content callback is the largest measured browser interval.
2. Use final function-name provenance from the next official FIR 4.34
   package. The accepted cached-prelude release has no recoverable internal
   map; the historical named projection package has different executable
   sections and cannot name the current capture. Keep sampled host attribution
   and diagnostics-off timing separate while those names are unavailable.
3. Qualify future same-source backend and codec packages before promoting them
   to a shared comparator. Do not silently advance the baseline.

No live pin move, package publication, new transport layer or competing producer
campaign is part of this consolidation. Existing raw evidence and frozen source
archives remain intact.

## Earlier investigations

- [FIR adapter header v2](FIR_ADAPTER_HEADER_V2.md): paired timings and sampled
  profiles from September 16. JavaScript adapter frames are resolved; FIR internal
  Wasm symbols are stripped. These are historical artifacts, not the current
  checked-codec comparison.
- [FIR session retention](FIR_SESSION_RETENTION.md) and
  [shared widget package](SHARED_WIDGET_PACKAGE_20260917.md): lifecycle and initial
  package/codec experiments; later reports above supersede their next-step notes.
- [Rendering focus](RENDER_FOCUS_20260917.md),
  [checked codec](CHECKED_JSON_CODEC_20260917.md),
  [inspection batching](CHECKED_JSON_BATCHING_20260917.md), and
  [scoped string interning](SCOPED_STRING_INTERN_20260917.md): mechanism experiments
  with their own baselines; their gains must not be combined into a speedup curve.
- [FLT root profile](FLT_ROOT_QUICK_PROFILE.md) and
  [FLT build profile](FLT_FUJISAKI_BUILD_PROFILE.md): server/build-side evidence,
  separate from browser replay timing.

## Reproduction and ownership

[Widget harness guide](../../tests/vir_preview/README.md) documents controls,
replay modes and offline symbolication. Commands reuse the existing Chromium
harness; no new browser/LSP infrastructure is introduced.

Raw local captures live under the repository root's `_out/<worktree>/`; frozen
source archives live under `.worktrees/_meta/widget-source-snapshots/`. Inspect the
report's exact capture and identity.json rather than substituting the current
`.lake/build` module set. Fresh captures/output directories must not overwrite
retained evidence. FIR owns producer generation; VBP owns consumer acceptance,
shared inputs and the single differential campaign.
