# Matched widget refresh on Lean 4.34

## Current timed-view refresh

The current paired demo uses the source-built `DirectCodecProbe` retained timed
view on VIR and immutable FIR package `58c676728ace1b0c3b0721fa`. Both use the
checked browser JSON codec and the same VBP `3839f92f` / VIR `cddcc35a` source
snapshot, identity `6c7b96d8afaed7798c9af86c72315f77a1f88a3ddcde4ea2ac11190044b40a94`.
FIR Wasm SHA256 is `f734de1aba28097bd009427e92bd00b78cdc79b5550f32759c1f633dcf9cb7d8`;
SHA256SUMS hash is `1ce76db7a0d7b356e2bd5b90a4ef546cefbf8e0e72f842f19ea927215c0a1a18`.

Rebuild each bundle with `VBP_DEMO_TIMED_CHECKED=1`, plus the backend-specific
input: `VBP_MATCHED_IR_SET=.lake/build/vir/module-sets/VersoBlueprintVirTests/NativeSession/DirectCodecProbe.irpkg-set.json`
for VIR, or `VBP_MATCHED_FIR_PACKAGE` pointing to the delivered `timed-6c7b96d8/packages/58c676728ace1b0c3b0721fa`
for FIR. Use the ordinary `build_checked_json_demo.mjs` command and
`.lake/build/matched-{vir,fir}-demo.js` output, then rebuild `MatchedPreview`.
Prior working generated bundles are preserved locally under
`.deps/pre-timed-demo-bundles`; the previous producer package is not modified.

Both backends pass the copied FIR SSR smoke / shared registered-widget checks
as applicable. Evidence: `_out/matched-demo-v434/{vir,fir}-timed-widget.json`.
The bar covers notification dispatch, snapshot/check waits, document evaluation,
remaining RPC time, reply-to-decoded endpoint, identity preparation, element
construction and content-effect observation. The last two boundary names do
not claim isolated React commit duration or completed paint. Cursor/control
updates retain the explicitly versioned last edit measurement.

The browser harness selects the backend only in its open-buffer source; it
does not rewrite the user's file or backend selection. Full-FLT widgets also
pass edit/control/cursor and retained-bar checks without React warnings;
evidence is `_out/matched-demo-v434/flt-{vir,fir}-timed-widget.json`. These
concurrent, debug-enabled acceptance runs are not backend speed measurements.
The paired browser replay results are recorded immediately below. The earlier sections
below retain the previous package/interpreter and direct-decoder experiments;
their commands are historical, not the current paired-demo configuration.

### Paired checked-codec replay

Fresh retained sessions ran sequentially in VIR–FIR–FIR–VIR order, using the
same authenticated 6,598,356-byte full-FLT response. Each session mounts once,
disables follow-cursor, retains an unchanged paragraph/control, then performs
two warm-up and six measured edits. React is production mode in Google Chrome
153.0.8010.36; highlighting, debug, string-intern experiments, host timers and
CPU sampling are disabled. Both backends invoke the shared timed view with
optional client timing inputs absent; normal rendering does not collect debug
samples. Codec/factory validation and setup are outside the measured boundary.

Arithmetic means over twelve measured updates per backend:

| Browser phase | VIR | FIR |
| --- | ---: | ---: |
| JavaScript JSON parse | 26 ms | 22 ms |
| Checked graph → Lean.Json → typed Preview | 1,658 ms | 1,474 ms |
| Decoded document → DOM observation | 2,450 ms | 1,865 ms |
| Total measured browser update | 4,134 ms | 3,360 ms |

The decoded-document phase includes identity preparation, element construction
and React reconciliation/DOM update; its endpoint is a MutationObserver, not
completed paint or an isolated React commit timer. RPC/LSP, server encoding,
elaboration, startup and passive-effect waiting are excluded. The physical
backend adapters differ by necessity; this is a runtime-plus-adapter comparison,
not isolated compiled-IR throughput. No comparison with older absolute timings
is claimed.

Per-session render means are 2,448 / 1,861 / 1,868 / 2,452 ms in run order.
FIR reduces that phase by 24.0% and 23.8% in the two pairs, respectively; total
reductions are 17.5% and 19.9% (18.7% pooled). Checked decoding improvements
are smaller and noisier (8.0% and 14.2% paired). Individual render ranges are
2,184–2,900 ms for VIR and 1,670–2,081 ms for FIR. These are two sessions per
backend, not a universal backend performance claim.

All four runs preserve the same normalized text and exact article DOM hash
`a9e9a56c67368a62745096dce9cbc06855793cdd79f912a78f201baa758769d9`,
7,011 total elements, retained controls and paragraph, and zero React warnings.
Only edit-marker/version metadata is normalized. Input, SDK, descriptor and
codec-binding hashes match across the runs.

Raw results/identities/source copies are under repository-root
`_out/matched-demo-v434/timed-pair-{vir-a1,fir-b1,fir-b2,vir-a2}/`.
`timed-pair-summary.json` in the same parent preserves the batch means, every
measured sample, paired deltas, identity checks and exclusions. Replay uses
`VBP_REPLAY_TYPED_PACKAGE=1 VBP_REPLAY_TIMED_VIEW=1 VBP_REPLAY_RENDER=1`
with `VBP_REPLAY_UPDATES=6`, the current DirectCodecProbe package-set descriptor,
and the delivered FIR package path only for FIR runs.

The isolated `feat/matched-demo-v434` checkpoint refreshes the shared upstream
ProofWidgets shell and interpreter to VIR `cddcc35a46fd4683d2437369072d4ecc5a5a84be`.
Lean remains `leanprover/lean4:v4.34.0-rc2`; the matching clean SDK manifest has
SHA256 `1556758818bb2fa72d237d9ca9dd91614b8e3c68bfb45af43a4481e67e78ba76`.

Both backends share `matched_document_component.mjs`: one native React
component receives the checked server Document JSON string, memoizes parsing
and runtime-local decoding by that string, and invokes the retained default
Lean view. RPC/editor subscription, cancellation, package loading and shell
lifetime remain upstream-owned. The selected external runtime is disposed
after the shell runtime, including failed-open cleanup.

A subtle sticky top-right label identifies the selected VIR/FIR renderer,
independently of debug mode. The shared wrapper forwards native RPC timestamps
separately from document decoding and memoizes the decoded endpoint across
control renders. An unchanged document with new RPC timestamps is not decoded
again, but receives a fresh endpoint timestamp.

The ESM bundle redirects `react-dom/client` to the ProofWidgets `react-dom`
entry, including imports already embedded in the frozen FIR provider bundle.
Bundling rejects external imports outside `react`, `react-dom` and
`@leanprover/infoview`. The IIFE Chromium harness can otherwise resolve a
subpath that the VS Code import map does not provide.

VIR uses the frozen `styles-baseline-ir/DecodeProbe.irpkg-set.json` from the
earlier paired campaign, verifying every member hash and length. FIR uses
immutable package `23dfd8ab282aa8b5b0b7d90b`, SHA256SUMS hash
`d6d33302cca5bd9aeba5bcbb19866d7f3bbe6f6648ec62c699833fce2a5aa122`.
All author-side provider source hashes and React lock identities are checked
against the refreshed dependency before bundling. This preserves the paired
renderer baseline while changing the VIR interpreter separately.

## Local rebuild

Install the exact SDK with the ordinary `:virSdk` facet and explicit
`VIR_SDK_ARCHIVE` / `VIR_SDK_EXPECT_COMMIT`. Then generate both bundles:

```sh
VBP_DEMO_MATCHED_BACKEND=vir \
VBP_MATCHED_IR_SET=/home/egallego/lean/verso-blueprint/_out/upstream-vir-20260917/styles-baseline-ir/DecodeProbe.irpkg-set.json \
VBP_DEMO_OUTPUT=.lake/build/matched-vir-demo.js \
node tests/vir_preview/build_checked_json_demo.mjs

VBP_DEMO_MATCHED_BACKEND=fir \
VBP_MATCHED_FIR_PACKAGE=/home/egallego/lean/fir/.worktrees/wasm-generation-4.34/.deps/native-session-probe/configured-bc9685f9/packages/23dfd8ab282aa8b5b0b7d90b \
VBP_DEMO_OUTPUT=.lake/build/matched-fir-demo.js \
node tests/vir_preview/build_checked_json_demo.mjs

scripts/lean-low-priority lake build +MatchedPreview:olean +MatchedPreview.Server:olean
node --test tests/vir_preview/demo_shell.test.mjs
```

The `MatchedPreview` library declares both embedded bundles with Lake `needs`.
The FIR package is copied and checksummed under `.deps/matched-fir-package`;
producer artifacts and existing live pins are untouched.

## Experimental direct-decoder/timing mode

The current VIR demo can instead use the latest source-built direct converter
with bounded string reuse and UTF-8/pointer scratch buffers. This is deliberately
**not a matched FIR comparison**: FIR retains its immutable checked-decoder
package and older compiled timing UI. Its backend label is shared and qualified;
the new Lean timing UI needs a new FIR package before adoption there.

```sh
LAKE_RESTORE_ARTIFACTS=true scripts/lean-low-priority lake build \
  +VersoBlueprintVirTests.NativeSession.DirectCodecProbe:vir
VBP_DEMO_MATCHED_BACKEND=vir VBP_DEMO_DIRECT_TYPED=1 \
VBP_MATCHED_IR_SET=.lake/build/vir/module-sets/VersoBlueprintVirTests/NativeSession/DirectCodecProbe.irpkg-set.json \
VBP_DEMO_OUTPUT=.lake/build/matched-vir-demo.js \
node tests/vir_preview/build_checked_json_demo.mjs
scripts/lean-low-priority lake build +MatchedPreview:olean
```

In this mode, debug shows the last completed edit/version measurement and its
editor version. Cursor replies, control changes and pending/error observations
update current status without replacing that bar. Before the first edit it
shows an explicitly labeled initial measurement. The bar partitions notification
dispatch, snapshot/check waits, evaluation/focus, RPC remainder, decode,
identity preparation, element construction and React/effect observation.
The browser endpoint is a passive content effect, not paint or React internal
commit duration. The demo-only clock uses `performance.now()` at coarse boundaries.

Fresh full-FLT replay on the same cddcc35a SDK, package set and authenticated
input used checked/direct/direct/checked order, two warmups and six measured
updates per browser session. Debug/highlighting and profiling were off.

| Browser phase (mean) | Checked | Direct |
| --- | ---: | ---: |
| JSON.parse | 17.2 ms | 13.3 ms |
| Typed conversion/decoding | 921.3 ms | 50.5 ms |
| Parse + decode | 938.5 ms | 63.8 ms |
| Decoded value → observed DOM | 1,446.2 ms | 1,116.7 ms |
| Browser total | 2,384.7 ms | 1,180.5 ms |

Parse/decode is 93.2% lower in this replay. Rendering was unchanged and noisy:
checked batch means were 1,282/1,610 ms versus direct 1,114/1,119 ms, so the
rendering difference is not evidence of a rendering optimization. These numbers
exclude server/LSP, encoding, transport, startup, passive effects and paint.
The earlier ~352 ms direct-decoder report did not include this complete scratch
configuration; the transitional ~70 ms report was a different implementation.

Raw identities, rows and DOM checks are at repository-root
`_out/matched-demo-v434/direct-refresh-{b01,c02,c03,b02}/`.
All four runs have identical response, SDK Wasm and package-set hashes and
the same normalized 7,011-element DOM. The first screening run `c01` is excluded
from this aggregate. Live fixture gates are `vir-edit-bar-refresh.json`,
`fir-backend-label-refresh.json` and `session-timing-refresh.json` in that directory.
The RPC harness emits its synthetic edit notification after waiting for server
diagnostics, so its bar is a lifecycle/accounting check, not keystroke latency.
External FLT acceptance starts Lake in the FLT project, not the VBP package root.

The assembled FLT widget also passes: registered shell, retained controls/bar,
one client package, three preview RPCs and no React warnings. Its single
debug-enabled observation (`flt-edit-bar-refresh.json`) is a different workload
from the frozen debug-off replay above:

| Live full-FLT notification → content effect | Time |
| --- | ---: |
| Dispatch + snapshot/check waits | 2.2 ms |
| Evaluate / locate focus | 15.0 ms |
| Encode / transport / scheduling remainder | 427.0 ms |
| Reply → decoded / scheduling | 116.7 ms |
| Identity preparation | 384.7 ms |
| Build React elements | 2,723.6 ms |
| React / effects / scheduling | 267.4 ms |
| Total | 3,936.5 ms |

This is functional timing-bar evidence, not a repeated latency benchmark or a
comparison with FIR. The synthetic notification starts after server diagnostics;
earlier elaboration is excluded. Restart the Lean server in the existing VS Code
demo to load the rebuilt embedded widget and its new clock-bearing client root.

## Shared FIR timing-view request and rendering attribution

FIR request `VBP-FIR-20260917-001` is delivered to its integration owner.
It requests `DirectCodecProbe.browserParsed`, `createTimedView` and
`renderTimedDecoded` from clean VBP `3839f92f` and the same cddcc35a/4.34-rc2
dependency closure. The complete 2,592-file source snapshot is retained under
repository-root `_out/matched-demo-v434/timed-fir-source/`:

- Source identity: `6c7b96d8afaed7798c9af86c72315f77a1f88a3ddcde4ea2ac11190044b40a94`.
- Archive SHA256: `4654b3d357fc8ecc8247ee65b0f64a2b74eb7e5ca9b7a808e8e20e7aa36b9ae7`.

Producer handoff and shared consumer qualification are pending. This request
keeps checked decoding on both backends for the next differential experiment;
it does not request a FIR port of the experimental raw-object converter.
Existing packages and live pins remain unchanged.

The VIR counterpart can already bundle the same source-built timed view while
using checked decoding (`VBP_DEMO_TIMED_CHECKED=1`, instead of
`VBP_DEMO_DIRECT_TYPED=1`). The selected package-set descriptor is still the
current `DirectCodecProbe`; this selects its `browserParsed` export, not the
direct converter. The prepared alternate bundle is
`.lake/build/matched-vir-timed-checked.js`, leaving the active fast VIR bundle
untouched. Bundling/import-map checks pass; shared live qualification waits for
the new FIR package and does not follow from bundling alone.

A fresh VIR sampled attribution capture is retained at
`_out/matched-demo-v434/render-profile-next/`. It uses the same authenticated
full-FLT response and source-built package as the direct replay, production
React, debug/highlighting off, two warmups and four measured retained updates.
This sampled run is not a new uninstrumented timing result. CDP main-thread
sampling is 1 ms, with bracketed clock calibration (0.334 ms uncertainty).
Intervals are weighted/clipped to the four recorded decode/render windows.

| Render-window self-time category | Sample share |
| --- | ---: |
| Interpreter dispatch/evaluation | 41.4% |
| Symbol/constant/name lookup | 15.2% |
| Allocation/refcount/vector storage | 6.8% |
| Other Wasm | 13.8% |
| JavaScript/browser | 22.7% |

These are disjoint self-time buckets over 5,530 ms of sampled render windows,
not contributions to the live 3.94 s sample. Host-dispatch inclusive time is
19.0%; it overlaps those buckets and must not be added. `commitRoot` inclusive
share is 0.46%, not paint or all React overhead. Raw and symbolicated profiles,
clock trials, package/input/source identities and `profile-summary.json` are
retained together. All 7,503 Wasm frames resolve; release/development SDK
non-custom sections match exactly before names are borrowed.

Source inspection confirms renderer styles are already constructed once per
component. Block/list/part props still use individual native property writes,
including identity/debug attributes. This is a candidate for the existing VIR
native-array/props review, not evidence that a particular write dominates.
The current shim already applies closures through the persistent interpreter;
lookup samples do not establish cache misses or reproduce the earlier temporary
closure-context issue. Representative feedback was sent once to the existing
VIR construction owner; no competing prototype or runtime change was started.

## Acceptance and demo

Both registered widgets pass real LSP/Chromium initial rendering, edit
notification, unchanged-props and cursor-update checks. Controls retain DOM
identity/state; the client package is built once, with one editor subscription
and listener, and no React warnings. Evidence is under
`_out/matched-demo-v434/{vir,fir}-widget.json` at the repository root.

The small fixture is `VersoBlueprintVirTests/MatchedPreviewServer.lean`.
Select its `useFir` boolean before running `native_browser_smoke.mjs` with
`VBP_NATIVE_MATCHED_BACKEND=vir|fir` and `--embedded-preview`; the registered
shell hash must match that backend. Set `VBP_NATIVE_PREVIEW_REPORT` to an
isolated output and run through `scripts/lean-low-priority lake env node`.

The independent FLT checkout is
`.worktrees/_reference-blueprints/edit/matched-demo-v434/verso-flt/`.
Open `FLTBlueprintMatchedDemo.lean`; its startup boolean selects VIR or FIR.
The unchanged full FLT root document is included by the module-system wrapper.
The checkout's `MATCHED_PREVIEW.md` explains use and the warmed Mathlib source
reuse. No previous FLT demo is retargeted.

The complete FLT wrapper also passes the same registered-widget, edit and
retained-control checks on both backends, with no React warnings. Reports are
`_out/matched-demo-v434/flt-{vir,fir}-widget.json`. These are real LSP/Chromium
checks, not automated VS Code acceptance.

Math is source-display mode on both backends; no optional native-math acceptance
is claimed. Debug timings cover server preparation only. These acceptance runs
do not replace the order-balanced performance campaign or establish new speed
numbers on the refreshed interpreter.
