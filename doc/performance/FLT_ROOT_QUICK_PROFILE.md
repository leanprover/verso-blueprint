# Full-root browser attribution before FIR

2026-09-15. One sampled prose edit in `FLTBlueprint.lean`, after one excluded
warmup, using the current checked-JSON/KaTeX preview. Debug and highlighting are
off. VBP `c2e9288f`, VIR `36d26bc2`, matched SDK and Lean 4.34.0-rc2 as in the
[adoption report](FLT_ROOT_PR188.md). No runtime, codec, or protocol changes.

The measured edit → accepted DOM interval is 2,954.1 ms, including a 343.1 ms
RPC and 2,604.9 ms reply → DOM interval. This is **one instrumented observation**,
not a new speedup measurement or a comparison with the earlier three-edit runs.
The user has edited the root since those runs; the current source stayed stable
during this capture. The reply has 6,594,620 characters / 6,596,187 UTF-8 bytes.

## Findings

The `previewDemo.parse` wrapper, whose body checks for a String and calls native
`JSON.parse`, receives about **15.9 ms of sample weight**. Decoding is not just
parsing those bytes. The current path is:

```text
JSON.parse → check the ordinary JS graph → copy into Lean.Json → FromJson Preview
```

`JsonValue.fromJs` validates the whole graph, then `readChecked` recursively calls
`jsonValue.inspect` and constructs Lean JSON nodes. `fromJson?` constructs the
typed document afterward. Object descriptor inspection occurs in both the check
and copy paths. These are actual implementation stages, not estimates of their
individual cost. No checks were removed.

The React render-call subtree contains 1,538.7 ms of sampled weight, including
the Lean renderer and preparation work called under `renderWithHooks`:

| Disjoint self-time bucket within that subtree | Sample weight |
| --- | ---: |
| Interpreter dispatch/evaluation | 456.5 ms |
| Symbol/constant cache lookup | 194.3 ms |
| `callObjectsImpl` host-call bridge | 301.3 ms |
| `readObjectArgv` | 73.9 ms |
| Everything else | 512.8 ms |

The enclosing host-call bridge subtree is 570.8 ms, **including** its 301.3 ms
self weight; do not add these numbers. This is not pure React reconciliation or
an exact timer around our element-construction function. The interpreter's
generic C++ frames also do not identify individual interpreted Lean declarations.

Source inspection of the pinned bridge shows binding lookup, argument lifting,
callback-set snapshots per argument, transaction handling, and result lowering
on each call. Those checks preserve lifetime/error semantics, but their repeated
cost is a concrete investigation target. FIR may remove much of the interpreter
work; it does not by itself establish that shared JavaScript bridge work goes away.
The [follow-up callback census](FLT_HOST_CALLBACK_CENSUS.md) quantifies that
bookkeeping and records a callback-free leaf-type optimization candidate.

**Conclusion:** payload size implies real traversal/copying work, but the current
decode/render times are not demonstrated lower bounds. Keep the format and wire
contract unchanged for the first FIR comparison. Compare the same payload and
features, then revisit host-call bookkeeping and conversion passes if still hot.

The server RPC remainder in this observation is 298.8 ms. It still combines
dispatcher waits, encoding, transport, and scheduling. The native capture includes
background Lean work through the browser update; its whole-process self profile
does not isolate encoding, so no encoding optimization claim is made here.

## Retained evidence

Repository-root `_out/browser-pr188/flt-root-quick-profile/` contains the original
CDP profile, symbolicated profile, sampled folded stacks/SVGs, native perf data,
source/dependency/harness identities, result, and exact captured response.

- `browser.symbolicated.cpuprofile`: load in Chromium's Performance panel.
- `live-edit.svg`: whole browser capture, **aggregated stacks**, not a timeline.
- `react-render-callbacks.svg`: stacks under `renderWithHooks`.
- `profile-summary.json`: self/inclusive weights and disjoint caller groups.
- `response.json`: immutable input for a later matched FIR replay.

CDP samples at 1 ms. All 3,667 WASM frame entries resolve using the SDK's matching
unstripped name section; release and unstripped executable sections are identical.
The surrounding capture has 3,220.9 ms sample weight, including RPC idle and
capture-control overhead outside the measured edit interval. Caller groups
subdivide that capture; they are not temporal decode/render intervals.

Reproduce the offline summary (no benchmark or runtime modification):

```sh
node tests/vir_preview/summarize_replay_profile.mjs \
  /absolute/path/to/_out/browser-pr188/flt-root-quick-profile \
  /absolute/path/to/flamegraph.pl --live
```

The existing latency harness produced the capture with `VBP_LATENCY_SAMPLING=1`,
`VBP_LATENCY_SAMPLES=1`, and `VBP_LATENCY_CAPTURE_RESPONSE=1`, root source
`FLTBlueprint.lean`, anchor `upstream formalization checkout.`, and the checked
demo shell/method/widget. Exact values are retained in `identity.json` and
`driver.mjs`. Root source SHA-256:
`0af0625166a378879f58d7bbf9ce62e3a548e2132b1b5549a5c8de30e4fa446e`.
