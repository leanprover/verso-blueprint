# Widget research harness

Maintainer tooling for experimental Lean-backed React widgets. Run commands from
the linked VBP worktree containing the matched SDK and dependencies. This is not
an end-user Blueprint generation interface.

See the [evidence index](../../doc/performance/README.md) for current conclusions
and exact artifact/source authority. Do not infer the benchmarked renderer from
the current Lean source file when loading a retained IR module set.

## Small controls

```sh
node --test tests/vir_preview/component_phase_probe_test.mjs
VBP_FIR_PROFILE_CAPTURE=/absolute/path/to/retained/fir-profile \
  node --test tests/vir_preview/fir_symbol_acceptance_test.mjs
```

The symbol test requires an existing FIR CPU capture. Without that environment
variable it explicitly skips; a skipped test is not symbol qualification. It
adds synthetic test-only names in temporary fixtures, never to producer packages.
It checks executable matching, mismatch/missing-name rejection, partial resolution
and refusal to overwrite output. Synthetic names are not FIR attribution.

## Captured-response replay

`decode_browser_smoke.mjs CAPTURE_DIR OUTPUT_DIR` reuses the existing Chromium
session driver. CAPTURE_DIR contains response.json and its capture result.json;
OUTPUT_DIR must be fresh. The driver verifies input/SDK identities and retains
raw results, source/module hashes, generated driver and complete output DOM.

For a frozen checked-codec renderer comparison:

```sh
env VBP_REPLAY_RENDER=1 VBP_REPLAY_UPDATES=4 \
  VBP_REPLAY_CHECKPOINT_COMPARISON=1 \
  VBP_REPLAY_PACKAGE_SET=/absolute/path/to/frozen/DecodeProbe.irpkg-set.json \
  node tests/vir_preview/decode_browser_smoke.mjs CAPTURE_DIR OUTPUT_DIR
```

`VBP_REPLAY_CHECKPOINT_COMPARISON=1` permits deliberate checkpoint comparison;
it is not evidence that sources are equivalent. Validate the declared frozen
source/renderer and resolved package/SDK identities separately.

Add `VBP_REPLAY_FIR_PACKAGE=/absolute/path/to/immutable/package` for FIR's checked
codec. The driver accepts the explicitly reviewed package checksums, copies it
and uses its session-owned decoded token and default view. A new package requires
explicit identity review and consumer qualification, not bypassing the checks.

Keep `VBP_REPLAY_DIRECT_TYPED`, `VBP_REPLAY_TYPED_PACKAGE`,
`VBP_REPLAY_STRING_INTERN`, `VBP_REPLAY_UTF8_SCRATCH` and
`VBP_REPLAY_POINTER_SCRATCH` unset for the matched checked-codec comparison.
Direct typed experiments use their own probe/layout package and are VIR-only.
Run VIR/FIR sequentially in AB/BA order; do not overlap builds or sampling with
headline measurements. Initial mount/control change and two warmups are excluded.

Four coarse browser-clock timestamps bracket parse, codec and decoded input to
MutationObserver acceptance after React DOM commit. RPC/LSP, server work,
transport, loading/instantiation, initial mount, paint and passive-effect waiting
are excluded. Output/retention assertions are outside timing. Redirect stdout to
a capture-specific log: the retained complete DOM makes output large.

## Separate sampled attribution

Add `VBP_REPLAY_PROFILE=1` only for a separate diagnostic run. The harness retains
the requested 1 ms CDP profile, source map and clock calibration. FIR also brackets
its retained factory callbacks and checks that content constructs once per update.
Those durations are not headline timing and do not replace whole-render bounds.

```sh
node tests/vir_preview/summarize_replay_profile.mjs PROFILE_DIR --out=FRESH_DIR
```

The summarizer resolves VIR names from its matched SDK, verifies calibration and
preserves explicit unknowns. `--out` writes derived reports/folded stacks separately
from the capture; omitting it retains the older in-capture output behavior.

For a reviewed named FIR artifact:

```sh
node tests/vir_preview/summarize_replay_profile.mjs FIR_PROFILE_DIR \
  --fir-named-wasm=/absolute/path/to/verified/named.wasm --out=FRESH_DIR
```

Every non-custom Wasm section must equal the captured FIR module. Both hashes and
frame-resolution counts are recorded. A code-different diagnostic module needs
its own capture; do not apply its names by ordinal to an old profile. Preserve
stripped frames until genuine matching provenance exists. Do not use declaration
or closure-dispatch order as a map, or borrow VIR indices for FIR.

The optional positional FLAMEGRAPH_PL argument generates aggregated flamegraphs
from the recorded folded stacks; these are not chronological timelines.

### FIR host-import census

Set `VBP_REPLAY_HOST_IMPORT_CENSUS=1` only with the accepted direct FIR package.
It patches the copied diagnostic `host-prototype.mjs`, never the producer package
or live widget. Fixed numeric counters record physical/logical import calls plus
allocation, resource and UTF-8 activity inside the existing component callback
brackets. There are no per-call clocks or logs.

The census and CPU sampler are mutually exclusive. Treat census timings as
instrumented: compare them with an adjacent census-off control using the exact
same input and package. Call and byte totals explain sampled attribution; they
are not elapsed-time estimates. Exact DOM/text, retention and warning checks
remain mandatory.

Add `VBP_REPLAY_HOST_STRING_CENSUS=1` for a separate, more invasive reuse pass.
It observes each string only after the normal UTF-8 decode and records the
decoder's existing byte length; it neither re-encodes strings nor times calls.
The report retains aggregate reuse plus only the top repeated values. Do not use
its elapsed timings as either headline data or host-counter overhead estimates.

## Boundaries

The generic renderer lives in `packages/verso-react`; Blueprint/RPC/widget policy
stays in VBP. This directory stages consumer experiments, not generic provider
infrastructure. Reuse package-owned physical adapters and the existing browser
driver. Unmount React before runtime disposal. Preserve producer outputs and live
demo pins unless adoption is separately requested and qualified.
