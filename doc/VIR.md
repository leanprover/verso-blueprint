# Optional VIR client support

`import VersoBlueprintVir` exposes VIR's resource values and export markers.
It does not acquire or initialize a browser runtime, and the normal
`VersoBlueprint` import and generator do not depend on it.

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

## External-markup application example

The published `index.html` is an interactive external-markup preview. It uses
the included sample or a generated `blueprint-manifest.json` selected from your
filesystem. Choose a node, language, source slot and display method to inspect
the selected attachment. Serve the output directory over HTTP, rather than
opening it as a `file:` URL.

The policy is `VersoBlueprint.ExternalMarkup.select`, available through
`import VersoBlueprintVir.ExternalMarkup`. It selects the first matching
attachment in preference order, skips native preferences, and preserves the
existing missing-markup/missing-renderer failure precedence. The caller handles
the native-preview path before requesting external-markup fallback.

For this VIR pin, the example invokes a supported `String → String` export with
ordinary JSON. Requests contain only normalized language/slot descriptors,
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
results with both VIR execution and the current JS selector, tests normalization,
callback identity/error recovery and disposal, and exercises the live controls
and manifest upload.

This is an optional application example, not a default-site migration or a
performance improvement claim. Ordinary Blueprint pages are unchanged. The
existing JS selector is retained as the production implementation and parity
oracle until a default-runtime migration is separately selected.
