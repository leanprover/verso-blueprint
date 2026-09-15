# Browser checkpoint: native React props, 2026-09-15

The preview now consumes VIR `6e91bed8` on Lean **4.34.0-rc2**, including the
native props/JSX follow-up at `3b2cfd2f`. The earlier `6fb749af` checkpoint was
superseded before adoption. The isolated VBP worktree is `browser-pr187`, based
on `c4430bfe`; the working FLT demo and its dependency pins are unchanged.

The integration and browser correctness checks pass. Performance is promising
but **does not yet establish a reliable speedup from the VIR update alone**.
The checked JSON bridge remains the much clearer improvement and is still an
experimental fixture, not the production RPC decoder.

## Measured boundary

Replay the captured response for FLT's **First Reductions Of The Problem**
chapter, not the whole FLT project. Each update changes one prose marker and
the response version. The real preview component stays mounted; debug and
highlighting are off, and follow-cursor is disabled after the initial mount.

Time starts before decoding an already available response and ends at the
MutationObserver following React's DOM commit. This includes decoding,
component execution, reconciliation, DOM updates, and intervening scheduling.
It excludes LSP/RPC, server elaboration, runtime/package startup, paint, and the
explicit passive-effect settling wait between observations. No `flushSync` is
used for timed updates. Only three coarse timestamps are taken per update;
there is no profiler or per-host-call instrumentation in this campaign.

Four independent browser/runtime sessions ran **old/new/new/old**, with no
concurrent task-owned builds. Each session used two warmup pairs and sixteen
measured pairs, reversing string/checked-JSON order each pair. Thus each row
below pools **32 observations from two sessions**. This is a local screening
experiment; background machine load was not controlled.
The machine used a Ryzen AI 9 HX 370, Linux 7.2.5, Chrome 153.0.8010.36,
Node 24.21.0 and production React 19.2.7 for the measured browser bundle.

| VIR checkpoint / decoder | Decode | Render to DOM | Response to DOM |
| --- | ---: | ---: | ---: |
| Old `9fafe9cf`, Lean string parser | 207.9 ms | 250.6 ms | 474.1 ms |
| New `6e91bed8`, Lean string parser | 211.3 ms | 239.0 ms | 451.7 ms |
| Old, experimental checked JSON bridge | 35.5 ms | 272.1 ms | 310.3 ms |
| New, experimental checked JSON bridge | 34.0 ms | 246.1 ms | 288.7 ms |

Values are independently computed medians, so phase medians need not sum to
the total median. Session-level medians show the uncertainty hidden by pooling:

| Run order | String response to DOM | Checked JSON response to DOM |
| --- | ---: | ---: |
| Old 1 | 509.7 ms | 324.8 ms |
| New 1 | 442.6 ms | 282.8 ms |
| New 2 | 462.8 ms | 289.2 ms |
| Old 2 | 438.0 ms | 270.0 ms |

The final old session was faster than either new session. Therefore the pooled
4.7%/7.0% reductions are observations, not a demonstrated VIR-only improvement.
In contrast, adjacent paired comparisons show median response-to-DOM reductions
of **37.5% on old VIR and 37.4% on new VIR** from using the checked JSON path.
These are median paired percentages, not ratios of pooled medians.

The remaining browser work is substantial: roughly 240–250 ms from decoded
preview to committed DOM on the new checkpoint. A browser profile of that
interval is the next useful investigation; these timers do not attribute it
to a particular renderer helper or React internals.

## What changed

- Both the independent Manual renderer and the Blueprint adapter now build
  native props/styles and JSX elements. Retired `Props.Entry` and tag builders
  are not recreated in VBP.
- Stateful components use `FunctionComponent (Props.WithData T)`, with explicit
  Lean handles in `data`. Component identity, state, hook dependencies and
  rendering policy are retained.
- RPC imports move from `Vir.Infoview.Surface` to `Vir.Infoview.Client`. The
  accepted child element stays memoized during pending requests; the old control
  already contains that optimization. Production RPC still uses `Preview.decode`.
- A diagnostic export renders decoded values through the actual component.
  The same JavaScript replay driver runs against either matched source/SDK pair;
  it reuses the existing VIR Chromium harness rather than adding an LSP/CDP stack.

The checked bridge is the previously tested `Lean.Vir.JsonValue` source from
`5953a7aef6fe9ec83481e313fb045fc27f7a1a9e`, relocated only for diagnostic imports.
It uses `JSON.parse`, checked conversion to `Lean.Json`, then existing
`FromJson Preview`. The source is checked against its safe-integer contract
before timing. The diagnostic browser bundle adds the missing brand query to
the SDK's actual Lean-handle WeakMap module **in memory**, not to producer source
or installed SDK files. This is not a claim that the bridge is shipped by the
new VIR checkpoint. Full JSON equality is checked before rendering.

## Validation and evidence

Current evidence is under repository-root `_out/browser-pr187/`:

- `renderer/renderer-acceptance.json`: generic Manual output, keys, Blueprint
  math metadata, informal content, external markup and malformed fallbacks.
- `session-final.json`: Strict Mode, retained controls, follow-cursor, debug-only
  timing and scale geometry, status transitions and disposal, without warnings.
- `string-rpc.json`: real-server String RPC, cancellation, stale/malformed
  reply suppression, edit notifications, retained controls and subscription
  cleanup, without React warnings. This is functional acceptance, not a latency run.
- `widget.json`: registered embedded shell, real RPC, follow-cursor, retained
  controls and unsubscribe; eight preview requests reuse one client package,
  without React warnings. The test editor forwards edits after diagnostics;
  it is not VS Code latency evidence. Its test seam now forwards upstream's
  `DocumentPosition` export, which the new shell imports.
- `decode-contract/result.json`: full JSON/Preview equality, valid scalar and
  recursive JSON cases, rejected unsafe numeric sources and invalid JS values,
  including branded Lean handles. Its decoder-only samples are not in the table.
- `final-old-1`, `final-new-1`, `final-new-2`, `final-old-2`: final measured cohort.
  Each contains `result.json`, `identity.json`, the response and fixture sources.
  Identity records include exact package-member, SDK, WASM, driver and input hashes.
  `source.patch` retains the tracked VBP changes against `c4430bfe`; the new
  diagnostic source files are copied into each final cohort directory.

All four final runs retain the same checkbox and an unchanged document node,
commit every requested version, and render 356 elements. The normalized document
DOM hash, including tags, attributes and inline styles, is identical:
`4d079cdcb7aace634a0fe78a1c130563a0f71acbf79ca84b7b9afefdac9c298d`.
Only attribute order and the edited version/prose marker are normalized.
The response is 221,382 UTF-8 bytes, SHA-256
`f0e70f669518c96fb8211678ad83dd0765396b5e3b3ec513702faad55cfc47be`.

Earlier `replay-*` runs are screening/debugging evidence, **not pooled into this
table**. An initial text comparison accidentally included versioned CSS text;
it failed and was corrected to compare the document. Subsequent static review
caught a flattened fallback style and overwritten Blueprint math class. The
final cohort follows those fixes and adds the stronger DOM comparison.

Lean Beam was used for local checkpoints and then stopped. The renderer and
preview checkpoint directories were moved to `beam-checkpoints/`, and a
cache-disabled batch build regenerated the affected modules and six runtime
fixture packages successfully (1055-job plan; not 1055 newly compiled jobs).
The failed earlier batch log is retained separately. No shared cache was deleted.

The new source/SDK identity and installation recipe are in
[NATIVE_PREVIEW_SESSION.md](NATIVE_PREVIEW_SESSION.md#current-isolated-setup).
The old control remains in `native-preview-vir-refresh`; only its diagnostic
`DecodeProbe.lean` gained the rendering exports. Its production code and pins
were not changed. No live FLT/VS Code latency claim or publication is made here.

## Reproduce

Build the probe in each selected worktree using its matching toolchain and SDK:

```sh
LAKE_RESTORE_ARTIFACTS=true scripts/lean-low-priority lake build \
  +VersoBlueprintVirTests.NativeSession.DecodeProbe:vir
```

From `browser-pr187`, use the same driver for both roots, selecting a fresh
output directory each time:

```sh
VBP_REPLAY_ROOT=/absolute/path/to/selected-worktree \
VBP_REPLAY_RENDER=1 VBP_REPLAY_CHECKPOINT_COMPARISON=1 \
scripts/lean-low-priority node tests/vir_preview/decode_browser_smoke.mjs \
  /absolute/path/to/verso-blueprint/_out/native-preview-vir-refresh/flt/decode-input \
  /absolute/path/to/verso-blueprint/_out/browser-pr187/fresh-run
```

The comparison flag permits a different checkpoint from the capture producer;
it still requires payload integrity, identical Lean toolchain, and an SDK matching
the selected worktree's exact VIR pin. It records both identities. The original
strict same-checkpoint decoder mode remains available without that flag.

## Conversion audit and browser profile

Follow-up: inspect avoidable representation changes, then sample the existing
renderer. **No production Lean code or dependency pins changed in this follow-up.**

### Conversion audit

| Path | Finding |
| --- | --- |
| `LeanRef.toJSL` / `fromJSL`, `Props.WithData` | Retained Lean handles and native object field access, not document serialization. There is bookkeeping, but no recursive document copy at these boundaries. |
| `Js.erase`, component/props shape casts | Runtime identity-preserving casts. They are not conversions to optimize away. |
| Native element props/styles | Already JS objects. They do not go through JSON or the retired property-list conversion. |
| `children.map pure` followed by JSX spread | Builds an array of actions for already-built nodes, then JSX executes each action while pushing into a native array. A direct built-node path can avoid this intermediate representation. It is a candidate, not a measured saving. |
| `Node.text`, `ElementType.tag` | Their JS host implementations are identities, but they still cross the VIR host boundary. Necessary string encoding is separate from those redundant identity calls; removal belongs in a supported upstream API/compiler path. |
| `blockIdentityHints` / `partIdentityHints` | Serialize block content/title into JSON strings for content-based React identity, even with highlighting off. This is real re-encoding, but it serves insertion/reorder stability; dropping it or substituting positional keys would change behavior. |
| Debug dependency and control values | Small Nat→String→JS conversions and eager initial-state handles recur. Worth simplifying where appropriate, but not established hotspots. |

The audit used the actual matched SDK implementations of the host boundary,
React hosts, Lean-reference intrinsics, and the JSX expansion, not just names
that look like conversions. In particular, generic host dispatch distinguishes
explicit conversions from native JS resource passing.

### Sampled evidence

Capture: `_out/browser-pr187/conversion-profile-1/`. The same 16 paired FLT
updates run after warmup with Chrome CPU sampling at 1000 µs. Sampling starts
only after warmup and stops before final DOM validation. The existing three
timestamps partition decoding and decoded-preview→DOM; a CDP/performance clock
calibration has ±0.557 ms uncertainty. These are diagnostic measurements, not
new headline benchmark timings.

For the **checked-JSON path's render interval**, 3,839 overlapping samples cover
4,035.5 ms across 16 updates. Disjoint leaf-time categories are:

| Category | Share of render-window sampled time |
| --- | ---: |
| Interpreter dispatch / expression evaluation | 43.8% |
| Symbol, constant and name lookup | 15.7% |
| Allocation, reference counting and vector storage | 10.8% |
| Other WASM runtime work | 12.5% |
| JavaScript / browser, including GC and scheduling | 17.1% |

The string-decoder path has the same general render profile. Separately, the
generic host-call boundary (`callObjectsImpl`, including its children) occupies
14.3% of the checked-path render window. This overlaps the table and is **not**
all string conversion. Explicit `liftObjectValue` and `makeObjectValue` subtrees
occupy 1.6% and 0.8%; they are nested attribution, not additive estimates.
`commitRoot` occupies 0.29% (~0.73 ms/update sampled), whereas 96.3% is beneath
React's render-with-hooks call, overwhelmingly in the Lean interpreter beneath
it. “Beneath React” does not mean time spent implementing React reconciliation.

The optimized unstripped SDK WASM supplies 2,849 function names. Before using
them, the script checks that all non-custom sections exactly match the measured
release WASM; all 4,204 WASM frame occurrences resolve. This resolves interpreter
and runtime C++ functions, **not the names of interpreted Lean declarations**.
Consequently this profile does not yet prove how much time goes to identity
serialization versus child-array construction or other Lean renderer helpers.

Useful artifacts:

- `browser.symbolicated.cpuprofile`: load directly in Chrome DevTools.
- `browserParsed-render.svg`: sampled aggregate flamegraph for the remaining
  renderer work; not a chronological timeline.
- `whole-decode.svg`, `browserParsed-decode.svg`, `whole-render.svg`: other slices.
- `profile-summary.json`, `profile-clock.json`, `wasm-symbols.json`: attribution,
  clock uncertainty, hashes and symbol evidence. Raw profile and folded stacks
  are retained too. The rendered DOM hash still matches the preceding campaign.

The child-array experiment below tests the already-built-node→action-array detour.
Separately measure
identity serialization before changing its policy. Do not spend the next slice
on React commit optimizations or removing necessary `LeanRef` ownership.

To reproduce sampling, add `VBP_REPLAY_PROFILE=1` to the replay command above.
The flag is compiled out of ordinary replay mode. To resolve names and generate
the four flamegraphs using the retained FlameGraph tool:

```sh
node tests/vir_preview/summarize_replay_profile.mjs \
  /absolute/path/to/conversion-profile-1 \
  /absolute/path/to/flamegraph-tools/flamegraph.pl
```

### Child-array experiment: not adopted

The candidate replaced generic-renderer JSX spreads of `children.map pure` with
`Node.createElement` and `Js.Array.ofArray` for already-rendered children. No new
helper layer, key policy, props, or session-state change was introduced. JSX
remained for children that genuinely are rendering actions. This removes the
intermediate array of actions, but `Js.Array.ofArray` still loops and pushes each
child through the same host API; it is not a bulk host transfer.

Evidence is retained under `_out/browser-pr187/child-array/`. `baseline/` and
`candidate/` contain exact source and complete replay package sets; the latter
also retains generated C. Only the `VersoReact.Renderer` member changes:
463,789 → 436,302 bytes (−5.9%). The package set loses four declarations.
Both use VIR `6e91bed`, its matched release SDK, and the same captured FLT chapter.
The driver now supports `VBP_REPLAY_PACKAGE_SET` and validates every member's
declared size and SHA-256 before using a retained package set.

Eight fresh browser sessions ran in order A/B/B/A/B/A/A/B (`before-a`, `after-a`,
`after-b`, `before-b`, `after-c`, `before-c`, `before-d`, `after-d`). Each has two
warmup pairs and 16 measured updates per decoder: 64 observations per
renderer/decoder combination. No profiler or host timing instrumentation was
enabled. Debug, highlighting and follow-cursor were off. This measures captured
response → DOM commit, not server elaboration, RPC, paint, or full edit latency.

Pooled medians in milliseconds, retaining **all** sessions:

| Decoder | Renderer | Decode | Render → DOM | Total |
| --- | --- | ---: | ---: | ---: |
| String | JSX baseline | 213.1 | 242.2 | 454.5 |
| String | Direct child array | 240.7 | 271.0 | 517.1 |
| Checked browser JSON (experimental) | JSX baseline | 34.8 | 249.1 | 285.1 |
| Checked browser JSON (experimental) | Direct child array | 37.7 | 272.9 | 314.2 |

These are not evidence of a gain. Paired session-median render deltas, candidate
minus baseline, were −18.3/+7.0/+58.8/+41.1 ms for the string path and
−29.1/−6.2/+64.9/+40.2 ms for checked JSON. The untouched string decoder also
shifted −12.0/+6.0/+45.0/+41.4 ms. Execution variability or shared-runtime
effects therefore remain confounded with the candidate; do not attribute the
whole slowdown to child handling, normalize it away, or keep only the first
favorable pair. `summary.json` retains per-session medians and paired deltas;
each run retains raw observations and package/SDK/input identities.

The candidate passed Beam sync (zero diagnostics), batch builds of all four
affected test packages, generic/Blueprint SSR acceptance, and retained React
StrictMode session acceptance. Every replay preserved the same normalized DOM
hash `4d079cdcb7aace634a0fe78a1c130563a0f71acbf79ca84b7b9afefdac9c298d`,
checkbox state/identity and unchanged paragraph, with no React warnings.
The early `before-1` attempt is not a timing run: it stopped before browser
launch because the snapshot omitted the root member. That unchanged member was
recovered only after verifying its bytes against the baseline descriptor hash.

The post-change diagnostic capture is `profile-after/`, with 1 ms CPU sampling,
±0.755 ms clock calibration, and all 3,482 WASM frame occurrences resolved.
Its checked-JSON render slice has 4,189 samples: dispatch/evaluation 46.7%,
symbol/name lookup 16.4%, allocation/refcount/vector storage 10.5%, other WASM
12.5%, and JS/browser 14.0%. Host-boundary inclusive share is 11.7%; React
`commitRoot` is 0.22%. The broad runtime profile remains similar; the smaller
host share alone does not establish fewer absolute milliseconds or identify
the interpreted Lean helpers responsible.

**Decision:** performance benefit is inconclusive, so the candidate is not
adopted. Restore the simpler JSX renderer byte-for-byte and rebuild its package
sets; preserve the candidate and reports for reproduction. The SDK pin and live
FLT demo are unchanged. Before another source rewrite, use finer diagnostic
attribution for content-identity serialization versus VDOM construction, then
validate any hypothesis again without diagnostic instrumentation.

To replay either retained implementation, use the ordinary replay command with
`VBP_REPLAY_PACKAGE_SET=/absolute/path/to/child-array/{baseline,candidate}/DecodeProbe.irpkg-set.json`.
Keep the same SDK/root and comparison flag as this campaign. The snapshot is a
local experiment artifact, not a published runtime package or new production API.

### Identity attribution: JSON fingerprints dominate

The next diagnostic separated extension identity resolution, JSON fingerprint
generation, sibling-key allocation, and the remaining generic renderer work.
It reused the same FLT single-chapter response, VIR `6e91bed`, release SDK,
production React, and retained preview with debug/highlighting/follow-cursor off.
It is a phase attribution experiment, **not an optimization or an edit-latency
measurement**. Artifacts: `_out/browser-pr187/identity-phases/`.

Two refined captures (`diagnostic-2`, `diagnostic-3`) each contain two warmup
pairs and 16 measured updates per decoder. All 32 observations per decoder are
included in `summary.json`. Medians in milliseconds:

| Phase | String decoder path | Checked browser JSON path |
| --- | ---: | ---: |
| Decode response, before rendering | 200.3 | 33.0 |
| Resolve extension identities / normalize singleton concatenations | 6.9 | 7.1 |
| Build JSON fingerprints (`toJson` + `Json.compress`) | 173.2 | 176.4 |
| Allocate sibling keys, disambiguate duplicates, build identity paths | 4.7 | 4.8 |
| Other generic renderer work: VDOM, props, styles, extension rendering | 41.0 | 43.0 |
| Outside generic renderer → DOM observation | 6.4 | 5.7 |
| **Render → DOM total** | **232.3** | **235.7** |
| **Response → DOM total** | **433.4** | **270.1** |

Medians of individual phases need not add to the median total. The median
per-update identity share is 80.0% on both paths; JSON fingerprint generation
alone is roughly three quarters of rendering. This identifies the next target
much more specifically than the earlier interpreter-heavy sampled stacks.
Extension metadata decoding is real work, but is not the dominant cost here.
These numbers do not establish that eliminating this work would yield an 80%
end-to-end speedup, nor do they permit dropping content-based React keys.

#### Instrumentation and limits

Only the generic renderer was temporarily patched. A block group first unwraps
singleton concatenations and resolves explicit extension identities; a second
pass computes JSON fingerprints only for blocks lacking those identities; the
original sibling allocator then runs unchanged. Section title fingerprints use
the original helper. This preserves the identity values, but deliberately
separates the pure computation into passes for attribution; allocation/lifetime
and compiler shape are not exactly the uninstrumented renderer's.

Each of 110 sibling groups (153 block entries and seven subparts per update)
has one string boundary and three size barriers through existing VIR bindings.
No new host API, per-node clocks, document copying, or producer changes were
needed. The forced sizes prevent the compiler from moving the actual computation
past its boundary. Generated C was checked: normalization/extension callback
map precedes the first `js.nat`, JSON fingerprint map precedes the second, and
`allocateSiblingIdentities` precedes the third. The same original allocator and
fingerprint semantics remain in the ordinary renderer. An outer boundary
measures the generic renderer, including its extension callbacks; the outside
remainder includes VBP/session setup, React scheduling/reconciliation and DOM
observation, not just React commit.

The probe records `performance.now()` around these boundaries without CPU
sampling or host-call tracing. Host handler bodies are excluded between phases;
emitter-side dispatch, helper bookkeeping and marker costs are not all excluded.
One empty-work calibration group runs per render: observed elapsed 0–0.1 ms,
median 0 ms at the browser timer's resolution. **That is not zero overhead** and
does not measure the full instrumentation perturbation. No calibration value
was subtracted from the measurements.

Ordinary controls bracketed the refined diagnostic sessions in A/B/B/A order.
Session-median render times (string / checked JSON) were:

| Session | Render → DOM, ms |
| --- | ---: |
| `control-a` | 236.8 / 239.4 |
| `diagnostic-2` | 237.5 / 261.2 |
| `diagnostic-3` | 228.9 / 233.7 |
| `control-b` | 233.5 / 233.3 |

This is a useful scale check, not a precise overhead estimate. Session drift is
still present; use the large, repeated phase difference to select a target,
not small differences between these totals. `diagnostic-1` is retained as the
earlier, coarser probe: its ~191 ms identity-hints bucket combined extension
decoding and JSON fingerprints and must not be described as serialization alone.

All captures preserved the normalized DOM hash from the preceding campaign,
checkbox state/identity, and an unchanged paragraph, without React warnings.
Probe unit tests cover passthrough, phase ordering, malformed/incomplete groups,
and the outer render interval. Beam checked the initial diagnostic source with
zero diagnostics; each refinement was batch-built into its replay package.
The ordinary renderer source was then restored byte-for-byte and the four
affected test packages rebuilt. No markers remain in the ordinary renderer or
live FLT demo. The diagnostic source, generated C, and full package set are
retained under `instrumented/`; the uninstrumented control remains the previous
`child-array/baseline/` package set.

Reproduction: add `VBP_REPLAY_IDENTITY_PHASES=1` and point
`VBP_REPLAY_PACKAGE_SET` at `identity-phases/instrumented/DecodeProbe.irpkg-set.json`
in the normal replay command. Do not combine it with CPU sampling. Summarize
refined captures with:

```sh
node tests/vir_preview/summarize_identity_phases.mjs \
  /absolute/path/to/summary.json \
  /absolute/path/to/diagnostic-2 /absolute/path/to/diagnostic-3
```

**Next target:** distinguish construction of the temporary JSON tree from its
string serialization, then optimize that normal path while preserving exact
keys and duplicate handling. Avoid introducing a new document model, moving
work across the RPC boundary, or adopting memoization without first measuring
this narrower opportunity. Any candidate still needs diagnostics-off timings
and retained-state acceptance.

### JSON split: serialization, not tree construction

The next probe splits the fingerprint phase at the completed JSON-tree array.
Evidence is retained in `_out/browser-pr187/json-phases/`, including the exact
diagnostic Lean source, generated C, and replay package set in `instrumented/`.
This is the same FLT chapter, SDK, toolchain and display configuration as above.

Two diagnostic sessions each retain 16 updates per decoder after two warmup
pairs. Across all 32 observations per decoder, median milliseconds are:

| Phase | String decoder path | Checked browser JSON path |
| --- | ---: | ---: |
| Decode response | 222.5 | 36.5 |
| Extension identity resolution / normalization | 8.1 | 8.1 |
| Construct JSON trees for fingerprints | **5.9** | **6.0** |
| Serialize trees with `Lean.Json.compress` | **179.5** | **182.5** |
| Allocate sibling keys | 5.3 | 5.7 |
| Other generic renderer work | 48.9 | 49.8 |
| Outside generic renderer → DOM observation | 6.7 | 6.5 |
| **Render → DOM total** | **264.2** | **255.9** |
| **Response → DOM total** | **487.2** | **294.3** |

Individual phase medians are not additive. Serialization accounts for roughly
97% of the fingerprint-generation time. The conclusion is not that the JSON
representation is intrinsically too expensive: constructing it is comparatively
cheap here. The main cost is serializing it through the Lean interpreter to
recompute content-based keys on each update.

The original probe is extended with one extra size barrier per sibling group.
Explicitly identified blocks still skip JSON generation. Otherwise the exact
same `toJson` result is constructed first and passed to the exact same
`Json.compress`; section titles are treated similarly. Generated C confirms
the sequence: extension resolution, first barrier, JSON construction, second
barrier, compression, third barrier, key allocation, fourth barrier. It retains
a sibling group's JSON trees until the compression pass, unlike the normal
interleaved map. This changes temporary lifetime/allocation behavior, so these
are diagnostic phase estimates, not a candidate optimization's headline result.

The independent uninstrumented controls bracketed the diagnostic sessions:

| Session, in execution order | Render → DOM, string / checked JSON (ms) |
| --- | ---: |
| `control-a` | 253.3 / 279.0 |
| `diagnostic-a` | 248.7 / 247.6 |
| `diagnostic-b` | 267.5 / 270.2 |
| `control-b` | 234.8 / 247.8 |

All sessions used the same probe source hashes; the two diagnostic sessions
also used identical package-set hashes. The controls show substantial timing
variation and do not isolate a precise instrumentation penalty. In particular,
do not interpret differences from the previous campaign's medians as a speedup
or regression. Empty-work calibration was 0–0.1 ms, median zero at the timer's
resolution; no overhead subtraction was applied. All 110 sibling groups, 153
block entries and seven subparts remain accounted for on every update.

The DOM digest, unchanged-paragraph identity, checkbox state, and absence of
React warnings pass throughout. Beam reports zero diagnostics; the diagnostic
package builds successfully. The normal renderer has been restored byte-for-byte
and its affected package sets rebuilt. Live FLT, dependency pins and upstream
repositories are untouched. Probe tests cover both phase layouts, and the
summary script rejects mixed package/SDK/input/probe identities. Reproduce with
the existing identity-phase command, selecting
`json-phases/instrumented/DecodeProbe.irpkg-set.json`, and summarize
`diagnostic-a` and `diagnostic-b` with `summarize_identity_phases.mjs`.

**Initial follow-up target:** an accelerated, byte-equivalent serialization
path. The pinned Lean printer uses a work queue for JSON traversal and byte/char
loops for string escaping; this experiment does not yet split their individual
costs. An alternative must preserve exact output—including escaping, object
ordering and numbers—and must include any JS/Lean conversion cost in its
benchmark. A browser stringifier is not to be substituted on assumed equivalence.
No new document format, positional/hash-only keys, or custom VBP transport is
justified by these measurements.

### Serializer follow-up: inconclusive; identity placement under discussion

The explicit-work-list serializer passed 80 byte-equivalence cases, including
the captured FLT response, plus depth-5000 and width-5000 stress cases. Renderer
and retained-session acceptance passed. Matched packages differed only in the
renderer member selecting the original or experimental serializer.

The unprofiled ABBA campaign did not show a consistent improvement:

| Run | Checked-JSON render → DOM (ms, median) |
| --- | ---: |
| Original A | 243.7 |
| Work-list A | 225.5 |
| Work-list B | 259.8 |
| Original B | 229.7 |

Evidence is retained under `_out/browser-pr187/list-serializer/`. A subsequent
direct character-loop variant passed Beam checking but has not been built or
benchmarked. It remains diagnostic-only; the production renderer was restored
byte-for-byte to `list-serializer/Renderer.before.lean`. No live demo changed.

Serializer tuning is paused to consider preparing fallback identities on the
server instead. This JSON pass is not RPC encoding: the browser reconstructs
JSON from decoded blocks solely to obtain content-based React keys. A faster
RPC codec therefore does not remove it. A server-side experiment must account
for native preparation, additional payload size, decoding and full
edit-to-preview latency, while preserving sibling identity semantics. No new
payload design or server-side identity implementation has been adopted.

## Positional identity control (2026-09-15)

**Decision: useful performance control, rejected for adoption.** Removing JSON
fingerprints cuts browser rendering time by about 73–74%, but positional identity
transfers state to unrelated unlabeled blocks on insertion/deletion. The original
renderer is restored; no live demo, dependency pin, RPC or server path changed.

### Scope and identity audit

The only renderer change returns empty identity hints instead of JSON
fingerprints for ordinary blocks and section titles. Existing extension semantic
IDs, singleton-concat handling, sibling occurrence disambiguation and key
allocation remain unchanged. This deliberately tests the existing positional
fallback, including its ancestor-path behavior, rather than redesigning it.

Ordinary `Lean.Doc.Block` constructors have no persistent source identity.
Manual extension/section IDs are assigned during traversal (`VersoManual.Basic`
`freshId`, `TraversePart` and `genreBlock`); availability does not establish
stability across independent edits. The captured FLT document contains zero
non-null `id` or `tag` fields. VBP's explicit informal/external-markup labels
remain available through the existing extension identity callback.

### Matched FLT replay

The input is the same single FLT chapter, not the full FLT document. SDK, source
input, probe, decoding paths and diagnostics settings are fixed. Baseline and
candidate each have 68 package members and 12 diagnostic exports. Removing
reachable serialization work changes six packaged members, including the
renderer; it is not a dependency revision change. Package bytes fall from
2,471,726 to 2,374,405. Full immutable sets and source snapshots are retained in
`_out/browser-pr187/positional-identity/{baseline,candidate}/`.

Each run has two warmup pairs and 16 measured pairs, alternating string and
checked-JSON decoding. Policy order is baseline A, candidate A, candidate B,
baseline B; pooled medians below use 32 observations per decoder/policy. Timing
uses the existing three coarse timestamps, without host timers or CPU sampling.

| Decoder / phase | Content fingerprints | Positional control | Change |
| --- | ---: | ---: | ---: |
| String: decode | 224.6 ms | 241.5 ms | +7.5% |
| String: render → DOM | 255.9 ms | 65.4 ms | −74.4% |
| String: response → DOM | 487.8 ms | 305.8 ms | −37.3% |
| Checked JSON: decode | 35.9 ms | 40.7 ms | +13.4% |
| Checked JSON: render → DOM | 265.1 ms | 72.3 ms | −72.7% |
| Checked JSON: response → DOM | 301.0 ms | 111.1 ms | −63.1% |

Individual render medians (string / checked JSON) are 242.5 / 245.5 ms,
76.6 / 76.9 ms, 63.2 / 71.1 ms, and 266.5 / 267.8 ms in execution order.
Background variation is visible, including slower decoding in the candidate
cohort; nevertheless both comparisons show a large rendering reduction.
Medians of separate phases need not add to the median total. This is browser
response replay, not live edit-to-preview latency: it excludes server work,
RPC/LSP transport, paint and passive-effect completion. Checked JSON remains an
experimental codec, not an adopted production dependency.

All timed runs retain the follow-cursor checkbox and an unchanged paragraph,
produce 356 elements, and have no React warnings. Text and presentation DOM are
equivalent across policies. The summary excludes only block identity diagnostics
(`data-verso-render-id`, `data-verso-identity-origin`, and their `title`) from that
cross-policy comparison; raw DOM snapshots preserve them. All other attributes,
styles, text and element structure are checked.

### Retention behavior: neither policy is a general solution

`identity_browser_cases.mjs` drives real React roots and VIR-generated elements.
The fixture's uncontrolled HTML disclosures expose browser-owned state; paragraph
cases also record selection. No replacement reconciliation or custom host API is
used. Twelve cases run under each policy with policy-specific expectations.

| Edit | Content fingerprints | Positional control |
| --- | --- | --- |
| Paragraph text | Remounts paragraph | Retains paragraph |
| Insert/reorder before paragraph | Retains the logical paragraph | Reuses its position for another paragraph |
| Labeled disclosure body | Retains disclosure, remounts edited paragraph | Retains both |
| Insert/reorder labeled disclosure | Retains disclosure and child | Retains disclosure, remounts child |
| Unlabeled disclosure body | Remounts, loses open state | Retains open state |
| Insert before open unlabeled disclosure | State stays with original | State transfers to inserted disclosure |
| Delete open unlabeled disclosure | State disappears | State transfers to following disclosure |
| Section title / enclosing quotation edit | Nested labeled disclosure remounts | Nested labeled disclosure survives |

Both policies cannot distinguish an inserted identical sibling from existing
identical occurrences. The positional paragraph insertion/reorder cases also
move the observed selection from `B` to `A`; retaining a DOM position is not
retaining document identity. The content-key reorder preserves the paragraph
node but loses selection in this fixture, so node retention alone is not a
selection guarantee.

Moving a labeled parent remounts its positional children because existing
fallback keys include the full ancestor debug path. React needs sibling-local
keys, so this is a separate, concrete improvement candidate. It does not solve
unlabeled sibling matching.

The candidate also fails the three existing `VersoReactTests` guards for insertion
change detection/count and reordered content. These failures are preserved in
`existing-tests-candidate.log`; expectations were not weakened. The original
renderer was restored byte-for-byte and the affected test/renderer/session
package targets rebuilt successfully.

### Attribution and next decision

Fresh before/after profiles use 1 ms CPU sampling with matched release WASM and
verified debug symbols; both have zero unresolved WASM frames. These are
diagnostic captures, not the headline measurements. The candidate render phase
is about 60–61% JavaScript/browser self time, with about 53–54% of total samples
under the runtime's `callObjectsImpl` boundary; React `commitRoot` accounts for
about 0.9–1.0%. These inclusive percentages overlap. Most of the remaining cost
is not React DOM commit; interpreted Lean stacks are much smaller after removing
the serialization caller path. The profiler resolves interpreter/native symbols,
not individual interpreted Lean declarations, so it cannot directly assign every
sample to `Json.compress`.

Next: separate sibling-local React identity from navigation/debug paths, and
decide how unlabeled stateful blocks acquire stable identity. Do not move whole
subtree serialization to the server merely to preserve the current scheme.
No new document representation, matching algorithm or identity policy is adopted
by this experiment.

### Reproduction and evidence

Use the existing replay command with `VBP_REPLAY_PACKAGE_SET` selecting the
retained baseline/candidate descriptor. For untimed behavioral checks, replace
`VBP_REPLAY_RENDER=1` with `VBP_REPLAY_IDENTITY_TEST=content` or `position`, matching
the selected package. All outputs must use fresh directories. Summarize the
retained ABBA campaign with:

```sh
node tests/vir_preview/summarize_identity_experiment.mjs \
  /absolute/path/to/verso-blueprint/_out/browser-pr187/positional-identity
```

`summary.json` contains raw-run summaries, range/median statistics, changed
package members, presentation verification and the full behavioral observations.
Each replay retains source, SDK/package/input identity and raw timing rows.
`profile-{before,after}/` contain raw and symbolicated profiles, folded stacks,
clock calibration and profile summaries. New source checks used Lean Beam with
zero diagnostics; dependency validation used targeted Lake builds, not Beam
saved artifacts or a clean full-workspace rebuild.

Restoration gates pass: generic/Blueprint renderer acceptance, retained-session
Chromium acceptance (including controls and debug metrics), and all nine existing
phase-probe tests. Both the renderer source and rebuilt DecodeProbe descriptor
match the baseline byte-for-byte. The Beam owner is stopped. Logs are retained
as `restored-{build,renderer,session}.log` and `probe-tests.log`.

## Sibling-local React keys (2026-09-15)

The follow-up keeps the existing content-fingerprint block policy and separates
React keys from navigation paths. Inline keys are now relative to their immediate
siblings; list items and description terms/values likewise use local keys. Source
addresses remain unchanged in DOM metadata and focus comparisons. The dormant
positional block fallback also uses the local index rather than a full source
path, without enabling that fallback for ordinary blocks. No retained registry,
memoization, wrapper component, RPC change or alternate document format was added.

This fixes a bug in the content-key renderer, independently of the rejected
positional experiment. After inserting an earlier block, a retained paragraph
could recreate its open footnote because the footnote's key contained its old
ancestor path. Similarly, moving a retained list recreated its items and their
stateful descendants.

The extension API now explicitly calls the first `renderInline?` argument a
sibling-local key, not a source path. `renderMath` uses the same convention, and
the VBP adapter and package README are updated. Callers must not interpret these
keys as source addresses; navigation continues to use renderer DOM metadata.

The matched browser fixture runs 21 scenarios per version. Nine added
parent-movement checks reproduce remounts before the fix and retain the original
nodes afterward: footnote, math, emphasis, nested bold, recognized inline
extension, unsupported inline marker, and disclosures inside unordered, ordered
and description lists. Footnotes/inline disclosures and list disclosures retain
their open state. Navigation addresses change with the inserted source block,
and are identical between the old and new implementations for each scenario.
Rendered text is also identical. The original twelve identity scenarios retain
their existing behavior: content edits can still remount fingerprinted blocks;
this patch does not claim to solve that policy problem.

The generic package also gains a non-browser regression asserting that an
insertion before retained parents does not change their inline/list descendant
keys. Existing change-highlighting guards remain intact. Targeted Lake builds,
generic/Blueprint React renderer acceptance and retained-session Chromium
acceptance pass. Beam checks the renderer with zero diagnostics; no Beam saves
or clean whole-workspace build are used.

Evidence is retained under `_out/browser-pr187/local-react-keys/`, including
immutable baseline/candidate package sets, source snapshots, build logs,
`behavior-before-final/`, `behavior-after/`, renderer and session reports.
The two behavior captures have identical probe source hashes and SDK identity;
use `VBP_REPLAY_IDENTITY_TEST=content-path` with the baseline and `content-local`
with the candidate to reproduce them. The earlier `content`/`position` fixture
modes still run only the original twelve cases for the positional experiment.

This is a correctness change, not adoption of the 74% rendering reduction.
Fingerprint construction/serialization is unchanged. Stable identities for
unlabeled stateful blocks remain the next design decision; sibling-local indices
alone do not preserve identity across edits within that sibling list.

The FLT replay also passes with both decoder paths: 356 elements, retained
follow-cursor checkbox and unchanged paragraph, no React warnings, and exactly
the same full DOM/text digests as the pre-change renderer (no identity attributes
excluded). This single replay is output/regression validation, not a matched
performance claim. Its raw results are in `flt-replay/`. The live demo and
upstream checkouts remain untouched; all work is local and uncommitted.

## Retained structural fingerprints (2026-09-15)

Adopted locally in the research preview: replace full JSON-string React keys
with session-owned tokens, without adopting the rejected positional fallback.
`VersoReact.Fingerprint` hashes existing Manual blocks and section titles.
Hash matches only select candidates: exact typed equality decides whether to
reuse a token. A different value receives a fresh token, including when a
colliding predecessor disappeared before the new value arrived. Duplicates share
a content token and retain the existing sibling-occurrence disambiguation.

The existing preview `ChangeState` owns the assignments alongside the document.
The transition is pure and participates in React's render replay; there is no
mutable global registry, ref-based allocator, new component wrapper, or custom
reconciler. Only the current document's distinct values are retained, using
current value references. Retired tokens are never reassigned. Loading/error
states preserve the last accepted assignments as they already preserve the last
document; unmounting resets the session. Cursor/version/control-only updates reuse
the assignments when document content is equal.

`Renderer.prepareIdentities` visits all blocks, including hidden descendants,
without invoking rendering callbacks. `Options.identities?` supplies the prepared
state to the ordinary renderer. Stateless calls still use serialized-content
keys. Optional change highlighting also keeps its separate serialized snapshots;
these measurements have debug and highlighting **off**. Typed equality can be
stricter than the old printer: hand-built `JsonNumber` values `⟨1, 0⟩` and
`⟨10, 1⟩` print identically but are different Lean values. They receive different
tokens. This is not a claim of universal equivalence to printer-normalized keys.

### Matched FLT browser measurement

Evidence: `_out/browser-pr187/structural-fingerprints/`. The input is the captured
FLT chapter **First Reductions Of The Problem**, not the whole FLT blueprint:
221,382 UTF-8 bytes, SHA-256
`f0e70f669518c96fb8211678ad83dd0765396b5e3b3ec513702faad55cfc47be`.
Each replay changes the existing text marker and version. The real retained
preview decodes the reply and renders through React; it is not a renderer-only
microbenchmark.

Two immutable package sets use the same 70-module inventory, 16 exports, exact
VIR `6e91bed8`, matched SDK/Wasm, toolchain, driver and input. Only
`Preview.Component` and `Preview.Component.Content` package members differ:
the baseline has the same fingerprint implementation/test surface but does not
enable it in the preview. Total package bytes are 2,934,837 versus 2,973,990.
Source snapshots and descriptors are under `baseline/` and `candidate/`.

Order: baseline, candidate, candidate, baseline. Each fresh browser/runtime has
two warmup pairs and sixteen measured pairs, alternating decoder order: **32
observations per decoder per variant**. No concurrent build, Beam session, host
phase probe, or CPU profiler runs during these headline measurements. Timing
starts before decoding and ends at the MutationObserver after the DOM commit.
It includes identity preparation, the guarded React state update/retry, rendering
and commit; it excludes RPC/LSP/server work, paint and passive-effect settling.

| Browser path / phase | Serialized keys | Retained typed fingerprints | Change |
| --- | ---: | ---: | ---: |
| Current string decoder: decode | 203.1 ms | 197.1 ms | unchanged code |
| Current string decoder: preparation + render to DOM | 234.9 ms | 74.6 ms | −68.2% |
| Current string decoder: complete reply processing | 435.9 ms | 272.8 ms | −37.4% |
| Experimental checked-JSON decoder: decode | 32.8 ms | 34.0 ms | unchanged code |
| Experimental checked-JSON decoder: preparation + render to DOM | 234.9 ms | 76.6 ms | −67.4% |
| Experimental checked-JSON decoder: complete reply processing | 268.2 ms | 110.1 ms | −58.9% |

Values are pooled medians, so phase medians need not sum to the total median.
Candidate render medians in the separate runs are 71.3/76.3 ms (string) and
75.6/76.8 ms (checked JSON); baseline run medians are 232.9/236.9 and
234.9/240.8 ms. Outliers remain: this is a local replay result, not a latency
guarantee or a fresh live-editor measurement. The checked-JSON decoder remains
an experimental comparison, not an adopted RPC protocol change.

Reproduce the summary with:

```sh
node tests/vir_preview/summarize_identity_experiment.mjs \
  /home/egallego/lean/verso-blueprint/_out/browser-pr187/structural-fingerprints structural
```

### Correctness and remaining work

Both browser identity variants pass all 21 edit/insertion/deletion/reorder cases,
including disclosure state and moved-parent inline/list descendants. Forced-hash
collisions run in Lean and in the actual VIR browser runtime, covering duplicates,
replacement without coexistence, retirement/reintroduction, and bounded state.
The corpus covers all block/inline forms, extension payloads, and decoded copies.
Additional final regressions check map insertion-order independence and the
documented numeric representation distinction. Those test-only additions follow
the immutable timing snapshots; the measured production implementation is unchanged.

The FLT presentation comparison preserves structure, text, styles and all other
attributes, ignoring only identity diagnostics (`data-verso-render-id`,
`data-verso-identity-origin`, and block `title`). The 356-element preview retains
the follow-cursor checkbox and unchanged paragraph, with no React warnings.
The session acceptance also passes StrictMode, status transitions, diagnostic
controls, highlighting, retained options, effect deduplication, and intentional
reset on unmount. Renderer/Blueprint adapter acceptance passes as well.

A separate diagnostic capture in `profile-after/` retains the raw and symbolicated
CPU profiles plus folded stacks. Approximately 38–41% of sampled render-window
time is beneath the generic `callObjectsImpl` host boundary; React `commitRoot`
is below 1%. These inclusive samples are not additive phase timings. The symbols
identify native interpreter/runtime functions, not individual interpreted Lean
declarations; they do not isolate preparation or prove that reconciliation is
free. They point toward the runtime/host boundary as a useful next investigation.

This slice preserves complete-content identity and remount-on-content-edit for
unlabeled blocks. It does not implement edit-stable semantic matching, subtree
caching, a document-delta protocol, or a serialized intermediate format. Hashing
and exact comparison can still revisit nested content, and preparation includes
hidden descendants. The small typed fingerprint boundary now makes those costs
inspectable without reintroducing JSON serialization. No upstream dependency pin
or live FLT demo was changed; the work remains local and uncommitted.
