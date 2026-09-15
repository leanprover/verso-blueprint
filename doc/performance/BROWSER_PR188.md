# PR188 integration and preview timing cleanup

## Exact setup

- Lean: `leanprover/lean4:v4.34.0-rc2`.
- VIR: `36d26bc224f0c2a52cd586587b2c3e1b1ade70d6`, the six-file 4.34 overlay on
  committed PR188 source `37904929b9affc1fb5a709918bc7ebbafb82a87a`.
- SDK SHA-256: `6711afbc9065a0c7bab3a8bc3ada26a8097fe9c555cb466bf16d8a930e6a2660`.
- Verso: `52c8c9557bcb5cc8c0edc0ee37e74311a3d53ee9`, with the explicit local
  [list-source-range patch](../../tests/vir_preview/patches/README.md).

The source/SDK pair matches the completed upstream handoff
`ROOT-VIR-PR188-434-COMPLETE-20260915-001`. This remains a **local-only** dependency
recipe. It does not cover the producer's subsequent uncommitted work.
The ordinary String decoder remains the default; the explicit checked-JSON,
clock, and math demo seams are unchanged. This base does not provide the requested
public browser clock or checked-JSON decoder.

The isolated `browser-pr188` worktree starts at VBP checkpoint `01f8ec60`.
The prior `browser-pr187` worktree, running FLT demo, and user edits are preserved.
Retained inputs and evidence live under repository-root
`_out/browser-pr188/adoption/`, including a copy of the matched SDK archive.

## Changes

PR188 accepts native child arrays directly and removes JSX spread of Lean arrays.
Rendering now explicitly converts existing Lean traversal results at that boundary;
it does not add an adapter layer or change the document representation. Dynamic
preview controls have stable React keys. Renderer assertions use React's own
`Children.forEach`, which handles nested child arrays without assuming flat props.

The debug timing bar now:

- distinguishes **RPC server only** from **RPC to content passive effect**;
- calls the server phases **Snapshot wait**, **Checks wait**, and
  **Evaluate / locate focus**, rather than implying total elaboration time;
- pairs browser observations with the exact accepted response timestamps, not
  just editor version/cursor (which can repeat across requests);
- derives total elapsed time from request/effect endpoints and checks that the
  phase estimates fit before calculating residuals;
- rejects negative, non-finite, out-of-range, reversed, or overlapping timing
  samples and explicitly labels invalid browser data instead of silently hiding it.

No new per-node instrumentation, polling, or server serialization is introduced.
These are accounting fixes, not a measured speedup.

## Why server numbers can look too small

The timer starts **inside the preview RPC handler**. Lean's RPC dispatcher has
already waited for imports and located the registered procedure's snapshot before
calling it. The handler then waits for the document's end snapshot and checked
environment. These measure remaining waits, including scheduling, not the complete
document's elaboration or compiler CPU time. If those environments are ready, the
waits can be nearly zero even for the complete FLT blueprint.

A cursor move sends another RPC; its accepted timings replace the edit request's
timings. The bar is a latest-request view, not a retained last-edit profile.
Earlier edit/server work, encoding, and transport are absent from the server-only
bar. With the demo clock, the RPC remainder includes dispatcher setup as well as
encoding, transport, and scheduling. Its attribution cannot be made more precise
from these boundaries alone. Even the complete bar excludes edit-to-request,
startup, and paint. Use the external edit harness for integral latency.

## Validation

Use the existing scripts with the retained archive; no new harness is required:

```sh
export VIR_SDK_ARCHIVE=/absolute/path/to/_out/browser-pr188/adoption/lean-vir-sdk.tar.gz
export VBP_RENDERER_REPORT_DIR=/absolute/path/to/_out/browser-pr188/renderer
export VBP_NATIVE_SESSION_REPORT=/absolute/path/to/_out/browser-pr188/session.json
npm --prefix .lake/packages/lean_vir ci --no-audit --no-fund
scripts/test-verso-react.sh
scripts/test-vir-native-session.sh
VBP_NATIVE_PREVIEW_REPORT=/absolute/path/to/_out/browser-pr188/embedded.json scripts/test-vir-preview-widget.sh
VBP_NATIVE_PREVIEW_REPORT=/absolute/path/to/_out/browser-pr188/string-rpc.json scripts/test-vir-native-preview.sh --string-preview
```

Session acceptance includes eleven timing/correlation cases executed by the actual
Wasm runtime, retained controls, scales, missing/zero timings, and React StrictMode.
The embedded gate exercises the registered shell and real Lean RPC, math, list
cursor positions, edits, and the full eight-phase bar. Neither is a whole-FLT
latency measurement or a VS Code paint test. Historical chapter timings in
`BROWSER_PR187.md` must not be relabeled as whole-FLT or PR188 measurements.

Completed on 2026-09-15: renderer SSR, StrictMode session, embedded real-RPC demo,
and ordinary String-RPC gates pass. Session and embedded gates report zero React
warnings. Reports are `renderer-fixed/renderer-acceptance.json`,
`session-fixed.json`, `embedded-fixed.json`, and `string-rpc.json` under the evidence
directory above. Targeted Lean builds (including the decoding probe) and nine
profiling-helper tests also pass. Earlier failing logs are retained: they caught
the missing control keys and the test walker's flat-children assumption. No
whole-FLT benchmark or live VS Code retarget was performed in this slice.
