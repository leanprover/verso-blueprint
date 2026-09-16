# Shared widget demo and baseline inputs

2026-09-16. Infrastructure, correctness, and a current-FIR diagnostic baseline;
no VIR/FIR speed comparison or optimization assignment yet. Both backends share
one experiment owner. Renderer/source and infrastructure alignment now takes
priority over further differential measurement.

## Alignment priority

Current-renderer acceptance now passes at
`_out/browser-pr188/current-renderer-acceptance-v2/`: immutable FIR4776f86e and
matching VBP92db6325/VIR36d26bc2 control produce identical real React SSR and
Chromium DOM for rich fixtures and captured full-FLT before/after documents.
Six rich updates retain details, malformed JSON recovers, escaped callbacks and
provider-error identity survive, and unmount/disposal checks pass. No timings.
The first attempt used the host audit inventory instead of the generated typed
manifest and failed admission; the second uses renderer.wasm.json correctly.

The FIR demo bundle now uses `createCurrentRendererHostPrototype` with the
compiled Boolean ABI helper and current generic VIR providers. Select the
approved source with `VBP_MATCHED_CURRENT=1` when preparing the bundle or matched
fixture/acceptance. The old immutable a48 producer output is preserved. The live
qualification result is tracked separately from renderer-only acceptance.

The initial FIR artifact used VBP c4430bfe and VIR 9fafe9cf; the current
VIR demo uses the renderer at VBP 92db6325 and VIR 36d26bc2. Shared RPC lifecycle
does not make these equivalent: the FIR view also omits the current identity,
focus, controls, diagnostics and KaTeX path.

The producer rebuild and typed adapter now pass default-options parity, an
intermediate gate. VBP owns the remaining common entry/options contract, shell
and RPC/session path, and one
acceptance harness; backend-specific code should be limited to runtime/ABI
adaptation. Full-widget comparison requires matching optional features too.

Live qualification passes separately at
`_out/browser-pr188/current-fir-live-widget/result.json`: one mount plus two
edits produce three FIR renders, one RPC per edit, unchanged RPC String delivery,
one client package, retained document DOM and zero React warnings. The full-FLT
input has no details element; details retention is covered by the rich fixtures.

## Shared widget presentation and provider modules

Both widget paths now call `Component/Shell.lean` for the preview region,
sticky header, separate document container, and loading/error presentation.
This is a stateless rendering function; existing RPC subscriptions, hooks,
content dependencies and runtime ownership remain unchanged. The FIR header
still identifies its backend and default-options limitation.

The current FIR bundle imports React, collection and value provider modules
from the same pinned VIR source paths as the upstream shell. Each imported
file is verified against the staged SDK manifest before bundling. This produces
one implementation of each provider module while preserving separate provider
instances and disposal scopes. Bundle size changes from 4,071,617 to 4,064,183
bytes; no latency improvement is claimed from this change.

Focused Lean builds and the existing VIR session/RPC browser checks pass,
including sticky-shell placement, control retention, coherent timing samples
and notification cleanup. Full-FLT FIR acceptance passes at
`_out/browser-pr188/shared-shell-fir-live/result.json`: the common sticky header
retains DOM identity across two edits, with one RPC and one FIR render per edit,
unchanged String delivery and zero React warnings. The client package is
249,934 bytes (306 declarations); no timing report was collected.
Matching optional identity, focus, change markers and math behavior remains the
next integration contract; the current FIR entry accepts a document String
with default renderer options.

## Stateful options alignment checkpoint

`createEncodedDocumentComponent` accepts native React props with a `document`
String containing the existing `Document.encode` output. Create its React type
once. It decodes accepted String changes inside the executing runtime and calls
the existing `renderSession`, sharing controls, fingerprint state, change
highlighting, focus policy and an optional explicitly supplied math component.
Decoded documents and Lean refs never cross between VIR and FIR. Document-only
input does not carry RPC timing; browser timing remains unavailable here.

VIR qualification at `encoded-document-options-session.json` covers StrictMode,
unchanged-input reuse, retained DOM/options, actual change/focus rendering, and
malformed-input recovery. Beam and a focused 1030-job package build pass.
FIR subsequently packaged this same factory at `c560f6a4`. Matched consumer
qualification at `component-campaign-20260916-01/result.json` passes exact SSR
for three package fixtures and captured full-FLT before/after Strings, plus
Chromium DOM equality, native follow/highlight events, retained controls/shell/
document, malformed recovery and unmount/disposal. Both factories use frozen
source identity `2c1ef0f6`; VIR was rebuilt with a private Lake `--packages` map.
SSR uses production React; browser correctness uses development React.
Live RPC adoption, optional native math and the full nullable/form-value/debug
scale branch campaign remain separate. Working live demos are unchanged.

## Isolated full-FLT element construction

Evidence: `component-phases-20260916-01/{identity,result}.json`.
Four paired full-FLT before/after update rounds, alternating AB/BA order, after
two warmup updates per backend. Production React, no StrictMode, diagnostics and
change highlighting off, default follow-cursor policy, optional math absent.
One component/root per backend, resources retained until session disposal.

| Backend | Median | Range | Samples |
| --- | ---: | ---: | ---: |
| VIR | 1.360 s | 1.335–1.429 s | 4 |
| FIR | 1.521 s | 1.494–1.545 s | 4 |

The measured content callback receives an already-decoded Document and prepared
identities. Its interval includes native props/LeanRef access, rendering and JS
host calls, style/fragment construction and effect registration. Decoding,
identity preparation, RPC, React reconciliation/DOM commit and passive effects
are excluded. Exact DOM equality and one successful content callback per update
are checked after each round. The diagnostic provider wraps only the two native
component functions, with two browser clock reads per callback; it does not time
individual host calls or serialize document values.

FIR is about 12% slower in this small rendering replay. This is a phase result,
not a full-widget latency comparison or pure Wasm-versus-interpreter cost: host
calls remain inside the measured path. The replay factory uses the shared Lean
`Document.decode`, while the current live VIR widget uses a different explicit
codec; outer callback timings must not be presented as live decoding latency.
Native math, GC equivalence and general native-provider adoption are unqualified.

## Historical FIR diagnostic baseline

`_out/browser-pr188/fir-direct-string-timing/result.json`: seven measured edits
after one warmup, retained full-FLT document, 6,612,290-character Document replies,
production React, diagnostics/highlighting off. The shell has no timing hooks,
guard counters, callback census, or profiler; the existing external harness
records edit/RPC/DOM endpoints and reads existing server timing fields afterward.
Edits are in-memory only. One package per session, one RPC per edit, retained
document DOM and no React warnings.

| Interval | Median | Middle 50% | Range |
| --- | ---: | ---: | ---: |
| Edit to accepted DOM | 2.995 s | 2.650–3.411 s | 2.462–3.640 s |
| RPC | 0.419 s | 0.401–0.444 s | 0.359–0.551 s |
| Reply to accepted DOM | 2.524 s | 2.239–3.011 s | 2.047–3.081 s |

These are independently summarized medians, not additive phase values. Quartiles
use linear interpolation at `(n - 1) * p`. The endpoint is a MutationObserver
after the accepted version's DOM commit, not VS Code paint. RPC includes the
test HTTP bridge; its residual is not a direct encoding measurement. Server
snapshot wait, checked-environment wait and evaluation have respective medians
46.0, 19.8 and 19.1 ms. The 337.1 ms median RPC residual includes encoding,
transport, scheduling and other unseparated work.

This is not a backend comparison or a before/after speedup. The full browser
interval still combines FIR decoding/rendering, shell scheduling and React/DOM.
The old combined decode/render hook has been removed; isolated component
phases use the matched campaign below. Normal measurement selects
`VBP_LATENCY_BACKEND=fir VBP_LATENCY_FIR_MODE=timing`; the default FIR mode retains
correctness-only guards and makes no timing claims.

## What can be seen now

The new FIR VS Code demo is `FLTBlueprintFirDemo.lean` in the same FLT workspace.
It is a separate copy of the root Blueprint so existing user edits and the VIR
registration in `FLTBlueprint.lean` remain untouched. Its wrapper identifies FIR.
Restart the Lean server after a rebuild. This is the actual ProofWidgets RPC
path, not a standalone browser substitute.
The dedicated file has one `FLTBlueprint.DemoPreview.useFir` flag: true selects
FIR, false selects the fast VIR demo, with matching widget/props and just one
mounted backend. Changing backend resets controls; ordinary edits retain them.
This selection does not make the two live configurations a matched benchmark.

The temporary view reuses the existing VBP RPC lifecycle with a dedicated
`FirJsonPreview.Server.previewDocument` endpoint. The server sends the existing
`Document.encode` output directly. The client retains the native JavaScript
String as `props.document` to FIR's stable native React component: only FIR decodes it.
There is no shell Preview decoding, document reconstruction, or re-encoding.
The standard VIR widget retains its existing Preview endpoint and decoder.
The component uses the same frozen Lean session, controls, identity preparation
and renderer as the matched VIR control. Controls and open details retain state
through edits. RPC failures now leave the last accepted document mounted and
show a separate request-error message; recovery retains controls and DOM identity.
Failure clears response timing so the retained document is not presented as a
newly measured response. Initial failures have no document to retain.
Its document-only boundary supplies no RPC/browser timings;
math remains source display (`none`), not the live VIR/KaTeX variant.
One FIR session and one native component type belong to each upstream
shell runtime; creation failure, obsolete setup and normal disposal release it.
The Wasm and adapter are bundled locally with no extra CDN or WASI setup.

Build the separate FIR shell (the VIR shell is not overwritten):

```sh
VBP_DEMO_OUTPUT="$PWD/.lake/build/fir-json-demo.js" \
VBP_DEMO_FIR_PACKAGE="$PWD/.deps/adapter-header-v2-20260916" \
node tests/vir_preview/build_checked_json_demo.mjs
scripts/lean-low-priority lake build FirJsonPreview +FirJsonPreview.Server:olean
```

`VBP_DEMO_FIR_PACKAGE` may name any copied package with the accepted immutable
identity; checksums, typed inventories, SDK/provider sources and React lock
identity are verified before bundling. The current package is local/provisional,
not a published dependency. BUILD SHA256 is
`1138101ee4bc83540af6fb84952143b65267f2a7a809a50b9b1f8db900583da4`;
Wasm SHA256 is
`98504ee775e4f4c6c1028d1e497671240ae79480023c0c648f5bc40bc89c0aa6`.
FIR mode omits the VIR JSON bridge, demo clock and KaTeX assets. Its active
binding is `previewDemo.componentFir`; there is no stateless `renderFir` path.
The live FIR demo adopts the accepted immutable header-v2 adapter; the original
package remains in `.deps/component-campaign-20260916-01/fir` for paired replay.
The new shared factory supports native timing props and explicit math/clock,
but this frozen FIR binary still uses its original clock-free `none` factory.
Full timing/math adoption awaits a newly compiled package, not a JS document shim.

The stateful full-FLT live gate uses the existing pinned ProofWidgets/LSP harness:

```sh
VBP_LATENCY_PROJECT=/path/to/verso-flt \
VBP_LATENCY_SOURCE=FLTBlueprintFirDemo.lean \
VBP_LATENCY_ANCHOR='This repository is the Verso blueprint integration layer for the FLT project.' \
VBP_LATENCY_BACKEND=fir \
VBP_LATENCY_WIDGET=FLTBlueprint.DemoPreview.widget \
VBP_LATENCY_SHELL="$PWD/.lake/build/fir-json-demo.js" \
VBP_LATENCY_SAMPLES=1 \
VBP_LATENCY_OUTPUT=/path/to/fresh-evidence-directory \
node tests/vir_preview/latency_browser_smoke.mjs
```

Correctness mode checks one stable native component, unchanged RPC Strings,
one request per edit, retained controls/document shell, and use of the real
server focus token. It does not report timings. Rich-fixture details retention
and malformed recovery use the matched component replay below; the full-FLT
live input itself has no details node.

Fresh stateful live evidence:
`_out/browser-pr188/fir-stateful-live-20260916-05/result.json`.
Mount plus two in-memory full-FLT edits use one component factory/client package,
three accepted document Strings and one preview RPC per edit. Controls, shell
and document DOM persist; follow toggles use an actual nonempty server focus;
there are no React warnings. The cleaned FIR bundle is 2,977,290 bytes, omitting
unused VIR JSON/clock/KaTeX code. These are correctness/size results, not a new
backend latency comparison. VIR cancellation/staleness/recovery regression:
`_out/browser-pr188/native-consolidation-20260916-01.json`; shared session/controls:
`_out/browser-pr188/session-consolidation-20260916-01.json`.

Immutable renderer acceptance at FIR `a48bbb4a` lives in
`_out/browser-pr188/json-renderer-acceptance-v2/`. Both the rich fixture and
captured full-FLT before/after documents have byte-identical real React SSR and
equal browser DOM under FIR and the source-matched VIR control. Six retained
rich updates preserve open details; malformed inputs recover, callbacks survive
updates, and unmount precedes disposal. No timing comparison was run.

The isolated VIR test entry in `.deps/matched-json-control` is generated by
`tests/vir_preview/prepare_matched_renderer.mjs` from the frozen existing renderer
fixture plus test-only entry points; neither renderer nor codec source is
retargeted. The current interactive shell is newer than that matched control.

Historical stateless Direct-String live acceptance passes at
`_out/browser-pr188/fir-direct-string-live/result.json`: one mount and two edits
produce exactly three FIR calls, one RPC per edit, and a retained document root.
A test-only guard rejects any shell Preview-parser call; the FIR argument equals
the unchanged RPC String on every update. No React warnings. The live client IR
package is 232,756 bytes (280 declarations), down from 2,621,056 bytes in the
initial integration; its report contains neither Document encoding nor decoding.
This is a client-package size result, not a latency or total-runtime size claim;
the immutable FIR Wasm is unchanged.

The shared RPC refactor also passes the standard VIR String-preview regression
at `_out/browser-pr188/fir-direct-string-vir-regression.json`: cancellation,
stale/malformed responses, editor subscriptions, retained controls and DOM, and
unmount/disposal. That runner now starts Lean in VBP for VBP fixtures instead of
incorrectly using VIR's package root. Focused batch build and Beam checks pass.

The document-String adapter's error lifetime is covered by the same runner's
`--encoded-document` mode. Evidence:
`_out/browser-pr188/encoded-rpc-retention-20260916-06.json` (initial rejection,
retained document and controls across RPC failure/recovery, malformed input,
cancellation, stale replies and disposal) and
`_out/browser-pr188/string-rpc-retention-20260916-03.json` (standard VIR adapter).
Both use real Lean RPC and Chromium under Strict Mode, not FIR execution or
performance measurements. The compiled FIR package is unchanged.
The live full-FLT FIR update gate also passes at
`_out/browser-pr188/fir-rpc-refactor-20260916-02/result.json`: one client package,
retained controls/DOM, one RPC per edit, and no React warnings. This covers normal
updates with the existing FIR package, not injected RPC failures or new timings.

Historical initial live ProofWidgets acceptance passes at
`_out/browser-pr188/fir-live-widget-v2/result.json`: two edits, one RPC per edit,
one client package, retained document root and no React warnings. Its FLT input
has no details node; details retention is covered by the rich renderer fixture.
The initial live run encountered missing canonical Lake artifacts; scoped
restoration plus `lake setup-file FLTBlueprintFirDemo.lean` repaired that local
setup without changing dependency pins.

- Full VIR ProofWidgets preview: open the existing FLT workspace and
  `FLTBlueprint.lean`, then place the cursor in its root document prose. This
  remains the working live demo. Pins and SDK are unchanged; the VBP session
  shell has the follow-up below. Restart the Lean server after rebuilding it.
- Historical FIR browser demo: real compiled Lean renderer, editable title, retained
  callback button, and close/unmount/dispose. It is explicitly a title-only
  fixture, not full Blueprint, RPC integration, or a performance display.

The FIR demo reuses the accepted SSR/browser test entry, pinned VIR host
bindings and generic Chromium driver. React owns the controls and retained DOM;
one FIR session lives outside React and is disposed after root unmount.
Only event handlers invoke updates; there is no polling or timing instrumentation.

### Preview shell follow-up

Controls and debug metrics live in a sticky header outside the document. The
bar retains a complete observation (server and browser timings together) until
the next content effect publishes its replacement. Auto scale uses the available
width and a 1–2–5 upper bound; manual scales retain 40 pixels per selected tick.

The document child element is retained across timing-panel and scale updates.
Its memo dependencies are the component type, the derived content revision and
follow-cursor. The revision changes for a new Preview, response timing (including
a refresh of an otherwise identical document), highlighting or debug mode.
Adding a content input must extend that invalidation contract. The commit
callback uses React's stable setter with a functional update, not a captured
debug-state value.

The Chromium regression counts actual document-root element construction, not
only DOM mutations or effects. Before this fix, enabling debug made four calls
in Strict Mode rather than its expected two. The updated fixture checks two,
zero calls for scale/unchanged-input updates, retained DOM/options, sticky
scroll behavior, responsive auto geometry, timing-only refresh and coherent
samples at every React commit. Evidence:
`_out/browser-pr188/sticky-shell-session.json`. The counter and React Profiler
are test-only; neither is added to the live widget. This is correctness evidence,
not a new speed comparison with FIR.

The full-FLT debug edit check also passes at
`_out/browser-pr188/sticky-shell-flt/result.json`: one client package, one preview
RPC per edit, retained controls, no React warnings, and all nine bar phases sum
to the independently measured notification-to-effect interval. One warmup and
one measured edit qualify the live bar; they are not a performance comparison.

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

## Historical baseline validation

Fresh `fir-error-aligned-consumer/acceptance.json` covers SSR, Chromium, Unicode
escaping, metadata, twenty retained-DOM updates, callbacks, ordinary provider
error recovery, completed unmount and post-disposal rejection; no React warnings.
`fir_demo_smoke.mjs URL PREPARED_VBP OUTPUT` checks the actual interactive demo's
input control, retained DOM, callback and close button and saves a screenshot.
`preview_inputs.test.mjs` checks byte-preserving unwrapping and malformed cases.

The encoded-Document entry subsequently passed matched renderer and live-widget
acceptance described above. A future performance comparison must use equivalent
payloads/options and production React, separating setup from retained updates.
FIR's deliberate session retention remains a stated configuration difference,
not pure interpreter overhead. Optimization work stays deferred.

## Matched stateful component rendering

The portable FIR none-component package and VIR control use frozen source
identity `2c1ef0f6`, VIR `36d26bc2`, and the same captured full-FLT inputs above.
Production SSR and retained Chromium DOM/control/recovery checks pass. This is
a consumer replay, not adoption in the live ProofWidgets demo; optional math
and the complete live RPC lifecycle remain separate gates.

The content callback receives an already decoded document and prepared identity
state. Its timer includes renderer execution and JS host calls, but excludes
document decoding, identity preparation, and React reconciliation/commit.
Production React, highlighting/debug off, two warmup updates per backend and
four paired rounds give:

| Backend | Median content callback | Range |
| --- | ---: | ---: |
| VIR | 1.360 s | 1.335–1.429 s |
| FIR | 1.521 s | 1.494–1.545 s |

Raw identities and observations: repository-root
`_out/browser-pr188/component-phases-20260916-01/`.
The shared outer callback uses plain Lean `Document.decode`, not the live VIR
checked codec; its duration must not be reported as live decoding performance.

A separate sampled Chromium capture attributes FIR content self time mainly
to its JS adapter (45.2%) and Wasm (45.8%). Header reads/writes and resource
boxing lead the named adapter costs; rendering-time UTF-8 conversion adds 4.5%.
VIR spends 35.5% in interpreter dispatch/evaluation, 12.5% in symbol/name lookup,
and 28.1% in its JS runtime/boundary. These are sampled attribution percentages,
not extra phase timings. FIR internal Wasm symbols are stripped. Sampling
increases runtime and its callback durations are not the timing baseline.

Capture, calibrated clock, source maps, symbolicated CPU profile, per-backend
folded stacks and attribution summary:
`_out/browser-pr188/component-profile-20260916-01/`.

Extended fidelity replay:
`VBP_COMPONENT_RICH=1 node tests/vir_preview/component_campaign_smoke.mjs CAMPAIGN OUTPUT`.
This reuses the existing Lean-generated rich fixture strings and checks seven
documents per backend, exact SSR/DOM equality, native controls, retained open
details through edits, informal/external markup, recovery, and disposal on both
backends. Evidence: `_out/browser-pr188/component-rich-20260916-01/`.
Rich acceptance cannot be enabled in measured mode, keeping the timing cohort
unchanged. The separate live FIR widget now mounts this shared stateful component
through the existing ProofWidgets shell; it does not create a second document shell.
