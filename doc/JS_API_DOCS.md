# Verso Blueprint JavaScript API

Verso Blueprint emits browser-facing ESM modules under `-verso-data/api/` in
generated sites. These modules are plain JavaScript, documented with JSDoc, and
checked with TypeScript's `allowJs` and `checkJs` workflow.

Start from the kind of client you are writing:

| Client | Import | Main entry point |
| --- | --- | --- |
| Render Blueprint previews or generated nodes in the browser | `./-verso-data/api/preview.mjs` | `createPreview()` |
| Read manifest/cache data without DOM rendering | `./-verso-data/api/data.mjs` | `createPreviewData()` |
| Read or render graph data | `./-verso-data/api/graph.mjs` | `loadGraphs()` or `renderGraphData()` |

Use the preview API for most custom browser clients. It owns manifest/cache
loading, rendered-fragment insertion, canonical generated-node loading, math
rendering, and hydration:

```js
// Import the render-capable API from the generated site.
import { createPreview } from "./-verso-data/api/preview.mjs";

// Create one renderer for this custom client and register any client widgets
// that need to run after Blueprint content is inserted.
const preview = createPreview({
  hydrators: {
    audit(root) {
      root.querySelectorAll("[data-audit-target]").forEach(bindAuditWidget);
    }
  }
});

// Render by Blueprint label. Native generated content is preferred; external
// markup fallbacks are used only when the native preview is unavailable.
await preview.renderNode(document.querySelector("#target"), {
  label: "Chapter2:Problem2.11.6",
  externalMarkup: {
    prefer: [
      { language: "verso", slot: "statement" },
      { language: "markdown", slot: "original", render: renderMarkdown },
      { display: "source" }
    ]
  }
});
```

Use the data API when your code owns all UI and only needs structured generated
data:

```js
// Import the data-only API when no DOM rendering is needed.
import { createPreviewData } from "./-verso-data/api/data.mjs";

// Create an isolated data loader for this client.
const data = createPreviewData();

// Load semantic manifest data and build the same preview key Blueprint uses.
const manifest = await data.loadManifest();
const entry = manifest.get(data.statementPreviewKey("Chapter2:Problem2.11.6"));
const sourceDocument = entry?.sources?.[0]
  ? await data.loadSourceDocument(entry.sources[0].document)
  : null;

if (entry) {
  console.log(entry.href, entry.label, entry.facet, sourceDocument?.title);
}
```

Use the graph API when you need finalized graph records, when you want to render
manifest graph data, or when you already have graph-block markup and want the
same interactive graph renderer used by generated Blueprint pages:

```js
// Graph rendering still needs the preview renderer for popovers and hydration.
import { createPreview } from "./-verso-data/api/preview.mjs";
import { loadGraphs, renderGraphData } from "./-verso-data/api/graph.mjs";

// Read graph records from the manifest without rendering them.
const graphs = await loadGraphs();

// Render manifest graph data with the interactive graph runtime. The graph
// record should carry Lean-emitted `variants`; embedded page scripts are only
// for graph blocks that already exist in generated markup.
const previewUtils = createPreview();
await renderGraphData(document.querySelector("#graph-host"), graphs[0], {
  previewUtils,
  layout: "fill"
});
```

## Modules

The generated-site public browser API is intentionally small: clients should
import the preview, data, and graph modules below from `-verso-data/api/`.
The shared types page documents generated declarations and JSDoc typedefs for
tooling; it is not a generated browser import target. The support modules
beside the public browser entrypoints in `-verso-data/` are private
implementation chunks for generated pages, Slides, and those entrypoints.

- [preview API](module-blueprint-preview-api.html): render Blueprint nodes,
  hydrate generated fragments, resolve canonical generated-node shells, and
  provide call-scoped external-markup fallback renderers.
- [data API](module-blueprint-data-api.html): load generated manifests,
  rendered-fragment caches, preview keys, and generated-data URLs without
  installing browser-global render hooks.
- [graph API](module-blueprint-graph-api.html): read graph data embedded in
  generated graph pages, load graph records from a manifest, render manifest
  graph data, or render generated graph blocks with an explicit preview
  renderer.
- [shared API types](module-blueprint-api-types.html): request, result, option,
  manifest, cache, graph, external-markup, and hydrator shapes.

## Rendering Paths

These generated docs describe the public JavaScript modules. They do not
document Blueprint's private runtime chunks directly.

| Path | Use | Avoid |
| --- | --- | --- |
| `api/preview.mjs` | Custom browser views that render previews, canonical nodes, external-markup fallbacks, or already-inserted fragments. | Reading `window.VersoBlueprint` or importing `Commands/*.mjs`. |
| `api/data.mjs` | Audit tools, dashboards, migration checks, and Node-like clients that only need generated JSON data. | Parsing rendered HTML to rediscover labels, graph topology, status, or dependencies. |
| `api/graph.mjs` | Graph dashboards and custom pages that read or render finalized graph records. | Calling graph render helpers without an explicit `previewUtils` renderer. |
| `blueprint-page-runtime.mjs` | Regular generated Manual pages; it starts Blueprint's bundled feature scripts for you. | Custom clients that need isolated loaders, custom fetchers, or independent render options. |

The generated manifest is the semantic data contract. The HTML cache is
rendered presentation. If a client needs labels, dependency metadata, graph
records, generated links, or status metadata, read the manifest through
`api/data.mjs` or `api/preview.mjs`. If it needs to display a preview, insert
the cached fragment or canonical generated node through `api/preview.mjs`.

## Key Types

- `BlueprintPreviewOptions`: loader, hydration, math-rendering, canonical-page,
  and cache options accepted by render-capable APIs.
- `BlueprintRenderNodeRequest`: label-oriented request accepted by
  `renderNode`.
- `BlueprintExternalMarkupPreference`: ordered fallback entry for Markdown,
  TeX, Verso source, or raw-source display when a native rendered preview is
  unavailable.
- `BlueprintPreviewApi`: the render-capable API returned by `createPreview`;
  it combines manifest/cache helpers with preview-specific render methods.
- `BlueprintRenderNodeResult`: typed success or diagnostic result returned by
  `renderNode`.

## Generated Artifacts

The declarations produced by `npm run build:types` are build artifacts under
`dist/types`; they are not tracked in source. `npm run check:types` verifies
that the generated public declarations keep named API types instead of
collapsing to broad `any` shapes. The HTML docs produced by `npm run docs` are
written to `_out/jsdoc-api`; `npm run check:docs` validates the generated
module pages, local links, and Blueprint typedef anchors.

CI uses the generated docs in two places:

- The Pages deployment workflow rebuilds and checks the same docs, then stages
  them under `_site/js-api/` so the public deployment exposes them at
  [leanprover.github.io/verso-blueprint/js-api/](https://leanprover.github.io/verso-blueprint/js-api/).
- `ci.yml` uploads `_out/jsdoc-api` as the `js-api-docs` artifact for direct
  inspection from pull requests and branch runs. Those artifact URLs are
  run-specific, so use the Pages deployment as the stable documentation link.

For the curated integration guide that also covers Lean APIs, generated data
files, and stability policy, see `doc/API.md` in the source repository.
