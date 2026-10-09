# Optional VIR client support

`import VersoBlueprintVir` exposes VIR's resource values and export markers.
It does not acquire or initialize a browser runtime, and the normal
`VersoBlueprint` import and generator do not depend on it.

The initial integration is deliberately limited to a pure Lean function called
from JavaScript. Document rendering, React and infoview are not included.
Use the package's pinned Lean toolchain; VIR source and runtime compatibility
must match. Lake acquires the exact precompiled runtime over HTTPS, requiring
`curl`. There is no local Wasm build or fallback runtime.

## Minimal example

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
recovery and disposal. It uses the repository's existing Playwright dependencies
and a Chromium browser; no widget, React or npm dependencies are involved.

Applications own their published resources and call `dispose()` when finished.
The [VIR client guide](https://github.com/ejgallego/lean-vir/blob/aa465b873387a0bf46669031da1af99f59b0f3b9/docs/guides/EMBEDDED_RESOURCES.md)
describes the upstream API. This example is a repository fixture, not a document
generator or a replacement for `lake exe vbp build`.
