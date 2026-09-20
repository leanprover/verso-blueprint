# Matched VIR/FIR preview experiment (Lean 4.34)

This report is the single retained status record for the matched preview
experiment. Superseded checked-codec bundles, copied packages, raw replay trees
and intermediate reports are intentionally not retained.

## Active invariant

The VIR and FIR demos must expose the same product surface:

- codec: `direct-typed/v1`;
- shared document traversal and renderer source;
- retained timed view and the same timing semantics;
- the same optional presentation components;
- one current bundle and immutable runtime identity per backend.

`matched_demo_bundle.mjs` has no checked/direct mode switches. VIR always uses
the specialized VBP traversal with bounded string reuse and UTF-8/pointer
scratch storage. FIR always uses `directParsed` from the one accepted direct
construction package. The builder checks the codec, package checksums, renderer
source identity and required capabilities; a backend cannot silently fall back
to the checked decoder.

The sticky top-right badge identifies only the execution backend (`VIR` or
`FIR`). It uses the editor's badge foreground/background rather than subtle
description text. Codec and renderer versions are deliberately absent from the
UI because they are invariants, not user-selectable modes.

The currently embedded bundles are direct, KaTeX-enabled and renderer-equivalent. Their
shared component SHA256 is
`4a0c855ed5d9bbe74cd17bf22885d8d65ae0cfb0846de50d3619075477468867`.
FIR uses the sole accepted successor package `2c53e82bae00662f4222be39`;
its package-checksum SHA256 is
`9f402d9bad725a36565c24fadaa67b798803c23cf883080d7c68203eb4d512eb`
and its Wasm SHA256 is
`ea321021839a3de18fc117eb934e718727a69c77732fcea85109526c771e0bc9`.
Registered-widget smoke passes for both backends: initial and edited document,
retained control and formula identity/state, real KaTeX HTML/MathML, one
subscription/listener, the complete timing bar, and no React warnings. Current
reports are:

- `_out/matched-demo-v434/matched-vir-widget.json`
- `_out/matched-demo-v434/matched-fir-widget.json`
- `_out/matched-demo-v434/matched-flt-vir-widget.json`
- `_out/matched-demo-v434/matched-flt-fir-widget.json`

These exercise the real Lean server and Chromium shell, but not VS Code itself.

## Direct construction result

The retired predecessor package `f98aef4a33788bb3158a24f3` was qualified against its
checked `browserParsed` control and matched VIR direct path. The full-FLT replay
uses production React, two warmups and six retained updates per session, with
diagnostics/highlighting/profiling disabled.

Both FIR decoder paths produced the same normalized 7,011-element DOM and text
hashes, retained the follow-cursor control and an unchanged paragraph, and
emitted no React warnings. React was unmounted before the retained session was
disposed.

| Full-FLT browser phase | Checked FIR | Direct FIR | Change |
| --- | ---: | ---: | ---: |
| `JSON.parse` | 19.1 ms | 23.5 ms | noise-sized |
| Typed document construction | 1,259.9 ms | 236.6 ms | -81.2% |
| Decoded value to observed DOM update | 1,608.9 ms | 1,782.2 ms | noisy |
| Parse through observed DOM update | 2,887.8 ms | 2,042.3 ms | -29.3% |

Construction improved in both AB/BA order pairs. Whole-update reductions were
13.4% and 44.2% because the larger render phase was temperature/order sensitive;
29.3% is the pooled result for this campaign, not a stable product-latency
claim.

The matched direct comparison measured VIR construction at 65.0 ms and FIR at
195.3 ms. Parse through observed DOM averaged 1,501.2 ms for VIR and 1,710.5 ms
for FIR. FIR's remaining construction overhead is a useful adapter target, but
render variation is too large for a general backend ranking.

The replay excludes RPC/LSP, server encoding, transport, package loading,
startup, paint and passive-effect waiting. The DOM endpoint is observed after a
React mutation, not isolated React internal commit time or completed paint.

## Shared math successor and rendering profile

The shared `DirectCodecProbe.createTimedView` obtains the downstream-owned
`previewDemo.mathComponent` and passes it to the existing renderer. VIR and FIR
import one module-scope `PreviewMath`, built from the same `createMathComponent`
implementation and local KaTeX module. The shell embeds one KaTeX stylesheet
with local fonts. The consumer builder rejects a FIR package without the exact
math-component import, frozen source identity and package checksum.

The successor input is:

- source identity: `c93f07625f9dde8d9bc8b4e4a16f5360a870f5258be68e2f6a544092fd351e8b`;
- archive SHA256: `bb187ac26ff124d61425c941da41943a3f6063346887611df66ead7521bbba70`;
- VBP commit: `f775b4f883fe6c6a10786cf9b08586f1c0a57b5e`;
- Lean toolchain: `leanprover/lean4:v4.34.0-rc2`;
- FIR package: `2c53e82bae00662f4222be39`.

Real-server Chromium acceptance passes on both the small fixture and the
complete FLT document. It checks real KaTeX HTML/MathML, no valid-math errors,
retained formula and control nodes across an edit, matched renderer output,
unmount-before-dispose and zero React warnings. The external FLT file is not
modified: the harness injects its two cursor anchors only into the opened
in-memory buffer.

The diagnostics-off full-FLT campaign used production React, two warmups and
six retained updates per session in VIR → FIR → FIR → VIR order. Both backends
produced the same normalized text and 110,018-element post-KaTeX DOM hashes.

| Retained full-FLT phase | VIR pooled mean | FIR pooled mean |
| --- | ---: | ---: |
| `JSON.parse` | 13.3 ms | 19.6 ms |
| Typed document construction | 66.0 ms | 202.0 ms |
| Decoded value to observed DOM update | 1,260.6 ms | 1,540.0 ms |
| Parse through observed DOM update | 1,339.9 ms | 1,761.6 ms |

The two order pairs put FIR's total overhead at 44.4% and 12.4%; the pooled
31.5% is therefore descriptive, not a stable backend ranking. Rendering itself
was 34.3% and 4.3% slower in the two pairs. The consistent remaining FIR cost
is typed construction, while rendering is strongly temperature/order sensitive.

A separate CDP-instrumented diagnostic run brackets actual component callbacks.
The session component runs twice for a changed document: the guarded render-time
state adjustment computes identities and asks React to retry, then the retry
observes the new state and constructs the retained content element.

| Diagnostic full-FLT phase | VIR mean | FIR mean |
| --- | ---: | ---: |
| First session pass and identity-state adjustment | 280.3 ms | 334.2 ms |
| Retried session/shell callback | 57.4 ms | 13.3 ms |
| Lean document → React elements | 934.3 ms | 909.7 ms |
| Remaining React/DOM-observation interval | 15.2 ms | 31.2 ms |

These diagnostic timings are two samples per backend under CPU sampling and are
not headline latency. The first callback also includes shell/session work and is
not a pure identity timer. The residual is computed within each sample after
subtracting all three non-overlapping callback brackets; it is not isolated
React internal commit time. The observed-DOM endpoint excludes paint and KaTeX
passive effects. Semantic checks wait for every formula effect outside the timed
region.

### Exact FIR symbol attribution

FIR supplied a standard-name-section companion for the accepted math package.
Its verifier covers all 3,346 import-first function rows and proves byte equality
of every non-custom section with captured release Wasm
`ea321021839a3de18fc117eb934e718727a69c77732fcea85109526c771e0bc9`.
The VBP summarizer resolved all 2,892 sampled FIR Wasm frames; no sampled frame
remained unresolved. The symbolized derived report is
`_out/matched-demo-v434/math-profile-fir-symbolized-01/`.

The dominant compiled path is repeated Blueprint extension decoding, not generic
React host work. In the two non-overlapping session/content callback windows:

| Sampled FIR attribution | Mean per update | Share of its window |
| --- | ---: | ---: |
| `prepareIdentities` within the session callbacks | 327.5 ms | 94.3% |
| `Lean.Name.fromJson?` below identity preparation | 272.4 ms | 78.4% |
| `Lean.Name.fromJson?` while constructing document elements | 427.0 ms | 46.9% |

Together, the two non-overlapping `Lean.Name.fromJson?` chains account for about
699.4 sampled ms per update, or 54.3% of the sampled parse-excluded FIR render
window. This is inclusive sampled attribution, not an elapsed-time savings
prediction.

Exact stacks connect both chains to VBP's `decodeExtension?`: identity
preparation calls `blockIdentity?`, while element construction calls both block
identity selection and `renderBlock?`. The decoded `BlockOccurrence` and
`ExternalMarkupBlockData` records contain `Data.Label`, which is a `Lean.Name`;
`Lean.Name.fromJson?` reparses its dotted string through `Substring.Raw.toName`
and `Lean.Syntax.splitNameLitAux`. Thus the same already-decoded extension JSON
is interpreted repeatedly during one retained update. The next bounded
experiment should decode the renderer-owned extension view once per document
update and reuse it for identity and presentation, while preserving the current
document codec and exact renderer semantics.

## Rebuild

The active direct bundles are generated without codec/version flags:

```sh
VBP_DEMO_MATCHED_BACKEND=vir \
VBP_MATCHED_IR_SET=.lake/build/vir/module-sets/VersoBlueprintVirTests/NativeSession/DirectCodecProbe.irpkg-set.json \
VBP_DEMO_OUTPUT=.lake/build/matched-vir-demo.js \
node tests/vir_preview/build_checked_json_demo.mjs

VBP_DEMO_MATCHED_BACKEND=fir \
VBP_MATCHED_FIR_PACKAGE=/absolute/path/to/the/accepted/direct/package \
VBP_DEMO_OUTPUT=.lake/build/matched-fir-demo.js \
node tests/vir_preview/build_checked_json_demo.mjs

LAKE_RESTORE_ARTIFACTS=true scripts/lean-low-priority lake build \
  +MatchedPreview:olean +MatchedPreview.Server:olean
node --test tests/vir_preview/demo_shell.test.mjs
```

`MatchedPreview` embeds both bundles through Lake `needs`. The FLT demo is
`.worktrees/_reference-blueprints/edit/matched-demo-v434/verso-flt/
FLTBlueprintMatchedDemo.lean`; its single `useFir` boolean selects the backend.
Saving that choice and restarting the Lean server is required because the
registered widget module changes.

The debug bar records the last completed edit/version rather than cursor-only
traffic. It partitions dispatch, server waits/evaluation, RPC remainder,
decoding, identity preparation, element construction and commit observation.
The demo clock is intentionally coarse and disabled from headline replay runs.
