# Consolidated VIR 4.34 refresh qualification

This is an isolated qualification, not adoption into the working widget or the
frozen FIR/VIR comparison campaign. No new performance result is claimed.

## Exact inputs

- Consumer base: `c6e84e25` (the working widget remains on this source).
- Previous VIR: `36d26bc224f0c2a52cd586587b2c3e1b1ade70d6`.
- Candidate VIR: `92d7cc91e4f9bbf48b7c113cfd76d56ff767df4d`, local
  `chore/lean-4.34-support`, clean at inspection.
- Lean: `leanprover/lean4:v4.34.0-rc2` on both sides.
- Candidate SDK archive SHA256:
  `0226a86f3ddd841dbd3197af2454ee7b63a602b8c2b097482f807725c08aa767`.
- Release Wasm SHA256:
  `3644f76050031b59ae84bd9f36379b6865a8c12d2438a83722ccc0613a8e916f`.
- Debug Wasm SHA256:
  `9587ab2f6042e0cb9306f95bb0ad4511b040e736662405a941a7d49b5f820f2e`.

All 32 SDK payload files were independently checked against their manifest
hashes. The manifest names the candidate source, reports `gitDirty: false`, and
declares React and React DOM `19.2.7`. The producer's successful browser gates
remain producer evidence; they are not consumer widget acceptance.

The candidate source and SDK were inspected in VIR's
`.worktrees/lean-4.34-support`. The upstream branch is local-only in its handoff;
the remote query returned no matching `chore/lean-4.34-support` branch.

## What is available

The candidate contains landed PR189 (`08c44141` is an ancestor). Its host
dispatcher no longer takes per-argument callback snapshots; result lifting is
direct and callback reclamation belongs to GC/disposal. Explicit host-effect
rollback remains. This targets work visible in our previous interpreter
profile, but its consumer speedup has not been measured here.

It also contains newer typed native React/JavaScript APIs and native primitive
operations. These require source migration rather than an SDK-only swap.

The public checked native-JSON codec and browser Performance clock are **not**
present in this checkpoint. Keep the experimental checked JSON bridge and the
demo-only clock until their upstream replacements are qualified. Do not replace
the efficient codec with the plain Lean JSON parser merely to update VIR.

## Consumer build discovery

The isolated dependency owner and both its nested and consumer Lake manifests
were retargeted to the exact candidate. The renderer modules
`VersoReact.Renderer`, `VersoReact`, and
`VersoBlueprintVir.Preview.Renderer` compiled successfully.

The initial `lake build VersoBlueprintVir` failed in the preview session module
because the consumer used removed React convenience APIs:

- `State` and its `set`/`modify` helpers;
- `StateTuple.toState`;
- `Hooks.DependencyList.ofArray`;
- `Callback.ofUnary`.

These are consumer adaptation work, not evidence of a candidate renderer bug.
The initial infoview bundle also lacked installed `esbuild`; package-local
`npm install --ignore-scripts --no-audit --no-fund` completed successfully.
The subsequent isolated `lake build @lean_vir/infoviewBundle` passes. A Lean
Beam check independently reports the same removed `State` and callback APIs in
the session module; no successful preview-module checkpoint is claimed.

## Implemented consumer migration

The preview and scalar test fixture now use native hook tuples
(`Js.Tuple2.first`/`second`), explicit `SetStateAction` values/updaters, native
nullary effect/memo functions, native dependency arrays and typed synthetic-event
callbacks. No compatibility `State` wrapper was introduced. Browser actions use
the public identity-only `DomM.toRuntime` boundary where required.

The render-path cleanup removes:

- Eight constant shell style builders: CSS preserves the layout and live theme
  variables; its immutable React stylesheet element is created once per factory.
  Timing-bar geometry remains dynamic. Initial RPC status styling is retained
  because it can appear before the document shell exists.
- Repeated conversion of the three immutable initial session values. They are
  captured by the factory; each mount owns independent React state and replaces
  values rather than mutating the shared initial objects.
- The RPC effect's Lean-backed cleanup-resource object: its native cleanup
  closure captures the active flag and abort controller directly.
- The content effect's no-op cleanup callback: setup returns native `undefined`.
- URI conversion, request-object creation and Lean-backed child props on unchanged
  panel progress updates. The widget memo now retains the complete child element
  by native component/session/URI/line/character dependencies. Child state and
  context updates remain React-owned.
- Unused state-setter projections on unchanged document renders and unused
  diagnostic-value projections with debug disabled.

## Consumer acceptance

Targeted preview, scalar/String/session IR-package and embedded-shell builds pass.
The matched SDK is installed through `:virSdk`, not manually copied Wasm. Twenty
JavaScript unit tests pass. Chromium gates pass for scalar RPC, String RPC,
encoded-document RPC, native session/timing accounting and the registered
embedded shell with real Lean RPC. They cover retained controls/error recovery,
cancellation/stale replies, scale changes, timing-only skip-decode, math,
informal blocks, focus and disposal with zero React warnings. Additional checks
assert one retained stylesheet, computed grid/flex/sticky layout and no inline
constant config-panel style.

The embedded gate requires the same four-line list-registration parser patch as
the working demo. It is now recorded at
`tests/vir_preview/verso-list-widget-registration.patch`, applied only to the
isolated consumer dependency. Exact patched Parser.lean SHA256:
`8929da2092f0966ec88c35cb031b36bf28796c335bff2e067cf3ff73ae16a113`.
The unpatched fresh dependency reproduces missing widget registrations at list
cursors; the patched dependency passes. No producer source was changed.

Browser reports live under `_out/upstream-vir-20260917/`. RPC reports include
SDK-manifest, relevant consumer-source and parser hashes; this is not a complete
frozen closure for FIR capture. The later Beam worker became stale following the
dependency rebuild and was stopped; successful batch/browser gates are the
acceptance evidence, not a claimed final Beam checkpoint or clean full CI run.

The initial read-only cached-output failure was resolved with scoped
`LAKE_RESTORE_ARTIFACTS=true` for these direct IR/file-consumer builds and tests;
the repository's normal cache-in-place policy is unchanged.

## Remaining work

The shared document renderer still builds constant style objects per node,
including paragraphs, lists, code and informal blocks. This is a separate,
promising host-call/allocation optimization; it has not been eliminated by the
shell CSS change. Profile and remove it next without changing document codecs or
identity semantics. Do not attribute an unmeasured speedup to this migration.

Full FLT consumer qualification and the same-input rendering profile are still
pending. Only after those gates pass should the working VIR pin/bundle change.

The existing FIR packages and their frozen source closures are unchanged. A new
matched FIR capture must use a complete frozen migrated source closure; it must
not silently reuse the older renderer artifact with a newer source identity.
