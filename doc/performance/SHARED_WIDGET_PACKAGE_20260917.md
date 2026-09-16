# Shared widget package and first current-VIR replay

## Input authority

FIR request `VBP-FIR-20260917-SHARED-PACKAGE-001` was queued to its root owner
(receipt `01a0ac69-1feb-76e0-9da5-e0bce8243f87`). It requests the existing W7
owner, not another producer or competing campaign.

The complete source snapshot contains 2,560 files:

- VBP consumer: `f66cd04f`.
- VIR: `92d7cc91e4f9bbf48b7c113cfd76d56ff767df4d`.
- Lean: `leanprover/lean4:v4.34.0-rc2`.
- Source identity: `25374b0a52d92c3dba6caff6d9cbd1e1e8bf8fc8412a83e7f9454be465563970`.
- Archive SHA256: `a54bbd3b58f7dbbaaa4371423a45b101b09d36e2cf758e470203570228b345e1`.

The content-addressed archive is under the repository's local
`.worktrees/_meta/widget-source-snapshots/`. It includes all resolved dependency
working sources and the dirty Verso list-registration parser patch. Mutable
capture, producer source changes and live pin changes are not authorized.

The requested configured root is
`VersoBlueprintVirTests.NativeSession.createBrowserEncodedDocumentComponent`:
the same compiled Lean component, native math argument and demo clock as VIR.
It currently uses `Document.decode`. The request separately identifies the
`DecodeProbe.browserParsed`, `createView` and `renderDecoded` roots for the
efficient-codec experiment. That codec checks native JSON, reconstructs
`Lean.Json`, and uses the existing `FromJson`; it is not a JavaScript document
decoder. Factory parity and codec parity must be reported separately.

The reviewed FIR extern-provenance repair is a prerequisite; its historical
`d356ba46` package is not adopted as the current-source comparator. Producer
package correctness does not replace consumer SSR/Chromium qualification.

## Replay protocol

Reuse `tests/vir_preview/decode_browser_smoke.mjs` with the full FLT captured
response, production React, retained controls and DOM, debug/highlighting off.
Timing includes decoding and render-to-DOM observation, but excludes RPC/LSP,
package loading, paint and passive-effect waiting. Two warmup pairs precede
order-alternating measured pairs. DOM/text equivalence, retained control state
and retained document nodes are checked outside timing.

Uninstrumented timing and CDP 1ms sampling are separate captures. Sampled
durations are attribution aids, not headline elapsed-time numbers. The reused
small-fixture driver's 60-second deadline was insufficient; the failed first
capture has no usable result. Full replay now has a ten-minute deadline and an
explicit even `VBP_REPLAY_PAIRS` setting (default 16).

Raw outputs live under `_out/upstream-vir-20260917/` in the repository root.
Historical FIR numbers are not a current-source backend comparison.

## First timing result

Capture `full-flt-replay-timing-02` contains 16 measured pairs after two warmup
pairs and an initial mount. The response has 6,596,789 JavaScript characters;
the rendered preview has 7,011 elements. Both decoder paths produce equivalent
normalized DOM/text and preserve the checkbox state and unchanged paragraph.
There are no browser warnings.

| Path | Decode median | Render-to-DOM median | Total median | Total range |
| --- | ---: | ---: | ---: | ---: |
| Plain Lean JSON parser | 6.769 s | 1.225 s | 8.083 s | 7.186–8.632 s |
| Checked native JSON → Lean.Json → FromJson | 0.941 s | 1.337 s | 2.363 s | 1.892–2.619 s |

These are independently calculated medians, not an additive phase breakdown of
one selected run. The checked path's decode interval includes JavaScript parsing,
native graph checks/conversion and typed reconstruction. Its render-to-DOM
interval includes identity preparation, React element construction, reconciliation
and DOM observation; it is **not** an isolated document-to-VDOM number. Server
encode/transport costs are outside this replay.

The plain-parser and checked paths alternate in one retained runtime. This is
useful codec screening, not a matched old/new consumer speedup or VIR/FIR ratio.
The remaining constant per-node style construction is a source-level candidate;
timing alone does not establish its contribution.

## First sampled attribution

`full-flt-replay-profile-02` separately samples two measured pairs after the
same warmups. Release and named SDK Wasm executable sections match; all 7,058
sampled Wasm frame nodes resolve, with no unresolved frames. The earlier
`full-flt-replay-profile-01` failed the clock uncertainty threshold and is not
used for phase attribution. Calibration now keeps five pre-sampling trials and
chooses the narrowest interval, without weakening the existing <5 ms check.
The accepted calibration uncertainty is 0.329 ms. No old callback-snapshot or
leaf-classifier frames occur in the symbolicated capture; their source paths
are removed in the current SDK. Twenty JavaScript unit tests, syntax checks and
`git diff --check` pass for the harness changes.

Within the checked path's **render-to-DOM** windows, sampled self time is:

| Sample bucket | Share |
| --- | ---: |
| Interpreter dispatch/evaluation | 38.2% |
| Symbol/constant/name lookup | 12.9% |
| JavaScript/browser, including boundary/providers | 28.1% |
| Other Wasm | 14.1% |
| Allocation/refcount/vector storage | 6.7% |

The inclusive `callObjectsImpl` host-boundary share is 22.6%; this overlaps
the self-time buckets and must not be added to them. The inclusive `commitRoot`
share is only 0.38% in this capture. That supports targeting interpreted
construction and host-boundary work before DOM commit; it does not isolate a
pure traversal timer or measure paint. Individual hot self frames include
`eval_body` (23.4%), interpreter `call` (11.6%), symbol hash lookup (9.2%),
`readObjectArgv` (5.3%) and the browser `decode` builtin (3.8%).

Checked-path decoding is mixed work: JavaScript/browser accounts for 47.3%
of its sampled self time, interpreted evaluation 28.7%, name lookup 7.2%,
allocation/refcount 7.6%, and other Wasm 9.1%. `encode` is a prominent browser
builtin frame (9.5%); the frame name alone does not mean document JSON
serialization. The bridge's `inspectNode` is 5.2%, and browser GC is 5.8%.
Conversion/boundary costs remain worth investigating; native parsing alone
is not the complete decoder cost.

Next: qualify the requested same-source FIR package, isolate the common content
callback in the existing differential campaign, then test constant renderer
style reuse/CSS against this representative input. No current VIR/FIR speedup
or style-specific percentage is claimed.
