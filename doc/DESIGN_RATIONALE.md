# Blueprint Design Rationale

Last updated: 2026-06-20

This document records the current architecture boundaries and the reasons the
Blueprint implementation is shaped the way it is.

It is intentionally not:

- the user-facing reference for options and rendering details
- the maintainer workflow guide
- the change backlog

Those responsibilities live in
[`MANUAL.md`](./MANUAL.md),
[`API.md`](./API.md),
[`MAINTAINER_GUIDE.md`](./MAINTAINER_GUIDE.md), and
[`ROADMAP.md`](./ROADMAP.md).

## Architecture Snapshot

### Canonical Semantic Source

Blueprint's core semantic model is a database of hybrid informal/formal
objects, each identified by a global label.

A labeled object may carry the informal statement or proof text, ownership and
group metadata, and links to formal material such as inline Lean code,
attributed compiled declarations, or external `(lean := "...")` references.

That database lives in `Environment.State`. Its object corpus lives in
`Environment.State.data`, with companion group and author metadata in the same
environment state. Elaboration and compilation are responsible for recording
the object-level facts and persisting them through Lean's compiled environment
data (oleans), rather than trying to precompute whole-site presentation.

Later, the generator binary re-enters that persisted state during Verso
traversal and assembles the final rendered metadata in document context.
Traversal resolves numbering, hrefs, cross-page references, previews, and
other relationships that depend on the whole rendered site rather than one
compiled object in isolation.

That boundary is deliberate. The environment answers "what is this informal
object, and what local formal/informal data belongs to it?" The
traversal/rendering pass answers "how do these objects sit inside this rendered
site?" Rendering and UI layers are expected to project from those two stages
rather than invent parallel sources of truth.

### Command Split

Command modules are split by concern:

- `VersoBlueprint/Graph.lean` owns the shared graph data model, finalized
  `GraphData` projection helpers, DOT rendering helpers, and graph-view
  variant construction used by page graphs and compact widgets
- `VersoBlueprint/GraphApi.lean` owns the traversal/cache-facing API for
  storing semantic graph data and finalizing it against completed traversal
  state
- `VersoBlueprint/Commands/Graph.lean`
- `VersoBlueprint/Commands/Summary.lean`
- `VersoBlueprint/Commands/Bibliography.lean`
- generic command CSS and shared preview/runtime asset injection in
  `VersoBlueprint/Commands/Common.lean`
- the target-details opener in `VersoBlueprint/Commands/open-target-details.js`
- the shared browser render API in `VersoBlueprint/Commands/preview-runtime.js`
- the inline-hover preview client in `VersoBlueprint/Commands/inline-preview.js`
- descriptor-driven summary and code-summary preview binding in the shared
  preview runtime

Informal-block support is now split across smaller modules instead of one large
`Block.lean` bucket:

- `Informal/Block.lean`:
  statement/proof block elaboration plus the top-level HTML block renderer
- `Informal/Block/Assets.lean`:
  block-specific CSS and browser JS bundle wiring; the block-owned preview
  handlers live in adjacent JS assets
- `Informal/Block/relation-panel.js`:
  relation-panel preview binding (`uses`, `used by`, and group panels)
- `Informal/Block/Store.lean`:
  stored-block lookup, merge, and numbering-resolution helpers used during
  traversal/rendering
- `Informal/MetadataView.lean`:
  shared metadata presentation policy used by block rendering and summary
  badges
- `Informal/Block/Common.lean`:
  shared block/code data structures and lightweight code-hover/panel markup
  helpers

Shared preview and rendering helpers live in `VersoBlueprint/Lib/`, notably:

- `HoverRender.lean`
- `PreviewSource.lean`

Shared and feature-specific browser assets stay with their owning commands:

- `Commands/preview-runtime.js`
- `Commands/inline-preview.js`
- `Commands/open-target-details.js`
- `Commands/graph.js`
- `Informal/Block/relation-panel.js`

Per-command CSS overlays stay with their commands:

- `Commands/graph.css`
- `Commands/summary.css`
- `Commands/bibliography.css`

## Rendering Clients

The same Blueprint object data is consumed in three broad ways:

1. local chapter content:
   inline references, informal blocks, and attached code snippets
2. global overview pages:
   graphs, summaries, and bibliography-style rollups
3. interactive clients:
   previews, widgets, and other runtime surfaces

This split is why one-source-of-truth pressure matters so much: local blocks,
global pages, and runtime widgets all need to agree on the same semantics while
projecting them differently.

## Blueprint Data Workflow

Blueprint has one semantic authoring model, but it deliberately crosses several
phase boundaries before a generated site is interactive. Each boundary exists
because the next phase owns facts that the previous phase cannot know yet:
compiled Lean elaboration owns local object semantics, Verso traversal owns
site-local anchors and numbering, preview-data emission owns whole-site cache
artifacts, and browser JavaScript owns interaction and hydration.

The current workflow is:

```mermaid
flowchart TD
  source["Blueprint source modules<br/>informal directives, Lean code, citations, groups"]
  elab["Lean / Verso elaboration<br/>directive parsing and local semantic registration"]
  env["Environment.State<br/>persistent semantic data in oleans"]
  traverse["Verso traversal<br/>numbering, hrefs, anchors, local preview blocks"]
  indexes["TraversalIndex domains<br/>Nodes, InlineCode, TraversalPreviews,<br/>LeanCodePreviews, citations, external-decl anchors"]
  render["HTML page rendering<br/>manual pages, graph, summary, bibliography"]
  manifest["PreviewManifest extra step<br/>semantic manifest and rendered-fragment cache"]
  artifacts["Generated artifacts<br/>HTML pages, assets, -verso-docs.json,<br/>blueprint-manifest.json, blueprint-html-cache.json"]
  browser["Browser runtime<br/>onRenderReady -> render API,<br/>graph/summary/block/slides JS"]
  consumers["External/custom consumers<br/>Slides, audit views, dashboards, custom wrappers"]

  source --> elab
  elab --> env
  env --> traverse
  traverse --> indexes
  indexes --> render
  indexes --> manifest
  render --> artifacts
  manifest --> artifacts
  artifacts --> browser
  artifacts --> consumers
  browser --> consumers
```

The same flow can be read as four contracts:

1. **Elaboration to environment.**
   Source directives, inline Lean blocks, `@[blueprint "..."]` attributes,
   external `(lean := "...")` references, group declarations, author
   declarations, citations, and metadata are elaborated into
   `Informal.Environment.State`. This is the canonical semantic store for
   Blueprint-owned facts. It is persisted through Lean environment extensions
   and imported through compiled oleans, so downstream modules see one merged
   object database.

2. **Environment to traversal.**
   During Verso traversal, Blueprint reads the semantic environment and writes
   render-time indexes into `TraverseState` through `TraversalIndex`. This is
   where site-local facts are created: rendered anchors, numbering caches,
   code-panel destinations, group and reverse-use panels, citation use sites,
   statement/proof preview entries, Lean declaration preview entries,
   public graph data records, and external declaration row anchors. These
   facts are intentionally not pushed back into `Environment.State`, because
   their values depend on the current rendered document and output mode.

3. **Traversal to generated artifacts.**
   Page rendering and preview-data emission both consume the traversal state.
   HTML pages get the visible document, graph, summary, bibliography, inline
   preview triggers, and feature-specific assets. The Blueprint preview-data
   extra step emits two structured files under `-verso-data/`:
   `blueprint-manifest.json`, which contains semantic preview entries, public
   graph data, and metadata, and `blueprint-html-cache.json`, which contains
   opaque rendered fragments plus the hover side data needed to hydrate those
   fragments inside generated pages.

4. **Artifacts to runtime and external consumers.**
   Browser code should treat the generated artifacts as immutable inputs. Page
   markup carries stable lookup keys and lightweight data attributes. Preview
   clients register setup work through `window.VersoBlueprint.onRenderReady`;
   once the shared runtime is installed, the callback receives the same API that
   is also exposed as `window.VersoBlueprint.render`. That API loads
   manifest/cache entries, inserts cached fragments as opaque HTML, hydrates
   nested preview widgets, renders math, and applies panel behavior.
   Feature-owned JavaScript such as graph, summary, relation-panel,
   inline-preview, and slide code binds those generic helpers to a concrete UI.
   Inline JavaScript asset order is not used as a readiness guarantee.
   Custom consumers should prefer the manifest/cache pair over scraping page
   HTML or re-solving Blueprint labels.

### Workflow Sources Of Truth

The main rule is: each fact has one owning phase, and later phases project from
that owner.

| Fact family | Owner | Stored as | Main consumers |
| --- | --- | --- | --- |
| Blueprint labels, node kind, declared dependencies, parent/group, owner, tags, priority, effort, PR URL | Elaboration | `Environment.State.data` and related environment maps | traversal, graph, summary, manifest construction |
| Group and author declarations | Elaboration | `Environment.State.groups` and `Environment.State.authors` | block rendering, summary, graph/group panels |
| Inline Lean and Rust attachments | Elaboration plus traversal | semantic code refs in environment; render-time code-panel indexes in `TraversalIndex.InlineCode` | block renderers, code panels, manifest entries |
| External Lean declaration snapshots | Elaboration / declaration snapshot registration | `ExternalRef` records on semantic nodes, enriched with presence/status/source/render data | block renderers, code-summary badges, summary, graph, manifest |
| Numbering, hrefs, anchors, preview keys | Traversal | `TraverseState` and `TraversalIndex` domains | page rendering, preview manifest, browser triggers |
| Statement/proof preview source blocks | Traversal | `TraversalIndex.TraversalPreviews` | manifest/cache emission, same-document manual grafts |
| Public graph data | Elaboration plus completed traversal | semantic `Informal.Graph.GraphData` cached in `TraversalIndex.Graphs`, then finalized through `Informal.GraphApi.finalData` for `blueprint-manifest.json.graphs`, page JSON, and bundled graph rendering | graph command rendering, browser runtime, custom graph consumers |
| Lean declaration preview fragments | Traversal | `TraversalIndex.LeanCodePreviews` | Lean links, manifest/cache emission |
| Rendered preview bodies | Preview-data emission | `blueprint-html-cache.json` | browser runtime, Slides, custom generated consumers |
| Semantic preview/catalog entries | Preview-data emission | `blueprint-manifest.json` | browser runtime, Slides, audit/custom UIs |
| Interaction state | Browser runtime | DOM state only | previews, panels, graph controls, custom wrappers |

This is why Blueprint keeps manifest state and traversal state separate even
when they describe the same object. Traversal state is the live, generator-local
working set. Manifest state is the serialized interchange artifact for
generated consumers. A renderer may project traversal state into manifest-shaped
entries for code reuse, but it should not pretend that generated manifest files
are the traversal source of truth inside the current generator.

### Render Path Inventory

There are several Blueprint render callers, but only a few true assembly
layers. The useful split is:

```mermaid
flowchart TD
  manualMain["Manual site generator<br/>PreviewManifest.blueprintMainWithPreviewData"]
  versoEmit["Verso Manual HTML emitters<br/>single-page and multi-page output"]
  informalManual["Informal Manual block renderer<br/>Informal.Block.toHtml"]
  commandRenderers["Command/inline renderers<br/>graph, summary, bibliography, math, cite, code"]
  previewExtra["Preview-data extra step<br/>emitBlueprintPreviewData"]
  previewFiles["Manifest/cache files<br/>blueprint-manifest.json<br/>blueprint-html-cache.json"]

  manualGraft["Manual graft command<br/>Graft.renderManualGraftNode"]
  traversalPreview["Traversal preview lookup<br/>PreviewSource / TraversalPreviews"]
  manualPreviewHtml["Manual preview-body render<br/>renderManualBlocksHtmlWithStateAndHovers"]

  slideMain["Slide deck generator<br/>Slides.slidesMainWithBlueprintPreviews"]
  slideRender["Slide node render<br/>Slides.Render.renderBlueprintSlideNode"]
  customRender["Custom generated consumer<br/>audit UI, dashboard, wrapper"]
  graftCache["Manifest/cache node render<br/>Graft.renderNodeFromManifestCache"]
  graftContent["Shared node assembly<br/>Graft.renderNodeWithContent"]
  manifestBlock["Manifest-backed block shell<br/>PreviewManifest.BlockRender.renderWithRenderedContent"]
  blockShell["Canonical block shell<br/>Informal.Block.Render.renderInformalBlockModel"]
  browserRuntime["Browser hydration<br/>onRenderReady -> render API<br/>and feature hydrators"]

  manualMain --> versoEmit
  versoEmit --> informalManual
  versoEmit --> commandRenderers
  manualMain --> previewExtra
  previewExtra --> previewFiles

  manualGraft --> traversalPreview
  traversalPreview --> manualPreviewHtml
  manualPreviewHtml --> graftContent

  previewFiles --> slideMain
  slideMain --> slideRender
  slideRender --> graftCache
  previewFiles --> customRender
  customRender --> graftCache
  previewFiles --> graftCache
  graftCache --> graftContent
  graftContent --> manifestBlock
  manifestBlock --> blockShell
  informalManual --> blockShell
  previewFiles --> browserRuntime
```

The current paths are:

| Path | Entry point | Data input | Shared assembly point | Output |
| --- | --- | --- | --- | --- |
| Normal Manual site pages | `Informal.PreviewManifest.blueprintMainWithPreviewData` | `Environment.State` plus `TraverseState` | `Informal.Block.Render.renderInformalBlockModel` for informal blocks; command-specific renderers for graph, summary, and bibliography | generated Manual HTML pages and assets |
| Preview manifest/cache emission | `Informal.PreviewManifest.emitBlueprintPreviewData` via `blueprintMainWithPreviewData` | completed Manual `TraverseState` and `TraversalIndex` domains | Manual preview render helpers plus manifest entry builders | `blueprint-manifest.json`, `blueprint-html-cache.json`, merged hover docs |
| Manual same-document graft | `Informal.Graft.renderManualGraftNode` through `{blueprint_node}` in Manual | current page traversal preview entry and current `TraverseState` | `Informal.Graft.renderNodeWithContent` | grafted Manual HTML block |
| Manual side-by-side graft wrapper | `Block.blueprintGraftSideBySide.toHtml` | already elaborated/rendered child blocks | wrapper only; child nodes follow the Manual graft path | side-by-side Manual HTML wrapper |
| Slides graft node | `Informal.Slides.slidesMainWithBlueprintPreviews` plus `Informal.Slides.renderBlueprintSlideNode` | serialized manifest/cache files copied from the Blueprint site | `Informal.Graft.renderNodeFromManifestCache` then `renderNodeWithContent` | static slide-node HTML plus slide assets |
| Slides side-by-side wrapper | `VersoSlides.BlockExt.wrap` emitted by `blueprint_side_by_side` in Slides | already rendered child slide blocks | upstream Slides wrapper; child nodes follow the Slides graft-node path | side-by-side slide HTML wrapper |
| External/custom generated consumers | direct calls to `Informal.Graft.renderNodeFromManifestCache` | serialized manifest/cache files | `Informal.Graft.renderNodeFromManifestCache` then `renderNodeWithContent` | consumer-owned HTML wrapper |
| Browser preview/panel hydration | `window.VersoBlueprint.onRenderReady` callback receiving the render API, plus registered feature hydrators | generated page markup, manifest/cache files, `-verso-docs.json` | JavaScript hydration only | interactive previews, panels, math, links |

This inventory is also the answer to "how many render contexts do we have?" for
grafted Blueprint nodes. `VersoBlueprint.Graft.Render` owns the one concrete
manifest/cache render context, `Informal.Graft.RenderContext`. It stores the
manifest index, HTML-cache index, and error logger. `VersoBlueprint.Slides.Render`
uses that context with slide-specific render configuration. Manual
grafts do not use a manifest render context, because they already have the live
`TraverseState`; they still end at `Informal.Graft.renderNodeWithContent` so the
block shell is assembled the same way.

### Node Component Ownership

A rendered Blueprint node is intentionally assembled from a small set of owned
components. When adding or changing node UI, use this table as the duplication
check: a component should have one semantic renderer, with genre- or
browser-specific code limited to configuration, lookup, insertion, or
hydration.

| Component | Single owner | Used by | Duplication status |
| --- | --- | --- | --- |
| Node wrapper, heading, title row, label, body container, and folded/open details shape | `Informal.Block.Render.renderInformalBlockModel` through `renderInformalBlockShell` | normal Manual blocks, manifest/cache rendering, grafted nodes, Slides nodes | single Lean owner |
| Statement metadata panel for owner, effort, priority, tags, and PR link | `Informal.Block.Render.renderStatementMetadataPanel` fed by `MetadataPresentation` | normal Manual blocks and manifest/cache-backed nodes | single node owner; summary renders separate badge views from the same metadata model |
| Header-extra slot ordering and wrapper classes | `Informal.Block.Render.renderHeaderExtras` | group, uses, used-by, code, and custom extras in normal and manifest-backed nodes | single layout owner |
| Relation panel/chip markup and relation-row badges | `Informal.RelatedPanel.renderPanel` | normal Manual nodes and manifest/cache-backed nodes through `PreviewManifest.BlockRender` | single Lean owner |
| Relation panel browser activation, loading/error replacement, and cache lookup | `Informal/Block/relation-panel.js` configured with `Commands/preview-runtime.js` `createPreviewSurface` trigger and dismissal binding | relation panels emitted by normal, grafted, Slides, and custom generated nodes | single JS owner for feature behavior; panel slots plus trigger/dismiss lifetime are shared through the surface, and relation-panel JS reuses the Lean-rendered loading body and only owns runtime error diagnostics |
| Code-summary trigger, template, and preview panel shell | `Informal.HoverRender.templatePreviewRoot`, configured by `Informal.CodeSummary.renderCodeSummaryPreview` | heading code badges and code-panel indicators | shared wrapper helper, code-summary-specific selectors |
| Code-summary semantics, declaration rows, status marks, and indicators | `Informal.CodeSummary` | node heading code extra and code-panel summary indicator | single semantic owner |
| Companion Lean/external-code panel shell | `Informal.mkCodePanel` | inline Lean panels, external declaration panels, Rust panels, manifest/cache-backed code panels | single panel-shell owner |
| External declaration rows and rendered declaration body strategy | `Informal.ExternalCode.renderExternalDeclRowsWith` | external-code panels and HTML-cache-backed Lean-code previews | shared row/status/footer owner with page-hover and self-contained body strategies |
| Manifest/cache-backed block shell assembly | `Informal.PreviewManifest.BlockRender.renderWithRenderedContent` | Slides, grafts, and custom generated consumers | single manifest-backed assembly owner; callers only supply config and content |
| Graft node lookup, diagnostics, and outer graft attrs | `Informal.Graft.renderNodeFromManifestCache` / `renderNodeWithContent` | Manual grafts, Slides grafts, external generated consumers | single graft owner |
| Browser manifest/cache loading and body-fragment insertion | `Commands/preview-runtime.js` `resolvePreview` and `renderPreviewInto` | graph, summary, relation panels, inline previews, custom browser clients | single JS data/cache owner |
| Browser canonical generated-node insertion | `Commands/preview-runtime.js` `resolveCanonicalPreview` and `renderCanonicalPreviewInto` | standalone/custom browser clients that want regular Blueprint node visuals | single JS canonical-preview owner |
| Browser preview panel behavior | `Commands/preview-runtime.js` `createPreviewSurface`, descriptor-driven template binding, `hidePreviewSurfaces`, and panel helpers | summary, code-summary, inline-preview, relation-panel, Slides, and graph feature scripts | single JS behavior helper; feature scripts pass selectors/defaults through rendered descriptors or feature-specific callbacks instead of owning panel slots, trigger lifetimes, dismissal binding, or close-button wiring |
| Browser preview-panel DOM creation and runtime diagnostic message markup | `Commands/preview-runtime.js` `createPreviewPanel`, `createPreviewSurface`, and `previewMessageHtml` | inline preview panels, relation-panel runtime errors, and future bundled feature panels that need runtime-created chrome | single JS panel/message/surface construction helper; feature scripts pass classes/slots/text |
| Browser inline-preview panel behavior, child panel, footer, and nested hover behavior | `Commands/inline-preview.js` configured with `Commands/preview-runtime.js` `createPreviewSurface` | inline Lean links, bibliography links, single relation chips, nested previews | feature-owned preview lookup and nested-panel rules; panel slots, header/footer updates, close-button behavior, trigger lifetime, pointer checks, and resize/scroll binding use surfaces |
| Browser graph preview, group-hover, popover, dismiss, and reposition behavior | `Commands/graph.js` configured with runtime surfaces and popover helpers | graph command output | feature-owned graph state; preview panel slots, trigger lifetimes, Escape close, and resize/scroll binding use surfaces; popover binding uses the shared runtime popover helper |
| Browser summary and code-summary preview binders | `Informal.HoverRender.templatePreviewDescriptorAttrs` emitted by Lean and auto-bound by `Commands/preview-runtime.js` | summary page labels and code-summary triggers in Manual pages, grafted nodes, and Slides | selector configuration is data on the rendered root; no per-feature JS binder owns this path |

When adding node UI, use this checklist before introducing a renderer or
browser helper:

1. Identify the semantic owner for the component in the table above.
2. Keep genre-specific Lean code to lookup, options, rendered body content, or
   caller-provided attributes.
3. Keep browser code to cache lookup, insertion, hydration, and interaction
   behavior; do not reconstruct node semantics from DOM fragments.
4. Prefer existing shell, metadata, relation-panel, code-panel, and preview
   helper APIs before adding a new wrapper.
5. Add a new owner to this table when a genuinely new component appears.

### Render-Path Consequences

The workflow implies a few constraints for renderers:

- **Manual rendering can use traversal directly.**
  Same-document commands such as Manual grafts can resolve the target through
  traversal indexes because the current page traversal state is available. They
  may still project the result into the manifest entry shape so the block shell
  and relationship panels use the same assembly code as generated consumers.

- **Generated consumers use manifest/cache.**
  Slides, external audit interfaces, and custom dashboards should read
  `blueprint-manifest.json` plus `blueprint-html-cache.json`. They should not
  reconstruct relationship panels, code bodies, status badges, or hover payloads
  by scanning raw document HTML.

- **Browser JavaScript hydrates; it does not own semantics.**
  Runtime code may load cached HTML, insert it into panels, render math, and
  bind nested preview handlers. It should not decide whether a node is
  formalized, which dependencies exist, or how related panels are structured.
  Browser clients and bundled feature JavaScript should use
  `window.VersoBlueprint.onRenderReady` for startup and the callback's render
  API argument to resolve manifest/cache entries and hydrate inserted fragments.
  After readiness, that same API is also available as
  `window.VersoBlueprint.render`, but direct reads should not be used as a
  startup synchronization mechanism. This keeps preview synchronization on one
  runtime API instead of splitting lookup and hydration across feature-owned
  helpers or relying on incidental inline-script order.

- **The browser render API has two tiers.**
  Custom clients should treat `onRenderReady`, manifest/cache loading and
  status readers, keyed lookup, `resolvePreview`, `renderPreviewInto`,
  `resolveCanonicalPreview`, `renderCanonicalPreviewInto`, and `hydrate` as the
  stable integration surface. `resolvePreview` and `renderPreviewInto` expose
  body fragments for clients that own their wrapper. The canonical-preview
  helpers follow the manifest entry's generated-page link and extract the
  actual Lean-rendered Blueprint node wrapper, so clients that want normal
  Blueprint visuals do not need to reconstruct headings, relation chips, or
  code extras in JavaScript. Blueprint's bundled feature
  scripts also share helper methods for runtime panel creation, surface-owned
  trigger/dismissal binding, surface-owned panel positioning and pointer
  checks, template-root binding, and feature hydrator registration. Those
  helpers keep bundled graph, summary, relation-panel, inline-preview, and
  slide scripts on one runtime path. `createPreviewSurface` is the
  component-shaped helper in this tier: it groups panel slots, behavior state,
  custom body rendering, content updates, trigger binding, dismissal binding,
  reposition binding, pointer checks, and keep-open checks without exposing a
  stable external contract. These helpers are not a public custom-client
  contract unless promoted into the API reference's stable API table. New public
  browser APIs should start as stable custom-client entries only when an
  external interface can describe its responsibility without depending on
  Blueprint-owned DOM structure; otherwise they should remain bundled helpers
  until the argument shape is clearer.

- **Split JavaScript by responsibility, not feature semantics.**
  The current preview runtime is still bundled as one asset, but its internal
  responsibilities are the boundaries for any future split: preview-data access,
  fragment rendering and hydration, template binding, panel/surface content,
  panel lifecycle, debug/hydration hooks, and API readiness. These groups are
  deliberately close to future component boundaries. A split module may load
  files, join entries by preview key, insert opaque fragments, own a preview
  surface's local UI state, or call hydrators; it should not infer Blueprint
  relation topology, ownership, status, or code associations from HTML markup.

- **Keep readiness and API guards source-level.**
  Feature JavaScript must start through `window.VersoBlueprint.onRenderReady`;
  direct reads from `window.VersoBlueprint.render` are limited to the runtime
  bootstrap path. Stable render API additions must be reflected in the API
  reference's custom-client table, while bundled helper additions stay out of
  that table unless intentionally promoted. Lean rendering tests should assert
  emitted markup, stable API wiring, and removed legacy paths; source-level
  guards and browser tests own private JavaScript helper shape. The harness test
  `tests/harness/test_preview_runtime_api_docs.py` owns these source-level
  guardrails so Lean rendering tests can focus on emitted markup, assets, and
  behavior instead of brittle JavaScript object-shape assertions.

- **Fallbacks should be diagnostic, not alternative data paths.**
  If a manifest entry or rendered-fragment body is missing, the UI should
  expose a clear local diagnostic. Silently falling back to page-local stale
  templates or ad hoc label scans creates a second source of truth.

### Manifest And Rendered-Fragment Cache Contract

The preview manifest and rendered-fragment cache have separate responsibilities:
the manifest owns semantics, and the cache owns presentation. The manifest is
the authoritative source for labels, facets, titles, hrefs, group membership,
relation topology, Lean-code associations, ownership metadata, tags, priority,
effort, and external markup metadata. The rendered-fragment cache stores opaque
HTML bodies keyed by the same preview keys, plus the Verso hover payloads needed
by those bodies.

Consumers should join the two files by preview key at the last responsible
moment. A renderer may use the manifest entry to decide what the object means
and how to wrap it, then use the cached fragment as the already-rendered body.
Browser clients may insert that fragment and hydrate it. They should not scrape
cached fragments to rediscover labels, dependencies, code status, group
membership, or other semantic facts. If a new generated consumer needs another
semantic fact, add that fact to `PreviewManifest.Entry` or a typed structure
referenced from it; do not encode it only in rendered HTML.

This rule keeps custom consumers independent of presentation markup. It also
lets Blueprint change CSS, heading layout, relation-panel markup, or rendered
code-panel structure without changing the semantic data contract. Cached HTML
may visibly contain relation panels, code panels, and headings, but those are a
rendering of manifest semantics, not a second data source.

### Body Fragments vs Full Node Wrappers

The rendered-fragment cache should not grow into a second node-wrapper cache
just because a browser client wants a whole Blueprint node. The current split is
intentional:

- `blueprint-html-cache.json` stores reusable rendered bodies. Those fragments
  are small enough to use in hovers, relation panels, custom cards, Slides, and
  generated consumers that provide their own wrapper.
- `blueprint-manifest.json` stores the semantic entry, including the generated
  page `href` and preview key needed to find the canonical page occurrence.
- the generated HTML page remains the owner of the exact page-level node shell:
  heading layout, wrapper attributes, relation-panel placement, code extras,
  folded state, and any future page-local affordances.

For `renderCanonicalPreviewInto`, the browser runtime therefore follows
`manifestEntry.href`, loads the generated page, clones the linked node, rebases
links, inserts the copy, and hydrates it. That JavaScript is justified because
it delegates shell structure back to the Lean-generated page instead of
duplicating shell semantics in browser code.

Adding a richer cache would be justified only if a repeated real use case needs
canonical node wrappers without page fetches and the cost is visible. In that
case the new artifact should be an explicit generated-node cache, not an
overloaded HTML-cache entry. It should still be produced by the same Lean block
shell renderer and keyed by the same manifest preview key, so JavaScript remains
a loader/inserter rather than the owner of Blueprint semantics.

### Phase Boundary Checklist

When adding a new Blueprint surface, choose its data boundary explicitly:

1. If the fact is authored by a directive or Lean declaration, put it in
   `Environment.State` or a typed semantic model referenced from it.
2. If the fact depends on document placement, rendered numbering, hrefs, or
   anchors, put it in a `TraversalIndex` domain.
3. If a semantic fact must be consumed outside the current generator process,
   emit it through `PreviewManifest`.
4. If a rendered body must be reused outside the current page render, put the
   already-rendered fragment in the rendered-fragment cache and keep it opaque
   to consumers.
5. If the fact is only UI interaction state, keep it in browser-owned DOM or JS
   state.
6. If two phases need the same shape, share a projection or renderer, not the
   mutable phase-local store itself.

## External Declaration Model

External Lean declarations are handled in stages.

1. A `(lean := "...")` reference first becomes a stable record saying "this
   Blueprint object points at this Lean declaration."
2. That record is then enriched with facts such as whether the declaration is
   present, where it came from, whether a source link is available, and what
   rendered declaration content was produced.
3. Local block rendering uses that enriched record to build hover and panel
   views.
4. Global summaries and graphs read the same enriched record for status and
   reporting.

The goal is to avoid a world where local rendering, global status, and preview
surfaces each re-resolve external declarations differently.

## Code Rendering Path Map

The "code rendering path" is not one pipeline; it is a small family of related
paths that share data and status helpers.

### Inline Lean attached to an informal block

This is the path for a rendered informal statement with a nearby Blueprint Lean
code block:

1. `Informal/Code.lean` elaborates the Lean block and records
   `InlineCodeData`.
2. `Informal/Block.lean` keeps semantic Lean associations accumulated across
   inline and external sources. Heading summaries prefer inline code when they
   need one compact status badge, while external declaration panels still render
   from the statement block's external references.
3. `Informal/CodeSummary.lean` computes the heading badge, summary hover body,
   and code-panel indicator from that resolved source.
4. `Informal/Block/Common.lean` provides the shared panel/header helpers used
   by both inline and external code panels.

This path owns semantic Lean completeness only. It does not currently carry a
separate "render health" channel because the code panel body is the original
rendered Lean block.

### External `(lean := "...")` references

This is the path for an informal block that points at a Lean-owned declaration:

1. `Informal/ExternalCode.lean` parses and resolves the directive names.
2. `ExternalRefSnapshot.lean` enriches each resolved declaration with:
   presence, proved status, provenance, source link, and direct declaration
   render result.
3. `ExternalDeclRender.lean` produces the direct external declaration HTML used
   by that snapshot from Verso Manual declaration/signature APIs.
4. `Informal/Block.lean` and `Informal/ExternalCode.lean` render the local
   external declaration panel from the enriched snapshot.
5. `Informal/CodeSummary.lean` renders the heading badge and panel indicator
   from the same external declaration snapshot.
6. `Commands/Summary.lean` and `Graph.lean` read the same snapshot-derived
   status for global reporting.

This path deliberately separates:

- semantic status:
  declaration present / missing / sorry-backed / axiom-like
- render health:
  whether the direct external declaration HTML render succeeded

Semantic status should not be downgraded by a renderer bug. Instead, renderer
problems surface as diagnostics alongside the semantic status.

### Shared preview and manifest path

Preview rendering has a shared-manifest path that reuses stored preview targets
rather than page-local template bodies:

1. `PreviewSource.lean` and `PreviewCache.lean` store statement/proof preview
   identities and blocks during traversal; citation traversal stores citation
   preview payloads under their own preview-data keys.
2. `PreviewManifest.lean` owns the Blueprint generator entry point and emits
   two files consumed by generated sites: the semantic Blueprint manifest and
   the rendered-fragment cache. The cache stores rendered fragments plus their
   Verso hover side table, while generated pages merge those hover payloads into
   `-verso-docs.json`. It also emits informal-block relationship topology,
   including uses, reverse uses, and group panel entries, while traversal state
   is still available.
3. `Commands/Common.lean` owns the browser-side preview runtime:
   rendered-fragment loading, missing-fragment diagnostics, hydration, math
   rendering, and anchored panel behavior.
4. Feature-owned JS such as `Commands/Summary.lean` summary preview wiring or
   `Informal/Block/Assets.lean` code-summary preview wiring binds the generic
   runtime to concrete surfaces.
5. `VersoBlueprint.Graft` provides the `{blueprint_node}` and
   `blueprint_side_by_side` grafting commands. Manual grafts resolve their exact
   traversal preview through `PreviewSource.lean`, project that preview into the
   same semantic entry shape emitted by `PreviewManifest.lean`, then use the
   shared manifest-backed block renderer. `VersoBlueprint.Graft.Render` owns the
   reusable manifest/cache rendering path for generated consumers; Slides supply
   slide-specific link attributes, classes, and diagnostics while delegating the
   semantic lookup and block assembly to that shared path. Browser JavaScript
   then hydrates links, math, and related-entry preview panels; it does not
   reconstruct Blueprint block markup or relationship topology from ad hoc
   manifest scans.

Inline Blueprint references, citation references, and the `used by`/group
relationship panels are now preview-data callers: the rendered page carries the
stable lookup key, while the preview body comes from the rendered-fragment
cache. Those surfaces deliberately avoid page-local fallback templates so
preview content has one generated source of truth. If the cache is unavailable
or missing an entry, the browser renders a local diagnostic message instead of
silently using stale local preview HTML.

### Blueprint render entry point

Blueprint generators call
`Informal.PreviewManifest.blueprintMainWithPreviewData`, not Verso's
`manualMain` directly. That wrapper is intentionally a thin orchestration
layer:

- Blueprint owns its extra CLI flags, Blueprint asset injection, post-traversal
  asset normalization, preview-data emission, and public xref
  filtering.
- Verso still owns document traversal, TeX emission, word counts, saved
  traversal-state serialization, search generation, the page shell, and the
  single-page/multi-page HTML emitters.

The important boundary is that Blueprint may adapt `TraverseState` and
`HtmlAssets` after traversal and before HTML emission, but it should not fork
Verso's HTML emitters unless upstream APIs leave no alternative. This keeps
local upstream workarounds, such as the highlighted-code docstring
`textContent` asset rewrite, on structured assets rather than on generated
HTML files.

The current public-xref filter still has a post-emit component: upstream Verso's
find-page writer embeds the full xref payload while emitting HTML, so Blueprint
rewrites `xref.json` and the find page after the Verso emitter runs. A future
upstream xref-emission hook would let this move into the same structured
pre-emit boundary as the asset normalization.

### Current diagnostic policy

The current policy is:

- semantic completion remains driven by `ProvedStatus`
- external render failures surface as local UI warnings
- optional summary diagnostics can expose those failures for maintainers
- coverage buckets and completion counts remain semantic rather than
  renderer-health-based

## Ownership Boundaries

Two naming domains must stay distinct:

1. Blueprint node labels are Blueprint-owned metadata.
2. `(lean := "...")` names are Lean-owned identifiers.

That boundary matters because convenience policies for Blueprint labels must not
quietly rewrite or reinterpret external Lean declaration names.

## Preview Rationale

### Shared Browser Runtime

Preview behavior is correctness-sensitive, and it is easy for multiple page
features to drift apart if each one hand-rolls its own browser logic. The
shared browser-side runtime therefore owns reusable operations such as:

- template collection and decoding
- math rendering for inserted preview bodies
- anchored-panel positioning
- close-button policy
- subtree hydration for nested preview content

The goal is consistent preview behavior across inline references, summary
panels, graph panels, and other Blueprint surfaces.

That runtime boundary is now explicit:

- `Commands/Common.lean` owns the generic preview runtime and reusable browser
  primitives
- feature-specific browser behavior stays with the owning feature when the code
  is not meaningfully shared; for example, informal-block preview handlers now
  live in `Informal/Block/Assets.lean`

### Separate Informal and Lean-Code Preview Identities

Statement and proof previews are keyed by `(label, facet)`. Lean-code previews
use `Informal.LeanCodePreview` under a Lean-name-oriented namespace. Citation
previews use a citation-oriented key containing the citation label, citation
style, and optional locator.

That split is deliberate:

- statement/proof previews are blueprint-entry overviews
- Lean-code previews are declaration-centric navigation
- citation previews are bibliography-entry hovers parameterized by rendered
  citation form and locator
- external-markup entries are semantic import witnesses and may intentionally
  have no rendered preview body

The UI can converge while the identity schemes remain distinct. Manifest entries
therefore carry a `targetKind` tag (`block`, `leanDecl`, `citation`, or
`externalMarkup`) instead of relying on every preview key to mean
`(label, facet)`.

### Shared Retrieval Namespace for Callers

Call sites that only need "give me the preview for this label" behavior should
prefer the shared `PreviewSource` namespace rather than decode
multiple storage formats directly.

That contract is intentionally narrow and phase-specific:

- traversal-time callers use its traversal helpers when they need cached
  preview blocks or manifest lookup keys
- environment-time callers use its environment helpers when they need semantic
  preview content from `Informal.Environment.State`
- renderers that only need one label at a time should prefer it over direct
  `PreviewCache.Entry` decoding

`PreviewSource` does not yet expose one top-level "best available preview"
selector. That is acceptable for now because current callers are still split
cleanly by phase and output needs.

The remaining direct `PreviewCache` decoding is in manifest construction, where
the code is intentionally enumerating all stored preview entries to emit the
shared browser manifest rather than retrieving previews one label at a time.

That convergence is not complete yet. Manifest construction still decodes
`PreviewCache` and `Informal.LeanCodePreview` entries directly because it
enumerates stored preview domains to emit the shared browser manifest.

### Traversal Storage Roles

Blueprint currently uses multiple storage channels during elaboration and
rendering:

- `Informal.Environment.State` for canonical semantic data authored in Lean
  modules
- `TraverseState.contents` for tiny traversal-local scalar state
- `TraverseState.domains` for link-oriented indexes plus local runtime caches

That mix is intentional, but the roles should stay explicit:

- semantic domains:
  stable document-level objects or declarations, whether or not the current
  renderer gives each one its own public anchor
- internal indexes:
  traversal-local lookup tables that support rendering but are not themselves
  semantic document objects
- runtime caches:
  stored preview payloads used to build shared browser manifests or local hover
  content
- accumulators:
  traversal-time backlink or ownership tables that are updated incrementally as
  blocks and inlines are traversed

`TraversalIndex` is the local module that names and classifies those stores.
Callers should prefer its typed APIs over reaching into raw domain names and
ad hoc JSON payloads directly.

### Process-Local Runtime Cache

`RuntimeCache` owns process-local facts that are expensive enough to avoid
recomputing but should not be serialized into `Informal.Environment.State` or
Verso traversal domains.

Current examples are source-link support data:

- module source path lookups, keyed by workspace root and module name
- Git root lookups, keyed by source directory
- GitHub repository URL and commit metadata, keyed by Git root

The cached values are only elaboration accelerators. Rendered declarations still
store concrete source links in their `ExternalRef` snapshots, so generated
artifacts do not depend on live cache state.

The API accepts fallback resolver actions instead of exposing the backing store.
That keeps callers independent of the storage strategy and leaves a narrow
future migration path to a Lake-integrated build-local file cache or daemon.

Functionally, the traversal indexes used by Blueprint have this shape. The
code-side inventory is `Informal.TraversalIndex.allSpecs`; the table below adds
the operational detail that is easier to read in prose.

| Index | Role | Functional map | Value description |
| --- | --- | --- | --- |
| `Nodes` | semantic domain | informal label -> `StoredBlockData` plus node anchor ids | Lightweight semantic node metadata: kind, parent/group, numbering caches, declared dependencies, ownership, tags, effort, priority, and PR URL. It deliberately excludes code/render payloads. |
| `InlineCode` | internal index | informal label -> `InlineCodeData` plus code-panel anchor ids | Inline/literate Lean code data for a node: declared definitions/theorems, command ordering, proof/code folding settings, and the code panel destination. |
| `ExternalMarkup` | semantic domain | informal label -> `ExternalMarkupSet` plus markup block anchor ids | Raw imported TeX/Markdown attachments keyed by language and slot, with optional project-relative LSP ranges for source comparison tooling. |
| `Groups` | semantic domain | group label -> `GroupBlockData` | Declared group metadata for a parent/group label, currently its display header. Group membership itself is stored on `Nodes` through each node's `parent`. |
| `TraversalPreviews` | runtime cache | `(informal label, preview facet)` -> `PreviewCache.Entry` plus preview anchor ids | Statement/proof preview blocks captured during traversal for hovers and preview-data emission. Entries may also carry HTML-cache keys for associated Lean-code previews; the code preview payloads themselves remain in `LeanCodePreviews`. |
| `LeanCodePreviews` | runtime cache | Lean declaration name -> `LeanCodePreview.Entry` plus declaration-preview anchor ids | Preview payloads for Lean declaration links, either from inline code blocks or external declaration snapshots. |
| `ExternalDeclAnchors` | internal index | `(informal label, canonical external declaration)` -> rendered declaration row anchor ids | Row-level destinations for rendered external declaration snippets, so summary and graph links can jump to the specific rendered occurrence. |
| `CitationPreviews` | runtime cache | `(citation label, citation style, locator kind, locator index)` -> `CitationPreviewData` | Bibliography hover payloads captured during citation traversal and rendered into preview data. |
| `Bibliography` | semantic domain | citation label -> bibliography entry anchor ids | Linkable bibliography entry destinations. |
| `CitationUsages` | accumulator | citation label -> `CitationUsageData` plus citation use-site ids | Backlink data accumulated from citation inlines, including rendered use-site destinations and human-readable location summaries. |

The auxiliary indexes above are normalized out of `Nodes` for different
reasons:

| Index | Main writers | Main readers | Normalization rule |
| --- | --- | --- | --- |
| `InlineCode` | `Block.informalCode.traverse` | Informal block/code renderers | Store at most one inline Lean code payload per informal label. The rendered statement then resolves inline code separately from the semantic node metadata, and inline code takes precedence over external declaration hints when both are available. |
| `ExternalMarkup` | `Block.externalMarkup.traverse` | Preview-manifest construction and optional external-markup display | Store markup attachments outside `Nodes` so late source blocks can be merged by label during traversal. Preview-backed labels expose the deterministic language/slot array on their block manifest entry; witness-only labels become semantic `externalMarkup` manifest entries without HTML-cache bodies. |
| `TraversalPreviews` | Informal block traversal, once per statement/proof block | `PreviewSource.traversalEntry?`, `PreviewSource.traversalEntryByKey?`, and preview-data construction | Store rendered-preview source blocks once per `(label, facet)`, where facet is statement or proof. Entries may point at associated Lean-code HTML-cache keys, but they do not duplicate declaration-preview payloads. This keeps hover/cache consumers from embedding preview bodies into every link or node entry. |
| `LeanCodePreviews` | Inline Lean code traversal and external declaration snapshot registration | Lean-code preview-data construction and Lean declaration links via the shared lookup key | Store declaration previews by canonical Lean declaration target, not by the Blueprint block or link occurrence that mentions it. Inline and external declaration previews therefore share the same declaration-preview namespace. |
| `ExternalDeclAnchors` | Informal block traversal for rendered external declarations | Informal block rendering plus summary/graph/code-summary links that jump to rendered external rows | Store only occurrence-specific row anchors keyed by `(informal label, canonical declaration)`. The same Lean declaration may be rendered under multiple Blueprint labels, and each rendered row needs its own destination. |
| `CitationPreviews` | Citation inline traversal | Preview-manifest construction and citation inline hovers via the shared lookup key | Store bibliography hover data once per rendered citation target and locator. Inline citations then carry a manifest key instead of owning page-local preview templates. |
| `CitationUsages` | Citation inline traversal | Bibliography rendering | Accumulate bibliography backlinks by citation label. Each citation use contributes a rendered href plus a structured location summary, while bibliography entries remain the semantic/linkable destinations in `Bibliography`. |

In particular, the main Blueprint node index is now intentionally slimmer than
the full `BlockData` payload used by block rendering. Code-specific
render/runtime data such as `codeData` belongs to dedicated traversal indexes
and block-local rendering inputs, not to the semantic node index itself.

Most traversal payloads use compact internal JSON to keep repeated preview and
cross-reference data small. That JSON is not a public interchange schema:
callers should go through `TraversalIndex` or the relevant typed model module.
Internal traversal/domain cache data is regenerated by the current generator;
old cache files are not a public API contract.

This does not mean every internal store has already moved off traversal
domains. Under current upstream Verso APIs, domains are still operationally
better than `TraverseState.set/get?` for hot per-entry updates, while
`TraverseState.set/get?` remains a good fit for tiny scalar state such as the
global numbering counter.

If Verso later grows a typed traversal-store API with linkable entries,
Blueprint should be able to migrate behind `TraversalIndex`: semantic domains
would remain the public link surface, while internal indexes, runtime caches,
and accumulators could move to the new backend without changing rendering
callers.

### Portable Snippet Rendering

Some previews are rendered inside a full page, while others are rendered in
isolated contexts such as editor or LSP hovers. Isolated renderers therefore
cannot rely on page-global hover tables. That is why Blueprint sometimes
rewrites hover payloads into self-contained HTML. Generated preview-cache
fragments are not treated as isolated snippets: they keep normal
`data-verso-hover` attributes and carry hover payloads as cache side data, so
generated pages and Slides can use the standard Verso hover path without
duplicating hover HTML into every fragment.

### Server-Mode Lean Elaboration

Blueprint Lean blocks elaborate both during ordinary document generation and
inside the interactive Lean server.

Server-mode elaboration is intentionally cheaper. `VersoBlueprint.Lean`
consults `Elab.inServer` directly instead of threading a block-level flag
through Blueprint code-block configuration. When `Elab.inServer` is `true`, it
skips declaration analysis and the expensive full highlighted-code pass, and
falls back to plain-text block and output payloads. The richer analysis and
highlighting path remains for non-server document generation, where render
quality matters more than editor latency.

## Graph and Completion Rationale

### Two-Track Status Model

The graph pipeline computes two orthogonal tracks per node:

- statement track (`StatementStatus`) drives border color
- proof/background track (`ProofStatus`) drives fill color

This keeps "can I state it?" separate from "can I finish the proof?" instead of
collapsing all progress into one overloaded color.

The current proof fill progression is:

- `not ready`
- `ready to formalize`
- `Lean code incomplete`
- `locally formalized`
- `locally formalized + dependencies complete`

That third state is intentionally a fill state rather than a warning: it marks
nodes where associated Lean code exists but is still incomplete, while keeping
missing-reference and missing-declaration problems in the warning channel.

### Completion Policy

Completion blocking policy is centralized in one place so summary pages, graph
coloring, and other status views do not silently drift apart.

Definitions and theorem-like nodes intentionally differ:

- definitions are blocked by both type-side and body-side gaps
- theorem-like statements are blocked only by statement/type gaps
- proof completion is blocked by any gap

### Precision and Warning Policy

Inline code has finer-grained provenance than external declaration snapshots.
The UI should expose useful external information without pretending it has the
same precision as local literate code.

Warning conditions such as missing external declarations, unresolved Blueprint
references, and Lean-only-without-informal-statement are modeled separately
from fill colors. Incomplete associated Lean code is instead promoted into the
proof-fill track so the graph can distinguish "not started", "started but
incomplete", "locally complete", and "complete with dependencies" directly in
the node fill.

## Active Tension Points

These are the current architectural fault lines that still deserve care:

1. status semantics can still drift between local block rendering and global
   outputs
2. preview retrieval still has multiple internal representations and adapters
3. external hover and panel rendering still share concepts that are not fully
   unified in one view model
4. preview regressions are easy to miss without traversal-level regression
   coverage

Those concerns motivate the cleanup priorities tracked in
[`ROADMAP.md`](./ROADMAP.md).
