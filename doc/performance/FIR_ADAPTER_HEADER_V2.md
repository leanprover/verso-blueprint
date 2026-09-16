# FIR adapter header v2: package-only acceptance

2026-09-16. Qualified for the provisional local `none`-component experiment;
not adopted in source or the live demo. Main lacks the prototype stack, so
source landing remains parked under `ROOT-W7-20260916-026`.

The candidate caches DataView by memory.buffer identity and uses fresh scalar
header snapshots/direct eight-word writes. Wasm, complete frozen source/setup,
typed inventories, native provider, document bytes and generic VIR/React
provider identities are unchanged. Other runtime helpers are byte-identical.
No object layout, resource ownership, or GC policy change is tested here.

| Identity | Baseline | Candidate |
| --- | --- | --- |
| Package handoff | c560f6a4 | W7 15fae0eb, functional adapter 59ccf4f9 |
| BUILD SHA256 | `33b3ad90c23864fc17bc8a50624de3e68aa43256ce1a1b7a40d20dbe2bef72f8` | `1138101ee4bc83540af6fb84952143b65267f2a7a809a50b9b1f8db900583da4` |
| Adapter SHA256 | `789af23513e7758e6c5df419586386a15f5cfbea45e1a9da3a041b020b517dcc` | `65184bffa3cf1aaadbd50dbe3a2d43b3d2bc790414ed808b342a01acf0db1bfd` |

Shared Wasm SHA256:
`98504ee775e4f4c6c1028d1e497671240ae79480023c0c648f5bc40bc89c0aa6`.
Frozen source `2c1ef0f6`, setup `6bbd2b32`, Lean 4.34.0-rc2,
VIR `36d26bc2`, React 19.2.7. Candidate sums SHA256:
`5fc1acd26ee4f85615f93ef5f231b7fe1fd02261e31076d932686a66b73ec9d1`.
Producer package is copied into consumer `.deps/adapter-header-v2-20260916`;
all campaign inputs and packages are verified before execution.

## Correctness

`_out/browser-pr188/adapter-v2-parity-20260916-02/` records direct baseline/candidate
and VIR SSR equality for seven inputs: package fixtures, captured full-FLT
before/after Strings and existing Lean-generated rich fixtures. Malformed
recovery passes. Candidate/VIR Chromium DOM equality, eight updates/backend,
native controls, retained shell/article, three rich updates preserving open
details, informal/external markup, recovery, unmount/disposal and zero React
warnings pass. Paired timing replays additionally check fresh baseline/candidate
DOM equality and retained article after each update.

Root's 32 producer controls cover nested growth, scalar snapshots and post-growth
corruption. They are supplied producer evidence, not a new consumer rerun of that
test suite. Optional native math, general GC, main integration and the four known
4.34 audits remain outside this acceptance.

## Unsampled content timings

Production React, highlighting/debug/math off; one retained session per variant,
two full-FLT warmup updates per variant, then four AB/BA rounds in each of two
fresh browser sessions. Both variants share compiled Wasm bytes but instantiate
separate owned memories and provider state. No per-host-call timers. The content
callback receives decoded Document and prepared identity state; timing includes
renderer, host calls, props access and effect registration, **not** decoding,
identity preparation or React reconciliation/commit. Plain Lean Document.decode
in the outer callback is not the original live VIR checked decoder.

| FIR variant | Median, eight updates | Range |
| --- | ---: | ---: |
| Baseline | 2.539 s | 2.375–2.697 s |
| Header v2 | 1.554 s | 1.284–1.689 s |

Median paired reduction: **38.3%**; all eight pairs improve (34.4–48.3%).
Separate batch medians: 2.558→1.636 s and 2.440→1.431 s. Absolute times vary;
do not compare these with the earlier isolated VIR/FIR batch or infer an
edit-to-preview speedup. Raw observations and identities:
`adapter-v2-timing-20260916-{01,02}/` under the same `_out/browser-pr188` root.

## Separate sampled attribution

Fresh baseline/candidate Chromium profiles, 1ms sampling, two content windows
each; clock uncertainties 0.421/0.5145ms. Least-uncertain of five retained clock
observations selected before sampling, still requiring <5ms. The first candidate
attempt failed before recording; preserved separately, not included in results.
JS is source-mapped; VIR release/dev executable sections match. FIR internal
symbols are stripped. Shared V8 JS/Wasm trampolines do not establish module
ownership. Sampling disturbs runtime; profile durations are not timing results.

| Disjoint content self samples | Baseline | Header v2 |
| --- | ---: | ---: |
| FIR JS adapter | 46.2% | 20.6% |
| FIR Wasm | 45.1% | 69.3% |
| Host UTF-8 conversion | 4.3% | 5.5% |

Header named self samples drop 12.9→0.7%, view 5.4→1.9%; writeHeader is no longer
a leading named frame. Inlining prevents treating absent named frames as zero
work. Wasm's larger share is not a claim that unchanged Wasm became slower.
Resource boxing/allocation and host string conversion remain visible costs.
Evidence: `adapter-baseline-profile-20260916-01/` and
`adapter-v2-profile-20260916-02/`: raw/symbolicated CPU profiles, calibrated clocks,
source maps, folded stacks, Wasm symbol evidence and profile-summary.json.

## Reproduce without adoption

Use the existing frozen campaign and copied candidate; do not change live package
pins or rebuild/retarget producer sources. Fresh output directories are required.

```sh
VBP_COMPONENT_RICH=1 VBP_COMPONENT_FIR_PACKAGE=/path/to/copied-v2 \
node tests/vir_preview/component_campaign_smoke.mjs /path/to/frozen-campaign /path/to/parity

VBP_COMPONENT_MEASURE=1 VBP_COMPONENT_ADAPTER=1 \
VBP_COMPONENT_ACCEPTANCE=/path/to/parity VBP_COMPONENT_FIR_PACKAGE=/path/to/copied-v2 \
node tests/vir_preview/component_campaign_smoke.mjs /path/to/frozen-campaign /path/to/timings

VBP_COMPONENT_MEASURE=1 VBP_COMPONENT_PROFILE=1 \
VBP_COMPONENT_ACCEPTANCE=/path/to/parity VBP_COMPONENT_FIR_PACKAGE=/path/to/copied-v2 \
node tests/vir_preview/component_campaign_smoke.mjs /path/to/frozen-campaign /path/to/profile
node tests/vir_preview/summarize_replay_profile.mjs /path/to/profile --component
```

Decision: accept the immutable v2 package for this bounded consumer experiment;
correctness, paired content performance and expected profile movement agree.
Baseline artifacts, source/toolchain pins and live demo remain unchanged.
