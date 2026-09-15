# Full FLT root preview: PR188 adoption

2026-09-15. The live FLT project now uses VBP `browser-pr188` and VIR
`36d26bc224f0c2a52cd586587b2c3e1b1ade70d6`, with the
[matched SDK and local Verso patch](BROWSER_PR188.md). The full
`FLTBlueprint.lean` root selects `CheckedJsonPreview.widget` with
`FLTBlueprint.FastPreview.panelProps`: checked JSON, structural fingerprints,
KaTeX, and the explicit demo clock. This previews the assembled document, not
just the root file's own prose. Existing FLT source edits were preserved.

## Comparable edit latency

Both campaigns edit root prose at `upstream formalization checkout.` using the
existing real-LSP/embedded-browser harness, production React, highlighting and
debug off. Each uses warm built dependencies, a fresh LSP/browser, one excluded
warmup, and three measured in-memory edits. No reference-index readiness gate
is used. The endpoint is the accepted version's DOM mutation, not VS Code paint.

| Measurement | Before: PR187 | After: PR188 |
| --- | ---: | ---: |
| Edit → accepted DOM, median | 3,316.1 ms | 4,401.6 ms |
| Range | 3,141.2–3,471.6 ms | 4,093.0–4,985.6 ms |
| RPC, median | 389.6 ms | 592.5 ms |
| Reply → accepted DOM, median | 2,922.5 ms | 3,804.7 ms |

No speedup is established: this comparison is **32.7% slower**. The small,
sequential, variable-load campaigns are a regression signal, not an isolated
attribution to VIR. VBP's notification accounting also changed. Phase medians
are calculated independently and need not sum to the total median.

Both return 6,594,619 JSON characters per measured edit. Decode and browser
rendering deserve priority over the small remaining server waits. The RPC
remainder also contains dispatcher waits, encoding, transport, and scheduling;
the server's internal timers do not measure all elaboration.
The subsequent [quick sampled profile](FLT_ROOT_QUICK_PROFILE.md) separates
interpreter and host-call costs without changing the runtime or wire contract.

## Complete observed edit bar

The debug-only bar partitions observed notification → content passive effect
into dispatch, snapshot wait, checked-environment wait, evaluation/focus lookup,
RPC remainder, decode, identity preparation, element construction, and remaining
React/effects/scheduling. It excludes physical keystroke → notification, startup,
and paint. Later cursor refreshes are explicitly labelled as RPC-only intervals.

A separate debug-on campaign checks all nine segments against the independently
exposed start/effect endpoints and the external edit/RPC timestamps. One actual
sample, the median bar total in that campaign:

| Phase | Time |
| --- | ---: |
| Notification → dispatch | 2.4 ms |
| Snapshot wait | 43.9 ms |
| Checked-environment wait | 32.2 ms |
| Evaluate / locate focus | 26.3 ms |
| RPC remainder | 575.3 ms |
| Decode | 1,475.9 ms |
| Identity preparation | 398.9 ms |
| React element construction | 2,660.9 ms |
| Remaining React/effects/scheduling | 489.5 ms |
| **Observed notification → content effect** | **5,705.3 ms** |

This is a diagnostic sample, not the debug-off comparison above. Debug-on/off
campaign variation prevents estimating instrumentation overhead by subtraction.
The content effect follows the first accepted DOM update by 359.5–427.5 ms in
this campaign; that delay is not a measurement of React's internal commit time.
Moving the harness's large post-DOM verification after a two-frame yield did
not eliminate it. No causal attribution to KaTeX or React is established.
A final one-edit boundary check explicitly asserts that the measured effect
precedes the harness's verification. It passes (including the warmup), with a
228.1 ms DOM-to-effect delay. This confirms that the gap can occur without that
verification inside the interval; it is not another performance cohort.

## Evidence and checks

Local evidence is under repository-root `_out/browser-pr188/`:

- `flt-root-before-fast/result.json`: PR187 comparison input.
- `flt-root-after-fast/result.json`: PR188 debug-off comparison.
- `flt-root-after-debug-isolated/result.json`: separate debug accounting run.
- `flt-root-debug-boundary-check/result.json`: verification starts after the effect.
- `flt-switch-before/source-and-config.tar.gz`: preserved pre-switch source/config.
- `adoption/flt-root-build.log`: successful SDK, preview module, and full root build
  (5,099 jobs); no claim about full-site generation or its existing label issues.
- `adoption/notification-session.json` and `notification-embedded.json`: thirteen
  runtime timing/correlation cases and real-RPC edit/cursor acceptance.
- `adoption/notification-string-rpc.json`: ordinary String-RPC acceptance,
  including stale-edit suppression, subscription cleanup, and retained controls.

Reports retain source, dependency, SDK, shell, harness, and dirty-diff identities.
The root source SHA-256 is
`e2d3a07251fe93f0659d1f8a16a14d5997b70f676b2e199ceb810e37e4a79f66`.
VBP starts at `715f8d15` plus the recorded timing changes; baseline is `01f8ec60`.
The failed `flt-root-before` attempt overlapped a user edit and is excluded.
The earlier `flt-root-after-debug` run allowed verification before the effect
and is retained for diagnosis, not used for phase attribution.

For interactive use, run **Lean: Restart Server** in the existing FLT VS Code
window, enable **Debug details**, and edit root prose. Leave highlighting off.
No FLT mathematical content, labels, or formalization files were changed by this
adoption. Generated evidence and SDK archives are local artifacts, not Git files.
