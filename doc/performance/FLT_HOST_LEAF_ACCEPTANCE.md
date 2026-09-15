# Full-FLT acceptance: callback-free host arguments

2026-09-15. Follow-up to the [callback census](FLT_HOST_CALLBACK_CENSUS.md).

Historical leaf-only acceptance. The revised reachability contract has its own
[successor acceptance](FLT_HOST_REACHABILITY_ACCEPTANCE.md); this report does
not qualify that changed callback-lifetime policy.

## Decision

The reviewed leaf fast path passes the full-FLT consumer checks. Its intended
hotspot shrinks substantially in a fresh browser profile: `callObjectsImpl`
self weight falls from 374 ms to 74 ms. The first normal-mode comparison improves
from 2.69 s to 2.39 s, but a much slower final control block prevents a reliable
overall speedup estimate. This supports the upstream mechanism, not a precise
percentage claim or adoption of a new SDK.

Only an isolated JavaScript bundle was changed. Live demo output, dependency
pins, Lean artifacts, SDK, Wasm, and producer worktree remain untouched.

## Exact boundary

Producer commit `8b3f96f746c64a1821d4bcba2077c6c0ca611d70` is based on
`41b00f5b556ed0977539d57871fa915e752b2a29` (Lean 4.33). FLT continues to use VIR
`36d26bc224f0c2a52cd586587b2c3e1b1ade70d6`, with its matched Lean 4.34.0-rc2 SDK.
The producer's pre-fix `runtime/host-state.js` is byte-identical to that SDK's
file. We substitute only the reviewed successor of this file; all its imports
still resolve within the pinned runtime. No 4.33 Lean/Wasm artifact is consumed.

| Artifact | SHA-256 |
| --- | --- |
| Base host-state source | `5c008097a38986b829416ed2f5598563363c6e8f82e0e077c56d078da93d4344` |
| Candidate host-state source | `e0312e31b111ef41eab3cace59615d1a41147c2aae758d811ac58dd6518c2881` |
| Control bundle (also the unchanged live bundle) | `a8d19c2c50208fca3d3708f10c6db5130f229a7dad10cf41928bc2d62d168111` |
| Candidate bundle | `da48ce2e52fda8089c1c14d3025533797b5b7c43087da046d7efff8efa30fb8b` |
| SDK manifest | `e77db750fd798a8e635b637e477e3d7b81a8ad86fa4656f2bd570d82680fbc88` |
| Release Wasm | `3644f76050031b59ae84bd9f36379b6865a8c12d2438a83722ccc0613a8e916f` |

The two bundle manifests differ in exactly one runtime source hash. VBP starts
at `d7158d7413adab3dddcf01191e330f2086275861` plus the retained qualification
harness changes; each capture records its tracked diff and driver hashes.

## Representative measurements

A prose edit at `upstream formalization checkout.` in `FLTBlueprint.lean`
refreshes the entire assembled FLT blueprint. Each block starts a fresh browser
and LSP worker over warm built dependencies, performs one excluded warmup, then
three measured in-memory edits. Order is control–candidate–candidate–control.
React production; highlighting, debug timing, census and sampling off. Host:
AMD Ryzen AI 9 HX 370, 24 logical CPUs.

The endpoint is harness edit submission to MutationObserver observation of the
accepted document version's DOM commit, **not VS Code keystroke-to-paint**.

| Block | Median total | Total range | Median reply-to-DOM |
| --- | ---: | ---: | ---: |
| Control 1 | 2689 ms | 2510–2846 ms | 2363 ms |
| Candidate 1 | 2394 ms | 2299–2676 ms | 2041 ms |
| Candidate 2 | 2384 ms | 2315–2578 ms | 2035 ms |
| Control 2 | 4158 ms | 3736–4577 ms | 3495 ms |

Order-paired block medians suggest reductions of 295 ms (11.0%) and 1774 ms
(42.7%), respectively. The final control's reply-to-DOM increases from 3152 to
3495 to 4233 ms; the cause is not established. Do not pool these observations
into a claimed speedup, discard the slow control, or attribute its drift to the
patch. This small campaign is consumer qualification plus exploratory timing.

Source SHA-256 stayed
`e2d3a07251fe93f0659d1f8a16a14d5997b70f676b2e199ceb810e37e4a79f66`.
Every campaign loaded the same single client package, SHA-256
`fc7d7b3137d81e0e1371c2cb1892fa2f9fc2d0c73a6d65b891864786293c2074`,
without warnings. Measured payload lengths are 6,594,618–6,594,619 characters;
payload byte equality was not measured. Server timing fields vary per response.

## Fresh attribution

Separate control/candidate captures each contain one measured edit after one
warmup. CPU sampling is enabled, debug/census disabled. These observations are
not headline timings. Release Wasm frames are resolved using the matched SDK's
unstripped Wasm after verifying identical executable sections; no unresolved
Wasm frames remain.

| Sampled weight | Control | Candidate |
| --- | ---: | ---: |
| Host dispatcher `callObjectsImpl`, self | 374 ms | 74 ms |
| Its self weight under React render callbacks (subset above) | 298 ms | 51 ms |
| Entire React render-callback stacks, inclusive | 1462 ms | 1254 ms |
| Interpreter dispatch/evaluation, self category | 630 ms | 651 ms |
| Symbol/constant/name lookup, self category | 238 ms | 211 ms |

The host-bridge reduction agrees with the proposed mechanism. Interpreter and
lookup work remain substantial. Caller groups are disjoint subdivisions of the
whole capture, not chronological phases; inclusive weights must not be added
to self weights. Capture scope also includes RPC idle and profiling controls.

The independent three-resource/56-root reproducer now observes zero registry
traversals and zero callback creation, versus six traversals/336 visits before.
Producer-reported lifecycle, composite, failure and reentry checks are separate
evidence; this consumer campaign does not repeat all producer unit tests.

A separate candidate debug run passes the nine-phase bar accounting and
effect-before-verification checks. Its bar ends at the passive effect, 280 ms
after the DOM endpoint in this capture, so its 2947 ms total must not be compared
directly with the harness's 2673 ms DOM total. It is not React internal commit
duration. No debug result is included in the normal-mode table.

## Reproduction and evidence

Local evidence root: repository-root `_out/browser-pr188/host-leaf-acceptance/`.
`control/` and `candidate/` hold exact bundles and identity sidecars;
`ab-control1/`, `ab-candidate1/`, `ab-candidate2/`, `ab-control2/` contain raw rows,
source/SDK identities, copied shell, driver and client package. Profiles are in
`control-profile/` and `candidate-profile/`, including original and symbolicated
CPU profiles, `profile-summary.json`, and caller-group SVG flamegraphs.
`candidate-debug/` and `producer-repro.json` hold the additional checks.

Build isolated bundles with `tests/vir_preview/build_checked_json_demo.mjs`:
set `VBP_DEMO_OUTPUT` to a new output path; for the candidate additionally set
`VBP_DEMO_HOST_STATE` to the producer's `web/src/runtime/host-state.js` and
`VBP_DEMO_HOST_STATE_SHA256` to the candidate hash above. The builder verifies
base SDK sources and refuses an override targeting the live output.

Run `node tests/vir_preview/latency_browser_smoke.mjs` with:

```sh
VBP_LATENCY_PROJECT=/home/egallego/lean/verso-blueprint/.worktrees/_reference-blueprints/edit/native-preview-modules/verso-flt
VBP_LATENCY_SOURCE=FLTBlueprint.lean
VBP_LATENCY_ANCHOR='upstream formalization checkout.'
VBP_LATENCY_METHOD=CheckedJsonPreview.Server.previewDocument
VBP_LATENCY_WIDGET=CheckedJsonPreview.widget
VBP_LATENCY_SAMPLES=3
VBP_LATENCY_SHELL=/home/egallego/lean/verso-blueprint/.worktrees/browser-pr188/.lake/build/checked-json-demo.js
```

Export those values; set `VBP_LATENCY_OUTPUT` to a fresh capture directory and
`VBP_LATENCY_SHELL_OVERRIDE` to the control/candidate bundle. Leave diagnostic
options unset. Both configurations use the same override mechanism. For the
separate profile or debug capture use one measured sample and set only
`VBP_LATENCY_SAMPLING=1` or `VBP_LATENCY_DEBUG=1`, respectively.

Qualification is limited to this exact JS delta on the pinned 4.34 consumer.
A future matched SDK/pin update remains a separate integration step.
