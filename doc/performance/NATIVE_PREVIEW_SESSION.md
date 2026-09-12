# Native Blueprint preview

Experimental integration on the refreshed VBP module-system base. This is a
correctness checkpoint, not a latency measurement or replacement for the working
FLT demo.

## Current isolated setup

The manifests pin Lean **4.34.0-rc2**, Verso `52c8c955`, and VIR
`6c69603950955e8a9f8d874432b20d40ea557005`. The independent
[verso-react](../../packages/verso-react/README.md) package uses the same pair.
The integration was transplanted onto VBP `c47e317a` without unrelated profiling
changes. Source dependencies are independent clones, not producer worktrees.

VIR still uses a local Git URL. This is reproducible with retained inputs,
but **not yet a public download-and-build recipe**. The matching SDK archive
has SHA-256
`b8d501cee398bfab2f1f5f080580ece7e83a0ebf4c3fc355456a2abce7053a68`.
The release WASM hash is
`3a92152e4431f86b73525cc23f88498f7b6c66f0f9e10ba10374eaf20a2c6e3f`.
The existing `:virSdk` facet installs the archive. Test scripts derive the expected
source revision from the manifest and check the installed identity.
Do not mix toolchains or copy individual runtime files.

Prerequisites: the pinned Elan toolchain, Node/npm, Chromium for VIR's browser
harness, the local VIR Git source containing the pin, and the matching SDK archive.
From a fresh integration checkout, run `scripts/lean-low-priority lake update`
to acquire dependencies, then:

```sh
export VIR_SDK_ARCHIVE=/absolute/path/to/lean-vir-sdk.tar.gz
export VBP_RENDERER_REPORT_DIR=/absolute/path/to/verso-blueprint/_out/native-preview-modules/renderer
export VBP_NATIVE_SESSION_REPORT="$VBP_RENDERER_REPORT_DIR/../session.json"

npm --prefix .lake/packages/lean_vir ci --no-audit --no-fund
scripts/test-verso-react.sh
scripts/test-vir-native-session.sh
VBP_NATIVE_PREVIEW_REPORT="$VBP_RENDERER_REPORT_DIR/../scalar-rpc.json" scripts/test-vir-native-preview.sh
VBP_NATIVE_PREVIEW_REPORT="$VBP_RENDERER_REPORT_DIR/../string-rpc.json" scripts/test-vir-native-preview.sh --string-preview
VBP_NATIVE_PREVIEW_REPORT="$VBP_RENDERER_REPORT_DIR/../widget.json" scripts/test-vir-preview-widget.sh
```

Report paths are explicit so reruns cannot overwrite another experiment's
evidence by default. Packaging uses scoped artifact restoration for this VIR pin;
the upstream cache repair is not part of this checkpoint.

## Architecture

- `VersoReact` renders the existing `Part Genre.Manual` tree. It owns ordinary
  document rendering, not RPC, widgets, state, or Blueprint extension semantics.
- `Preview.Renderer` supplies Blueprint extension rendering and identities.
  Math/external markup preserve source, without KaTeX/Markdown typesetting.
  Unknown extensions stay visible.
  Informal blocks consume the base's `BlockOccurrence` and display "Statement"
  or "Proof". Precise theorem/lemma titles require the canonical node metadata
  now held outside the Part in `RenderModel`. Wiring that existing model into
  preview is a separate design decision, not an invented default kind.
- `Preview.Component` owns ordinary React state and controlled inputs. Stable
  component types and keys preserve controls across edits. Highlighting is off
  by default. Browser timings remain pending upstream; server durations are
  displayed only when provided.
- `Preview.Rpc` uses the native editor context and edit-notification hook. One
  ordinary effect owns each request and its `AbortController`. Cleanup disables
  publication before aborting. The server returns an explicitly encoded String,
  decoded once per accepted reply; there is no state-serialization layer.
- `Preview.Widget` adapts VIR's cursor/session surface. `useMemo` stabilizes
  parameters; checked conversions produce JSON numbers, not Lean bigints.
  `vir_proof_widget` supplies registration and mounting.
- `Preview.Server` is a separate meta import. It reads the open module's Verso
  document from the end-of-file snapshot, waits for the checked environment,
  verifies the complete Manual document type, and evaluates it. The normal
  document is intentionally evaluated with `checkMeta := false`.

Ordinary `import VersoBlueprint` does not import VIR. The server endpoint is not
part of the client's runtime closure. No new build, traversal, document cache,
scheduler, transport, or document format is added. The server still waits for
the **whole document**; this slice does not make elaboration incremental.

## Embedded demo and acceptance

[EmbeddedPreviewServer.lean](../../tests/VersoBlueprintVirTests/EmbeddedPreviewServer.lean)
contains an actual Blueprint with prose, an informal theorem/proof, math, and an
external Markdown summary. After building the widget target above, open this
worktree as the VS Code folder and put the cursor on either `trivial` before the
document. Edit the prose to request the new document. Placement inside arbitrary
Verso syntax is not covered by this fixture.

The browser test reuses VIR's real-LSP harness and official `RpcSessions`.
It obtains panel props and registered JavaScript through Lean widget RPC, checks
the generated shell hash, and runs that exact shell. The shell packages the
client from the live server snapshot and reads matched WASM through asset RPC.

The campaign checks edited text, retained controls, unchanged-input suppression,
cursor correlation, subscription cleanup, and the runtime asset hash. Separate
scalar/String campaigns cover cancellation, stale replies, Strict Mode, decoding
failures, and disposal. The harness forwards edit notifications **after
diagnostics**: these are correctness checks, not latency measurements or live
VS Code/FLT acceptance.

**Known strict gate:** pinned VIR synchronously unmounts its inner React root
from the outer shell's effect cleanup. React warns about unmounting a root while
rendering. The widget test records functional observations, then fails on this
warning. It is not suppressed or patched locally. VIR has reviewed the lifecycle
issue; no reviewed repair has been adopted here. The working FLT demo remains
unchanged until a successor passes this gate.

Historical profiling, widget campaigns, and evidence remain on the earlier
research branches; they are not acceptance evidence for this base.

## Local validation, 2026-09-13

Reports are retained under repository-root `_out/native-preview-modules/`.
The standalone renderer build/test and generic/Blueprint React output tests pass.
Retained-session Chromium, scalar RPC (12 requests), and String RPC (23 requests,
including cancellation and edit notifications) pass without React warnings.
The embedded campaign renders real statement/proof occurrences and edited prose,
retains controls, and builds its client package once across three preview requests.
Its strict exit remains nonzero solely for the upstream unmount warning above.

The default VBP build and explicit preview/module-boundary targets pass with
warmed dependency caches; existing base warnings remain. Beam checks of the
server endpoint, adapter, and document fixtures had zero diagnostics. This is
not a clean-machine build or live FLT acceptance. One sandbox rebuild encountered
a read-only cached `.ilean`; the authorized retry and subsequent sandboxed
campaigns succeeded without changing cache permissions or patching dependencies.
