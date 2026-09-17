# Performance research

These are experimental evidence reports, not published package benchmarks.
Start with the current comparison below; older captures may use different
renderers, codecs, runtime policies or timing boundaries.

## Current widget evidence

| Question | Authoritative report | Scope |
| --- | --- | --- |
| How do VIR and FIR compare on matching input/source/codec? | [Checked-codec comparison](VIR_FIR_CHECKED_COMPARISON_20260917.md) | Unsampled AB/BA, frozen pre-style renderer, default view |
| Where does FIR spend time? | [Frozen FIR profile](FIR_FROZEN_REPLAY_20260917.md) | Separate sampled session/content callbacks; internal symbols pending |
| What changed in the renderer? | [Component-owned styles](STYLE_REUSE_20260917.md) | VIR-only source candidate; small provisional gain, not yet the FIR comparator |
| What is the faster decoding prototype? | [Direct typed decoder](DIRECT_TYPED_DECODER_20260917.md) | VIR-specific constructor path, not a matched FIR result |
| Which upstream base and SDK are used? | [VIR refresh](VIR_UPSTREAM_REFRESH_20260917.md) | Exact source/SDK identities and qualification |
| Where is the refreshed live matched demo? | [Matched 4.34 demo](MATCHED_DEMO_V434.md) | New interpreter/SDK, frozen paired renderer; startup VIR/FIR toggle |

Do not compare an inner content callback with an entire render-to-DOM interval.
Do not compare FIR's checked Lean.Json/FromJson path with VIR's direct typed
constructor and call the difference backend overhead. Independent phase medians
are not additive. MutationObserver acceptance after DOM commit is not paint.

The checked comparison deliberately excludes later style reuse and direct-codec
optimizations. Matching output qualifies the tested default-view slice, not every
math/extension/options branch. Session age is matched; retention policies differ.
Each report records its own input/source/package hashes and raw capture names.

## Consolidation and next steps

1. Qualify and profile the FIR diagnostic artifact. The current release binary has no
   surviving internal map; this does not mean FIR cannot be profiled. The producer
   returned a symbol-bearing diagnostic in `W7-ROOT-20260917-017`, preserving
   the existing source closure and packages. Its final executable sections differ
   from release: names are **not valid for the saved release profile**. Root review
   and a fresh diagnostic consumer capture are pending. Apply names to saved
   captures only when all non-custom Wasm sections match.
2. Use named attribution to choose the next renderer/adapter change. Preserve
   unsampled headline runs separately from diagnostic captures.
3. Qualify a future same-source package before making style reuse or a different
   codec the shared VIR/FIR comparator. Do not silently advance the baseline.

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
