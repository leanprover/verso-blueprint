# Blueprint Design Rationale

Last updated: 2026-05-04

This document records the current architecture boundaries and the reasons the
Blueprint implementation is shaped the way it is.

It is intentionally not:

- the user-facing reference for options and rendering details
- the maintainer workflow guide
- the change backlog

Those responsibilities live in
[`MANUAL.md`](./MANUAL.md),
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

- `VersoBlueprint/Commands/Graph.lean`
- `VersoBlueprint/Commands/Summary.lean`
- `VersoBlueprint/Commands/Bibliography.lean`
- generic command CSS and shared preview/runtime primitives in
  `VersoBlueprint/Commands/Common.lean`

Informal-block support is now split across smaller modules instead of one large
`Block.lean` bucket:

- `Informal/Block.lean`:
  statement/proof block elaboration plus the top-level HTML block renderer
- `Informal/Block/Assets.lean`:
  block-specific CSS and browser JS bundles, including the block-owned preview
  handlers (`used by` and code-summary preview wiring)
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

Graph-specific browser assets stay with the graph command:

- `Commands/graph.js`
- `Commands/graph-toc-toggle.js`

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
2. `Informal/Block.lean` resolves block-level code source precedence during
   HTML rendering, preferring inline code over any external-code hint.
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
3. `DocGenNameRender.lean` produces the direct external declaration HTML used by
   that snapshot.
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
   preview payloads under their own manifest keys.
2. `PreviewManifest.lean` owns the Blueprint generator entry point and renders
   the shared preview manifest consumed by the generated site.
3. `Commands/Common.lean` owns the browser-side preview runtime:
   manifest loading, missing-manifest diagnostics, hydration, math rendering,
   and anchored panel behavior.
4. Feature-owned JS such as `Commands/Summary.lean` summary preview wiring or
   `Informal/Block/Assets.lean` code-summary preview wiring binds the generic
   runtime to concrete surfaces.

Inline Blueprint references, citation references, and the `used by`/group
relationship panels are now manifest callers: the rendered page carries the
stable lookup key, while the preview body comes from the shared manifest. Those
surfaces deliberately avoid page-local fallback templates so preview content has
one generated source of truth. If the manifest is unavailable or missing an
entry, the browser renders a local diagnostic message instead of silently using
stale local preview HTML.

### Blueprint render entry point

Blueprint generators call
`Informal.PreviewManifest.blueprintMainWithSharedPreviewManifest`, not Verso's
`manualMain` directly. That wrapper is intentionally a thin orchestration
layer:

- Blueprint owns its extra CLI flags, Blueprint asset injection, post-traversal
  asset normalization, shared preview-manifest emission, and public xref
  filtering.
- Verso still owns document traversal, TeX emission, word counts, saved
  traversal-state serialization, search generation, the page shell, and the
  single-page/multi-page HTML emitters.

The important boundary is that Blueprint may adapt `TraverseState` and
`HtmlAssets` after traversal and before HTML emission, but it should not fork
Verso's HTML emitters unless upstream APIs leave no alternative. This keeps
local compatibility workarounds, such as the highlighted-code docstring
`textContent` asset rewrite, on structured assets rather than on generated HTML
files.

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

The UI can converge while the identity schemes remain distinct. Manifest entries
therefore carry a `targetKind` tag (`block`, `leanDecl`, or `citation`) instead
of relying on every preview key to mean `(label, facet)`.

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
- `TraverseState.domains` for link-oriented indexes plus some legacy local
  caches

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

Functionally, the traversal indexes used by Blueprint have this shape. The
code-side inventory is `Informal.TraversalIndex.allSpecs`; the table below adds
the operational detail that is easier to read in prose.

| Index | Role | Functional map | Value description |
| --- | --- | --- | --- |
| `Nodes` | semantic domain | informal label -> `StoredBlockData` plus node anchor ids | Lightweight semantic node metadata: kind, parent/group, numbering caches, declared dependencies, ownership, tags, effort, priority, and PR URL. It deliberately excludes code/render payloads. |
| `InlineCode` | internal index | informal label -> `InlineCodeData` plus code-panel anchor ids | Inline/literate Lean code data for a node: declared definitions/theorems, command ordering, proof/code folding settings, and the code panel destination. |
| `Groups` | semantic domain | group label -> `GroupBlockData` | Declared group metadata for a parent/group label, currently its display header. Group membership itself is stored on `Nodes` through each node's `parent`. |
| `TraversalPreviews` | runtime cache | `(informal label, preview facet)` -> `PreviewCache.Entry` plus preview anchor ids | Statement/proof preview blocks captured during traversal for hovers and the shared preview manifest. |
| `LeanCodePreviews` | runtime cache | Lean declaration name -> `LeanCodePreview.Entry` plus declaration-preview anchor ids | Preview payloads for Lean declaration links, either from inline code blocks or external declaration snapshots. |
| `ExternalDeclAnchors` | internal index | `(informal label, canonical external declaration)` -> rendered declaration row anchor ids | Row-level destinations for rendered external declaration snippets, so summary and graph links can jump to the specific rendered occurrence. |
| `CitationPreviews` | runtime cache | `(citation label, citation style, locator kind, locator index)` -> `CitationPreviewData` | Bibliography hover payloads captured during citation traversal and rendered into the shared preview manifest. |
| `Bibliography` | semantic domain | citation label -> bibliography entry anchor ids | Linkable bibliography entry destinations. |
| `CitationUsages` | accumulator | citation label -> `CitationUsageData` plus citation use-site ids | Backlink data accumulated from citation inlines, including rendered use-site destinations and human-readable location summaries. |

The auxiliary indexes above are normalized out of `Nodes` for different
reasons:

| Index | Main writers | Main readers | Normalization rule |
| --- | --- | --- | --- |
| `InlineCode` | `Block.informalCode.traverse` | Informal block/code renderers | Store at most one inline Lean code payload per informal label. The rendered statement then resolves inline code separately from the semantic node metadata, and inline code takes precedence over external declaration hints when both are available. |
| `TraversalPreviews` | Informal block traversal, once per statement/proof block | `PreviewSource.traversalEntry?` and preview-manifest construction | Store rendered-preview source blocks once per `(label, facet)`, where facet is statement or proof. This keeps hover/manifest consumers from embedding preview bodies into every link or node entry. |
| `LeanCodePreviews` | Inline Lean code traversal and external declaration snapshot registration | Lean-code preview-manifest construction and Lean declaration links via the shared lookup key | Store declaration previews by canonical Lean declaration target, not by the Blueprint block or link occurrence that mentions it. Inline and external declaration previews therefore share the same declaration-preview namespace. |
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
Where a payload replaced a previously derived object encoding, readers keep
legacy object support so existing cached traversal/domain data can still be
understood during the transition.

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

### Self-Contained Snippet Rendering

Some previews are rendered inside a full page, while others are rendered in
isolated contexts such as editor or LSP hovers. Isolated renderers therefore
cannot rely on page-global hover tables. That is why Blueprint sometimes
rewrites hover payloads into self-contained HTML.

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
