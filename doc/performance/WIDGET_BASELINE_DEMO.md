# Shared widget demo and baseline inputs

2026-09-16. Infrastructure and correctness only; no VIR/FIR speed comparison or
optimization assignment yet. Both backends share one experiment owner.

## What can be seen now

- Full VIR ProofWidgets preview: open the existing FLT workspace and
  `FLTBlueprint.lean`, then place the cursor in its root document prose. This
  remains the working live demo; no pin, SDK, shell or source was changed here.
- FIR browser demo: real compiled Lean renderer, editable title, retained
  callback button, and close/unmount/dispose. It is explicitly a title-only
  fixture, not full Blueprint, RPC integration, or a performance display.

The FIR demo reuses the accepted SSR/browser test entry, pinned VIR host
bindings and generic Chromium driver. React owns the controls and retained DOM;
one FIR session lives outside React and is disposed after root unmount.
Only event handlers invoke updates; there is no polling or timing instrumentation.

From this worktree, choose a **new** output directory:

```sh
node tests/vir_preview/fir_renderer_smoke.mjs \
  /home/egallego/lean/fir/.worktrees/wasm-generation-4.34 \
  /home/egallego/lean/verso-blueprint/.worktrees/native-preview-vir-refresh \
  /home/egallego/lean/verso-blueprint/_out/browser-pr188/fir-demo-new \
  --serve
```

The process prints its localhost URL and stays running; Ctrl-C stops it. Its
`server.json` records PID/URL and `identity.json` records source/artifact pins.
Without `--serve`, the same command runs SSR and Chromium acceptance and exits.
All paths are local maintainer setup, not an end-user package interface.

The full VIR workspace can be opened with:

```sh
code --new-window /home/egallego/lean/verso-blueprint/.worktrees/_reference-blueprints/edit/native-preview-modules/verso-flt \
  --goto /home/egallego/lean/verso-blueprint/.worktrees/_reference-blueprints/edit/native-preview-modules/verso-flt/FLTBlueprint.lean:45:4
```

## Frozen FIR baseline and source parity

Consumer tests originate at `ae281ff8`, integrated here as `af686d4c`. The
successor runner extracts adapter source from immutable FIR
`8ec770fd90c6b8e8c7e4483998650030f2cf868e`; it verifies experimental Wasm SHA-256
`f8c9a6733d1e3d6414efa6619a7dbf13450e7f6c9fd2495442f75e045c896865`.
It consumes verified SDK JavaScript from VIR
`9fafe9cfd594213ee39dc8205b08084c31101816`, Lean 4.34.0-rc2, React 19.2.7.
The current checkout's newer Lake pin is not silently used for this old fixture.

The prepared `native-preview-vir-refresh` tree's following files match FIR's
frozen VBP `c4430bfe` byte-for-byte (checked with `git diff --exit-code`):

| File | SHA-256 |
| --- | --- |
| `packages/verso-react/VersoReact/Renderer.lean` | `0bf82dd6ba8b7a3188072f9f4a56aecb55efda7283805acd8d21f5ebd8d74a53` |
| `src/VersoBlueprintVir/Preview/Renderer.lean` | `f71035bbed37d779db8efdd77c4a4f471512efd2f01daa5008ff682e43230926` |
| `src/VersoBlueprintVir/Preview/Model.lean` | `1465239968cdc09827b8d8d47b891693fd6ae1b464faa2c520aba5a3b2ae1377` |

Use that source/API baseline for the first matched renderer replay. The newer
live VIR renderer includes native JS props/JSX and math-component changes; it
must be an explicit later variant, not compared silently with old FIR code.
The model/codec file itself is unchanged between these source checkpoints.
No claim yet that a matching JSON replay entry has been packaged for both sides.

## Shared FLT before/after inputs

Evidence: repository-root `_out/browser-pr188/widget-baseline-inputs/`.
The existing edit harness captured an initial accepted full-root FLT document
and its final accepted prose edit, in one LSP/browser session. Disk source was
unchanged; edits were in memory. `identity.json`/`result.json` preserve the exact
project, input source, driver, package and SDK identities. This is a fresh input
cohort, not a replay of historical performance results.

`initial-response.json` and `response.json` retain complete `Preview.encode`
strings. `before.document.json` and `after.document.json` remove **only** the
existing `Preview.ready` envelope. Their inner bytes are unchanged, including
number spelling and field order; no JS copy of the Document schema is introduced.
Both backends must still validate these through existing Lean `Document.decode`.

| Input | Bytes | SHA-256 |
| --- | ---: | --- |
| Before | 6,598,303 | `38575e74378c5225832838c2b0cd487ae7ed7aecd5eeac77f98118b992dc90ff` |
| After | 6,598,333 | `5657c4f64ca0b5fdc25a5ec4f450e360be64bbb1a0237f232320f5590807786c` |

`inputs.json` is the hash inventory. Request captures with the existing
`VBP_LATENCY_CAPTURE_RESPONSE=1` option; this now saves both endpoints. Capture
results are not timing baselines, and malformed/non-ready envelopes fail closed.

## Validation and remaining gate

Fresh `fir-error-aligned-consumer/acceptance.json` covers SSR, Chromium, Unicode
escaping, metadata, twenty retained-DOM updates, callbacks, ordinary provider
error recovery, completed unmount and post-disposal rejection; no React warnings.
`fir_demo_smoke.mjs URL PREPARED_VBP OUTPUT` checks the actual interactive demo's
input control, retained DOM, callback and close button and saves a screenshot.
`preview_inputs.test.mjs` checks byte-preserving unwrapping and malformed cases.

FIR's `ROOT-W7-20260915-043` already owns the encoded-Document entry. On its exact
handoff, compose rich-content/error/lifetime checks and package the matching VIR
entry. Compare decode + render with decode + render, setup separately from
retained updates, same payloads/options and production React. Full Preview/RPC
comes later. FIR's deliberate session retention remains a stated configuration
difference, not pure interpreter overhead. Optimization work stays deferred.
