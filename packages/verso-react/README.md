# Verso React renderer

An experimental, independently buildable Lake package for rendering
`Verso.Doc.Part Verso.Genre.Manual` with native React through VIR. It lives in
the VBP repository but does not depend on Blueprint, its RPC, or its widget.
It depends on Verso and VIR; it is not a backend-independent HTML generator.

## Use

The package has its own `lakefile.lean`, manifest, toolchain and tests. From
this directory:

```sh
lake build
lake test
```

A local consumer can add:

```lean
require «verso-react» from "/path/to/verso-blueprint/packages/verso-react"
```

The public Lean entry point is:

```lean
import VersoReact

def renderDocument (part : Verso.Doc.Part Verso.Genre.Manual) :
    Lean.Vir.React.ReactM (Lean.Vir.Js Lean.Vir.React.Node) :=
  VersoReact.Renderer.render part
```

Call this as an ordinary render helper inside a React component. It creates
nodes; it does not create a React root, manage state, register a widget, fetch
documents, or install a runtime. The application owns those operations.

This checkpoint uses Lean **4.34.0-rc2**, Verso `52c8c955`, and VIR `6c696039`.
VIR's exact pin still uses a local Git URL; this is not yet a published
download-and-build recipe. Do not mix its Lean packages or SDK with another
toolchain. The parent VBP package obtains VIR through this dependency.
The parent [native setup recipe](../../doc/performance/NATIVE_PREVIEW_SESSION.md#current-isolated-setup)
records the matching SDK and the existing build/test commands.

## Boundary

The input is the existing Manual tree, with no projected or serialized
intermediate document model. Ordinary blocks/inlines, lists, descriptions,
parts, math source, React keys, and optional change/focus markers live here.
`renderBlockIds`, `changedBlockIds`, and `changedBlockIdsAndCount` operate on
the same tree; call them only when the application needs change diagnostics.

`Renderer.Extensions` supplies three optional application functions:

- `renderInline?` replaces a recognized inline extension. Returning `none`
  displays the extension marker and its original children.
- `renderBlock?` receives the key, an attribute builder, the extension and a
  lazy child renderer. It can preserve the children or skip them for hidden
  content. Returning `none` displays the marker and children.
- `blockIdentity?` supplies a semantic identity for an extension. It is used
  consistently for React keys and change matching; duplicates are disambiguated.

These are render helpers, not hook scopes or a component registry. Keep them
free of effects and do not call React hooks from them. `Options.attributes`
adds application metadata to the outer article; RPC versions, timing and
cursor correlation are not part of the renderer's document input.

VBP's adapter remains in `src/VersoBlueprintVir/Preview/Renderer.lean` in the
parent package. It owns Blueprint math/preludes, informal blocks, external
markup modes, and their identities. Unknown or malformed extensions remain
visible. Math and external markup are currently source-preserving, not KaTeX
or Markdown typesetting; this extraction does not change that fidelity.
The Part-only Blueprint adapter shows "Statement"/"Proof": exact mathematical
kinds now belong to the separate canonical render model, not block occurrences.

## Runtime acceptance

The package owns the plain-Manual fixtures and React output/key assertions in
`tests/`. The parent repository's `scripts/test-verso-react.sh` runs those plus
the Blueprint adapter through freshly generated VIR packages and actual React
server rendering. It reuses VIR's public SDK/runtime/host bindings; no custom
host or duplicate browser/LSP harness is introduced.

From the parent repository, after `npm ci` in `.lake/packages/lean_vir`:

```sh
VIR_SDK_ARCHIVE=/path/to/matching/lean-vir-sdk.tar.gz \
VBP_RENDERER_REPORT_DIR=/absolute/path/to/verso-blueprint/_out/native-preview-modules/renderer \
  scripts/test-verso-react.sh
```

The packaging build uses scoped artifact restoration pending VIR's reviewed
cache-in-place fix. The standalone Lean build does not require the SDK, npm,
or Blueprint. Runtime acceptance checks rendered output and React keys, not
browser reconciliation, editor notifications, or latency. The full native
widget migration remains separate.
Set `VBP_RENDERER_REPORT_DIR` to retain acceptance output in a separate directory.
