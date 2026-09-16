# FIR fresh versus retained sessions

2026-09-17. Consumer diagnostic using the accepted header-v2 package; no decoder,
producer, live demo or pin changes. This is not another FIR/VIR speed comparison.

## Results

Two sequential Chromium runs with opposite execution orders, four paired edits
per run. Each input occurs in both first/second positions. Production React,
math/debug/highlighting and CPU sampling off. The timed boundary is the existing
decoded-document/prepared-identities-to-React-elements callback, excluding
decoding, identity preparation and React reconciliation/commit.

| FIR session | Median | Range | Samples |
| --- | ---: | ---: | ---: |
| Fresh, warmed | 1,120 ms | 977–1,337 ms | 8 |
| Retained | 1,235 ms | 1,012–1,412 ms | 8 |

The median **paired** retained-minus-fresh difference is 98 ms (+9.5%); five of
eight pairs are slower, with paired differences from -56 to +269 ms. Both run
medians point in the same direction, but this small, noisy cohort does not prove
that heap/resource growth causes the difference. Even the initial pair, with
matching resource counts/frontiers, differs. Do not compare these absolute
timings with earlier VIR/FIR runs as if they were one cohort.

Each complete update adds exactly 201,870 JS resource entries and advances the
native heap frontier by about 19.65 MiB. After two warmups and four measured edits,
the retained session has 1,211,221 entries and a 135.25 MiB frontier, versus
605,611 entries / 76.30 MiB after a fresh session's two warmups and measured edit.
These snapshots cover the complete update, not only the timed rendering phase.
The frontier is not a live-memory/RSS measurement, and entries are handles,
not counts of distinct React nodes. Retention until disposal is intentional in
this prototype; bounded long-lived resource reclamation remains unqualified.

Fresh sessions compile no new module: all use one shared compiled Wasm module,
and each is warmed with the target document then its opposite before measurement.
The retained session is initially warmed the same way, then alternates documents.
Opening, warmup, stats, output comparison and disposal are outside the timer.
No forced GC or per-host-call instrumentation is added. Browser-wide pressure,
engine warmup and the different identity histories remain possible confounders.

## Correctness and evidence

All measured updates construct exactly one successful content callback and retain
their document DOM node. Fresh and retained sessions deliberately have different
render-ID histories: retained identity survives prose edits. Output comparison
therefore removes only `data-verso-render-id` and the identity line of its render
tooltip, checking all remaining markup exactly. Unmount precedes disposal, and
the diagnostic verifies the disposed state.

Raw results and exact source/package/provider/input/harness identities:
`_out/browser-pr188/fir-session-age-20260917-{03,04}/`. The two preceding failed
attempts remain preserved and excluded: their raw-HTML comparison rejected the
expected history-dependent IDs. All 20 existing JS tests also pass.

Inputs are the frozen full-FLT before/after document strings. FIR BUILD SHA256:
`1138101ee4bc83540af6fb84952143b65267f2a7a809a50b9b1f8db900583da4`;
Wasm SHA256: `98504ee775e4f4c6c1028d1e497671240ae79480023c0c648f5bc40bc89c0aa6`.
Source `2c1ef0f6`, VIR `36d26bc2`, Lean `v4.34.0-rc2`.

Reproduce from the prepared research checkout, using a fresh output directory:

```sh
VBP_COMPONENT_MEASURE=1 VBP_COMPONENT_RETENTION=1 \
VBP_COMPONENT_FIR_PACKAGE="$PWD/.deps/adapter-header-v2-20260916" \
VBP_COMPONENT_ACCEPTANCE="/home/egallego/lean/verso-blueprint/_out/browser-pr188/adapter-v2-parity-20260916-02" \
node tests/vir_preview/component_campaign_smoke.mjs \
  "$PWD/.deps/component-campaign-20260916-01" /absolute/fresh/output
```

Repeat sequentially with `VBP_COMPONENT_RETENTION_REVERSE=1` and another output.
The snapshot stats already supplied by FIR are read outside timed callbacks.
An exact function-index symbol map was requested from FIR for the unchanged
accepted Wasm; no rebuild or interruption of the configured-factory repair was
requested. Until it arrives, the earlier sampled Wasm hotspot is not attributable
to a specific Lean declaration or allocator path.
