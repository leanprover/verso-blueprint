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
- use `api/graph.mjs` when a client needs graph data or graph rendering
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
without depending on `window.VersoBlueprint`. Generated slide decks load
`-verso-data/blueprint-slide-runtime.mjs`, which constructs the same renderer
shape and passes it explicitly to the slide, inline-preview, relation-panel,
and graph feature scripts.

## Choosing an API

Start from what you are building:

| You are building | Start with | Why |
| --- | --- | --- |
| A small browser script or standalone web page | [`api/data.mjs`](#browser-esm-apis), [`api/preview.mjs`](#browser-esm-apis), or [`api/graph.mjs`](#browser-esm-apis) | These are normal ESM modules, so clients can use regular `import { ... } from ...` syntax. |
| A script loaded by a generated Blueprint page | `createPreview()` from [`api/preview.mjs`](#browser-esm-apis) | The generated module constructs the renderer directly from emitted runtime modules without waiting on a page-global render hook. |
| A Node-like audit or migration tool that only reads generated data | `createPreviewData()` from [`api/data.mjs`](#browser-esm-apis) | It loads manifest/cache data without importing render, hydration, or DOM surface code. |
| A graph dashboard or audit page | [`loadGraphs()`](#graph-data-apis) | It reads finalized graph records from `blueprint-manifest.json`, even when the current page has no rendered graph block. |
| A custom browser widget beside an existing graph block | [`getGraphData(element)`](#graph-data-apis) | This reads the graph data and its `variants` from the single payload embedded next to a rendered graph. `getGraphVariants(element)` remains a convenience projection. |
| A custom page or slide that wants to render manifest graph data | [`renderGraphData(host, graph, { previewUtils })`](#graph-data-apis) | It constructs the standard graph block from finalized graph data and initializes the same renderer used by generated graph pages. |
| A custom page or slide that already has graph-block markup | [`renderGraphBlock(element, { previewUtils })`](#graph-data-apis) | It loads the graph renderer and initializes an existing standard graph block, using an explicit preview renderer for graph popovers. |
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
or is part of Blueprint's generated slide runtime.

| Context | Entry point | What it owns | What callers should use |
| --- | --- | --- | --- |
| Regular generated Manual page | `-verso-data/blueprint-page-runtime.mjs` | Creates one renderer with `createPreview()`, starts inline previews, relation panels, graphs, and descriptor-bound template previews. | Nothing extra; `withBlueprintAssets` installs this module. |
| Generated Blueprint slide deck | `-verso-data/blueprint-slide-runtime.mjs` | Creates one renderer with `createPreview()`, starts inline previews, relation panels, graphs, and slide-node hydration. | Nothing extra; `slidesMainWithBlueprintPreviews` installs this module. |
| Custom browser page, dashboard, audit view, or slide adapter | `-verso-data/api/preview.mjs` | Manifest/cache loading, preview lookup, rendered-fragment insertion, canonical node loading, math rendering, and hydration. | `createPreview()`, then `resolvePreview`, `renderPreviewInto`, `renderCanonicalPreviewInto`, `renderNode`, or `hydrate`. |
| Data-only browser or Node-like client | `-verso-data/api/data.mjs` | Manifest/cache URL helpers, loading, status readers, source-document lookup, source-metadata resolution, and graph-data loading without DOM rendering. | `createPreviewData()`, `loadManifest`, `loadSourceDocuments`, `resolveSourceMetadata`, `loadHtmlCache`, `loadGraphs`, or single-entry readers. |
| Graph data or graph rendering | `-verso-data/api/graph.mjs` | Graph JSON discovery, manifest graph loading, graph-block construction, lazy graph runtime loading, and graph initialization. | `loadGraphs`, `getGraphData`, `getGraphVariants`, `renderGraphData(host, graph, { previewUtils })`, or `renderGraphs(root, { previewUtils })`. |
| Blueprint-owned panels in generated pages | Renderer bundled helpers | Panel slots, content updates, trigger lifetime, dismissal, repositioning, diagnostics, and shared preview lookup. | Feature scripts use `createPreviewSurface`, `renderPreviewIntoSurface`, or `resolvePreviewHtml`; custom clients should not import these helpers directly. |
| Summary and code-summary previews | Lean-emitted template descriptors plus `preview-runtime-template.mjs` | Selector configuration and binding for preview templates. | Emit descriptor attributes from Lean; no feature-specific startup script is needed. |

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
- `blueprint-html-cache.json` contains rendered body fragments keyed by
  preview keys for entries that have generated preview bodies. Some semantic
  entries, such as source-backed external markup generated with
  `--external-markup-render none`, intentionally have no cache fragment. The
  cache is presentation data; do not parse it to rediscover graph topology,
  labels, statuses, or dependency relationships.
- `api/graph.mjs` exposes graph-data helpers for ordinary browser `import`
  usage, plus graph-block rendering helpers for pages that carry generated
  graph markup.
- `api/data.mjs` exposes manifest/cache/key/URL helpers and source-metadata
  resolution for clients that do not need to render DOM previews.
- `api/preview.mjs` exposes the preview/render API for ordinary browser
  `import` usage.

The manifest is the semantic data contract for generated-site consumers.
Cached HTML is an opaque rendered fragment cache that can be inserted and
hydrated. The cache also carries the Verso hover payloads referenced by those
rendered fragments; generated Blueprint pages merge them into
`-verso-docs.json`, and Slides preloads them when rendering a deck.

The manifest may also contain VBP-internal generated-data markers used to
diagnose stale artifacts. These markers are not public compatibility promises
and may change whenever VBP needs a new internal reader boundary. Public
clients should use the semantic entries, graph records, source documents, and
generated browser APIs described here rather than depending on those markers.

In practice:

- use the manifest when you need to count nodes, inspect statuses, follow
  dependencies, or build a graph view
- use `entry.href` to jump to a generated Blueprint occurrence, and read
  `entry.sourceLocation` when a client needs the source file/range that
  produced the manifest entry; source location is an explicit result object
  with `{ ok, location, error }`, not an optional field
- use the HTML cache when you already know a preview key and want the rendered
  statement/proof/code fragment
- keep the manifest and cache from the same generated site; keys are shared,
  but the rendered HTML is not a portable semantic source

Generator-side data flow is source-to-traversal-to-public JSON. During Manual
traversal, Blueprint records preview identities, rendered bodies, Lean-code
associations, citations, graph data, and external-source witnesses in traversal
state and traversal domains. `Informal.PreviewManifest.buildPreviewDataFiles`
then normalizes those phase-local records into the semantic manifest and the
rendered-fragment cache. Generated ESM APIs load those two files; they do not
rerun traversal and should not recover semantics by scraping cached HTML.

Source-provenance data also lives in the manifest. Declared source documents
are exported as `sourceDocuments`. Each manifest entry carries a `sources` array
of zero or more refs pointing back to those documents. An abbreviated excerpt
looks like this:

Clients should read `entry.sources`; the manifest does not emit a singular
`entry.source` field. Most block and external-markup entries have at most one
source ref, while Lean-code preview entries can aggregate refs from multiple
sourced Blueprint nodes that share the same rendered Lean preview.

Generated browser APIs expose the same split. Data-only clients should use
`api/data.mjs` when they only need manifest facts: `loadManifestEntry`,
`loadSourceDocument`, `loadSourceDocuments`, and `resolveSourceMetadata` do not
import DOM rendering code. Render-capable clients should use `api/preview.mjs`
when they also need `resolvePreview`, `renderNode`, canonical node loading, or
hydration. Both entrypoints reuse the cached manifest load; resolving source
metadata does not fetch a second JSON file.

Clients can call `resolveSourceMetadata(source)` from either entrypoint when
they want the source refs attached to a preview joined with declared
source-document metadata. The `source` argument can be a preview key, a manifest
entry, or a result returned by `resolvePreview`, `resolveCanonicalPreview`, or
`renderNode`:

```javascript
const key = api.statementPreviewKey("Chapter2:Problem2.11.6");
const sourceMetadata = await api.resolveSourceMetadata(key);
if (sourceMetadata.ok) console.log(sourceMetadata.sources[0].document?.title);
```

`api/data.mjs` exposes `resolveSourceMetadata` both as an isolated
`createPreviewData()` instance method and as a module-level named export. Use
the instance method when a client supplies a custom `fetchJson`; the module-level
export is convenient for ordinary generated-site scripts that use the default
loader.

Generated Blueprint node shells render a compact source chip and lightweight
source preview from this same manifest data. The API itself returns structured
metadata only: richer PDF page viewers and crop overlays remain Blueprint/Verso
interface work rather than browser API policy. Returned file paths and
PDF/image/text coordinates are metadata; `resolveSourceMetadata` does not fetch
those assets or decide how a richer source review interface should look.

```json
{
  "sourceDocuments": [
    {
      "id": "paper",
      "title": "Representation Theory",
      "kind": "pdf",
      "pdf": "source/paper.pdf",
      "pageRoot": "source/pages",
      "imageRoot": "source/pages/images"
    }
  ],
  "previews": [
    {
      "sources": [
        {
          "document": "paper",
          "spans": [
            {
              "page": "12",
              "text": {
                "path": "source/pages/page-12.md",
                "startLine": 41,
                "endLine": 45
              },
              "pdf": {
                "path": "source/pages/page-12.pdf",
                "image": "source/pages/images/page-12.png",
                "box": {
                  "scale": 2,
                  "pageWidth": 1600,
                  "pageHeight": 2200,
                  "xMin": 120,
                  "yMin": 240,
                  "xMax": 980,
                  "yMax": 520
                }
              }
            }
          ]
        }
      ]
    }
  ]
}
```

When a sourced Blueprint node has associated Lean code previews, the
corresponding `leanDecl` or `inlineLeanCode` manifest entries also expose every
owning ref in `sources`. External declaration previews are keyed by canonical
Lean declaration; inline-code previews are keyed by the inline Blueprint code
label, so all declarations from one inline block share one rendered preview
entry. Declaration-specific inline identity is the owning inline code label plus
the declaration's position in the owning block entry's ordered inline code
metadata (`definedDefs` followed by `definedTheorems`). This lets audit clients
follow the source-document, Blueprint-node, and Lean-code chain without
scraping rendered HTML.

Lean-side clients that need common manifest queries should use the helper
methods on `Informal.PreviewManifest.File` rather than reimplementing filters:
`queryableStatementEntries`, `findQueryableEntriesByLabel`,
`findPrimaryQueryableEntry?`, `blockStatementEntries`,
`findBlockEntriesByLabel`, `findPrimaryBlockEntry?`, `sourceDocument?`,
`entriesWithSource`, `entriesForSourceDocument`, `ownerValues`, `tagValues`,
and `workQueueEntries`. Use the queryable helpers for the same node selection
as `lake exe vbp query`; use the block-only helpers when a consumer explicitly
needs rendered block entries and should exclude source-backed bodyless
external-markup nodes. Entry-level helpers
`Entry.hasSourceDocument`, `Entry.matchesText`, and `Entry.matchesCode` provide
the same source filtering and search predicates used by the `lake exe vbp query`
interface.

```lean
import VersoBlueprint.PreviewManifest

def primaryNodeTitle?
    (manifest : Informal.PreviewManifest.File)
    (label : String) : Option String :=
  (manifest.findPrimaryQueryableEntry? label).map (·.title)

def workQueueLabels
    (manifest : Informal.PreviewManifest.File) : Array String :=
  manifest.workQueueEntries.map (·.authoredLabel)
```

Generator-side Lean callers can configure source-backed external-source cache
fragments with `Informal.ExternalMarkupRender.Config`. The
default mode, `.markdown`, renders selected Markdown slots through MD4Lean with
raw HTML disabled and falls back to escaped source if MD4Lean cannot render the
fragment; TeX falls back to escaped source. `.source` always emits escaped
source; `.none` keeps
external-markup entries semantic-only with no generated HTML-cache fragment.
Relation, graph, and Lean-code preview references are serialized only when the
referenced preview key resolves through both the manifest and HTML cache.
Page-local relation panels and graph widgets that are rendered before generated
data finalization may still start from traversal preview candidates; browser
preview APIs report semantic-only missing bodies as
`semantic-preview-body-missing` rather than as stale cache data.
Set `showSourceNotice := false` when an embedding context should omit the
visible source-backed notice from generated fragments.

#### Manifest Label Fields

Manifest entries serialize several label-like fields with distinct roles:

- `key` is the stable lookup/cache identifier for a manifest entry. It may
  contain a target-family prefix such as `externalMarkup:` and should not be
  treated as display text.
- `targetKind` says how to interpret the key namespace: `block`, `leanDecl`,
  `inlineLeanCode`, `citation`, or `externalMarkup`.
- `label` is the canonical target label used for semantic identity.
- `authoredLabel` is the authored/display string form. UI and review clients
  should prefer it when presenting or round-tripping labels that contain
  punctuation.

Relation entries in `uses`, `usedBy`, and `group.entries` carry their own
`previewKey` field. That field is either a non-empty key that resolves through
both the manifest and rendered-fragment cache, or `null` when the related node
has no manifest/cache-backed preview in the generated artifact set. Fresh
generated data does not use an empty string as a no-preview sentinel.

Use `Informal.PreviewManifest.previewMetadataLosses state manifest` to audit
whether traversal-preview metadata survived manifest construction. A non-empty
result means a traversal preview, such as a bodyless directive carrying
`(lean := ...)`, had Lean preview keys that were not represented by the matching
manifest entry. The standard preview-data generator reports the same condition
as a non-fatal warning so source-backed import issues are visible without blocking
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

def allRenderedGraphEntries
    (state : Verso.Genre.Manual.TraverseState) :
    Array (Except Informal.TraversalIndex.DecodeError
      (Informal.TraversalIndex.StoredEntry Informal.Graph.GraphData)) :=
  Informal.GraphApi.cachedEntries state
```

`cachedEntries` preserves malformed traversal-cache records as `DecodeError`
values and successful records as canonical-name/data pairs, so callers can
report corruption instead of silently omitting graphs. The generated-manifest
path reports those errors and continues with valid graph entries.

Generated `blueprint-manifest.json` includes a `graphs` array. Each entry
contains `schemaVersion`, `nodes`, `edges`, and `groups`, with status enums,
dependency axes, preview keys, hrefs when traversal resolved them, and visual
metadata for renderers that want Blueprint's default styling. Graph schema
version 2 serializes each node `previewKey` as a string or `null`.

That finished traversal state is the stable boundary. Consumers should not
reconstruct graph hrefs or titles from lower-level traversal internals when the
finalized graph data is available.

Finalized graph data is traversal-backed. Imported semantic nodes or code-only
nodes that have no rendered occurrence in the current site are omitted from the
public graph; explicit unknown-reference diagnostics are retained. Graph node
`previewKey` values are selected preview keys finalized against the generated
manifest/cache pair: when a statement preview is unavailable but a proof preview
exists, graph and relation UI can point at the proof preview. Bodyless
source-backed nodes can point at their `externalMarkup:<label>` preview only
when that key has a manifest entry and rendered cache body. When a retained node
has no manifest/cache-backed preview in the generated artifact set, the finalized
`previewKey` is `null` and bundled graph variants omit the node from
`previewKeyByNodeId`. Use fixed facet keys such as
`PreviewCache.statementKey` or `PreviewCache.proofKey` only when your code is
explicitly requesting that facet.

| Need | Use |
| --- | --- |
| Best preview candidate for one label from finished traversal state | `PreviewSource.Selection` |
| Manifest/cache-backed preview key in generated data | Finalized relation or graph node `previewKey` |
| Explicit statement facet identity | `PreviewCache.statementKey label` |
| Explicit proof facet identity | `PreviewCache.proofKey label` |

The bundled graph renderer uses that finalized graph data as its block-level
source of truth. Lean attaches DOT render variants with
`Informal.Graph.GraphData.renderVariants` during graph finalization, so page
rendering and custom clients exercise the same graph record shape without
scraping rendered graph pages.

Browser callers can use the generated ESM graph module directly:

```javascript
// Import graph helpers from the generated graph API module.
import { loadGraphs, getGraphData } from "../-verso-data/api/graph.mjs";

// Load every finalized graph record from blueprint-manifest.json.graphs.
const graphs = await loadGraphs();

// Read graph data embedded in a rendered graph block on the current page.
const graph = getGraphData(document);
```

For rendering new graph blocks, prefer `loadGraphs()` and the manifest graph
record's Lean-emitted `variants` field. Generated graph blocks embed one
`script.bp-graph-data` payload that carries both the graph data and its render
variants for reading back graph blocks that already exist on a generated page,
including markup emitted by the page renderer.

The same module can render a graph from finalized manifest data. Rendering also
needs the Blueprint browser render runtime for preview surfaces, popovers, and
hydration. Custom module-only pages should pass an explicit API object as
`previewUtils`, usually one created with `createPreview()`. The ESM render
helpers lazy-load the interactive graph runtime, so callers should `await` them.

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";
import { loadGraphs, renderGraphData } from "../-verso-data/api/graph.mjs";

const previewUtils = createPreview();
const [graph] = await loadGraphs();
if (graph) {
  await renderGraphData(document.querySelector("#graph-host"), graph, {
    previewUtils,
    layout: "fill"
  });
}
```

Use `createGraphBlock(graph, options)` when a client wants to construct the
standard `.bp_graph_fullwidth` element first and insert or render it later. Use
`renderGraphData(host, graph, options)` when the host should be populated and
rendered in one call. Both helpers consume the graph record's precomputed
`variants` array, or an explicit `options.variants` override. They return
`null` when neither source provides render variants.

The module can also initialize an existing graph block. That compatibility path
is for markup that is already present, such as the standard
`.bp_graph_fullwidth` markup emitted by `{blueprint_graph}`, including its
embedded `script.bp-graph-data` payload.

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

Standalone clients that do not render a graph block can still load the manifest
graph records directly:

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
  neutral DOM shell used by generated interfaces. The decoder requires the
  encoded preview key rather than deriving one from label/facet attributes. The
  shell carries the `bp_graft_manifest_node` class as a stable selector for
  custom consumers.
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
client-facing node lists, prefer
`PreviewManifest.File.queryableStatementEntries` and
`findPrimaryQueryableEntry?` so label/facet selection matches the generated
`vbp` query API, including source-backed bodyless external-markup nodes. Code
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
page-global render hooks. Graph
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
const sourceMetadata = await data.resolveSourceMetadata(entry);
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
| `api/data.mjs` | Data-only clients: generated-data URLs, manifest/cache loading, semantic label/declaration resolution, source-metadata resolution, status readers, and preview-key helpers. |
| `api/preview.mjs` | Render-capable clients: data helpers, semantic label/declaration resolution, preview resolution, fragment insertion, canonical node rendering, label-based `renderNode`, and hydration. |
| `api/graph.mjs` | Graph clients: finalized graph loading, embedded graph-block data access, manifest-data graph rendering, and graph-block rendering with an explicit preview renderer. |

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

ESM clients can use the same semantic resolvers after importing the generated
preview module:

```javascript
import { resolveDeclaration, resolveLabel } from "./api/preview.mjs";

const label = await resolveLabel("addition_right_identity", { facet: "statement" });
const declaration = await resolveDeclaration("Nat.add");

if (label.ok && label.sourceLocation.ok) {
  console.log(label.href, label.sourceLocation.location.path);
}
if (declaration.ok && declaration.sourceLocation.ok) {
  console.log(declaration.href, declaration.sourceLocation.location.path);
}
```

Data-only clients can import the same resolvers from `api/data.mjs` when they
do not need DOM rendering or hydration:

```javascript
import { resolveLabel } from "./api/data.mjs";

const result = await resolveLabel("addition_right_identity");
if (result.ok) {
  console.log(result.key, result.sourceLocation);
}
```

## Browser Runtime API

Browser-side custom interfaces should start from `createPreview()` in
`api/preview.mjs`. It returns the render API object that loads the manifest and
rendered-fragment cache from the page's `-verso-data/` directory, keeps load
status for diagnostics, and hydrates inserted fragments. The renderer is scoped
to the importing module; clients do not need page-global render hooks.

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

Use `resolveLabel` when the client starts from a Blueprint block label rather
than a manifest key. It resolves only block entries, defaults to the statement
facet, and returns both the generated-page `href` and the manifest
`sourceLocation` result:

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";

const api = createPreview();
const result = await api.resolveLabel("addition_right_identity", { facet: "statement" });
if (result.ok) {
  console.log(result.href);
  if (result.sourceLocation.ok) {
    console.log(result.sourceLocation.location.path);
  } else {
    console.warn(result.sourceLocation.error);
  }
}
```

Use `resolveDeclaration` when the client starts from a Lean declaration name and
needs a declaration-keyed preview entry. It resolves external/declaration-keyed
manifest entries and returns both the generated Blueprint occurrence `href` and
the manifest `sourceLocation` result. Inline-code previews are keyed by the
inline Blueprint code label; clients that start from an inline block should read
that block entry's `leanCodePreviewKeys` or call `resolvePreview` with the
explicit preview key. The `href` points to the generated Blueprint preview
occurrence; the `sourceLocation` points to the Lean source definition:

```javascript
import { createPreview } from "../-verso-data/api/preview.mjs";

const api = createPreview();
const result = await api.resolveDeclaration("Nat.add");
if (result.ok) {
  console.log(result.href);
  if (result.sourceLocation.ok) {
    console.log(result.sourceLocation.location.path);
  } else {
    console.warn(result.sourceLocation.error);
  }
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
import { loadGraphs, renderGraphData } from "../-verso-data/api/graph.mjs";

const previewUtils = createPreview();
const [graph] = await loadGraphs();
await renderGraphData(document.querySelector(".current-slide"), graph, {
  previewUtils,
  layout: "fill"
});
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

Generated slide decks load one slide-specific module entrypoint:
`-verso-data/blueprint-slide-runtime.mjs`. `withBlueprintSlidesAssets` injects
it with Slides `extraHead`. New custom clients should import the ESM modules
directly.

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
| `api.loadSourceDocuments(options)` / `api.loadSourceDocument(id, options)` | Read declared source-document metadata from the manifest, either as the full list or by source-document id. |
| `api.dataApiModuleUrl()` | Resolve the generated ESM data API module URL for dynamic imports from custom clients. |
| `api.previewApiModuleUrl()` | Resolve the generated ESM preview/render API module URL for dynamic imports from custom clients. |
| `api.graphApiModuleUrl()` | Resolve the generated ESM graph API module URL for dynamic imports from custom clients. Use this instead of hard-coding a relative `-verso-data/api/graph.mjs` path when code may run from `html-multi/`, `html-single/`, slides, or embedded contexts. |
| `api.previewKey(label, facet)` / `api.statementPreviewKey(label)` | Build normalized preview keys for custom render targets. |
| `api.resolveLabel(label, options)` | Resolve a Blueprint block label and optional `{ facet }`, returning `{ ok, label, facet, key, reason, manifestEntry, href, sourceLocation }`. |
| `api.resolveDeclaration(declName, options)` | Resolve a declaration-keyed Lean preview entry from a Lean declaration name, returning `{ ok, declaration, key, reason, manifestEntry, href, sourceLocation }`. Inline code previews are keyed by their inline Blueprint code label and should be loaded through the explicit key in `leanCodePreviewKeys`. |
| `api.resolvePreview(key, options)` | Resolve manifest data and a rendered body fragment together, returning `{ ok, key, reason, manifestEntry, htmlCacheEntry, html, diagnosticHtml }`. |
| `api.renderPreviewInto(element, key, options)` | Write the rendered body fragment or diagnostic HTML into `element`, then hydrate nested previews and math. Render options may set `hydrators`, `inheritPageHydrators`, `templateBinder`, `hydrate: false`, or `renderMath: false`. |
| `api.resolveCanonicalPreview(key, options)` | Resolve the same data as `resolvePreview`, then load the generated page named by `manifestEntry.href` and return `canonicalHtml` plus `canonicalSourceHref` for the real Blueprint node wrapper. |
| `api.renderCanonicalPreviewInto(element, key, options)` | Write the canonical Blueprint node wrapper or diagnostic HTML into `element`, then hydrate nested previews and math. It accepts the same hydration options as `renderPreviewInto`. |
| `api.renderNode(element, request, options)` | Render by label as a generated Blueprint node: native content uses the canonical generated shell, and external markup uses the same shell with a call-scoped TeX/Markdown body renderer from `request.externalMarkup` or `request.preferredExternalMarkup`. It accepts the same hydration options as `renderPreviewInto`. |
| `api.resolveSourceMetadata(source, options)` | Resolve source provenance for a preview key, manifest entry, or render result. It joins `entry.sources` with declared source documents and returns `{ ok, key, manifestEntry, sources }`. |
| `api.hydrate(element, options)` | Hydrate custom wrappers that inserted cached rendered fragments themselves. It accepts the same hydration options as `renderPreviewInto`. |

## Preview Result Shapes

Preview/render helpers resolve to plain objects with an `ok` boolean and the
normalized preview `key`. Successful render results include semantic manifest
data and the rendered HTML used by the operation. Failed render results include
a `reason` and `diagnosticHtml` suitable for insertion into the page.
`resolveSourceMetadata` is data-only: it returns source metadata and failure
reasons, but no rendered HTML. It also does not load source PDFs, extracted
text, or page images; callers use the returned paths and spans in the source UI
they own.

| Helper | Success shape | Failure shape |
| --- | --- | --- |
| `resolveLabel(label, options)` | `{ ok: true, label, facet, key, manifestEntry, href, sourceLocation }` | `{ ok: false, label, facet, key, reason, manifestEntry, href, sourceLocation }` |
| `resolveDeclaration(declName)` | `{ ok: true, declaration, key, manifestEntry, href, sourceLocation }` | `{ ok: false, declaration, key, reason, manifestEntry, href, sourceLocation }` |
| `resolvePreview(key)` | `{ ok: true, key, manifestEntry, htmlCacheEntry, html }` | `{ ok: false, key, reason, diagnosticHtml }` |
| `renderPreviewInto(element, key, options)` | The `resolvePreview` success shape after writing `html` into `element` and hydrating it. | The `resolvePreview` failure shape after writing `diagnosticHtml` into `element`. |
| `resolveCanonicalPreview(key)` | `{ ok: true, key, manifestEntry, htmlCacheEntry, html, canonicalHtml, canonicalSourceHref }` | `{ ok: false, key, reason, diagnosticHtml }` |
| `renderCanonicalPreviewInto(element, key, options)` | The `resolveCanonicalPreview` success shape after writing `canonicalHtml` into `element` and hydrating it. | The `resolveCanonicalPreview` failure shape after writing `diagnosticHtml` into `element`. |
| `renderNode(element, request, options)` | Native-preview success shape with `renderMode: "native"` and `canonicalHtml`, or external-markup success shape with `renderMode: "external-markup"`, `externalMarkup`, and `canonicalHtml`. | `{ ok: false, key, reason, manifestEntry?, externalMarkup?, nativePreview?, diagnosticHtml }` after writing diagnostics unless `options.diagnostics === false`. |
| `resolveSourceMetadata(source)` | `{ ok: true, key, manifestEntry, sources }`, where each source has `{ sourceRef, documentId, document, spans }`. | `{ ok: false, key, reason, manifestEntry?, sources: [] }`. |

The most common failure `reason` values are:

- `missing-key`
- `missing-label`
- `label-entry-missing`
- `missing-declaration`
- `declaration-entry-missing`
- `manifest-entry-missing`
- `html-cache-entry-missing`
- `semantic-preview-body-missing`
- `canonical-href-missing`
- `canonical-preview-node-missing`
- `canonical-preview-load-failed`
- `external-markup-entry-missing`
- `external-markup-missing`
- `external-markup-renderer-missing`
- `external-markup-render-failed`
- `external-markup-node-shell-missing`
- `external-markup-node-shell-load-failed`
- `source-missing`

`semantic-preview-body-missing` means the manifest entry exists and the HTML
cache is loaded, but the entry is semantic-only in this artifact set and has no
rendered preview body. This is distinct from `html-cache-entry-missing`, which
signals a preview key that should have a cache fragment but does not.

Treat `html` and `canonicalHtml` as opaque rendered fragments. Use
`manifestEntry` for semantic facts such as labels, titles, dependency metadata,
group data, code associations, and generated links.

Blueprint's bundled graph, summary, relation-panel, inline-preview, and slide
JavaScript receive the same render API from the generated page or slide module
entrypoint. Custom clients should get the same API shape from `createPreview()`
so preview lookup, diagnostics, and hydration stay on one runtime path without
depending on page globals. The runtime keeps
manifest/cache load state private; clients should inspect it through
`readManifestStatus()` and `readHtmlCacheStatus()` rather than reading `window`
globals.

Slide decks keep their slide-specific rehydration bridge under the same
namespace as `window.VersoBlueprint.slides`. That bridge is for the generated
slide asset and does not expose the general render API; custom preview clients should use the stable render API table
above unless a slide-specific hook is explicitly documented there.

For semantic queries, use `resolveLabel`, `resolveDeclaration` for
declaration-keyed previews, or use the manifest entry returned by
`resolvePreview` or `loadManifestEntry`. Do not parse inserted or cached
fragments to rediscover labels, source locations, dependencies, group
membership, Lean-code associations, or status metadata. The cached fragment is
presentation: it may display those facts, but the manifest
is the data contract.

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

Blueprint's browser source files are ESM modules. Browser logic should be
written as ESM source and started through one explicit entrypoint.

The current private source chunks are:

| Chunk | Private responsibility |
| --- | --- |
| `preview-runtime-base.mjs` | Small shared helpers, template collection, HTML escaping, and debug hooks. |
| `preview-runtime-data.mjs` | Manifest/cache loading, status readers, and store lookups. |
| `preview-runtime-render.mjs` | Manifest/cache joins, rendered-fragment insertion, diagnostics, and canonical generated-node fetching. |
| `preview-runtime-source-metadata.mjs` | Source-provenance lookup and source-document joins for structured metadata. |
| `preview-runtime-hydration.mjs` | Math rendering, fragment hydration, and feature hydrator dispatch. |
| `preview-runtime-lifecycle.mjs` | Trigger, dismissal, popover, resize/scroll, and keep-open lifetimes. |
| `preview-runtime-surface.mjs` | Preview panel slots, behavior state, content updates, panel creation, and diagnostic message markup. |
| `preview-runtime-template.mjs` | Descriptor-driven binding for Lean-emitted template preview roots. |
| `preview-runtime-api.mjs` | Stable render API assembly and `createPreviewRuntimeApi`. |

Two adjacent implementation files are shared by bundled pages and generated ESM
modules:

| Chunk | Private responsibility |
| --- | --- |
| `blueprint-graph-core.mjs` | Graph JSON discovery, graph manifest loading, and graph-data normalization shared by the page runtime, slide runtime, and `api/graph.mjs`. |
| `blueprint-preview-core.mjs` | Generated-data URL helpers and preview-key construction shared by the page runtime, slide runtime, `api/data.mjs`, and `api/preview.mjs`. |
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
own feature scripts can share runtime mechanics without duplicating them. A
helper is not a custom-client contract unless it is promoted into the stable
table above.
The intended path for Blueprint-owned panels is `createPreviewSurface`; it owns
content updates plus trigger, dismissal, and reposition lifetimes. Lower-level
helpers remain exported only where bundled graph popovers, positioning
callbacks, or generated preview code still need them directly.

| Helper family | Helpers | Bundled consumers |
| --- | --- | --- |
| Template lifecycle | `collectPreviewTemplates` | Template-only code-summary previews; summary preview descriptors switch to manifest/cache lookup when `allow-html-cache` is enabled |
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
surface controller. It keeps caller-provided headings for loading and local
diagnostics, then prefers the resolved manifest entry title once lookup reaches
a manifest entry; header-label provenance remains source-node driven.
`resolvePreviewHtml` provides the narrower shared lookup
path for bundled feature scripts that already own their panel rendering but
still want key-based manifest/cache resolution and generated diagnostics on
lookup failure. Bundled feature scripts should prefer
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

For a browser-only client, there are two good starting points:

- copy one of the small inline examples above when you only need a single
  preview or graph record
- inspect the in-repo showcase when you want a full page with status text,
  diagnostics, module imports, rendered Blueprint nodes, and graph access

The in-repo `preview_runtime_showcase` test blueprint includes the same pattern
as a standalone browser client on its `Custom Render Client` page. It also
includes a graph-data card that imports `loadGraphs()` from `api/graph.mjs` to
read `blueprint-manifest.json.graphs` without embedding a rendered graph, a
`type="module"` example that imports `renderPreviewInto` from
`-verso-data/api/preview.mjs`, `renderNode` cards for native label rendering and
a metadata-bearing external-markup node with a call-scoped body renderer and
generated source refs, and a graph module example that imports `loadGraphs`
from `-verso-data/api/graph.mjs`.

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
