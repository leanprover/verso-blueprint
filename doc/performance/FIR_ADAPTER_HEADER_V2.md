# FIR adapter header v2: package-only acceptance

2026-09-16. Initially qualified for the provisional local `none`-component
experiment; subsequently adopted in the separate FIR demo (see below).
Main lacks the prototype stack, so
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

## Fresh matched VIR / FIR v2 comparison

Two fresh browser sessions use the same frozen factory, captured full-FLT
before/after inputs, providers and options as above. Each session performs two
warmup updates/backend and four AB/BA rounds, without CPU sampling. This compares
FIR v2 against the frozen VIR `36d26bc2`, not newer VIR optimizations.

| Backend | Content median, eight updates | Range |
| --- | ---: | ---: |
| VIR | 1.309 s | 1.022–1.486 s |
| FIR header v2 | 0.836 s | 0.707–1.230 s |

Median paired reduction is **29.6%**; FIR is faster in every pair (8.8–46.4%).
The ratio of independent pooled medians gives 36.1%; the paired statistic above
preserves update and run-order correspondence. Batch medians are VIR/FIR
1.341/0.836 s and 1.285/0.859 s. Absolute FIR times differ from the preceding
baseline/candidate experiment: only within-run paired comparisons support the
claims here.

Every round passes exact DOM equality and retained article checks. The boundary
remains decoded Document and prepared identities to returned React elements;
it excludes decoding, identity preparation and React reconciliation/commit.
The outer callback records combined document-session work, not independent
decode and identity phases. No total preview speedup or fine phase attribution
is inferred. Neither the live FIR package nor VIR source/SDK pins are changed.

Raw results and complete command/input/artifact identities are retained in
`_out/browser-pr188/vir-fir-v2-timing-20260916-{01,02}/`. Reproduce using the
unsampled timing command above with `VBP_COMPONENT_ADAPTER` omitted, selecting
the copied v2 package and its parity acceptance directory.

## Demo adoption and remaining alignment

The separate `.lake/build/fir-json-demo.js` now bundles the verified v2 package
(2,977,956 bytes). The original fast VIR bundle, frozen baseline package,
producer sources, Lean toolchain and SDK pins remain unchanged. The dedicated
FLT demo currently selects VIR on disk; its editor-owned registration is not
silently rewritten. The FIR live gate can select FIR explicitly in memory using
`VBP_LATENCY_FIR_REGISTRATION=1`, recording the effective source and checking the
original source hash afterward.
`fir-v2-adopted-live-20260916-02/result.json` passes the actual full-FLT
ProofWidgets/LSP shell: one factory/package, three accepted Strings, one RPC per
edit, retained DOM/controls and real server focus, zero warnings. Disk source is
unchanged; no live timing claim is made. The preceding attempt is excluded because
the on-disk demo selected VIR rather than the requested FIR widget.

The shared Lean `EncodedDocumentProps` schema declares the unchanged document
String plus requested/received/notified native Number-or-undefined fields.
`createEncodedDocumentRpcComponent` owns the common RPC adaptation. No decoded
document, Lean reference, extra document JSON conversion, or second shell crosses
runtimes. The factory has explicit optional math and clock inputs. Document
decoding and timestamp observation have separate native React memo dependencies.

`native-timing-props-20260916-04.json` records shared Chromium StrictMode checks:
timing-only updates refresh the coherent bar, preserve DOM/options, and skip
decoding; unchanged props and scale-only updates skip content construction;
absent timestamps remain unavailable. The timing bar calls the received-to-
decoded interval "Reply → decoded / scheduling": it is not a pure decoder timer.
Targeted batch build passes (1049 jobs); this is not clean full-project CI.

The existing FIR Wasm still contains the old clock-free `none` factory. The
new shared factory is therefore preparation, not a live FIR math/timing claim.
Request `VBP-FIR-20260916-CONFIGURED-FACTORY-001` asks the producer for a portable
isolated successor compiling the actual
`VersoBlueprintVirTests.NativeSession.createBrowserEncodedDocumentComponent`
entry with a native math argument and the explicitly demo-only browser clock.
Complete frozen source identity: `d356ba46715f26c2f427d40d82f46b85e05c0eee9ac7436604dfae9bbdcbdcb6`;
archive SHA256: `cc5d3b28d9459909f6878019f4410246db7030f45e74bc7ccef0b4475336786e`.
It preserves all dependency working bytes, including the dirty parser; private
setup regeneration must record new inventory/artifact/plugin identities.

Next acceptance uses the same configured entry, document inputs, native math
component, clock and providers for both backends. It must qualify real KaTeX,
full timing accounting, recovery and retained controls before adoption. The
experimental fast-decoder VIR demo remains separately labeled; its numbers
must not be compared with the plain Lean decoder in these frozen controls.
