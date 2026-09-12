/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprintVir.Preview.Widget

/-!
Opt-in native React component for Blueprint previews.

VBP owns the Manual document model, renderer, extension semantics, and session
policy. VIR supplies native React and runtime infrastructure. Create the
component once with `VersoBlueprint.Experimental.VirPreview.createComponent`
and render it with `Lean.Vir.React.Node.component`, explicitly converting the
existing `Preview` to native props with `Lean.Vir.LeanRef.toJSL`.

`createRpcComponent method` connects an existing native RPC session to the same
renderer. The server returns `Preview.encode preview` as a String. The client
checks the string and decodes it once per accepted response, retaining the typed
value in React state. Render under the infoview's native `EditorContext` and pass
the document URI in `RpcInput.uri`; matching edit notifications refresh the
request. `RpcInput.params` must have stable native identity until the request
changes; `revision` permits an additional explicit refresh. Effect cleanup aborts
obsolete requests and suppresses their replies independently of cancellation.

`createWidgetComponent method` adapts VIR's native cursor/session surface to an
RPC taking `Lean.Lsp.Position` and returning that String. Register the resulting
component with `vir_proof_widget`; the upstream shell owns its root and context.
See `doc/performance/NATIVE_PREVIEW_SESSION.md` for setup and the outstanding
upstream nested-root cleanup warning before adopting this in the live FLT demo.

This experimental library is intentionally separate from `VersoBlueprint` so
ordinary Blueprint imports and compilation do not pull VIR into their closure.
-/
