# FIR-compiled preview baseline

This fork prepared the FIR renderer bridge acceptance and now owns later FIR
optimization. The existing VIR widget-backend owner coordinates integration of
both backends and runs the differential experiments, so their inputs and timing
boundaries have one owner. This fork will not run a competing comparison campaign.
It does not own Verso finalization changes or the other fork's VIR optimizations.
FIR's renderer-only source-to-Wasm result is accepted. The title-only host
fixture now passes real React SSR and Chromium consumer checks; full-document
input and performance remain unmeasured. The full widget is not yet compiled/validated.

## Current slice (2026-09-15)

### Real React consumer acceptance

The user authorized proceeding without waiting for the host-exception fix.
Consumer tests use the immutable adapter from
`0c2eaa623640067406099afa9cef33e242c4136b` and its separate 1,406,967-byte
experimental Wasm (SHA-256
`8729a670b5ba9c4f233cb5c7ca27b05c5f0658c8e9a764cee4a524182caf11e7`).
The runner extracts the adapter from that Git object, verifies the Wasm hash,
and verifies the pinned VIR SDK JavaScript hashes before consumption. It does
not use moving producer JavaScript or rebuild anything in FIR/VIR.

`tests/vir_preview/fir_renderer_smoke.mjs` reuses the pinned VIR host bindings
and generic Chromium driver. With React 19.2.7, checks pass for:

- Real SSR output, Unicode, escaped script-like title text, and version/correlation metadata.
- Twenty changed title renders in one browser React root and one FIR session,
  retaining the article and heading DOM objects, plus an unchanged render.
- Retained Lean callbacks after renders; completed React unmount before
  disposal; rejected renderer and callback calls after disposal.
- No browser React warnings. The test uses a StrictMode wrapper but does not
  claim Lean component hook/effect coverage: this entry returns document nodes.

The fixture constructs an otherwise empty document in Lean. It cannot yet test
body blocks, external markup/details state, full preview controls, or RPC.
This is a correctness result, not a timing comparison or complete preview acceptance.
Ordinary host failure recovery remains upstream work and is deliberately not
part of this happy-path gate.

Repeat locally from this worktree:

```sh
node tests/vir_preview/fir_renderer_smoke.mjs \
  /home/egallego/lean/fir/.worktrees/wasm-generation-4.34 \
  /home/egallego/lean/verso-blueprint/.worktrees/native-preview-vir-refresh \
  /home/egallego/lean/verso-blueprint/_out/fir-preview-baseline/renderer-host
```

The final argument receives `acceptance.json`, frozen adapter/Wasm/import
inventory, and test bundles. The runner fails on a changed producer Wasm rather
than silently adopting a successor. The next requested producer entry accepts
the existing `Document.encode` JSON string, calls `Document.decode` in compiled
Lean, then the same `Renderer.render` with default options. No general
Document/Options marshaller or duplicate JavaScript schema is needed. The full
RPC payload is `Preview`, not `Document`; this first entry is renderer-only.

### Producer and ownership background

FIR narrowed the first target to the actual
`VersoBlueprint.Experimental.VirPreview.Renderer.render`, excluding the
NativeSession hooks/state and StringPreview RPC paths. Root accepted clean
`655ee20266e86cdb0210a7cc1ef7cff8ff9bb345` in
`ROOT-W7-20260915-038`: deterministic Node-valid Wasm, twelve intentional VIR
function imports, zero memory/native/runtime-operation imports. This is
structural validation, not browser execution or a full FIR 4.34 migration.

The renderer artifact is 1,388,311 bytes, SHA-256
`4fe536beab3f476496f1f63750b774fb2d65b20d1f2f73d954577b1a87a83dc5`.
Its frontier includes `Callback.ofUnary`; callback behavior cannot be assumed
covered just because ordinary renderer inputs need not exercise it.

Emilio approved the next bounded adapter-and-correctness slice. FIR/W7 already
owns implementation via `ROOT-W7-20260915-040`; VBP sent acceptance requirements
as `VBP-FIR-20260915-001`, without opening another implementation lane:

- One instance and strong JS-value table per session; real typed marshalling
  and synchronous retained callbacks. In-session growth is accepted; no
  per-render rewind, token recycling or fine-grained reclamation.
- Actual React nodes with existing Blueprint output semantics; reuse renderer
  assertions rather than create a second renderer or transport.
- One React root across updates, stable keys/unaffected DOM, native details
  interaction, repeated callback invocation and rejection after disposal.
- Complete React unmount before disposal. Preserve JavaScript value identity;
  invalidate escaped callbacks through the session even if JS still holds them.
- W7 owns adapter/bridge tests; VBP owns consumer browser acceptance once the
  exact handoff is available. No producer edits to VBP/VIR are requested.

RPC/session integration and timing runs are later steps. A renderer-only result
does not include `Preview.decode` or server latency. Deliberate retention can
also change reclamation cost, so future comparisons must not label all timing
differences pure interpreter overhead. Keep the pinned VIR semantics and leave
any future host redesign or permanent cross-backend ABI outside this prototype.

## Frozen comparison source

- VBP base: `c4430bfe2c898c0312903ae46c45b410d253ebf4`.
- Apply the existing accepted-preview child-element memoization in `Preview/Rpc.lean`.
  Its complete source SHA-256 is
  `b11a19b76283fec7137c2ea623b94b178dbae29095ec41a775c2045781d30ea6`.
  This matches the other fork's measured source; it is not a FIR optimization.
- Lean: `leanprover/lean4:v4.34.0-rc2`.
- VIR: `9fafe9cfd594213ee39dc8205b08084c31101816`.
- Verso: `52c8c9557bcb5cc8c0edc0ee37e74311a3d53ee9`.

The repository Lake manifest remains authoritative for all other dependencies.
Use this fork's source, not a moving producer worktree. Do not retarget the live
FLT demo while preparing the compiled backend.

## Existing FIR package is historical, not a matched baseline

`FIR-VBP-20260909-002` was accepted and closed. It names FIR producer
`8848d822f0035f6d8a02ac66a892926d763c4725`, VBP
`cad90a2f59544833a81a456b72a0fd52d8f28b1c`, and VIR
`90aa3f4938152d455ce4d5ddb79073729fc2df71`.
That package compiles the previous `Widget.mount` / `Widget.unmount` roots and
41 host imports. The current widget exposes native React component factories,
uses native JavaScript props and retained Lean values, and owns its RPC hooks.
The old package cannot establish current-code parity or an interpreter speedup.

FIR's existing package driver deliberately rejects different source hashes.
Do not weaken that check or overwrite the accepted package. A new source target
needs a separate package and a review of the current host ABI and ownership.
The main FIR checkout inspected at `fdef2c1e` still pins Lean 4.33; its ordinary
build artifacts must not enter this exact-4.34 experiment.

## Original full-widget plan (later stages, not current authorization)

1. First capture, compile and resident-link the existing
   `VersoBlueprintVirTests.NativeSession` exports `createComponent` and `render`
   in an isolated exact-4.34 fixture. The renderer-only pivot above supersedes
   this as the first probe; full NativeSession work remains a later stage.
   Record its exact host frontier and either a validated Wasm artifact or the
   first concrete blocker. Compilation is not browser/lifetime acceptance.
   After separate review of the current-ABI adapter, reuse its browser campaign for real React
   rendering, Strict Mode, retained controls, updates, errors, effects, unmount
   and disposal. This is a correctness gate, not the FLT performance workload.
2. Compile the existing `VersoBlueprintVirTests.StringPreview` exports
   `createComponent` and `render`. These call the actual `createRpcComponent`
   implementation, including `Preview.decode`, cancellation, notification
   refresh, obsolete-response suppression, and stable accepted-child identity.
   Reuse the String RPC acceptance campaign without rewriting these behaviors
   in JavaScript or recreating an imperative root protocol.
3. Integrate the compiled factory with the same native infoview panel boundary
   used by `createWidgetComponent`. Preserve the editor context, request shape,
   document response and ordinary React root. Any runtime/ABI adapter belongs
   at the backend boundary, not in a duplicate renderer.
4. Run a matched FLT edit campaign with both backends. Require correctness
   before interpreting timing differences.

The retained VIR `StringPreview.report.md` reports 2,778 declarations, 46 JS
host imports and two exports. This is a useful inventory of the current native
API surface, not FIR closure/linking evidence. In particular, the retarget must
handle explicit LeanRef retain/release, typed callback and effect conversions,
memo calculations, native state setters, promises, abort signals and the
infoview notification/RPC host bindings. Do not implement substitutes for
React, DOM or RPC behavior in the FIR adapter.

## Timing contract

- Same FLT chapter, initial text, fixed-width prose edit, cursor position,
  renderer source, Lean/VIR dependencies and server endpoint.
- Whole single-file chapter payload; debug and change highlighting off;
  production React for timings. Strict Mode correctness is a separate gate.
- Fresh runtime per session, retained across edits. Record setup/compilation
  separately; do not rebuild the client artifact for every document edit.
- Finish background reference indexing with `$/lean/waitForILeans`, then one
  warmup and seven measured edits per session, using order-balanced backends.
- Measure edit-to-accepted-DOM plus server snapshot/check/evaluation, RPC and
  reply-to-DOM. DOM commit is not browser paint or full VS Code latency.
- Include response decoding on both sides. If first measuring a renderer-only
  replay, label it separately and do not compare it to the full RPC interval.
- Preserve raw observations, exact source/artifact/SDK hashes, semantic output
  checks and retained-control assertions. No interpreted fallback is allowed
  inside a claimed non-interpreted FIR baseline.

Historical VIR late-edit medians and diagnostic samples remain in the other
fork's `NATIVE_PREVIEW_LATENCY.md`; they are context, not a replacement for a
fresh matched control.

## Initial coordination (historical; current scope above)

The consumer worktree is `.worktrees/fir-preview-baseline`, branch
`feat/fir-preview-baseline`. Output belongs under `_out/fir-preview-baseline/`.
FIR owns its generator, resident runtime and physical ABI. The assessment
`FIR-VBP-20260913-002` concludes that the current source shape is plausible but
not compiled, and the old adapter does not cover its current API/lifetime rules.
Emilio reviewed that result and approved the first capture/link probe only.

`VBP-FIR-20260913-002` closes the assessment; new request
`VBP-FIR-20260913-003` authorizes the isolated NativeSession probe through FIR's
integration owner. The coordinator was notified once. No browser adapter,
StringPreview extension, general compiler/runtime repair, benchmark, publication
or cleanup is authorized by that request. On failure, FIR should report the
concrete blocker rather than expand the task. On success, VBP and Emilio will
review adapter scope before proceeding. Session routing details stay in the
untracked message drafts, not this tracked plan.
