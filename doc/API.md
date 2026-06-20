# Blueprint API Reference

This document is for integration work: custom generators, dashboards, audit
pages, slide adapters, and browser scripts that need to read Blueprint data or
render Blueprint fragments outside the standard generated pages.

For authoring syntax and rendering behavior, see
[`MANUAL.md`](./MANUAL.md). For the architecture boundaries behind these APIs,
see [`DESIGN_RATIONALE.md`](./DESIGN_RATIONALE.md).

If you are not sure where to start, read [Choosing an API](#choosing-an-api)
first. The short version is:

- use the generated ESM modules for ordinary browser `import { ... } from ...`
  JavaScript
- use `window.VersoBlueprint.onRenderReady` when your script is loaded inside a
  generated Blueprint page and must wait for the page runtime
- use the generated manifest for semantic data and the HTML cache for rendered
  fragments
- use the Lean graft/render APIs when a generator wants to place Blueprint nodes
  into a custom page

## Contents

- [Stability Policy](#stability-policy)
- [Choosing an API](#choosing-an-api)
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

Compatibility globals such as `window.bpGraphApi` remain available for
graph-specific clients, but new browser code should prefer the generated ESM
modules or `window.VersoBlueprint.onRenderReady`.

## Choosing an API

Start from what you are building:

| You are building | Start with | Why |
| --- | --- | --- |
| A small browser script or standalone web page | [`api/preview.mjs`](#browser-esm-apis) or [`api/graph.mjs`](#browser-esm-apis) | These are normal ESM modules, so clients can use regular `import { ... } from ...` syntax. |
| A script loaded by a generated Blueprint page | [`window.VersoBlueprint.onRenderReady`](#browser-runtime-api) | The callback waits for the generated runtime, manifest, cache, and hydration hooks. |
| A graph dashboard or audit page | [`loadGraphs()`](#graph-data-apis) | It reads finalized graph records from `blueprint-manifest.json`, even when the current page has no rendered graph block. |
| A custom browser widget beside an existing graph block | [`getGraphData(element)`](#graph-data-apis) and `getGraphVariants(element)` | These read the graph data embedded next to a rendered graph. |
| A custom page that needs a rendered preview body only | [`renderPreviewInto(element, key)`](#browser-esm-apis) or [`api.renderPreviewInto`](#browser-runtime-api) | This inserts the cached rendered fragment into your own wrapper. |
| A custom page that should look like generated Blueprint nodes | [`renderCanonicalPreviewInto(element, key)`](#browser-esm-apis) or [`api.renderCanonicalPreviewInto`](#browser-runtime-api) | This inserts the standard Blueprint node wrapper and body. |
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
  usage.
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

Three common workflows consume that same model:

1. A Manual page can graft a node from the same document while traversal state
   is still available.
2. A Slides deck or generated audit page can graft nodes from a manifest/cache
   pair emitted by a Blueprint site.
3. Browser-side UI can use `window.VersoBlueprint.onRenderReady` or the
   generated ESM modules to resolve and insert previews after the page loads.

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

Browser consumers that are already using the runtime API can read page-local
graph data from the render API:

```javascript
window.VersoBlueprint.onRenderReady((api) => {
  const block = document.querySelector(".bp_graph_fullwidth");
  const graph = api.getGraphData(block);
  console.log(graph?.nodes.length ?? 0);
});
```

Standalone clients that do not render a graph block on the current page can
load the manifest graph records instead:

```javascript
window.VersoBlueprint.onRenderReady(async (api) => {
  const graphs = await api.loadGraphs();
  for (const graph of graphs) {
    console.log(graph.key, graph.nodes.length, graph.edges.length);
  }
});
```

When a client must resolve the module URL relative to an arbitrary generated
page, use `api.graphApiModuleUrl()` from the render API:

```javascript
// Wait until the generated preview runtime has installed the render API.
window.VersoBlueprint.onRenderReady(async function (api) {
  // Resolve and import the generated graph API module relative to this page.
  const graphApi = await import(api.graphApiModuleUrl());

  // Load every finalized graph record from the generated manifest.
  const graphs = await graphApi.loadGraphs();

  // Use the records in the custom client.
  console.log(graphs.length);
});
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
`PreviewManifest.HtmlCache.File.findHtml?` when you need direct lookup. Code
panels can reuse `HtmlCache.File.codeHtmlBodies`.

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

- `preview.mjs`
- `graph.mjs`

The relative path depends on the generated page location. Root generated pages
can import from `-verso-data/api/...`; nested generated pages commonly import
from `../-verso-data/api/...`. Generated clients that need to resolve the
module URL from an arbitrary page should use `api.previewApiModuleUrl()` or
`api.graphApiModuleUrl()`.

The root files `-verso-data/blueprint-preview-api.mjs` and
`-verso-data/blueprint-graph-api.mjs` are still emitted as compatibility
targets. The generated data directory also contains implementation support
files used by those modules, such as `blueprint-graph-core.js`. Those support
files are not public import paths. New clients should use the shorter
`-verso-data/api/` paths.

URL, graph-data, and key helpers in `api/preview.mjs` are available
immediately. Manifest/cache loading, rendering, and hydration helpers wait for
the page runtime before delegating to the shared render API. In the preview ESM
module, `ready` is a Promise for the runtime API object.

Use these modules when the client can use normal JavaScript modules:

```javascript
import { renderPreviewInto } from "../-verso-data/api/preview.mjs";
import { loadGraphs } from "../-verso-data/api/graph.mjs";
```

If the script does not know how deeply nested the current page is, wait for the
runtime and ask it for the correct module URL with `api.previewApiModuleUrl()`
or `api.graphApiModuleUrl()`.

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

Resolve the generated module path from the runtime:

```javascript
// Wait for the generated runtime so it can resolve URLs for this page.
window.VersoBlueprint.onRenderReady(async function (api) {
  // Dynamically import the generated preview/render module.
  const previewApi = await import(api.previewApiModuleUrl());

  // Build a normalized preview key from a label and facet.
  const key = previewApi.previewKey("addition_right_identity", "statement");

  // Choose the DOM element that will receive the rendered fragment.
  const target = document.querySelector("#audit-preview");
  if (target) {
    // Render the preview body fragment through the imported module.
    await previewApi.renderPreviewInto(target, key);
  }
});
```

The generated ESM modules expose these entrypoint groups:

| Module | Exports |
| --- | --- |
| `api/preview.mjs` | URL helpers: `dataUrl`, `manifestUrl`, `htmlCacheUrl`, `graphApiModuleUrl`, `previewApiModuleUrl`; runtime readiness: `onRenderReady`, `currentRenderApi`, `getRenderApi`, `ready`; manifest/cache helpers: `loadManifest`, `readManifestStatus`, `loadManifestEntry`, `loadHtmlCache`, `readHtmlCacheStatus`, `loadHtmlCacheEntry`; graph-data helpers re-exported from the graph module; preview/render helpers: `previewKey`, `statementPreviewKey`, `resolvePreview`, `renderPreviewInto`, `resolveCanonicalPreview`, `renderCanonicalPreviewInto`, `hydrate`. |
| `api/graph.mjs` | URL helpers: `dataUrl`, `graphApiModuleUrl`; page-embedded graph helpers: `graphCanvasFor`, `readGraphJsonScript`, `graphFallbackVariants`, `getGraphData`, `getGraphVariants`; manifest graph helpers: `normalizeGraphData`, `graphsFromManifest`, `loadJson`, `loadManifestGraphs`, `loadGraphs`. |

## Browser Runtime API

Browser-side custom interfaces should start through
`window.VersoBlueprint.onRenderReady`. The callback receives the shared render
API installed by the standard Blueprint preview/runtime asset. It loads the
manifest and rendered-fragment cache from the page's `-verso-data/` directory,
keeps load status for diagnostics, and hydrates inserted fragments.

Use `renderPreviewInto` when the client just needs to place a preview body
fragment into the page:

```javascript
window.VersoBlueprint.onRenderReady(async function (api) {
  const key = api.previewKey("addition_right_identity", "statement");
  const target = document.querySelector("#audit-preview");
  if (!target) return;

  const result = await api.renderPreviewInto(target, key);
  if (result.ok) {
    console.log(result.manifestEntry.title);
  }
});
```

Use `renderCanonicalPreviewInto` when the client wants the same Blueprint node
wrapper that appears on the generated page. This resolves the semantic manifest
entry, follows its generated-page link, extracts the canonical node by id, and
hydrates the inserted copy:

```javascript
window.VersoBlueprint.onRenderReady(async function (api) {
  const key = api.previewKey("addition_right_identity", "statement");
  const target = document.querySelector("#audit-preview");
  if (!target) return;

  const result = await api.renderCanonicalPreviewInto(target, key);
  if (result.ok) {
    console.log(result.canonicalSourceHref);
  }
});
```

Use `resolvePreview` when the client needs semantic data before deciding how to
display the preview:

```javascript
window.VersoBlueprint.onRenderReady(async function (api) {
  const key = api.previewKey("addition_right_identity", "statement");
  const result = await api.resolvePreview(key);
  if (!result.ok) return;

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
  if (!inserted.ok) return;
  document.querySelector("#audit-previews").appendChild(row);
});
```

After readiness, the same API is available as `window.VersoBlueprint.render`.
Scripts that are emitted as Blueprint inline assets should still use
`onRenderReady`: Verso stores inline JavaScript assets as a set, so source-list
order is not a synchronization guarantee.

Blueprint's bundled preview clients get a small readiness bootstrap before
their client code so `onRenderReady` is available even when the client asset is
emitted before `preview-runtime.js`.

Stable custom-client entrypoints:

| Entry point | Use |
| --- | --- |
| `window.VersoBlueprint.onRenderReady(callback)` | Run startup code that needs the render API, even if the client asset executes before `preview-runtime.js`. |
| `api.dataUrl(filename)` / `api.manifestUrl()` / `api.htmlCacheUrl()` | Resolve generated `-verso-data/` URLs relative to the current page. |
| `api.loadManifest()` / `api.loadHtmlCache()` | Load the generated `Map` values keyed by preview key. |
| `api.readManifestStatus()` / `api.readHtmlCacheStatus()` | Inspect diagnostics such as `idle`, `loading`, `ready`, and `error`. |
| `api.loadManifestEntry(key)` / `api.loadHtmlCacheEntry(key)` | Read one generated entry by key. |
| `api.getGraphData(element)` / `api.getGraphVariants(element)` | Read page-embedded graph data and render variants from a rendered graph block. |
| `api.graphsFromManifest(manifestJson)` / `api.loadManifestGraphs(url, options)` / `api.loadGraphs()` | Decode or fetch finalized graph records from `blueprint-manifest.json.graphs`; `loadGraphs` uses the current page's generated manifest URL. |
| `api.graphApiModuleUrl()` | Resolve the generated ESM graph API module URL for dynamic imports from custom clients. |
| `api.previewApiModuleUrl()` | Resolve the generated ESM preview/render API module URL for dynamic imports from custom clients. |
| `api.previewKey(label, facet)` / `api.statementPreviewKey(label)` | Build normalized preview keys for custom render targets. |
| `api.resolvePreview(key)` | Resolve manifest data and a rendered body fragment together, returning `{ ok, key, reason, manifestEntry, htmlCacheEntry, html, diagnosticHtml }`. |
| `api.renderPreviewInto(element, key, options)` | Write the rendered body fragment or diagnostic HTML into `element`, then hydrate nested previews and math. |
| `api.resolveCanonicalPreview(key)` | Resolve the same data as `resolvePreview`, then load the generated page named by `manifestEntry.href` and return `canonicalHtml` plus `canonicalSourceHref` for the real Blueprint node wrapper. |
| `api.renderCanonicalPreviewInto(element, key, options)` | Write the canonical Blueprint node wrapper or diagnostic HTML into `element`, then hydrate nested previews and math. |
| `api.hydrate(element, options)` | Hydrate custom wrappers that inserted cached rendered fragments themselves. |

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

The most common failure `reason` values are:

- `missing-key`
- `manifest-entry-missing`
- `html-cache-entry-missing`
- `canonical-href-missing`
- `canonical-preview-node-missing`
- `canonical-preview-load-failed`

Treat `html` and `canonicalHtml` as opaque rendered fragments. Use
`manifestEntry` for semantic facts such as labels, titles, dependency metadata,
group data, code associations, and generated links.

Blueprint's bundled graph, summary, relation-panel, inline preview, and slide
JavaScript also start through `onRenderReady` and receive the same render API.
Custom clients should do the same so preview lookup, diagnostics, and hydration
stay on one runtime path. The runtime keeps manifest/cache load state private;
clients should inspect it through `readManifestStatus()` and
`readHtmlCacheStatus()` rather than reading `window` globals.

Slide decks keep their slide-specific rehydration bridge under the same
namespace as `window.VersoBlueprint.slides`. That bridge is for the generated
slide asset; custom preview clients should use the stable render API table
above unless a slide-specific hook is explicitly documented there.

For semantic queries, use the manifest entry returned by `resolvePreview` or
`loadManifestEntry`. Do not parse inserted or cached fragments to rediscover
labels, dependencies, group membership, Lean-code associations, or status
metadata. The cached fragment is presentation: it may display those facts, but
the manifest is the data contract.

## Bundled Helper Boundary

Bundled-feature helper APIs are intentionally narrower than the stable API.
They are exported on `window.VersoBlueprint.render` so Blueprint's own feature
scripts can share runtime mechanics without duplicating them. They are not a
custom-client contract unless they are promoted into the stable table above.
The intended path for Blueprint-owned panels is `createPreviewSurface`; it owns
content updates plus trigger, dismissal, and reposition lifetimes. Lower-level
helpers remain exported only where bundled graph popovers, positioning
callbacks, or generated preview code still need them directly.

| Helper family | Helpers | Bundled consumers |
| --- | --- | --- |
| Template lifecycle | `collectPreviewTemplates` | Graph-local preview stores; summary and code-summary previews use Lean-emitted DOM descriptors that the runtime auto-binds |
| Surface, shell, and content | `createPreviewSurface`, `createPreviewPanel`, `previewMessageHtml`, `escapeHtml` | Graph preview panels, inline preview panels, relation panels, and runtime diagnostics |
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
Bundled feature scripts should prefer `surface.bindTriggers`,
`surface.bindDismissal`, `surface.bindRepositioner`, `surface.position`,
`surface.pointerWithin`, and `surface.shouldKeepOpen` over direct lifecycle
helpers. External clients should stay on the stable custom-client API above.

For new custom interfaces, prefer the highest-level entry point that fits the
job; see [Choosing an API](#choosing-an-api).

Future public browser APIs should be added to the stable custom-client table
when they are intended for external clients such as audits, dashboards, slide
adapters, or comparison views. Bundled helpers can still exist for Blueprint's
own JavaScript, but they should stay outside the public table until their
argument shape and compatibility expectations are ready to support those
clients.

## Standalone Example

For a browser-only client, there are two good starting points:

- copy one of the small inline examples above when you only need a single
  preview or graph record
- inspect the in-repo showcase when you want a full page with status text,
  diagnostics, module imports, rendered Blueprint nodes, and graph access

The in-repo `preview_runtime_showcase` test blueprint includes the same pattern
as a standalone browser client on its `Custom Render Client` page. It also
includes a graph-data card that calls `api.loadGraphs()` to read
`blueprint-manifest.json.graphs` without embedding a rendered graph, a
`type="module"` example that imports `renderPreviewInto` from
`-verso-data/api/preview.mjs`, and a graph module example that imports
`loadGraphs` from `-verso-data/api/graph.mjs`.

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
