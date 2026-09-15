# Native Blueprint preview

## Current development: PR188 and timing cleanup

See [the PR188 setup and acceptance record](BROWSER_PR188.md) for the current
VIR `36d26bc2` pin and matching SDK. The prior PR187 worktree remains untouched;
the live FLT demo now uses PR188 with the checked decoder and clock. See the
[whole-FLT root edit measurements](FLT_ROOT_PR188.md). The bar now includes
observed edit-notification-to-dispatch time and checks its complete partition
against elapsed notification-to-content-effect time.

Sections below are retained checkpoint/history notes, not the setup identity or
current measurement coverage of this checkout. The timing-accounting follow-up
described below is implemented here.

## Research checkpoint and whole-FLT timing caveat (2026-09-15)

This checkpoint retains the native JSX migration, retained structural fingerprints,
experimental checked-JSON decoder, KaTeX leaf, list-source-range patch, and browser
profiling/acceptance tools. Generated bundles, SDKs, and raw profiles remain local
artifacts, not Git contents. The local Verso patch must still be applied explicitly;
the source pin alone does not contain that repair. This is an experimental local
checkpoint, not a publication-ready or publicly reproducible release.

The whole-FLT preview is now being tried interactively. Its displayed performance
numbers are **not validated as whole-document latency**. Inspection of the saved
FLT checkout found that `FLTBlueprint.lean` still registers
`Lean.Vir.Infoview.widget` with `FLTBlueprint.Preview.panelProps`: the default String
decoder and no browser clock. Only `FLTBlueprint/Chapters/Reductions.lean` selects
the checked-JSON demo widget with its clock and math component. Unsaved editor
changes may differ; the live FLT checkout is intentionally left untouched.

Without that clock, the bar reports only server snapshot/checked waits and document
evaluation. Those waits start at the RPC request, not the edit; they can be tiny
when an environment is already ready. They exclude encoding, transport, browser
decoding/rendering, and earlier server work. Even the clock-enabled bar ends at a
content passive effect, not paint, and omits edit-to-request and startup costs.
Turning debug on after a response does not retroactively measure that response.

The clock-enabled accounting also needs a bounded follow-up: invalid timing falls
back to server-only display, and the browser residual uses saturating subtraction
without checking that preparation plus rendering fits the enclosing interval.
The reported total is a sum of phase estimates, not an independently checked
request-to-effect interval. These are audit findings, not established causes of
the user's observed numbers. Before reporting whole-FLT performance, confirm the
active widget, correlate one accepted update across phases, validate the elapsed
total and residuals, and compare against an external browser observation. Keep
debug-on/off runs separate to quantify instrumentation overhead.

The retained `demo-integral-final` profile below is **one Reductions chapter edit**,
not the complete FLT blueprint. No new benchmark was run for this checkpoint.

## Demo: math, list navigation, and the processing bar (2026-09-15)

The checked-JSON demo now includes KaTeX. Each formula is a stable React leaf;
its effect depends on source, prelude, and display mode. React owns an empty
container and KaTeX owns only its descendants. Unchanged formulas are not
typeset again. Matching CSS/WOFF2 fonts are bundled locally, with `trust: false`
and visible invalid-TeX output. Ordinary renderer factories still default to
source-preserving math; the demo explicitly supplies the leaf component.

Enable **Debug details**, then edit the document. The bar measures **RPC request
to the content passive effect**, not physical keystroke-to-paint. It partitions:

- server snapshot wait, checked-environment wait, and document evaluation;
- RPC remainder (encoding, transport, and scheduling together);
- accepted-response decoding;
- identity/change preparation and React element construction;
- remaining React, effects (including math), and scheduling.

Server waits are subdivisions of RPC, not additional elapsed time. The remainder's
position is schematic, not a claim that transport occurs entirely after server
work. React's internal commit duration is not measured. Auto selects a readable
time scale; explicit scales remain available. Timings stay hidden outside debug.
Three browser clock reads bracket each demo RPC/decoder; preparation/render/effect
reads are debug-only. No per-node instrumentation, polling, or global DOM observer
is added to the widget. Client timing metadata is ordinary React input, separate
from the document wire format. The clock binding is demo-only pending upstream;
the VIR coordinator has received Emilio's priority request.

The list-discovery repair is a four-line **local Verso parser patch**, not a
VIR/JavaScript workaround. Its synthetic list delimiters now carry source
positions like paragraphs and definition lists. See
[`patches/README.md`](../../tests/vir_preview/patches/README.md) before reconstructing
this demo from fresh dependencies. The VIR source/SDK remain unmodified.

Validation and captures: `_out/browser-pr187/math-and-lists/`;
the regenerated integral profile is `_out/browser-pr187/demo-integral-final/index.html`.
The report is one sampled real-LSP/browser warm edit, with native worker lanes,
browser samples, exact SDK symbols and raw downloads—not a latency distribution
or VS Code paint measurement. Earlier reports/sections below describe the prior
server-only and untypeset checkpoints.

**2026-09-15 demo update:** the embedded fixture and FLT's `Reductions.lean`
now explicitly select the temporary `CheckedJsonPreview` codec, paired with
retained structural fingerprints. The ordinary RPC/widget factories still
default to the String decoder. `tests/vir_preview/build_checked_json_demo.mjs`
bundles the unchanged pinned VIR shell/lifecycle with the existing experimental
JSON bindings and a native parse call; it verifies source/SDK identity and writes
a demo-only `Widget.Module` bundle. Lake tracks that embedded file through
`checkedJsonDemoBundle`. No producer or SDK files are modified. The demo server
validates the safe-integer domain before encoding. This bridge should be deleted
when the pinned VIR supplies the JSON codec.

`scripts/test-vir-preview-widget.sh` prepares this bundle and validates the
registered checked-JSON shell, real RPC, edits, retained controls/focus, and
unsubscription. Evidence lives in `_out/browser-pr187/checked-json-demo/`.
The live FLT folder is
`.worktrees/_reference-blueprints/edit/native-preview-modules/verso-flt/`;
its `PREVIEW_DEMO.md` records exact rebuild/open instructions. Browser timings
in the research report remain replay measurements, not the widget's server bar
or a new editor-latency claim.

Experimental integration on the refreshed VBP module-system base. This is a
correctness checkpoint, not a latency measurement or replacement for the working
FLT demo.

## Current isolated setup

The manifests pin Lean **4.34.0-rc2**, Verso `52c8c955`, and VIR
`6e91bed83168c9cddf4f85e97cf0c58fc1e01e3d`. The independent
[verso-react](../../packages/verso-react/README.md) package uses the same pair.
Source dependencies are independent clones, not producer worktrees.
This VIR candidate includes native panel props and same-tree React rendering,
the PR187 native props/JSX API and follow-up `3b2cfd2f`, plus the 4.34 overlay.
It is a local experimental successor, not a published 4.34 release.

VIR still uses a local Git URL. This is reproducible with retained inputs,
but **not yet a public download-and-build recipe**. The matching SDK archive
has SHA-256
`82cab0c34b507c7cd1b765483547b4fb11d909da84aadfa408a06883251bb85a`.
The release WASM hash is
`3644f76050031b59ae84bd9f36379b6865a8c12d2438a83722ccc0613a8e916f`.
The existing `:virSdk` facet installs the archive. Test scripts derive the expected
source revision from the manifest and check the installed identity.
Do not mix toolchains or copy individual runtime files.

Prerequisites: the pinned Elan toolchain, Node/npm, Chromium for VIR's browser
harness, the local VIR Git source containing the pin, and the matching SDK archive.
From a fresh integration checkout, run `scripts/lean-low-priority lake update`
to acquire dependencies, then:

```sh
export VIR_SDK_ARCHIVE=/absolute/path/to/lean-vir-sdk.tar.gz
export VBP_RENDERER_REPORT_DIR=/absolute/path/to/verso-blueprint/_out/browser-pr187/renderer
export VBP_NATIVE_SESSION_REPORT="$VBP_RENDERER_REPORT_DIR/../session.json"

npm --prefix .lake/packages/lean_vir ci --no-audit --no-fund
scripts/test-verso-react.sh
scripts/test-vir-native-session.sh
VBP_NATIVE_PREVIEW_REPORT="$VBP_RENDERER_REPORT_DIR/../scalar-rpc.json" scripts/test-vir-native-preview.sh
VBP_NATIVE_PREVIEW_REPORT="$VBP_RENDERER_REPORT_DIR/../string-rpc.json" scripts/test-vir-native-preview.sh --string-preview
VBP_NATIVE_PREVIEW_REPORT="$VBP_RENDERER_REPORT_DIR/../widget.json" scripts/test-vir-preview-widget.sh
```

Report paths are explicit so reruns cannot overwrite another experiment's
evidence by default. Packaging conservatively retains scoped artifact restoration.
The upstream cache repair is included, but these preview gates do not establish
cache-only correctness; removing the override is a separate validation.

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
  Components use `FunctionComponent (Props.WithData T)` with explicit Lean
  handles in the `data` prop. Elements/styles use native props and JSX; the
  retired Lean property-list builders are not recreated downstream.
- `Preview.Rpc` uses the native editor context and edit-notification hook. One
  ordinary effect owns each request and its `AbortController`. Cleanup disables
  publication before aborting. The server returns an explicitly encoded String,
  decoded once per accepted reply; there is no state-serialization layer.
- `Preview.Widget` reads native `PanelWidgetProps` and calls the actual
  `useRpcSession` hook. Cursor coordinates stay JavaScript numbers; `useMemo`
  stabilizes the request object. `vir_proof_widget` registers one function-component
  factory, which React invokes in the surrounding infoview tree. There is no
  normalized Surface, mount entry, mount ID, or nested React root.
- `Preview.Server` is a separate meta import. It reads the open module's Verso
  document from the end-of-file snapshot, waits for the checked environment,
  verifies the complete Manual document type, and evaluates it. The normal
  document is intentionally evaluated with `checkMeta := false`.
- `Preview.Source` maps the cursor to Verso's retained `FinishedPart` source
  syntax, using the same positional addresses as the renderer. No source parser,
  wire format, source-map cache, or extra RPC is introduced.

### Follow cursor

**Follow cursor** highlights the enclosing source block or heading. It uses
Lean's UTF-16-to-UTF-8 position conversion and Verso's original/synthetic source
ranges, not text matching. A list or directive selects its enclosing top-level
block; a concatenation passes focus to its rendered children without introducing
DOM wrappers. Included documents use their local name anchor, not source ranges
from another file. Positions between source ranges or outside the document clear focus.

Disabling Follow cursor removes the indicator but continues accepting cursor
updates; reenabling it displays the latest position without another RPC. Controls
retain their state across cursor movement and document edits.

**Automatic scrolling is not implemented.** The pinned VIR has DOM queries but
neither a public `Element.scrollIntoView` binding nor custom runtime extensions.
The remaining upstream primitive is a native DOM scrolling operation with explicit
options. VBP can then invoke it from an ordinary React effect using a local ref,
with nearest-block scrolling and no focus stealing. Do not add a parallel shell
or global DOM polling to work around this gap.

### Timing display

Enable **Debug details** to show the timing bar and metrics together, without
another expander. They are absent in normal mode. One stacked bar shows
server preparation for the accepted response: blue **Snapshot** wait, amber
**Checked** environment wait, and green **Document** evaluation/reconstruction
and cursor lookup in the retained source syntax.
The **Scale** selector offers **1, 10, 100, or 1000 ms per tick**, with each tick
occupying 40 CSS pixels. The default is 1 ms, making millisecond-scale demo events
visible; choose a coarser scale for FLT. The choice survives edits and Debug off/on.
At the selected scale, doubling a duration doubles its width, even across responses
or panel sizes. It does not automatically rescale each response to fill the panel.
Long bars scroll horizontally instead of rescaling or clipping the measurement.
Zero-duration phases have no width; absent timing is shown as unavailable, not zero.
A single total sits above the bar. Hover a segment or legend label for its phase
duration; the total's tooltip explains measurement scope. Editor version/status
and change-analysis counts appear below it, with no nested expander.

The preview RPC takes four monotonic timestamps, with no per-node probes,
extra rendering traversal, logs, timers or request. Measurements are collected for each
successful document response independently of the Debug checkbox; changing a
control reuses that response's server measurement. The bar reads the accepted
response directly, without duplicating timings in post-commit state. Scale
changes do not repeat the diagnostic effect, send an RPC, or take a new measurement.
Snapshot/checked waits include
scheduling and document work remaining when the RPC starts. The interval ends
before response encoding. It excludes work before RPC entry, transport, and
browser rendering, so it is **not edit-to-preview latency**. Browser timing remains
pending the pinned VIR API; no VBP-local browser binding has been added.

The timing acceptance reports in `_out/native-preview-modules/timing-zoom/` check
debug-only visibility, actual browser geometry against a 1:2:3 sample, all four
selectable scales and their persistence, 6/600/1200 ms measurements, horizontal scrolling in a narrow panel, distinct
colors, accessible labels, missing/zero measurements, and fresh measurements
from the real document RPC across edits. The refreshed campaign also keeps
the strict zero-React-warning gate.

Ordinary `import VersoBlueprint` does not import VIR. The server endpoint is not
part of the client's runtime closure. No new build, rendering traversal, document cache,
scheduler, transport, or document format is added. The server still waits for
the **whole document**; this slice does not make elaboration incremental.

## Embedded demo and acceptance

[EmbeddedPreviewServer.lean](../../tests/VersoBlueprintVirTests/EmbeddedPreviewServer.lean)
contains an actual Blueprint with prose, an informal theorem/proof, math, and an
external Markdown summary. After building the widget target above, open this
worktree as the VS Code folder. After a rebuild, restart the file's Lean server.
Put the cursor inside the statement, proof, or heading to see its focus indicator;
either `trivial` before the document leaves the document unfocused. Edit the prose
to request the new document. The preview does not yet scroll to the indicator.

The browser test reuses VIR's real-LSP harness and official `RpcSessions`.
It obtains panel props and registered JavaScript through Lean widget RPC, checks
the generated shell hash, and runs that exact shell. The shell packages the
client from the live server snapshot and reads matched WASM through asset RPC.
The open document and its imports must use the module system. A compiled widget
package test alone does not check that live requirement.

The campaign checks edited text, retained controls, unchanged-input suppression,
cursor correlation, real source-to-DOM focus, disabled/reenabled Follow cursor,
panel registration inside a statement, subscription cleanup, and the runtime asset hash. Separate
scalar/String campaigns cover cancellation, stale replies, Strict Mode, decoding
failures, and disposal. The harness forwards edit notifications **after
diagnostics**: these are correctness checks, not latency measurements or live
VS Code/FLT acceptance.

**Strict lifetime gate:** the refreshed embedded campaign passes with zero React
warnings. VIR now renders the Lean component in the existing tree. The test still
rejects every unexpected React warning; none is filtered or suppressed. The
working FLT demo and its previous VBP/SDK pair remain unchanged during validation.
Unmounting UI is not hard runtime disposal: surviving callbacks retain their
runtime generation according to VIR's ownership contract.

Historical profiling, widget campaigns, and evidence remain on the earlier
research branches; they are not acceptance evidence for this base.

## Previous candidate validation, 2026-09-13

These results concern VIR `9fafe9cf`, not the current `6e91bed8` pin. See
[the browser checkpoint report](BROWSER_PR187.md) for current validation and timings.

Reports live under repository-root `_out/native-preview-vir-refresh/`:

- Independent SDK installation: exact clean source identity, all 32 payload
  hashes, and host-binding module import pass. The retained input archive is
  `inputs/lean-vir-sdk.tar.gz`.
- `renderer/renderer-acceptance.json`: generic Manual and Blueprint rendering pass.
- `session.json`: Strict Mode, retained controls, debug-only timing and selectable
  scale, timing geometry, and disposal checks pass without React warnings.
- `scalar-rpc.json` and `string-rpc.json`: real-server RPC, cancellation, stale
  replies, and edit-refresh campaigns pass; String RPC makes 23 requests.
- `widget.json`: registered shell, live snapshot packaging and workspace WASM,
  edited document, source focus, retained controls/scale, and unsubscribe pass.
  Eight preview requests build one client package; React warnings are empty.
- Lean Beam checks the native-props widget module with no diagnostics.

This is isolated consumer acceptance, not FLT/VS Code acceptance, a new latency
measurement, or approval of all upstream changes. The old VBP worktree, user-edited
fixture, and live FLT dependency pins are preserved.

To move FLT later, switch its VBP path to this worktree, update Lake, install this
SDK, and remove `with mountId := ...` from its `vir_proof_widget` registration.
Keep module headers on the open Blueprint files. Rebuild and validate live
packaging before restarting the editor; do not mix the old JS SDK with this pin.

## Previous baseline validation, 2026-09-13

Reports are retained under repository-root `_out/native-preview-modules/`.
The standalone renderer build/test and generic/Blueprint React output tests pass.
Retained-session Chromium, scalar RPC (12 requests), and String RPC (23 requests,
including cancellation and edit notifications) pass without React warnings.
The embedded campaign renders real statement/proof occurrences and edited prose,
retains controls, and builds its client package once across three preview requests.
Its strict exit remains nonzero solely for the upstream unmount warning above.

The follow-cursor campaign in `cursor/widget.json` adds statement/proof/heading
navigation and leaving the document: eight preview requests, one client package.
`VersoBlueprintVirTests.Source` covers half-open ranges, missing syntax, included
parts, and Unicode position conversion. Renderer acceptance also checks empty and
nested concatenations, multiple focused children, and unfocused siblings.

The default VBP build and explicit preview/module-boundary targets pass with
warmed dependency caches; existing base warnings remain. Beam checks of the
server endpoint, adapter, and document fixtures had zero diagnostics. This is
not a clean-machine build or live FLT acceptance. One sandbox rebuild encountered
a read-only cached `.ilean`; the authorized retry and subsequent sandboxed
campaigns succeeded without changing cache permissions or patching dependencies.
