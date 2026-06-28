# Blueprint API Reference

This document is for integration work: custom generators, dashboards, audit
pages, slide adapters, and browser scripts that need to read Blueprint data or
render Blueprint fragments outside the standard generated pages.

For authoring syntax and rendering behavior, see
[`MANUAL.md`](./MANUAL.md). For the architecture boundaries behind these APIs,
see [`DESIGN_RATIONALE.md`](./DESIGN_RATIONALE.md).

For exact JavaScript signatures, typedefs, return shapes, and module-level
examples, use the
[generated JavaScript API reference](https://leanprover.github.io/verso-blueprint/js-api/).
This source document is the curated integration guide: it explains which API
surface to choose and where the stability boundaries are.

If you are not sure where to start, read [Choosing an API](#choosing-an-api)
first. The short version is:

- use the generated ESM modules for ordinary browser `import { ... } from ...`
  JavaScript
- use `createPreviewData()` from `api/data.mjs` when a client only needs
  manifest/cache data and should not import DOM rendering code
- use `createPreview()` from `api/preview.mjs` when a browser client needs to
  render Blueprint nodes, fragments, or external-markup fallbacks
- use `api/graph.mjs` when a client needs graph data or graph-block rendering
- use the generated manifest for semantic data and the HTML cache for rendered
  fragments
- use the Lean graft/render APIs when a generator wants to place Blueprint nodes
  into a custom page
- use the generated JavaScript API reference, not this guide, for exhaustive
  browser export documentation

## Contents

- [Stability Policy](#stability-policy)
- [Choosing an API](#choosing-an-api)
- [Rendering Path Map](#rendering-path-map)
- [Generated Data Files](#generated-data-files)
- [Graph Data APIs](#graph-data-apis)
- [Lean Graft and Render APIs](#lean-graft-and-render-apis)
- [Browser ESM APIs](#browser-esm-apis)
- [Browser Runtime API](#browser-runtime-api)
- [Preview Result Shapes](#preview-result-shapes)
- [Bundled Helper Boundary](#bundled-helper-boundary)
- [Standalone Example](#standalone-example)

## Stability Policy

Stable APIs are the documented Lean names, generated data files, generated ESM
modules, and browser runtime entrypoints listed here. They are intended for
custom generators, dashboards, audit pages, slide adapters, and standalone
browser clients.

Bundled helper APIs are narrower. They exist so Blueprint's own graph, summary,
relation-panel, inline-preview, and slide scripts can share runtime mechanics.
They are not a custom-client contract unless they are promoted into the stable
tables below.

Browser clients should use the generated ESM modules. `api/preview.mjs` imports
the renderer directly and exposes `createPreview()` so each client makes its
rendering dependency explicit at the call site. Regular generated Manual pages
load `-verso-data/blueprint-page-runtime.mjs` as a module script from
`extraHead`; that page runtime constructs the renderer and starts Blueprint's
own inline-preview, relation-panel, graph, and template-preview hydrators
without depending on `window.VersoBlueprint`. The remaining
`window.VersoBlueprint.onRenderReady` bridge is an internal adapter for the
current classic-script Slides output path. Adapter internals may be staged under
`window.VersoBlueprint.__private`, but that namespace is not a supported client
API.

## Choosing an API

Start from what you are building:

| You are building | Start with | Why |
| --- | --- | --- |
| A small browser script or standalone web page | [`api/data.mjs`](#browser-esm-apis), [`api/preview.mjs`](#browser-esm-apis), or [`api/graph.mjs`](#browser-esm-apis) | These are normal ESM modules, so clients can use regular `import { ... } from ...` syntax. |
| A script loaded by a generated Blueprint page | `createPreview()` from [`api/preview.mjs`](#browser-esm-apis) | The generated module constructs the renderer directly from emitted runtime modules without waiting on `window.VersoBlueprint.render`. |
| A Node-like audit or migration tool that only reads generated data | `createPreviewData()` from [`api/data.mjs`](#browser-esm-apis) | It loads manifest/cache data without importing render, hydration, or DOM surface code. |
| A graph dashboard or audit page | [`loadGraphs()`](#graph-data-apis) | It reads finalized graph records from `blueprint-manifest.json`, even when the current page has no rendered graph block. |
| A custom browser widget beside an existing graph block | [`getGraphData(element)`](#graph-data-apis) and `getGraphVariants(element)` | These read the graph data embedded next to a rendered graph. |
| A custom page or slide that already has graph-block markup | [`renderGraphBlock(element, { previewUtils })`](#graph-data-apis) | It loads the graph renderer and initializes the same block UI used by generated graph pages, using an explicit preview renderer for graph popovers. |
| A custom page that needs a rendered preview body only | [`renderPreviewInto(element, key)`](#browser-esm-apis) or [`api.renderPreviewInto`](#browser-runtime-api) | This inserts the cached rendered fragment into your own wrapper. |
| A custom page that should look like generated Blueprint nodes | [`renderCanonicalPreviewInto(element, key)`](#browser-esm-apis) or [`api.renderCanonicalPreviewInto`](#browser-runtime-api) | This inserts the standard Blueprint node wrapper and body. |
| A custom page that starts from a label and can render external TeX or Markdown fallback source | [`renderNode(element, request)`](#browser-esm-apis) | This renders the generated node shell for native previews and external-markup fallbacks; external renderers own only the content slot. |
| A Lean generator that renders Blueprint nodes into another page | [`Informal.Graft.renderNodeFromManifestCache`](#lean-graft-and-render-apis) | It reuses the generated manifest/cache pair while letting the generator choose wrapper classes and diagnostics. |
| Lean code that needs graph data during rendering | [`Informal.GraphApi`](#graph-data-apis) | It finalizes semantic graph data against completed traversal state. |

Prefer the highest-level entry point that matches the job. Direct
manifest/cache lookup is available, but it is usually only needed when a client
wants custom joining behavior or explicit diagnostics.

Two rules keep most integrations simple:

1. Treat `blueprint-manifest.json` as semantic data: labels, statuses, graph
   records, dependency data, preview keys, hrefs, and display metadata.
2. Treat `blueprint-html-cache.json` as rendered HTML: insert it and hydrate it,
   but do not parse it to recover semantic facts.

## Rendering Path Map

Most integrations fit one of the paths below. The main choice is whether the
client owns a custom interface, is part of Blueprint's generated page runtime,
or is still going through the classic Slides bridge.

| Context | Entry point | What it owns | What callers should use |
| --- | --- | --- | --- |
| Regular generated Manual page | `-verso-data/blueprint-page-runtime.mjs` | Creates one renderer with `createPreview()`, starts inline previews, relation panels, graphs, and descriptor-bound template previews. | Nothing extra; `withBlueprintAssets` installs this module. |
| Custom browser page, dashboard, audit view, or slide adapter | `-verso-data/api/preview.mjs` | Manifest/cache loading, preview lookup, rendered-fragment insertion, canonical node loading, math rendering, and hydration. | `createPreview()`, then `resolvePreview`, `renderPreviewInto`, `renderCanonicalPreviewInto`, `renderNode`, or `hydrate`. |
| Data-only browser or Node-like client | `-verso-data/api/data.mjs` | Manifest/cache URL helpers, loading, status readers, and graph-data loading without DOM rendering. | `createPreviewData()`, `loadManifest`, `loadHtmlCache`, `loadGraphs`, or single-entry readers. |
| Graph data or graph-block rendering | `-verso-data/api/graph.mjs` | Graph JSON discovery, manifest graph loading, lazy graph runtime loading, and graph block initialization. | `loadGraphs`, `getGraphData`, `getGraphVariants`, or `renderGraphs(root, { previewUtils })`. |
| Blueprint-owned panels in generated pages | Renderer bundled helpers | Panel slots, content updates, trigger lifetime, dismissal, repositioning, diagnostics, and shared preview lookup. | Feature scripts use `createPreviewSurface`, `renderPreviewIntoSurface`, or `resolvePreviewHtml`; custom clients should not import these helpers directly. |
| Summary and code-summary previews | Lean-emitted template descriptors plus `preview-runtime-template.mjs` | Selector configuration and binding for preview templates. | Emit descriptor attributes from Lean; no feature-specific startup script is needed. |
| Current classic-script Slides output | `Slides/ClassicPreviewAdapter.lean` and `window.VersoBlueprint.onRenderReady` | Classic-script compatibility for the same renderer shape used elsewhere. | Treat this as an internal bridge until the Slides path moves to the generated ESM entrypoints. |

The stable data boundary is the generated manifest/cache pair. The stable
browser module boundary is `api/data.mjs`, `api/preview.mjs`, and
`api/graph.mjs`. Files under `src/VersoBlueprint/Commands/` are implementation
chunks for Blueprint's own runtime unless this document lists a generated
module that re-exports a stable API.

## Generated Data Files

Generated Blueprint sites write reusable data under `-verso-data/`:

- `blueprint-manifest.json` contains semantic entries keyed by preview key,
  generated-page hrefs, graph records, labels, dependency data, Lean-code
  associations, group data, ownership, tags, priority, effort, status metadata,
  and display metadata.
- `blueprint-html-cache.json` contains rendered body fragments keyed by the
  same preview keys. It is presentation data; do not parse it to rediscover
  graph topology, labels, statuses, or dependency relationships.
- `api/graph.mjs` exposes graph-data helpers for ordinary browser `import`
  usage, plus graph-block rendering helpers for pages that carry generated
  graph markup.
- `api/data.mjs` exposes manifest/cache/key/URL helpers for clients that do not
  need to render DOM previews.
- `api/preview.mjs` exposes the preview/render API for ordinary browser
  `import` usage.

The manifest is the semantic data contract. Cached HTML is an opaque rendered
fragment cache that can be inserted and hydrated. The cache also carries the
Verso hover payloads referenced by those rendered fragments; generated
Blueprint pages merge them into `-verso-docs.json`, and Slides preloads them
when rendering a deck.

In practice:

- use the manifest when you need to count nodes, inspect statuses, follow
  dependencies, or build a graph view
- use the HTML cache when you already know a preview key and want the rendered
  statement/proof/code fragment
- keep the manifest and cache from the same generated site; keys are shared,
  but the rendered HTML is not a portable semantic source

Lean-side clients that need common manifest queries should use the helper
methods on `Informal.PreviewManifest.File` rather than reimplementing filters:
`blockStatementEntries`, `findBlockEntriesByLabel`, `findPrimaryBlockEntry?`,
`ownerValues`, `tagValues`, and `workQueueEntries`. Entry-level helpers
`Entry.matchesText` and `Entry.matchesCode` provide the same search predicates
used by the `lake exe vbp query` interface.

```lean
import VersoBlueprint.PreviewManifest

def primaryNodeTitle?
    (manifest : Informal.PreviewManifest.File)
    (label : String) : Option String :=
  (manifest.findPrimaryBlockEntry? label).map (·.title)

def workQueueLabels
    (manifest : Informal.PreviewManifest.File) : Array String :=
  manifest.workQueueEntries.map fun entry =>
    Informal.PreviewManifest.labelString entry.label
```

Generator-side Lean callers can configure markup-only external-source cache
fragments with `Informal.PreviewManifest.ExternalMarkupRenderConfig`. The
default mode, `.markdown`, renders selected Markdown slots with MD4Lean/MD4C
and falls back to escaped source for TeX; `.source` always emits escaped source;
`.none` keeps external-markup entries semantic-only with no generated HTML-cache
fragment.

Use `Informal.PreviewManifest.previewMetadataLosses state manifest` to audit
whether traversal-preview metadata survived manifest construction. A non-empty
result means a traversal preview, such as a bodyless directive carrying
`(lean := ...)`, had Lean preview keys that were not represented by the matching
manifest entry. The standard preview-data generator reports the same condition
as a non-fatal warning so source-only import issues are visible without blocking
site generation.

Three common workflows consume that same model:

1. A Manual page can graft a node from the same document while traversal state
   is still available.
2. A Slides deck or generated audit page can graft nodes from a manifest/cache
   pair emitted by a Blueprint site.
3. Browser-side UI can use the generated ESM modules to create a renderer,
   resolve previews, and insert hydrated fragments after the page loads.

## Graph Data APIs

Lean callers can build the semantic graph object from elaboration state with
`Informal.Graph.buildData`. Before Verso traversal finishes, graph data is
semantic and may not yet include rendered hrefs or display titles:

```lean
import VersoBlueprint.Graph

def semanticGraph (state : Informal.Environment.State) :
    Informal.Graph.GraphData :=
  let roots := state.data.toArray.map (·.1)
  Informal.Graph.buildData state roots
```

Once traversal has completed, use `Informal.GraphApi` to finalize either one
rendered graph block or every graph cached during traversal:

```lean
import VersoBlueprint.GraphApi

def graphForRenderedBlock
    (state : Verso.Genre.Manual.TraverseState)
    (blockId : Verso.Multi.InternalId)
    (semantic : Informal.Graph.GraphData) : Informal.Graph.GraphData :=
  Informal.GraphApi.finalDataForBlock state blockId semantic

def allRenderedGraphs
    (state : Verso.Genre.Manual.TraverseState) :
    Array Informal.Graph.GraphData :=
  Informal.GraphApi.cachedData state
```

Generated `blueprint-manifest.json` includes a `graphs` array. Each entry
contains `schemaVersion`, `nodes`, `edges`, and `groups`, with status enums,
dependency axes, preview keys, hrefs when traversal resolved them, and visual
metadata for renderers that want Blueprint's default styling.

That finished traversal state is the stable boundary. Consumers should not
reconstruct graph hrefs or titles from lower-level traversal internals when the
finalized graph data is available.

Finalized graph node `previewKey` values are selected preview keys: when a
statement preview is unavailable but a proof preview exists, graph and relation
UI can point at the proof preview. Use fixed facet keys such as
`PreviewCache.statementKey` or `PreviewCache.proofKey` only when your code is
explicitly requesting that facet.

| Need | Use |
| --- | --- |
| Best rendered preview for one label from finished traversal state | `PreviewSource.Selection` or the finalized node `previewKey` |
| Explicit statement facet identity | `PreviewCache.statementKey label` |
| Explicit proof facet identity | `PreviewCache.proofKey label` |

The bundled graph renderer uses that finalized graph data as its block-level
source of truth and derives DOT render variants with
`Informal.Graph.GraphData.renderVariants`, so page rendering and custom clients
exercise the same graph record shape.

Browser callers can use the generated ESM graph module directly:

```javascript
// Import graph helpers from the generated graph API module.
import { loadGraphs, getGraphData } from "../-verso-data/api/graph.mjs";

// Load every finalized graph record from blueprint-manifest.json.graphs.
const graphs = await loadGraphs();

// Read graph data embedded in a rendered graph block on the current page.
const graph = getGraphData(document);
```

The same module can render an existing graph block. The block should use the
standard `.bp_graph_fullwidth` markup emitted by `{blueprint_graph}`, including
its embedded `script.bp-graph-data` and `script.bp-graph-variants` payloads.
Rendering also needs the Blueprint browser render runtime for preview surfaces,
popovers, and hydration. Generated graph pages and Blueprint slide decks include
that runtime internally; custom module-only pages should pass an explicit API
object as `previewUtils`, usually one created with `createPreview()`.
The ESM render helpers lazy-load the interactive graph runtime, so callers
should `await` them.

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";
import { renderGraphBlock } from "../-verso-data/api/graph.mjs";

const block = document.querySelector(".bp_graph_fullwidth");
if (block) {
  const previewUtils = createPreview();
  const controller = await renderGraphBlock(block, { previewUtils });
  controller.setView("full");
}
```

For slide or embed contexts whose container should own the graph height, pass
`layout: "fill"` or set `data-bp-graph-layout="fill"` on the graph block:

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";
import { renderGraphBlock } from "../-verso-data/api/graph.mjs";

const previewUtils = createPreview();
const block = document.querySelector(".bp_graph_fullwidth");
await renderGraphBlock(block, { previewUtils, layout: "fill" });
```

`await renderGraphBlock(block, options)` resolves to a controller with `render()`,
`scheduleRender()`, `setView(key)`, `setOptions({ direction, pack })`,
`setDirection(direction)`, `setPack(enabled)`, and
`setPreviewBehavior(mode, placement)`. Use `renderGraphs(root, options)` to
initialize every graph block under a document, element, or fragment.

Browser consumers should read graph data from the graph API, even when they are
also using the preview/render API:

```javascript
import { getGraphData } from "../-verso-data/api/graph.mjs";

const block = document.querySelector(".bp_graph_fullwidth");
const graph = getGraphData(block);
console.log(graph?.nodes.length ?? 0);
```

Standalone clients that do not render a graph block on the current page can
load the manifest graph records instead:

```javascript
import { loadGraphs } from "../-verso-data/api/graph.mjs";

const graphs = await loadGraphs();
for (const graph of graphs) {
  console.log(graph.key, graph.nodes.length, graph.edges.length);
}
```

## Lean Graft and Render APIs

Custom generators should follow the same manifest/cache path as Slides. This is
the right layer for audit reports, dashboards, comparison pages, and other
interfaces that create their own wrappers around Blueprint nodes.

The useful data boundary is small:

- `Informal.Graft.BlueprintNodeConfig` is the command-level selection shape. It
  records the label plus options such as `facet`, `displayLabel`, `compact`,
  `showHeader`, and `siteBase`.
- `BlueprintNodeConfig.toNode` normalizes that selection into
  `Informal.Graft.BlueprintNode`, including the exact preview `key`.
- `BlueprintNode.toAttrs` and `BlueprintNode.fromAttrs?` encode and decode the
  neutral DOM shell used by generated interfaces. The shell carries the
  `bp_graft_manifest_node` class as a stable selector for custom consumers.
  Slides use `Informal.Slides.blueprintNodeAttrs` and
  `Informal.Slides.renderedBlueprintNodeAttrs` to add slide-specific classes
  without making them part of the generic graft contract.
- `Informal.Graft.setClassAttr`, `Informal.Graft.appendClassAttr`, and
  `BlueprintNode.renderedAttrsWithClass` let custom renderers replace or extend
  CSS classes without creating duplicate `class` attributes.
- `Informal.Graft.SideBySideConfig` parses wrapper options such as `+boxed`.
  Its `attrs` helper produces the standard wrapper classes. Slides layer
  `Informal.Slides.sideBySideAttrs` on top for deck-specific wrappers, and
  custom consumers can ignore both helpers and arrange nodes in their own UI.
- Slide generators and other generated consumers should import and use the
  `Informal.Graft` node/config names directly.

`VersoBlueprint.Graft.Render` packages that lookup-and-render path for custom
interfaces. A consumer such as an audit view can provide its own wrapper
classes and diagnostics while reusing the same manifest/cache content:

```lean
import VersoBlueprint.Graft

def renderAuditNode
    (manifest : Informal.PreviewManifest.File)
    (htmlCache : Informal.PreviewManifest.HtmlCache.File)
    (label : String) : IO Verso.Output.Html := do
  let node :=
    ({ label := label, compact := true, showHeader := false } :
      Informal.Graft.BlueprintNodeConfig).toNode
  let ctx := Informal.Graft.RenderContext.ofPreviewData? (some manifest) (some htmlCache)
  Informal.Graft.renderNodeFromManifestCache
    {
      blockRenderConfig := {
        wrapperClass := "audit_blueprint_node"
        codeBodyClass := "audit_blueprint_code"
      }
      nodeAttrs := fun node =>
        node.renderedAttrsWithClass "audit_graft_node"
    }
    ctx
    node
```

Use `PreviewManifest.File.findEntry?` and
`PreviewManifest.HtmlCache.File.findHtml?` when you need direct lookup. For
client-facing node lists, prefer `PreviewManifest.File.blockStatementEntries`
and `findPrimaryBlockEntry?` so label/facet selection matches the generated
`vbp` query API. Code panels can reuse `HtmlCache.File.codeHtmlBodies`.

`renderNodeFromManifestCache` has three diagnostic branches that custom
interfaces can keep or override with `ManifestRenderConfig.renderMissingNode`:
missing manifest, missing manifest entry for the normalized node key, and
missing rendered-fragment body for a manifest entry. The cache-miss branch also
calls the context's `logError` callback so generators can fail or report broken
manifest/cache pairs consistently.

Consumers that already have a semantic manifest entry and rendered body content
can call `Informal.Graft.renderNodeWithContent` directly. This keeps the graft
node attributes, wrapper classes, and `displayLabel`/`compact`/`showHeader`
behavior aligned with `{blueprint_node}` while letting the caller decide where
the content came from.

For still lower-level consumers, the final shared block-shell assembly point
remains `Informal.PreviewManifest.BlockRender.renderWithRenderedContent`. Pass
it the semantic manifest entry plus `BlockRender.RenderedContent`, using
`BlockRender.RenderedContent.ofHtmlStrings` when the body came from
`blueprint-html-cache.json`. The render options map directly to graft behavior:
`displayLabelOverride?`, `compact`, and `showHeader`.

## Browser ESM APIs

Generated sites emit importable modules under `-verso-data/api/`:

- `data.mjs`
- `preview.mjs`
- `graph.mjs`

This section is a navigation guide for choosing the right generated module. It
is intentionally not the exhaustive JavaScript reference. Use the
[generated JavaScript API reference](https://leanprover.github.io/verso-blueprint/js-api/)
for complete export lists, signatures, typedefs, result shapes, and examples.

The relative path depends on the generated page location. Root generated pages
can import from `-verso-data/api/...`; nested generated pages commonly import
from `../-verso-data/api/...`. Generated clients that need to resolve the
module URL from an arbitrary page should use the same generated-data path
convention as `dataUrl`: find `/html-multi/` or `/html-single/` in the current
URL and append `-verso-data/api/data.mjs`,
`-verso-data/api/preview.mjs`, or `-verso-data/api/graph.mjs`.

Generated sites also emit root implementation modules,
`-verso-data/blueprint-data-api.mjs`,
`-verso-data/blueprint-preview-api.mjs`, and
`-verso-data/blueprint-graph-api.mjs`. The public `api/*.mjs` modules re-export
those implementations from stable, shorter import paths. The generated data
directory also contains internal support files used by those modules, such as
`blueprint-graph-core.mjs`, `blueprint-preview-core.mjs`,
`blueprint-api-common.mjs`, the `Commands/preview-runtime-*.mjs` renderer
chunks, and the `Commands/graph-runtime-core.mjs`/`Commands/graph.mjs` graph
renderer chunks. Those support files are not public import paths. New clients
should use the `-verso-data/api/` paths.

URL, key, manifest/cache, rendering, hydration, and graph helpers are available
through generated ESM modules. `api/preview.mjs` constructs its renderer
directly from emitted runtime chunks; it does not need
`window.VersoBlueprint.render` or `window.VersoBlueprint.onRenderReady`. Graph
helpers live in `api/graph.mjs`. Use `createPreview()` when a client wants an
explicit renderer object. The top-level helper functions use module-local
defaults for small scripts.

Use these modules when the client can use normal JavaScript modules:

```javascript
import { createPreviewData } from "../-verso-data/api/data.mjs";
import { renderPreviewInto } from "../-verso-data/api/preview.mjs";
import { loadGraphs } from "../-verso-data/api/graph.mjs";
```

If the script does not know how deeply nested the current page is, resolve the
generated data URL using the same marker convention as the core helpers: find
the `/html-multi/` or `/html-single/` path segment and append
`-verso-data/api/data.mjs`, `-verso-data/api/preview.mjs`, or
`-verso-data/api/graph.mjs`.

Load generated data without importing render code:

```javascript
import { createPreviewData } from "../-verso-data/api/data.mjs";
import { loadManifestGraphs } from "../-verso-data/api/graph.mjs";

const fetchJson = async (url) => readFromClientCacheOrFetch(url);
const data = createPreviewData({ fetchJson });

const manifest = await data.loadManifest();
const entry = await data.loadManifestEntry(data.previewKey("addition_right_identity", "statement"));
const graphs = await loadManifestGraphs(data.manifestUrl(), { fetchJson });
```

Render only a preview body fragment:

```javascript
// Import the key builder and body-fragment renderer from the generated module.
import {
  previewKey,
  renderPreviewInto
} from "../-verso-data/api/preview.mjs";

// Build the manifest/cache key for one rendered statement preview.
const key = previewKey("addition_right_identity", "statement");

// Choose the DOM element where the rendered fragment should be inserted.
const target = document.querySelector("#audit-preview");
if (target) {
  // Render only the preview body fragment into the target element.
  await renderPreviewInto(target, key);
}
```

Render the full generated Blueprint node from a module path and key:

```html
<!-- Provide a target element for the rendered Blueprint node. -->
<div id="blueprint-node"></div>

<script type="module">
  // Point at the generated ESM preview/render API module.
  const apiModulePath = "../-verso-data/api/preview.mjs";

  // Use a full preview key: "<label>--<facet>".
  const key = "addition_right_identity--statement";

  // Import the full-node renderer from the generated module.
  const { renderCanonicalPreviewInto } = await import(apiModulePath);

  // Find the target element in this page.
  const target = document.querySelector("#blueprint-node");
  if (target) {
    // Render the same Blueprint node wrapper used on the generated page.
    const result = await renderCanonicalPreviewInto(target, key);

    // Surface diagnostics when the key or generated source page is unavailable.
    if (!result.ok) {
      console.warn("Could not render Blueprint node:", result.reason);
    }
  }
</script>
```

Create an explicit renderer object and call the stable methods from it:

```javascript
import {
  createPreview,
  previewKey
} from "../-verso-data/api/preview.mjs";

const api = createPreview();
const key = previewKey("addition_right_identity", "statement");
const target = document.querySelector("#audit-preview");

if (target) {
  await api.renderPreviewInto(target, key);
}
```

At a high level, the public generated browser modules are:

| Module | Purpose |
| --- | --- |
| `api/data.mjs` | Data-only clients: generated-data URLs, manifest/cache loading, status readers, and preview-key helpers. |
| `api/preview.mjs` | Render-capable clients: data helpers plus preview resolution, fragment insertion, canonical node rendering, label-based `renderNode`, and hydration. |
| `api/graph.mjs` | Graph clients: finalized graph loading, embedded graph-block data access, and graph-block rendering with an explicit preview renderer. |

Only the files listed in this table are public generated-site browser API
entrypoints. Other generated JavaScript files under `-verso-data/`, including
the `blueprint-*-core.mjs`, `blueprint-api-common.mjs`, and
`Commands/*.mjs` support chunks, are implementation modules owned by the
generated page runtime or by those public entrypoints.

The exact JavaScript signatures, typedefs, and module-level examples are
generated from JSDoc and published on GitHub Pages at
[leanprover.github.io/verso-blueprint/js-api/](https://leanprover.github.io/verso-blueprint/js-api/).
CI also uploads the same generated HTML as an artifact named `js-api-docs` for
PR-local inspection.
Locally, run `npm run docs` and open `_out/jsdoc-api/index.html`.

## Browser Runtime API

Browser-side custom interfaces should start from `createPreview()` in
`api/preview.mjs`. It returns the render API object that loads the manifest and
rendered-fragment cache from the page's `-verso-data/` directory, keeps load
status for diagnostics, and hydrates inserted fragments. The renderer is scoped
to the importing module; clients do not need `window.VersoBlueprint.render`.

Use `renderPreviewInto` when the client just needs to place a preview body
fragment into the page:

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";

const api = createPreview();
const key = api.previewKey("addition_right_identity", "statement");
const target = document.querySelector("#audit-preview");
if (target) {
  const result = await api.renderPreviewInto(target, key);
  if (result.ok) console.log(result.manifestEntry.title);
}
```

`createPreview(options)` also accepts data-loading and hydration defaults for
custom clients:

- `dataBaseUrl`: a generated `-verso-data/` URL or API-module URL used to
  resolve `blueprint-manifest.json`, `blueprint-html-cache.json`, and API
  module URLs. The public ESM module supplies its own `import.meta.url` by
  default.
- `fetchJson`: an optional JSON loader `(url, options) => data`. Use this for
  standalone clients, tests, Node-like environments, authenticated requests, or
  clients that already own a cache. If omitted, VBP uses the ambient `fetch`.
- `fetchText`: an optional text loader `(url, options) => html` used by
  canonical-node rendering when it needs to load the generated source page.
- `loadDocument`: an optional canonical-page loader
  `({ url, sourceUrl, options }) => Document | string`. It overrides
  `fetchText`; string results are parsed with `DOMParser`.
- `canonicalBaseUrl`: an optional base URL for resolving manifest `href`
  values when the client is not running on a generated Blueprint page.
- `hydrators`: a function, array, `Map`, or plain object of named functions.
  Each hydrator receives `(root, context)` after VBP inserts a fragment.
- `inheritPageHydrators`: defaults to `true`. Set it to `false` for standalone
  clients that should not reuse generated-page feature hydrators.
- `templateBinder`: an optional function for clients that need to bind preview
  descriptors through their own component lifecycle.

Render-call options accept the same `fetchJson`, `fetchText`, `loadDocument`,
`canonicalBaseUrl`, `hydrators`, `inheritPageHydrators`, and `templateBinder`
keys, plus `hydrate: false` and `renderMath: false`. Per-call options override
factory defaults for that render.

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";

const api = createPreview({
  fetchJson: async (url) => {
    return readFromClientCacheOrFetch(url);
  },
  inheritPageHydrators: false,
  hydrators: {
    audit(root) {
      root.dataset.auditHydrated = "true";
    }
  }
});

await api.renderPreviewInto(target, key, {
  hydrators(root, context) {
    console.log("hydrated by", context.source);
  }
});
```

Use `renderCanonicalPreviewInto` when the client wants the same Blueprint node
wrapper that appears on the generated page. This resolves the semantic manifest
entry, follows its generated-page link, extracts the canonical node by id, and
hydrates the inserted copy:

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";

const api = createPreview();
const key = api.previewKey("addition_right_identity", "statement");
const target = document.querySelector("#audit-preview");
if (target) {
  const result = await api.renderCanonicalPreviewInto(target, key);
  if (result.ok) console.log(result.canonicalSourceHref);
}
```

Use `resolvePreview` when the client needs semantic data before deciding how to
display the preview:

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";

const api = createPreview();
const key = api.previewKey("addition_right_identity", "statement");
const result = await api.resolvePreview(key);
if (result.ok) {
  const row = document.createElement("section");
  row.className = "audit-preview-row";
  row.dataset.previewKey = result.key;
  const heading = document.createElement("h3");
  heading.textContent = result.manifestEntry.title;
  const body = document.createElement("div");
  body.className = "audit-preview-body";
  row.appendChild(heading);
  row.appendChild(body);
  const inserted = await api.renderPreviewInto(body, result.key);
  if (inserted.ok) document.querySelector("#audit-previews").appendChild(row);
}
```

Use `renderNode` when the client starts from a Blueprint label and wants a
generated Blueprint node. If native rendered content is available, VBP inserts
the regular generated node shell. If only external markup is available, VBP
still owns that shell: heading, relation chips, metadata, anchors, and
hydration. The call-scoped renderer receives only the node's content slot as
its target. The renderer is not registered globally.

The ownership boundary is strict:

- `renderNode` owns the outer Blueprint node shell.
- The supplied external-markup renderer owns only the body target passed as its
  second argument, which is the generated node's `.bp_content` slot.
- The renderer should replace or append children inside that body target; it
  should not replace the surrounding node, heading, relation chips, metadata
  panel, anchors, or hydrated preview controls.
- If external markup exists but VBP cannot find a generated node shell for the
  label, `renderNode` reports `external-markup-node-shell-missing` rather than
  inventing a different wrapper.

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";

const api = createPreview();
const target = document.querySelector("#comparison-preview");
if (target) {
  const result = await api.renderNode(target, {
    label: "Chapter2:Problem2.11.6",
    facet: "statement",
    externalMarkup: {
      prefer: [
        { language: "markdown", slot: "original", render: renderMarkdown },
        { language: "tex", slot: "original", render: renderTexSource },
        { display: "source" }
      ]
    }
  });

  if (!result.ok) {
    console.warn(result.reason);
  }
}

async function renderMarkdown(markup, target) {
  const node = await markdownToDom(markup.raw);
  target.replaceChildren(node);
}

async function renderTexSource(markup, target) {
  const pre = document.createElement("pre");
  pre.textContent = markup.raw;
  target.replaceChildren(pre);
}
```

The renderer receives
`{ raw, language, slot, location, node, manifestEntry, label, facet, nativePreview, externalMarkup }`
plus the node-body target element as its second argument. `node` and
`manifestEntry` are the manifest entry that owns the external markup; `location`
is the optional project-relative source range recorded by the `tex` or `md`
block. If the manifest has external markup but no generated Blueprint node shell
for the label, `renderNode` returns a typed diagnostic instead of inventing a
different wrapper shape.

A complete standalone version of this pattern is available in
[`standalone-render-node-markdown.js`](../tests/test_blueprints/preview_runtime_showcase/PreviewRuntimeShowcase/Chapters/standalone-render-node-markdown.js).
It does not use the showcase card UI: it binds one target element, calls
`renderNode`, and renders Markdown into the body slot supplied by VBP.

Graph rendering lives in `api/graph.mjs`, not on the stable preview API. Pass an
explicit preview renderer when the graph block needs preview panels or
hydration. This keeps the dependency visible at the render site while still
using the same graph runtime as generated graph pages:

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";
import { renderGraphs } from "../-verso-data/api/graph.mjs";

const previewUtils = createPreview();
const slide = document.querySelector(".current-slide");
await renderGraphs(slide, { previewUtils, layout: "fill", refresh: true });
```

### Runtime Readiness

Regular Manual pages load one module entrypoint:
`-verso-data/blueprint-page-runtime.mjs`. `withBlueprintAssets` injects it with
Manual's `extraHead` as:

```html
<script type="module" src="-verso-data/blueprint-page-runtime.mjs"></script>
```

That module imports `api/preview.mjs`, constructs the page renderer with
`createPreview()`, installs target-detail opening, and starts Blueprint's
inline-preview, relation-panel, graph, and template-preview bindings. Command
renderers still contribute markup, CSS, and stable data attributes, but they no
longer inject preview-runtime startup JavaScript into Manual `extraJs`.
`withBlueprintAssets` also includes the CSS needed for manifest-backed block
shells and source-backed external-markup fragments; feature-specific JavaScript
continues to be registered by the renderers that emit those interactive
features.

The private `window.VersoBlueprint.onRenderReady` bridge remains only for the
current classic-script Slides adapter. New custom clients should import the ESM
modules directly, or import
`blueprint-page-runtime.mjs` if they intentionally want the already-started page
renderer from a generated Manual page.

### Stable Custom-Client API

External clients should start from the stable API below. These entry points are
the contract for audit interfaces, dashboards, slide adapters, comparison
views, and browser-only examples. This table is a compact stability index used
by the docs tests to keep the public method set aligned with the runtime source;
the generated JavaScript API reference remains the detailed signature and type
reference.

| Entry point | Use |
| --- | --- |
| `createPreview(options)` | Construct a render API object from the generated ESM runtime modules. This is the preferred entry point for custom browser clients. `options.dataBaseUrl` and `options.fetchJson` configure JSON loading; `options.fetchText`, `options.loadDocument`, and `options.canonicalBaseUrl` configure canonical page loading; `options.hydrators`, `options.inheritPageHydrators`, and `options.templateBinder` configure hydration defaults for this renderer. |
| `api.dataUrl(filename)` / `api.manifestUrl()` / `api.htmlCacheUrl()` | Resolve generated `-verso-data/` URLs relative to the current page. |
| `api.loadManifest(options)` / `api.loadHtmlCache(options)` | Load the generated `Map` values keyed by preview key. `options.fetchJson` can override the renderer's default JSON loader for that call. |
| `api.readManifestStatus()` / `api.readHtmlCacheStatus()` | Inspect diagnostics such as `idle`, `loading`, `ready`, and `error`. |
| `api.loadManifestEntry(key, options)` / `api.loadHtmlCacheEntry(key, options)` | Read one generated entry by key. `options.fetchJson` can override the renderer's default JSON loader for that call. |
| `api.dataApiModuleUrl()` | Resolve the generated ESM data API module URL for dynamic imports from custom clients. |
| `api.previewApiModuleUrl()` | Resolve the generated ESM preview/render API module URL for dynamic imports from custom clients. |
| `api.previewKey(label, facet)` / `api.statementPreviewKey(label)` | Build normalized preview keys for custom render targets. |
| `api.resolvePreview(key, options)` | Resolve manifest data and a rendered body fragment together, returning `{ ok, key, reason, manifestEntry, htmlCacheEntry, html, diagnosticHtml }`. |
| `api.renderPreviewInto(element, key, options)` | Write the rendered body fragment or diagnostic HTML into `element`, then hydrate nested previews and math. Render options may set `hydrators`, `inheritPageHydrators`, `templateBinder`, `hydrate: false`, or `renderMath: false`. |
| `api.resolveCanonicalPreview(key, options)` | Resolve the same data as `resolvePreview`, then load the generated page named by `manifestEntry.href` and return `canonicalHtml` plus `canonicalSourceHref` for the real Blueprint node wrapper. |
| `api.renderCanonicalPreviewInto(element, key, options)` | Write the canonical Blueprint node wrapper or diagnostic HTML into `element`, then hydrate nested previews and math. It accepts the same hydration options as `renderPreviewInto`. |
| `api.renderNode(element, request, options)` | Render by label as a generated Blueprint node: native content uses the canonical generated shell, and external markup uses the same shell with a call-scoped TeX/Markdown body renderer from `request.externalMarkup` or `request.preferredExternalMarkup`. It accepts the same hydration options as `renderPreviewInto`. |
| `api.hydrate(element, options)` | Hydrate custom wrappers that inserted cached rendered fragments themselves. It accepts the same hydration options as `renderPreviewInto`. |

## Preview Result Shapes

Preview/render helpers resolve to plain objects with an `ok` boolean and the
normalized preview `key`. Successful results include semantic manifest data and
the rendered HTML used by the operation. Failed results include a `reason` and
`diagnosticHtml` suitable for insertion into the page.

| Helper | Success shape | Failure shape |
| --- | --- | --- |
| `resolvePreview(key)` | `{ ok: true, key, manifestEntry, htmlCacheEntry, html }` | `{ ok: false, key, reason, diagnosticHtml }` |
| `renderPreviewInto(element, key, options)` | The `resolvePreview` success shape after writing `html` into `element` and hydrating it. | The `resolvePreview` failure shape after writing `diagnosticHtml` into `element`. |
| `resolveCanonicalPreview(key)` | `{ ok: true, key, manifestEntry, htmlCacheEntry, html, canonicalHtml, canonicalSourceHref }` | `{ ok: false, key, reason, diagnosticHtml }` |
| `renderCanonicalPreviewInto(element, key, options)` | The `resolveCanonicalPreview` success shape after writing `canonicalHtml` into `element` and hydrating it. | The `resolveCanonicalPreview` failure shape after writing `diagnosticHtml` into `element`. |
| `renderNode(element, request, options)` | Native-preview success shape with `renderMode: "native"` and `canonicalHtml`, or external-markup success shape with `renderMode: "external-markup"`, `externalMarkup`, and `canonicalHtml`. | `{ ok: false, key, reason, manifestEntry?, externalMarkup?, nativePreview?, diagnosticHtml }` after writing diagnostics unless `options.diagnostics === false`. |

The most common failure `reason` values are:

- `missing-key`
- `manifest-entry-missing`
- `html-cache-entry-missing`
- `canonical-href-missing`
- `canonical-preview-node-missing`
- `canonical-preview-load-failed`
- `missing-label`
- `external-markup-entry-missing`
- `external-markup-missing`
- `external-markup-renderer-missing`
- `external-markup-render-failed`
- `external-markup-node-shell-missing`
- `external-markup-node-shell-load-failed`

Treat `html` and `canonicalHtml` as opaque rendered fragments. Use
`manifestEntry` for semantic facts such as labels, titles, dependency metadata,
group data, code associations, and generated links.

Blueprint's bundled graph, summary, relation-panel, and inline-preview
JavaScript receive the same render API from `blueprint-page-runtime.mjs`.
The classic-script Slides adapter receives that shape through the private
`onRenderReady` bridge. Custom clients should get the same API shape from
`createPreview()` so preview lookup, diagnostics, and hydration stay on one
runtime path without depending on page globals. The runtime keeps
manifest/cache load state private; clients should inspect it through
`readManifestStatus()` and `readHtmlCacheStatus()` rather than reading `window`
globals.

Slide decks keep their slide-specific rehydration bridge under the same
namespace as `window.VersoBlueprint.slides`. That bridge is for the generated
slide asset; custom preview clients should use the stable render API table
above unless a slide-specific hook is explicitly documented there.

For semantic queries, use the manifest entry returned by `resolvePreview` or
`loadManifestEntry`. Do not parse inserted or cached fragments to rediscover
labels, dependencies, group membership, Lean-code associations, or status
metadata. The cached fragment is presentation: it may display those facts, but
the manifest is the data contract.

### Component-Framework Pattern

Custom component frameworks should keep the same split. A React, audit, or
dashboard client owns its component tree, selection state, filters, and wrapper
markup, but it should treat Blueprint data as manifest/cache records loaded
through the render API. Components should pass preview keys to
`resolvePreview`, `renderPreviewInto`, `resolveCanonicalPreview`, or
`renderCanonicalPreviewInto`, or pass labels plus call-scoped external-markup
renderers to `renderNode`. They should render user-interface controls around
the returned manifest entry, not scrape generated Blueprint DOM, call private
bundled helpers, or couple component state to the current shape of the generated
preview runtime.

### Private Runtime Chunks

The `preview-runtime*` files under `src/VersoBlueprint/Commands/` are private
source chunks used to build the generated runtime asset and the generated ESM
preview module implementation. They are not client import targets and do not
change the public browser API. Custom clients should continue to use
`api/preview.mjs`; regular generated Manual pages start through
`blueprint-page-runtime.mjs`, which imports the public preview module and the
private feature modules it owns.

Blueprint's browser source files are ESM modules. The `BrowserAsset` adapter
layer remains only for the current classic-script Slides adapter. It is an
output shim, not a second source API: new browser logic should be written as ESM
source and started through one explicit entrypoint.

The current private source chunks are:

| Chunk | Private responsibility |
| --- | --- |
| `preview-runtime-base.mjs` | Small shared helpers, template collection, HTML escaping, and debug hooks. |
| `preview-runtime-data.mjs` | Manifest/cache loading, status readers, and store lookups. |
| `preview-runtime-render.mjs` | Manifest/cache joins, rendered-fragment insertion, diagnostics, and canonical generated-node fetching. |
| `preview-runtime-hydration.mjs` | Math rendering, fragment hydration, and feature hydrator dispatch. |
| `preview-runtime-lifecycle.mjs` | Trigger, dismissal, popover, resize/scroll, and keep-open lifetimes. |
| `preview-runtime-surface.mjs` | Preview panel slots, behavior state, content updates, panel creation, and diagnostic message markup. |
| `preview-runtime-template.mjs` | Descriptor-driven binding for Lean-emitted template preview roots. |
| `preview-runtime-api.mjs` | Stable render API assembly, `createPreviewRuntimeApi`, and the private `onRenderReady` installation used by the classic Slides adapter. |

Two adjacent implementation files are shared by bundled pages and generated ESM
modules:

| Chunk | Private responsibility |
| --- | --- |
| `blueprint-graph-core.mjs` | Graph JSON discovery, graph manifest loading, and graph-data normalization shared by the page runtime, `api/graph.mjs`, and the classic Slides adapter. |
| `blueprint-preview-core.mjs` | Generated-data URL helpers and preview-key construction shared by the page runtime, `api/data.mjs`, `api/preview.mjs`, and the classic Slides adapter. |
| `blueprint-api-common.mjs` | Common generated-ESM wrapper mechanics shared by `api/data.mjs` and `api/preview.mjs`, including default data-base options, URL/key forwarding, default API handles, fallback statuses, and method dispatch. |

The graph command also has private `graph-runtime-core.mjs` and `graph.mjs`
chunks. The core chunk owns graph option normalization, canvas sizing, graph
block state, script loading, and graph-specific panel positioning. `graph.mjs`
owns graph rendering orchestration, variant selection, and graph UI event
binding. Regular generated pages import them through `blueprint-page-runtime.mjs`;
custom clients should use `api/graph.mjs` or the render API instead.

## Bundled Helper Boundary

Bundled-feature helper APIs are intentionally narrower than the stable API.
They are present on the renderer returned by `createPreview()` so Blueprint's
own feature scripts can share runtime mechanics without duplicating them. The
classic Slides adapter also exposes that renderer as `window.VersoBlueprint.render`,
but that global is not a custom-client contract unless a helper is promoted into
the stable table above.
The intended path for Blueprint-owned panels is `createPreviewSurface`; it owns
content updates plus trigger, dismissal, and reposition lifetimes. Lower-level
helpers remain exported only where bundled graph popovers, positioning
callbacks, or generated preview code still need them directly.

| Helper family | Helpers | Bundled consumers |
| --- | --- | --- |
| Template lifecycle | `collectPreviewTemplates` | Graph-local preview stores; summary and code-summary previews use Lean-emitted DOM descriptors that the runtime auto-binds |
| Surface, shell, and content | `createPreviewSurface`, `createPreviewPanel`, `renderPreviewIntoSurface`, `resolvePreviewHtml`, `previewMessageHtml`, `escapeHtml` | Graph preview panels, inline preview panels, relation panels, and runtime diagnostics |
| Behavior, positioning, and dismissal | `bindAnchoredPopover`, `hidePreviewSurfaces` | Graph popovers, slide-change cleanup, and feature-specific positioning callbacks |
| Hydration and debug hooks | `registerPreviewHydrator`, `previewDebug`, `previewDebugLabel` | Bundled previews that need feature-specific post-render binding or local runtime diagnostics |

Template-preview roots emitted by Lean carry `data-bp-template-preview-*`
descriptor attributes. The shared runtime binds those descriptors on page load
and after preview-fragment hydration, so summary and code-summary previews do
not need feature-specific startup scripts.

`createPreviewSurface` is the higher-level bundled helper for Blueprint-owned
preview panels. It groups a panel's slots, current behavior, content/header
updates, close-button wiring, trigger binding, dismissal binding, reposition
binding, pointer checks, and keep-open checks into one controller object.
`renderPreviewIntoSurface` layers shared preview lookup, diagnostics, loading
content, stale-request checks, and rendered-fragment insertion on top of that
surface controller. `resolvePreviewHtml` provides the narrower shared lookup
path for bundled feature scripts that need to keep feature-specific panel
rendering or fallback rules. Bundled feature scripts should prefer
`surface.bindTriggers`, `surface.bindDismissal`, `surface.bindRepositioner`,
`surface.position`, `surface.pointerWithin`, `surface.shouldKeepOpen`, and
`renderPreviewIntoSurface` or `resolvePreviewHtml` over direct lifecycle and
cache-resolution helpers.
External clients should stay on the stable custom-client API above.

Inline-preview nesting is configured by private host policies in
`inline-preview.mjs`. Today those policies recognize relation panels, graph
preview panels, and graph group-hover panels, then choose anchored hover
behavior for nested previews inside those hosts. New bundled panel types should
add an explicit host policy instead of adding more ad hoc ancestor checks.

For new custom interfaces, prefer the highest-level entry point that fits the
job; see [Choosing an API](#choosing-an-api).

Future public browser APIs should be added to the stable custom-client table
when they are intended for external clients such as audits, dashboards, slide
adapters, or comparison views. Bundled helpers can still exist for Blueprint's
own JavaScript, but they should stay outside the public table until their
argument shape and compatibility expectations are ready to support those
clients.

## Standalone Example

The in-repo `preview_runtime_showcase` test blueprint includes the same pattern
as a standalone browser client on its `Custom Render Client` page. It also
includes a graph-data card that imports `loadGraphs()` from `api/graph.mjs` to
read `blueprint-manifest.json.graphs` without embedding a rendered graph, a
`type="module"` example that imports `renderPreviewInto` from
`-verso-data/api/preview.mjs`, `renderNode` cards for native label rendering and
a metadata-bearing external-markup node with a call-scoped body renderer, and a graph
module example that imports `loadGraphs` from `-verso-data/api/graph.mjs`.

The client asset lives in
[`custom-render-client.js`](../tests/test_blueprints/preview_runtime_showcase/PreviewRuntimeShowcase/Chapters/custom-render-client.js),
with the page shell in
[`CustomRenderClient.lean`](../tests/test_blueprints/preview_runtime_showcase/PreviewRuntimeShowcase/Chapters/CustomRenderClient.lean).
After generating the test blueprint, inspect
`_out/test-blueprints/preview_runtime_showcase/html-multi/Custom-Render-Client/`
or, from a linked worktree,
`_out/<worktree>/test-blueprints/preview_runtime_showcase/html-multi/Custom-Render-Client/`.
That fixture is exercised by the browser regression tests, so it is a better
starting point than copying code from a test body.
