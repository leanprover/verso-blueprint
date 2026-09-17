# Matched widget refresh on Lean 4.34

The isolated `feat/matched-demo-v434` checkpoint refreshes the shared upstream
ProofWidgets shell and interpreter to VIR `cddcc35a46fd4683d2437369072d4ecc5a5a84be`.
Lean remains `leanprover/lean4:v4.34.0-rc2`; the matching clean SDK manifest has
SHA256 `1556758818bb2fa72d237d9ca9dd91614b8e3c68bfb45af43a4481e67e78ba76`.

Both backends share `matched_document_component.mjs`: one native React
component receives the checked server Document JSON string, memoizes parsing
and runtime-local decoding by that string, and invokes the retained default
Lean view. RPC/editor subscription, cancellation, package loading and shell
lifetime remain upstream-owned. The selected external runtime is disposed
after the shell runtime, including failed-open cleanup.

VIR uses the frozen `styles-baseline-ir/DecodeProbe.irpkg-set.json` from the
earlier paired campaign, verifying every member hash and length. FIR uses
immutable package `23dfd8ab282aa8b5b0b7d90b`, SHA256SUMS hash
`d6d33302cca5bd9aeba5bcbb19866d7f3bbe6f6648ec62c699833fce2a5aa122`.
All author-side provider source hashes and React lock identities are checked
against the refreshed dependency before bundling. This preserves the paired
renderer baseline while changing the VIR interpreter separately.

## Local rebuild

Install the exact SDK with the ordinary `:virSdk` facet and explicit
`VIR_SDK_ARCHIVE` / `VIR_SDK_EXPECT_COMMIT`. Then generate both bundles:

```sh
VBP_DEMO_MATCHED_BACKEND=vir \
VBP_MATCHED_IR_SET=/home/egallego/lean/verso-blueprint/_out/upstream-vir-20260917/styles-baseline-ir/DecodeProbe.irpkg-set.json \
VBP_DEMO_OUTPUT=.lake/build/matched-vir-demo.js \
node tests/vir_preview/build_checked_json_demo.mjs

VBP_DEMO_MATCHED_BACKEND=fir \
VBP_MATCHED_FIR_PACKAGE=/home/egallego/lean/fir/.worktrees/wasm-generation-4.34/.deps/native-session-probe/configured-bc9685f9/packages/23dfd8ab282aa8b5b0b7d90b \
VBP_DEMO_OUTPUT=.lake/build/matched-fir-demo.js \
node tests/vir_preview/build_checked_json_demo.mjs

scripts/lean-low-priority lake build +MatchedPreview:olean +MatchedPreview.Server:olean
node --test tests/vir_preview/demo_shell.test.mjs
```

The `MatchedPreview` library declares both embedded bundles with Lake `needs`.
The FIR package is copied and checksummed under `.deps/matched-fir-package`;
producer artifacts and existing live pins are untouched.

## Acceptance and demo

Both registered widgets pass real LSP/Chromium initial rendering, edit
notification, unchanged-props and cursor-update checks. Controls retain DOM
identity/state; the client package is built once, with one editor subscription
and listener, and no React warnings. Evidence is under
`_out/matched-demo-v434/{vir,fir}-widget.json` at the repository root.

The small fixture is `VersoBlueprintVirTests/MatchedPreviewServer.lean`.
Select its `useFir` boolean before running `native_browser_smoke.mjs` with
`VBP_NATIVE_MATCHED_BACKEND=vir|fir` and `--embedded-preview`; the registered
shell hash must match that backend. Set `VBP_NATIVE_PREVIEW_REPORT` to an
isolated output and run through `scripts/lean-low-priority lake env node`.

The independent FLT checkout is
`.worktrees/_reference-blueprints/edit/matched-demo-v434/verso-flt/`.
Open `FLTBlueprintMatchedDemo.lean`; its startup boolean selects VIR or FIR.
The unchanged full FLT root document is included by the module-system wrapper.
The checkout's `MATCHED_PREVIEW.md` explains use and the warmed Mathlib source
reuse. No previous FLT demo is retargeted.

The complete FLT wrapper also passes the same registered-widget, edit and
retained-control checks on both backends, with no React warnings. Reports are
`_out/matched-demo-v434/flt-{vir,fir}-widget.json`. These are real LSP/Chromium
checks, not automated VS Code acceptance.

Math is source-display mode on both backends; no optional native-math acceptance
is claimed. Debug timings cover server preparation only. These acceptance runs
do not replace the order-balanced performance campaign or establish new speed
numbers on the refreshed interpreter.
