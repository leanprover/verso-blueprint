# Callback tracking in the pinned VIR host bridge

2026-09-15. Follow-up to the [full-root sampled profile](FLT_ROOT_QUICK_PROFILE.md).
This investigation changes only diagnostic harness code. The live demo, pinned
VIR source/SDK, runtime checks, and callback cleanup remain unchanged.

## Result

One full-root FLT prose edit performs **477,017 argument snapshots**, copying
**25,977,598 existing callback-root entries**. The bridge subsequently scans the
live set again to discover new roots; the entry count above counts copies only.
The largest observed live set contains 58 roots.

Only **17 argument lifts** add callbacks: 14 function arguments add 14 roots,
and three structure arguments add six roots. The other **477,000 lifts** add none.

| Argument kind | Lifts | Entries copied | New roots tracked |
| --- | ---: | ---: | ---: |
| Existing JS resource | 340,832 | 18,352,323 | 0 |
| Lean String | 136,158 | 7,623,961 | 0 |
| Nat / Bool | 10 | 510 | 0 |
| Function | 14 | 661 | 14 |
| Structure | 3 | 143 | 6 |

The biggest targets are `js.object.set` (189,084 arguments), `js.string`
(136,158), `jsonValue.inspect` (73,162), `js.array.push` (41,518), and
`react.node.createElement` (21,045). These are **argument counts, not host-call
counts**; a call can have several arguments. The census covers both decoding
and rendering through the accepted DOM update.

## Why this tracking exists, and a bounded candidate

The bridge snapshots `runtime.liveCallbacks` before lifting each argument and
collects new roots in `finally`. If a later argument, host binding, or result
conversion fails, the outer catch releases those newly lifted callbacks.
Removing this tracking indiscriminately would break failure cleanup.

However, pinned `liftObjectValue` returns an existing resource for `RESOURCE`,
and reads a scalar/string for the corresponding primitive tags. Those branches
do not create callbacks. `FUNCTION` calls `liftObjectFunction`, which roots a
new callback. Composite types recurse and can contain functions.

The smallest upstream candidate is therefore:

- Classify known callback-free leaf argument types from the existing descriptors.
  No special cases for Blueprint, React, JSON, or target names.
- Skip the snapshot/scan only for those leaves. Keep the current path for
  functions, all composites, and unknown types. A recursive classifier is not
  needed for this first slice.
- Preserve the per-call accumulated callback set and outer failure cleanup:
  a callback created by an earlier argument still needs release if a later
  callback-free argument fails. Keep host-call transactions/reentry unchanged.
- Validate nested function arguments, partial lifting failure, host exceptions,
  result-lowering failure, and successful callback retention before adoption.

An existing JS function passed as a `RESOURCE` is not a newly rooted Lean
callback. Likewise, callbacks created by invoking a host binding belong to a
different stage from argument lifting; this candidate does not change it.

This targets work shared by any backend that uses this bridge. FIR's actual
benefit still requires measurement; it is not assumed to erase JavaScript costs.

## Mechanism check, not a widget speedup

A separate Node check invokes the **unchanged** pinned `VirHostState` with mocked
lifting/lowering and a three-argument host function. It changes only the number
of retained roots: zero versus 56. Each run makes 20,000 calls; three warmups per
configuration precede six alternating-order pairs.

| Retained roots | Range across six runs |
| --- | ---: |
| 0 | 8.75–12.46 ms |
| 56 | 31.30–41.75 ms |

The populated-set path is about 3.3–3.6× slower in this mechanism check. It
demonstrates a real cost of unrelated retained roots. It **does not predict a
widget speedup**, measure Wasm conversion, or assign all the earlier 301 ms
bridge self weight to these snapshots. No optimized implementation was tested.

## Evidence and validation

Local evidence under repository-root `_out/browser-pr188/`:

- `flt-root-host-census/`: original result and identities, copied diagnostic
  shell/probe, plus `bridge-mechanism.mjs` and its raw `bridge-mechanism.json`.
- `flt-root-host-census-control/`: ordinary path succeeds with the census off;
  one package, no warnings, and no census fields in either warmup or measured row.

VBP starts at `15e6c378` plus the retained diagnostic harness changes; VIR is
`36d26bc2`, Lean 4.34.0-rc2. The diagnostic shell preserves the original snapshot,
scan, and cleanup code and only inserts counters around it. Its elapsed times
are not normal-mode performance evidence. Six probe tests and JS syntax/diff
checks pass. The normal control is regression validation, not a candidate timing.

The root file stayed unchanged within both campaigns, SHA-256
`e2d3a07251fe93f0659d1f8a16a14d5997b70f676b2e199ceb810e37e4a79f66`.
It differs from the preceding sampled capture because of intervening user edits.
Source/SDK/manifest, diagnostic shell, and probe identities are retained.

Select the census with `VBP_LATENCY_HOST_CENSUS=1` in the existing latency harness;
do not combine it with CPU sampling, response probes, React profiling, or debug
timing. No producer writes, pin changes, upstream messages, or publication were
made. The next step is a reviewed upstream candidate and matched full-FLT A/B.
