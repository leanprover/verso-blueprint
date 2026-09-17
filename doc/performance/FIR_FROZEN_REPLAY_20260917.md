# Frozen FIR artifact: FLT browser profile

For the subsequent matched backend comparison and current symbol disposition,
see [the checked-codec comparison](VIR_FIR_CHECKED_COMPARISON_20260917.md).
This report preserves the earlier screening and diagnostic captures; its timing
table is not the current balanced comparison.

Consumer package `23dfd8ab282aa8b5b0b7d90b`, from W7 checkpoint `ddac2af9`,
uses source snapshot `bc9685f9` (VBP `99caaacb`, VIR `92d7cc91`, Lean 4.34.0-rc2).
The Wasm is unchanged: 2,034,522 bytes, SHA256
`fa24e89b608d63b08c3c683f95f97d992862e3b756cc14827d96a4df1c4df5aa`.
BUILD SHA256:
`7e1342ec1eb3d78cab666d32edf2e5fa43d70102e19bb2cc02f8d9f6e87e1434`.
Checksum-manifest SHA256:
`d6d33302cca5bd9aeba5bcbb19866d7f3bbe6f6648ec62c699833fce2a5aa122`.
Each capture verifies and copies the complete immutable package. No producer
source, live widget, package pin or publication is changed. FIR root accepted
the provisional local package in `ROOT-W7-20260917-010`; this bounded consumer
experiment remains separate from live adoption or publication.

This artifact does **not** contain VBP `239e423c` style reuse or the VIR-only
direct typed converter. Its actual codec is JS JSON validation/conversion to
`Lean.Json`, followed by the compiled `FromJson Preview`. Its default
`createView/renderDecoded` path uses no configured native math component.

## Workload and qualification

The existing FLT response replay driver now accepts an explicit FIR-package mode;
Chromium launch, cleanup, CDP sampling and five-trial clock calibration are reused.
The browser entry uses `createConfiguredCodecSession` and the package-owned
providers with the application's single React installation. React is production
19.2.7. The copied package's standalone smoke passes checksums, 18 real-Wasm SSR
renders, malformed-codec recovery and retained callback/disposal checks.

Input is the unchanged 6,598,356-byte response from
`_out/browser-pr188/widget-baseline-inputs`, SHA256
`6ae2daf7641f9d8ae76d48a0bf57bc63a0d25c886c299643b487bfbf8fe6e2c3`.
Each update edits the captured text marker and document version. After initial
mount and a follow-cursor control change, the harness runs two warmups and four
measured retained updates. Debug and highlighting are off.

Full FLT Chromium rendering preserves 7,011 elements, checkbox identity/state
and an unchanged paragraph. No React/browser warnings are observed. Text SHA256:
`ae733007b2d233a50c10e0d95a360f80dab036e852b38bb87e609fbf100e9ad5`.
Four-update final DOM SHA256:
`4678d8b39055efd4f805b38025dc8c9a36bcbc77d9375ad8685b186a9e327213`.
Both match the four-update VIR `direct-pointer-render-02` capture, including tags,
styles and attributes. An initial comparison to an eight-update VIR capture
differs only in the edited paragraph's fingerprint and its diagnostic title:
those runs end at different marker versions. This is not a renderer divergence.
The `fir-bc968-dom-01` capture retains the complete tree for that inspection.
This qualifies this full-FLT/default-view slice, not all options or native math.

## Unsampled timings

Capture: `_out/upstream-vir-20260917/fir-bc968-replay-01`.
Four raw samples are retained; this is a screening run, not an order-balanced
VIR/FIR speedup claim.

| Observed boundary | Median |
| --- | ---: |
| Browser JSON.parse | 14.5 ms |
| Checked JSON → Lean.Json → typed Preview | 1,049.0 ms |
| Parse plus checked decoding | 1,063.5 ms |
| Decoded Preview → accepted DOM | 1,552.7 ms |
| Parse start → accepted DOM | 2,642.5 ms |

The render interval includes session/identity preparation, element construction,
React reconciliation/commit and scheduling up to MutationObserver acceptance.
It is not an isolated renderer CPU timer. RPC/LSP, server encoding, transport,
startup, package loading, Wasm instantiation, initial mount, paint and waiting for
passive effects are excluded. Independent phase medians must not be summed.

## Sampled document-to-elements attribution

`fir-bc968-profile-03` is a separate four-update CDP profile at a requested 1 ms
sampling interval. Two callbacks per factory are bracketed by the existing
component probe: content first, outer session second. The bootstrap creates the
configured factory and then the default view; only default-view callbacks are
observed during measured updates. These brackets are absent from headline timing.
Clock uncertainty is 0.464 ms, below the unchanged 5 ms rejection threshold.

Diagnostic callback medians: **1,255.4 ms** for decoded-document-to-elements and
**408.3 ms** for the combined outer-session calls. Every update has two outer
calls (the accepted-input state transition rerenders that shell) but only **one
content construction**. The outer phase is not a pure identity timer. These are
instrumented-run measurements, not a decomposition of the unsampled median.

Within the content callback, interval-weighted sampled self shares are:

| Disjoint bucket | Share |
| --- | ---: |
| FIR Wasm, internal symbols unavailable | 69.2% |
| FIR JS adapter | 19.0% |
| Host UTF-8 decoding builtin | 4.8% |
| Author provider bundle | 2.5% |
| Browser GC | 2.4% |
| Unattributed/browser | 1.5% |
| Shared JS/Wasm transition | 0.5% |
| React elements | 0.17% |
| React hooks | 0.05% |

These shares use 4,992.8 ms of sampled coverage across four content callbacks.
They are not end-to-end percentages. Session/content windows subdivide the
render window; parse/codec windows subdivide decoding. Do not sum overlapping
aggregate and subdivision windows. Source-map categories classify the producer's
bundled providers together rather than assigning their internal costs to React.

Prominent resolved content self frames include `resource` (7.0%), UTF-8 `decode`
(4.8%), `allocate` (3.6%), the adapter host dispatcher (2.9%) and cached-view
access (2.1%). However, most samples remain in Wasm bodies. The artifact has no
name section; function indices are retained as stripped FIR frames and are never
mapped through the unrelated VIR interpreter's symbols. A matching function-index
inventory or same-executable named artifact is needed before naming the dominant
internal callers. No compiler/runtime optimization is inferred yet.

The final harness also checks exactly one successful content construction inside
the default-view update window. `fir-bc968-profile-04` reruns those assertions on
two sampled updates. Raw profiles, source maps, calibrated timestamps, folded
stacks, source/bundle/package hashes and offline summaries are retained in the
capture directories. `fir-bc968-profile-02` is a rejected harness capture: the
source map was mistakenly served as JavaScript. It is excluded, and output
selection now explicitly selects the `.js` file.

## Retention and next target

The provisional FIR runtime intentionally retains a monotonic arena and JS
resources until unmount/disposal. In the unsampled measured cohort, the heap
frontier rises from 125.6 MB to 211.2 MB over three further updates, and resource
count rises from 1.26 million to 2.06 million. That is about 28.5 MB of arena and
266,817 resources per update, not proof of a leak or bounded live memory. React
is unmounted before session disposal. Timing comparisons must match session age.

First obtain exact FIR symbols to investigate the large Wasm bucket. Adapter
resource creation, allocation and UTF-8 work are secondary concrete targets;
React's own element/commit work is not the leading sampled cost. Any future
VIR/FIR comparison must align codecs and renderer options, not compare this
checked codec to VIR's approximately 70 ms direct-constructor prototype as if
only the backend changed. Style reuse remains a separate source candidate.

Harness checks: JavaScript syntax checks, callback-probe unit tests, copied
package SSR smoke, real full-FLT Chromium retention/output acceptance and offline
profile integrity checks. No new Lean source or whole-repository build is required.
