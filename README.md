# Verso Blueprint

Verso Blueprint is a Lean package for writing Blueprint documents in
[Verso](https://github.com/leanprover/verso).

A Blueprint project combines:

- informal mathematical exposition
- links to local Lean code or existing Lean declarations
- optional attached Rust code blocks on labeled nodes for mixed-language notes
- optional raw TeX source attachments on labeled nodes to help port existing TeX
- automatic tracking of formalization progress by analyzing the associated Lean
  code and declarations, including incomplete declarations such as `sorry`
- rendered overview pages such as dependency graphs and progress summaries
- HTML output with previews, navigation, and exported metadata

## Start Here

If you want to start a Blueprint project today, read these in order:

1. [project_template/README.md](./project_template/README.md)
2. [doc/GETTING_STARTED.md](./doc/GETTING_STARTED.md)
3. [doc/MANUAL.md](./doc/MANUAL.md)

## Current Project Shape

Today a Blueprint project usually owns three things:

- chapter modules containing the mathematical content
- a Blueprint top-level file that assembles chapters and rendered overview pages
- a site-generation executable that resolves forward references, computes
  metadata, and writes the generated output under `_out/`

`verso-blueprint` provides the Blueprint directives, rendering commands, preview
runtime, and support library code. The starter layout in
[project_template/](./project_template/) shows the recommended shape.
If you want to inspect that starter as a generated site before copying it, see
the [rendered project template](https://leanprover.github.io/verso-blueprint/reference-blueprints/project-template/).
For the broader rendered artifact index, including local test fixtures, see the
[published rendered artifact index](https://leanprover.github.io/verso-blueprint/).

## Core Features

### Labelled nodes and rich directives

Every Blueprint node is identified by a label such as `addition_spec` or
`addition_right_identity`. Those labels drive cross-references, graph nodes,
summary entries, code associations, TeX-source associations, and metadata
export.

When roles such as `{uses "foo"}[]` or citations have an empty payload,
Blueprint can automatically render text such as `Theorem N`.

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

### Math and TeX

Blueprint supports inline math such as ``$`n + 0 = n` `` and display math such as
``$$`\sum_{i=0}^{n} i = \frac{n(n+1)}{2}` ``. It also supports TeX preludes via
`tex_prelude` and best-effort KaTeX linting during elaboration. KaTeX is the
renderer used by the generated HTML.

Blueprint nodes can also carry raw general-TeX source through a labeled `tex`
code block:

````md
:::theorem "addition_right_identity"
For every natural number $`n`, $`n + 0 = n`.
:::

```tex "addition_right_identity"
\begin{theorem}\label{thm:addition-right-identity}
For every natural number $n$, adding zero on the right leaves it unchanged.
\end{theorem}
```
````

Today this raw TeX attachment is primarily a porting aid for existing TeX
sources. It is stored on the labeled node and is not rendered into the output
site. Other uses may be possible later.

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
switching, and the usual Blueprint hover/link previews.

Progress is computed automatically from the status of the associated Lean code
and declarations, so the HTML summary and graph views stay aligned with the
formal side. In particular, incomplete Lean declarations such as `sorry`
contribute automatically to the reported progress state.

### Metadata export

Blueprint can dump structured metadata for other tools, including the shared
preview manifest and its schema. These are command-line flags passed to the
generator binary, such as `--dump-manifest` and `--dump-schema`.

### Widget

The widget surface is experimental. Import `VersoBlueprint.Widget` explicitly if
you want to enable it.

## Reference Blueprints

The repository also tracks larger reference blueprints.

- [project_template/](./project_template/),
  [rendered site](https://leanprover.github.io/verso-blueprint/reference-blueprints/project-template/)
- [`ejgallego/verso-noperthedron`](https://github.com/ejgallego/verso-noperthedron),
  [rendered site](https://leanprover.github.io/verso-blueprint/reference-blueprints/noperthedron/)
- [`ejgallego/verso-sphere-packing`](https://github.com/ejgallego/verso-sphere-packing),
  [rendered site](https://leanprover.github.io/verso-blueprint/reference-blueprints/spherepackingblueprint/)
- [`ejgallego/verso-flt`](https://github.com/ejgallego/verso-flt),
  [rendered site](https://leanprover.github.io/verso-blueprint/reference-blueprints/verso-flt/)

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

### Developer Documentation

4. [doc/CONTRIBUTING.md](./doc/CONTRIBUTING.md): contribution conventions for
   this repository
5. [doc/MAINTAINER_GUIDE.md](./doc/MAINTAINER_GUIDE.md): repository-local
   generation, validation, CI publication, and worktree workflow
6. [scripts/README.md](./scripts/README.md): lightweight guide to the
   repository scripts and harness entry points
7. [doc/DESIGN_RATIONALE.md](./doc/DESIGN_RATIONALE.md): architecture and design
   boundaries
8. [doc/ROADMAP.md](./doc/ROADMAP.md): active cleanup and follow-up work
9. [doc/UPSTREAM_TODO.md](./doc/UPSTREAM_TODO.md): items intended to move back
   into `verso`

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
