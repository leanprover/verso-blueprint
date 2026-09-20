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

The currently embedded bundles are direct and source-display-equivalent. Their
shared component SHA256 is
`4a0c855ed5d9bbe74cd17bf22885d8d65ae0cfb0846de50d3619075477468867`.
Registered-widget smoke passes for both backends: initial and edited document,
retained control identity/state, one subscription/listener, the complete timing
bar, and no React warnings. Current reports are:

- `_out/matched-demo-v434/matched-vir-widget.json`
- `_out/matched-demo-v434/matched-fir-widget.json`

These exercise the real Lean server and Chromium shell, but not VS Code itself.

## Direct construction result

FIR package `f98aef4a33788bb3158a24f3` was qualified against the same package's
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

## Shared math successor

The old compiled timed factory always passed `mathComponent? := none`, so source
math was expected even though the shared renderer already supported a React
math component. The shared `DirectCodecProbe.createTimedView` now obtains the
downstream-owned `previewDemo.mathComponent` and passes it to the existing
renderer. Both bundles use the same `createMathComponent` implementation, local
KaTeX module and embedded KaTeX stylesheet/fonts.

VIR's new package builds successfully. FIR request `VBP-FIR-20260920-003` asks
for the exact same frozen source and one replacement direct package. The
consumer builder rejects FIR packages without the math-component import, so
KaTeX will not be activated on VIR alone.

Frozen successor input:

- source identity: `c93f07625f9dde8d9bc8b4e4a16f5360a870f5258be68e2f6a544092fd351e8b`;
- archive SHA256: `bb187ac26ff124d61425c941da41943a3f6063346887611df66ead7521bbba70`;
- VBP commit: `f775b4f883fe6c6a10786cf9b08586f1c0a57b5e`;
- Lean toolchain: `leanprover/lean4:v4.34.0-rc2`.

After the FIR successor arrives, one matched Chromium campaign will check real
KaTeX output, inline/display mode, TeX prelude, retained formula DOM, error
rendering, ordinary document fidelity, controls, timing, and disposal. Only
then will both active bundles move together.

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
