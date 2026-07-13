# Getting Started

This guide is the shortest path from "I want a Blueprint project" to "I can
render a first site".

If you are new to Verso, the easiest approach is to copy the starter template
and keep the initial structure intact while you replace the example content.

## What You Are Building

A Blueprint project usually has three moving parts:

1. one or more chapter modules with the mathematical content
2. one Blueprint top-level file that assembles the document
3. one generator entry point that renders the site

Many older examples call the top-level file `Contents.lean`. In this doc set we
refer to it as the Blueprint top-level file because the role matters more than
the filename.

## Choose labels first

Blueprint blocks are identified by labels chosen by the author.

Examples:

- `addition_spec`
- `addition_right_identity`
- `multiplication_assoc`

Those labels are the key to the whole system. They are used to:

- identify nodes in the summary and graph views
- connect dependency references with `{uses "addition_spec"}[]`
- point at a node without adding a dependency edge with `{bpref "addition_spec"}[]`
- attach inline Lean code with a labeled `lean` code block
- attach external TeX or Markdown source for porting with `tex` or `md` code
  blocks
- tag compiled declarations with `@[blueprint "label"]`, optionally using
  `(autoDeps := true)` or `set_option verso.blueprint.autoDeps true` to infer
  edges to directly referenced Lean declarations associated with Blueprint labels

If you pick stable labels early, the rest of the project structure becomes much
easier to maintain.

Unlike Lean code references, `{uses "addition_spec"}[]` can refer to a label
before its final use sites are elaborated. Blueprint resolves those forward
references when building the document.

Use `uses` when the current Blueprint node mathematically depends on the target
node. Use `bpref` for prose references that should render as Blueprint links but
should not affect the graph or dependency summaries.

When a dependency has no natural prose location, add it to the block metadata:

```lean
:::theorem "addition_assoc" (uses := "addition_spec, addition_comm")
```

Use `intent` on an inline use, or `uses_intent` on metadata-only uses, to record
whether an edge is regular, auxiliary, or technical. Allowed intent values are
`"regular"`, `"auxiliary"`, and `"technical"`; omitted values default to
`"regular"`:

```lean
:::theorem "addition_assoc" (uses := "addition_helper") (uses_intent := "technical")
This depends on {uses "addition_spec" (intent := "auxiliary")}[].
```

Use `(origin := "automatic")` on inline uses, or
`(uses_origin := "automatic")` on metadata-only uses, only when tooling needs to
distinguish author-written edges from automatically inferred edges. Allowed
origin values are `"manual"` and `"automatic"`; author-written dependencies
default to `"manual"`.

These metadata options are accepted only by dependency-bearing uses: inline
`uses` roles and block-level `(uses := ...)` entries. `bpref` is link-only and
does not accept `origin` or `intent`.

Statement and proof directives keep their dependencies separate in the rendered
headers. A theorem-level `(uses := ...)` or inline `{uses ...}` in the statement
contributes to the statement `uses` chip, while a proof-level `(uses := ...)` or
inline proof use contributes to the proof `uses` chip for the same label.

If the payload of `{uses "addition_spec"}[]` or `{bpref "addition_spec"}[]` is
empty, Blueprint can generate the visible text automatically, for example
`Theorem N`.

## Start from the template

Use [project_template/](../project_template/) as the starting point.

Its key files are:

- `ProjectTemplate/Chapters/Addition.lean`: the first chapter
- `ProjectTemplate/Chapters/Multiplication.lean`: the second chapter
- `ProjectTemplate/Chapters/Collatz.lean`: a third chapter with a deliberately
  unfinished open problem
- `ProjectTemplate/Blueprint.lean`: the Blueprint top-level file
- `ProjectTemplateMain.lean`: the generator entry point
- `lakefile.lean`: package configuration, including the optional generator
  executable

The template is intentionally small. It is meant to teach the shape of a
Blueprint project before you scale it up.

## The three Verso forms to recognize first

If you are new to Verso, there are only three forms you need to understand at
the start:

- `#doc (Manual) "Title" =>` starts a document module
- `{include 0 Some.Module}` includes a chapter into the top-level file
- `:::definition "label_1"` starts a Blueprint block

You can get a long way just by following those three patterns in the template.

## Read the first chapters

The starter chapters in
[project_template/ProjectTemplate/Chapters/Addition.lean](../project_template/ProjectTemplate/Chapters/Addition.lean)
and
[project_template/ProjectTemplate/Chapters/Multiplication.lean](../project_template/ProjectTemplate/Chapters/Multiplication.lean),
plus
[project_template/ProjectTemplate/Chapters/Collatz.lean](../project_template/ProjectTemplate/Chapters/Collatz.lean)
show the most important authoring patterns:

- definition, proposition, theorem, and proof blocks
- labels that identify nodes
- a `uses` link to another Blueprint entry
- a `bpref` link when prose should reference a node without adding a dependency
- a local Lean code block
- a statement linked to an existing Lean declaration
- optional metadata such as `parent`, `owner`, `tags`, `effort`, and `priority`

The examples are about basic arithmetic on natural numbers, followed by a small
Collatz chapter. They read like a real mathematical story, but they are still
small enough to copy and adapt.

## Read the Blueprint top-level file

The top-level file in
[project_template/ProjectTemplate/Blueprint.lean](../project_template/ProjectTemplate/Blueprint.lean)
does two jobs:

1. it includes the chapter modules into the document
2. it chooses which rendered overview pages to include

The starter template includes:

- the chapter pages with `{include 0 ProjectTemplate.Chapters.Addition}` and
  the other chapter includes
- a dependency graph with `{blueprint_graph}`
- a progress summary with `{blueprint_summary}`

That is the core HTML surface most projects want first. The dependency graph can
also take `(direction := LR | RL | TB | BT)`, `(pack := true | false)`, and
`(preview := pinned | hover)` with optional
`(previewPlacement := docked | anchored)`. Grouped projects expose the current
graph views and preview behavior and placement through the rendered page's
`View`, `Legend`, and `Graph options` controls.

## Read the generator entry point

The entry point in
[project_template/ProjectTemplateMain.lean](../project_template/ProjectTemplateMain.lean)
is the `main` function you run to generate the site.

The included CI script first builds the project's Lean library artifacts, then
runs the generator file through Lean:

```bash
lake update
./scripts/ci-pages.sh
```

Run `lake update` once after copying the template. After that, run
`./scripts/ci-pages.sh` whenever you want the same local build-and-render check
that the included GitHub Pages workflow uses. Internally that script uses:

```bash
lake build ProjectTemplate
lake lean ProjectTemplateMain.lean -- --run ProjectTemplateMain.lean --output _out/site
```

This path avoids building the generator executable and its transitive native
artifacts, which is usually the better tradeoff for CI and Mathlib-heavy
projects. If you repeatedly run the same generator locally and want a compiled
executable, the `blueprint-gen` executable declared in `lakefile.lean` still
supports:

```bash
lake exe blueprint-gen --output _out/site
```

To build a PDF as well as the HTML site, pass `--pdf`:

```bash
lake exe blueprint-gen --output _out/site --pdf
```

This writes `_out/site/pdf/main.pdf`. PDF generation requires a local
`lualatex`-compatible command; use `--pdf-engine <cmd>` if your command has a
different name.

## What to change first

After copying the template:

1. rename `ProjectTemplate` to your project name
2. change the document title in the Blueprint top-level file
3. replace the addition, multiplication, and Collatz chapters with your own
   first chapters
4. keep the generator entry point and top-level file structure until your
   project is stable

## What to read next

After the first site renders:

1. read [doc/MANUAL.md](./MANUAL.md) for the full authoring surface
2. read [doc/API.md](./API.md) when you need documented Lean, generated-data, or
   browser integration APIs; start with
   [Choosing an API](./API.md#choosing-an-api)
3. jump directly to [Browser ESM APIs](./API.md#browser-esm-apis) for regular
   `import { ... } from ...` JavaScript modules, or to
   [Graph Data APIs](./API.md#graph-data-apis) when you need graph records
4. return to [project_template/README.md](../project_template/README.md) when
   you want to compare your project against the starter layout
