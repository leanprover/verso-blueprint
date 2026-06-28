# Verso Blueprint

Verso Blueprint is a Lean package for writing Blueprint documents in
[Verso](https://github.com/leanprover/verso).

A Blueprint project combines:

- informal mathematical exposition
- links to local Lean code or existing Lean declarations
- optional attached Rust code blocks on labeled nodes for mixed-language notes
- optional external TeX or Markdown markup attachments on labeled nodes to help
  port existing sources
- automatic tracking of formalization progress by analyzing the associated Lean
  code and declarations, including incomplete declarations such as `sorry`
- rendered overview pages such as dependency graphs and progress summaries
- HTML output with previews, navigation, and exported metadata

## Start Here

If you want to start a Blueprint project today, read these in order:

1. [project_template/README.md](./project_template/README.md)
2. [doc/GETTING_STARTED.md](./doc/GETTING_STARTED.md)
3. [doc/MANUAL.md](./doc/MANUAL.md)
4. [doc/API.md](./doc/API.md) when you need stable Lean, generated-data, or
   browser integration APIs

## Current Project Shape

Today a Blueprint project usually owns three things:

- chapter modules containing the mathematical content
- a Blueprint top-level file that assembles chapters and rendered overview pages
- a generator entry point that resolves forward references, computes metadata,
  and writes the generated output under `_out/`

`verso-blueprint` provides the Blueprint directives, rendering commands, preview
runtime, and support library code. The starter layout in
[project_template/](./project_template/) shows the recommended shape.
For the broader rendered artifact index, including published reference
blueprints and local test fixtures, see the
[published rendered artifact index](https://leanprover.github.io/verso-blueprint/).

## Core Features

### Labelled nodes and rich directives

Every Blueprint node is identified by a label such as `addition_spec` or
`addition_right_identity`. Those labels drive cross-references, graph nodes,
summary entries, code associations, external-markup associations, and metadata
export.

When roles such as `{uses "foo"}[]` or citations have an empty payload,
Blueprint can automatically render text such as `Theorem N`.
Metadata-only dependencies can be written on a block with
`(uses := "foo, bar")`; inline and metadata-only uses can also carry intent tags
such as `"regular"`, `"technical"`, or `"auxiliary"`, plus an origin of
`"manual"` or `"automatic"`. Statement and proof directives render separate
`uses` chips, so proof-only prerequisites can stay attached to the proof header
without being folded into the statement chip.

Typical directives look like:

- `:::definition "addition_spec" (lean := "Nat.add, Nat.succ")`
- `:::theorem "addition_right_identity" (owner := "jason") (priority := "high")`
- `:::proof "addition_right_identity"`

````md
:::definition "addition_spec" (lean := "Nat.add, Nat.succ")
We write $`a + b` for the result of adding $`b` to $`a`.
:::

:::theorem "addition_right_identity" (owner := "jason") (priority := "high")
For every natural number $`n`, adding zero on the right leaves it unchanged:
$`n + 0 = n`.
:::

```lean "addition_right_identity"
theorem nat_add_zero_right (n : Nat) : n + 0 = n := by
  simp
```
````

### Connecting to Lean

Blueprint supports three main ways to connect informal nodes to Lean:

- inline code with a labeled Lean code block
- compiled code tagged with `@[blueprint "addition_right_identity"]`
- existing declarations referenced with `(lean := "Nat.add_assoc")`

```lean
@[blueprint "addition_right_identity"]
theorem nat_add_zero_right (n : Nat) : n + 0 = n := by
  simp
```

Add `(autoDeps := true)` when a tagged declaration, labeled inline Lean block,
or `(lean := "...")` statement should infer statement/proof dependency edges to
directly referenced Lean declarations that are already associated with Blueprint
labels. You can also set `set_option verso.blueprint.autoDeps true` for a file
or section, with local `(autoDeps := false)` available as an override. Inferred
edges are recorded with origin `"automatic"`; explicit `uses` and `proofUses`
entries remain manual unless written through the usual Blueprint dependency
syntax. Manual `{uses ...}` links remain available for prose-first Blueprint
nodes.

```md
:::theorem "addition_assoc" (lean := "Nat.add_assoc, Nat.add_comm")
This informal node is linked to existing compiled Lean declarations.
:::
```

### Attached Rust code

Blueprint also supports labeled inline Rust code blocks:

````md
:::definition "ffi_helper"
Helper routine mirrored in Rust.
:::

```rust "ffi_helper"
pub fn ffi_helper(x: i32) -> i32 {
    x + 1
}
```
````

Current behavior:

- the Rust block attaches to the Blueprint node with the same label
- the rendered page shows an associated Rust code panel
- rendering uses a small built-in syntax highlighter
- Rust blocks do not currently affect Blueprint progress/status semantics
- Rust diagnostics and external Rust references are not part of the current surface

### Math, TeX, and external markup

Blueprint supports inline math such as ``$`n + 0 = n` `` and display math such as
``$$`\sum_{i=0}^{n} i = \frac{n(n+1)}{2}` ``. It also supports TeX preludes via
`tex_prelude` and best-effort KaTeX linting during elaboration. KaTeX is the
renderer used by the generated HTML.

Blueprint nodes can also carry raw external markup through labeled `tex` and
`md` code blocks:

````md
:::theorem "addition_right_identity"
For every natural number $`n`, $`n + 0 = n`.
:::

```tex "addition_right_identity"
\begin{theorem}\label{thm:addition-right-identity}
For every natural number $n$, adding zero on the right leaves it unchanged.
\end{theorem}
```

```md "addition_right_identity" (slot := proof)
This was imported from a Markdown proof sketch.
```
````

Labeled standalone `tex` and `md` blocks are exported as semantic
external-markup catalog entries. Generated preview data also includes a
source-backed rendered fragment for markup-only entries: Markdown receives a
standard MD4Lean/MD4C HTML rendering with raw HTML disabled, while TeX is shown
as escaped source.
Pass `--external-markup-render source` to force escaped source text, or
`--external-markup-render none` to keep manifest-only entries without generated
HTML cache fragments. When the same label also has a rendered Blueprint
statement or proof, the raw markup is attached to that block's manifest entry
instead. Bodyless Blueprint directives that carry `(lean := ...)` still
contribute their Lean preview keys and code data to the exported manifest entry;
the generator warns if that metadata is ever dropped during manifest export.

These `ExternalMarkup` attachments are primarily a porting aid for existing
TeX or Markdown sources. They are stored on the labeled node, exported in the
Blueprint manifest, and are not rendered at their source location in the output
site by default. Use `slot` names such as `statement` and `proof` when one
Blueprint node corresponds to multiple source spans.

### Rendering to HTML

Blueprint can render:

- chapter pages
- a dependency graph with `blueprint_graph`
- an overview and progress summary page with `blueprint_summary`
- a bibliography page with `blueprint_bibliography`
- math-enabled previews and cross-links
- associated Rust code panels for labeled inline Rust blocks

The graph page is interactive rather than static: it can expose a view switcher
for grouped graphs, a legend popover, a `Graph options` control for direction
and component-packing switches, and graph-node previews that can be configured
as pinned or hover panels with docked or anchored placement.

Progress is computed automatically from the status of the associated Lean code
and declarations, so the HTML summary and graph views stay aligned with the
formal side. In particular, incomplete Lean declarations such as `sorry`
contribute automatically to the reported progress state.

### Metadata export

Blueprint can dump structured metadata for other tools, including the semantic
manifest, its schema, and the rendered-fragment cache
(`blueprint-html-cache.json`) used by preview consumers. The cache includes the
hover payloads needed by cached Lean fragments. These are command-line flags
passed to the generator binary, such as
`--dump-manifest`, `--dump-html-cache`, and `--dump-schema`. See
[doc/API.md](./doc/API.md) for the stable generated-data contract.

### JavaScript API tooling

The browser APIs emitted under `-verso-data/api/` remain plain JavaScript ESM.
API documentation is written in JSDoc, rendered with Docdash, and TypeScript
checks the public API entrypoints plus their direct support modules with
`allowJs` and `checkJs`.
The generated-site public browser entrypoints are `api/preview.mjs`,
`api/data.mjs`, and `api/graph.mjs`; the other emitted JavaScript modules are
private runtime support chunks for those entrypoints and generated pages.
This first pass intentionally focuses on the custom-client API surface; broader
private runtime coverage and `noImplicitAny` tightening are follow-up cleanup
items. TypeScript users consume generated declaration files from `dist/types`;
those files are build artifacts and are not tracked in source.

Useful maintainer commands:

- `npm run typecheck`
- `npm run build:types`
- `npm run check:types`
- `npm run docs`
- `npm run check:docs`

The rendered API reference is deployed on GitHub Pages at
[leanprover.github.io/verso-blueprint/js-api/](https://leanprover.github.io/verso-blueprint/js-api/).
CI also uploads the same generated HTML as the `js-api-docs` artifact on each
`ci.yml` run for PR-local inspection.

Custom clients can import the generated preview module directly from a rendered
site:

```js
import { createPreview } from "./-verso-data/api/preview.mjs";

const preview = createPreview();
const container = document.querySelector("#target");
if (!container) throw new Error("Missing preview target");

await preview.renderNode(container, {
  label: "Chapter2:Problem2.11.6",
  externalMarkup: {
    prefer: [
      { language: "verso", slot: "statement" },
      {
        language: "markdown",
        slot: "original",
        render: async ({ raw }, target) => {
          target.replaceChildren(renderMarkdown(raw));
        }
      },
      { display: "source" }
    ]
  }
});
```

### Widget

The widget surface is experimental. Import `VersoBlueprint.Widget` explicitly if
you want to enable it.

## Reference Blueprints

The repository also tracks larger reference blueprints.

- [project_template/](./project_template/), the in-repo starter template
- [`ejgallego/verso-sphere-packing`](https://github.com/ejgallego/verso-sphere-packing),
  [rendered site](https://leanprover.github.io/verso-blueprint/reference-blueprints/v4.30.0/spherepackingblueprint/)
- [`ejgallego/verso-noperthedron`](https://github.com/ejgallego/verso-noperthedron),
  [rendered site](https://leanprover.github.io/verso-blueprint/reference-blueprints/v4.30.0/noperthedron/)
- [`ejgallego/verso-flt`](https://github.com/ejgallego/verso-flt),
  [rendered site](https://leanprover.github.io/verso-blueprint/reference-blueprints/v4.30.0/verso-flt/)
- [`ejgallego/verso-carleson`](https://github.com/ejgallego/verso-carleson),
  [rendered site](https://leanprover.github.io/verso-blueprint/reference-blueprints/v4.30.0/verso-carleson/)

## Rendered Test Blueprints

The deployed test-fixture sites live under the GitHub Pages `test-blueprints`
tree:

- [categorized test blueprint index](https://leanprover.github.io/verso-blueprint/test-blueprints/)
- [preview runtime showcase](https://leanprover.github.io/verso-blueprint/test-blueprints/preview_runtime_showcase/html-multi/)

The distinction is:

- the categorized test blueprint index is the directory page for all local
  HTML-producing test fixtures
- `preview_runtime_showcase` is one specific standalone rendered site listed in
  that directory

Most entries in the test blueprint index are curated doc-backed fixtures. The
showcase is different: it is a small standalone Blueprint package used for the
browser/runtime regression path and for exercising richer cross-page behavior in
one place.

## Documentation

### User Documentation

Read these in order:

1. [project_template/README.md](./project_template/README.md): copyable starter
   project and file layout
2. [doc/GETTING_STARTED.md](./doc/GETTING_STARTED.md): first Blueprint walkthrough
3. [doc/MANUAL.md](./doc/MANUAL.md): authoring and rendering reference
4. [JavaScript API reference](https://leanprover.github.io/verso-blueprint/js-api/):
   browser-facing data, preview, graph, and shared type APIs
5. [doc/API.md](./doc/API.md): stable Lean, generated-data, and browser APIs

### Developer Documentation

6. [doc/CONTRIBUTING.md](./doc/CONTRIBUTING.md): contribution conventions for
   this repository
7. [doc/MAINTAINER_GUIDE.md](./doc/MAINTAINER_GUIDE.md): repository-local
   generation, validation, CI publication, and worktree workflow
8. [scripts/README.md](./scripts/README.md): lightweight guide to the
   repository scripts and harness entry points
9. [doc/DESIGN_RATIONALE.md](./doc/DESIGN_RATIONALE.md): architecture and design
   boundaries
10. [doc/ROADMAP.md](./doc/ROADMAP.md): active cleanup and follow-up work
11. [doc/UPSTREAM_BACKLOG.md](./doc/UPSTREAM_BACKLOG.md): items intended to move
   back into `verso`, Lake, or Lean

### Agent Helper Skill

The repository includes an agent-facing skill under
[`skills/verso-blueprint/`](./skills/verso-blueprint/) for Codex/Claude-style
local coding agents. The skill teaches agents to use `lake exe vbp ...` for
project discovery, build/serve previews, generated-data queries, and
post-edit checks.

This helper does not replace the normal Blueprint generation interface for
projects. `lake exe blueprint-gen ...` and the generator entry point remain the
documented user-facing rendering path. Treat `vbp` query JSON as an unstable
agent interface, not a public compatibility contract.

### Maintainer CLI Split

The repository now uses two small maintainer CLIs instead of one large mixed
surface:

- `python3 -m scripts.blueprint_harness`
  Worktree creation, root release-branch checks, landing, and local coordination
- `python3 -m scripts.blueprint_reference_harness`
  Reference-project generation, validation, cache sync, editable reference
  checkouts, and prune operations

The shell wrappers under [`scripts/`](./scripts/) still front the common
reference-generation and validation flows.

## Acknowledgements

Verso Blueprint builds on:

- [Verso](https://github.com/leanprover/verso), the document system used to
  write and render Blueprint documents
- [Lean 4](https://lean-lang.org/), the language and tooling used to elaborate
  the document and connect it to formal code

Verso Blueprint has been directly inspired by previous blueprint projects:

- [Patrick Massot's Lean blueprints](https://github.com/PatrickMassot/leanblueprint)
- [LeanArchitect](https://github.com/hanwenzhu/LeanArchitect)
- Side to side blueprints by Eric Vergo

We are very grateful to the authors of these projects for their hard work and contributions to the Lean community.
