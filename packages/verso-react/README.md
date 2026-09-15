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

This checkpoint uses Lean **4.34.0-rc2**, Verso `52c8c955`, and VIR `36d26bc2`.
VIR's exact pin still uses a local Git URL; this is not yet a published
download-and-build recipe. Do not mix its Lean packages or SDK with another
toolchain. The parent VBP package obtains VIR through this dependency.
The parent [native setup recipe](../../doc/performance/BROWSER_PR188.md)
records the matching SDK and the existing build/test commands.

## Boundary

The input is the existing Manual tree, with no projected or serialized
intermediate document model. Ordinary blocks/inlines, lists, descriptions,
parts, math source, React keys, and optional change/focus markers live here.
`renderBlockIds`, `changedBlockIds`, and `changedBlockIdsAndCount` operate on
the same tree; call them only when the application needs change diagnostics.

`Renderer.Extensions` supplies three optional application functions:

- `renderInline?` receives a sibling-local React key and replaces a recognized
  inline extension. Use the key on the returned element; it is not a source
  address. Returning `none` displays the extension marker and its original children.
- `renderBlock?` receives the key, an attribute builder, the extension and a
  lazy child renderer. It can preserve the children or skip them for hidden
  content. Returning `none` displays the marker and children.
- `blockIdentity?` supplies a semantic identity for an extension. It is used
  consistently for React keys and change matching; duplicates are disambiguated.

These are render helpers, not hook scopes or a component registry. Keep them
free of effects and do not call React hooks from them. Props and styles are native
JavaScript objects (`Js Props`), constructed with JSX or `js%{...}`. Pass styles
under the `style` property, not as top-level element properties. The block
attribute callback accepts a native style object and returns native element props.
`Options.attributes : Option (Js Props)` adds application metadata to the outer article; RPC versions, timing and
cursor correlation are not part of the renderer's document input.

React keys are local to each sibling list. Navigation/focus addresses remain in
`data-verso-block`, `data-verso-part`, and `data-verso-list-item`; do not derive
React keys from these paths. Inline and list-item positions are relative to their
retained parent, so moving that parent does not reset their state. This does not
provide stable identity for reordering those children within the parent.
Ordinary block keys still identify complete content: changing an unlabeled block
remounts it. Explicit extension identities retain their existing policy. Identical
unlabeled siblings are distinguished by occurrence, not by an inferred identity.

For a retained preview, keep a `VersoReact.Fingerprint.State` in the component's
existing React state, initially `default`. On a document-content update:

```lean
let identities := VersoReact.Renderer.prepareIdentities previous document extensions
VersoReact.Renderer.render document { identities? := some identities } extensions
```

Retain `identities` as part of the same pure state transition as the accepted
document; do not mutate a ref or global registry during render. Pass the state
prepared for that document and the same extension identity policy. Cursor,
version and display-control changes do not require preparing it again.

Preparation hashes the existing Lean values, then checks exact typed equality
within each hash bucket. Retained contents keep short tokens; different contents
get fresh tokens even on a hash collision. The state retains only the current
document's distinct values, while its counter prevents reuse of retired tokens.
These tokens are session-local React identities, not source addresses or a wire
format. Preparation visits hidden descendants too, but never calls the rendering
callbacks. Without `identities?`, stateless rendering keeps full serialized-content
keys. Optional change diagnostics still use their separate serialized snapshots.

Typed equality is deliberately representation-sensitive: for example, hand-built
JSON numbers with different mantissa/exponent pairs can print identically but
receive different tokens. It does not silently identify unequal Lean values.

VBP's adapter remains in `src/VersoBlueprintVir/Preview/Renderer.lean` in the
parent package. It owns Blueprint math/preludes, informal blocks, external
markup modes, and their identities. Unknown or malformed extensions remain
visible. Math defaults to source-preserving output. `Extensions.mathComponent?`
can supply a stable React leaf; `web/katex.mjs` is the optional KaTeX adapter used
by the local Blueprint demo. It owns only the descendants of its empty React
container, typesets in an effect keyed by source/prelude/mode, and cleans up on
replacement/unmount. The caller bundles matching KaTeX CSS/fonts once per shell.
External markup remains source-preserving, without Markdown typesetting.
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
