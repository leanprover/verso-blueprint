# VIR client support

`import VersoBlueprintVir` exposes VIR's resource values and export markers.
It does not acquire or initialize a browser runtime. Generated Blueprint sites
also publish a separate, Lake-prepared external-markup selection program and its
matching runtime. Browser loading remains lazy: native previews do not start VIR.

The Lean integration consists of pure functions called from JavaScript.
It does not use VIR's experimental DOM, React or infoview APIs.
Use the package's pinned Lean toolchain; VIR source and runtime compatibility
must match. Lake acquires the exact precompiled runtime over HTTPS, requiring
`curl`. There is no local Wasm build or fallback runtime.

## Runtime regression

The example exports `VersoBlueprintVirClientTests.Program.title : String → String`.
Its asset library declares the ordinary Lake prerequisite:

```lean
needs := #[`+VersoBlueprintVirClientTests.Program:virResourcePack]
```

The resource module uses VIR directly:

```lean
public import Vir.Resources.Assets

public def resources : Vir.Resources.ResourceSet :=
  include_vir_assets (modules := #[VersoBlueprintVirClientTests.Program])
```

The publisher calls `resources.forSite`, writes the returned files, and supplies
the returned runtime/program URLs to JavaScript's `createProgram`. No generated
build paths, manifest rewrites or VBP runtime wrapper are needed.

From this repository's checkout:

```sh
lake exe vir-client-example _out/vir-client-example
```

Run the focused regression through the existing browser harness:

```sh
uv run --project tests/browser --extra test python -m pytest tests/browser/test_vir_client.py -q --browser chromium
```

The fixture builds and serves the example using the usual worktree output paths.
The test reads only the published output, calls the real Wasm interpreter,
compares empty/ASCII/Unicode inputs against native Lean, and checks rejection,
recovery and disposal. The same fixture also publishes the application example
below. It uses the repository's existing Playwright dependencies and a Chromium
browser; no widget, React or npm dependencies are involved.

Applications own their published resources and call `dispose()` when finished.
The [VIR client guide](https://github.com/ejgallego/lean-vir/blob/aa465b873387a0bf46669031da1af99f59b0f3b9/docs/guides/EMBEDDED_RESOURCES.md)
describes the upstream API. This example is a repository fixture, not a document
generator or a replacement for `lake exe vbp build`.

## Generated-site external-markup selection

`createPreview().renderNode` uses the Lean selector when a native preview is
unavailable and the request supplies external-markup preferences. The generator
publishes the matching resources through `ResourceSet.forSite`; no test module
or example asset is needed by a production site. Builds prepare the program
through the resource library's `needs` declaration for
`+VersoBlueprintVir.ExternalMarkupProgram:virResourcePack`.

The browser opens one program lazily, shared by concurrent calls and separate
preview API instances on the same site. It retains the program across bfcache
navigation and disposes it on non-retained `pagehide`, including when opening
is still pending. Asset-loading or execution failures return
`external-markup-selection-failed` diagnostics; there is no JS policy fallback.
Reload the page after repairing a failed asset load.

This changes resource publication and the external-fallback execution path,
not the native-preview path. Serve the complete generated output over HTTP.
It is an integration and deduplication change, not a performance claim.

## External-markup application example

The published `index.html` is an interactive external-markup preview. It uses
the included sample or a generated `blueprint-manifest.json` selected from your
filesystem. The visible, searchable list includes authored names, facets,
titles and attachment counts, including nodes with no external markup. Select
a name to see its available language/slot pairs, then choose a language, source
slot and display method. Serve the output directory over HTTP, rather than
opening it as a `file:` URL.

The policy is `VersoBlueprint.ExternalMarkup.select`, available through
`import VersoBlueprintVir.ExternalMarkup`. It selects the first matching
attachment in preference order, skips native preferences, and preserves the
existing missing-markup/missing-renderer failure precedence. The caller handles
the native-preview path before requesting external-markup fallback.

For this VIR pin, production and the example invoke a supported `String → String`
export with ordinary JSON. Requests contain only normalized language/slot descriptors,
content-presence flags and renderer-availability flags. Results identify the
original attachment and preference by index. Raw source, provenance and
renderer functions never round-trip through Lean; JavaScript retains their
identity and uses VBP's existing host rendering helper.

String normalization remains in the JS adapter, using the existing browser
normalizers: ECMAScript trimming and Unicode lowercasing are not silently
replaced with Lean's string operations. There is no private object codec or
VBP-owned DOM binding. The source display is literal text, and the simple
callback is a callback example, not a Markdown/TeX renderer.

The publisher uses `writeBlueprintRuntimeModules` for the existing VBP host
modules and upstream `ResourceSet.forSite` for the matching VIR assets. Lake
declares the HTML/MJS example files and shared JSON cases as executable inputs.
The native publisher checks the expected selections; Chromium compares those
results with VIR execution and explicit expected fixtures, tests normalization,
callback identity/error recovery and disposal, and exercises the live controls
and manifest upload. Production render-node regressions cover the generated
shell, fallback precedence and diagnostics. The example uses the same adapter
and lazy program as generated pages; there is no duplicate JS selector.
