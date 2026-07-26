# Blueprint Manual

This document is the current reference for Blueprint authoring and rendering.
For stable Lean, generated-data, and browser integration APIs, see
[`API.md`](./API.md).

If you are starting a first project, read
[project_template/README.md](../project_template/README.md) and
[GETTING_STARTED.md](./GETTING_STARTED.md) before this manual.

## Contents

- [Mental Model](#mental-model)
- [Labels and Node Identity](#labels-and-node-identity)
- [Minimal Project Shape](#minimal-project-shape)
- [The Blueprint Top-Level File](#the-blueprint-top-level-file)
- [A First Chapter](#a-first-chapter)
- [Core Block Forms](#core-block-forms)
- [Connecting Blocks to Lean](#connecting-blocks-to-lean)
- [Attached Rust Code](#attached-rust-code)
- [Math, TeX, and external markup](#math-tex-and-external-markup)
- [Groups, Authors, and Metadata](#groups-authors-and-metadata)
- [Rendering Surface](#rendering-surface)
- [Metadata Export and Preview Data](#metadata-export-and-preview-data)
- [Reusing Blueprint Nodes and Previews](#reusing-blueprint-nodes-and-previews)
- [Blueprint APIs](#blueprint-apis)
- [The Generator Entry Point](#the-generator-entry-point)
- [Blueprint Options](#blueprint-options)
- [Experimental Widget](#experimental-widget)
- [Current Limits](#current-limits)

## Mental Model

A Blueprint project usually owns three things:

- chapter modules containing the mathematical content
- a Blueprint top-level file that assembles the document
- a generator entry point that renders the site

The Blueprint top-level file is often called `Contents.lean` in existing
projects, but the filename is not special. What matters is that one module
assembles the chapters and chooses the rendered overview pages.

## Labels and Node Identity

Blueprint nodes are identified by labels chosen by the author.

Examples:

- statement labels such as `addition_spec` and `addition_right_identity`
- group labels such as `addition_core`
- author ids such as `jason`

These identifiers are used by:

- `{uses "addition_spec"}[]` dependency references
- `{bpref "addition_spec"}[]` link-only references
- labeled inline Lean code blocks
- labeled inline Rust code blocks
- `tex` and `md` code blocks carrying external markup source
- `@[blueprint]` or `@[blueprint "label"]` on compiled Lean declarations
- summary and graph nodes
- preview lookup and exported metadata

Choose labels early and treat them as stable project identifiers.

Use `uses` when the current node depends on the target and should add an edge to
the graph and dependency summaries. Use `bpref` when prose should link to a
Blueprint node without registering that relationship as a dependency.

For dependencies that do not have a natural sentence-level reference, use the
block option `(uses := "label1, label2")`. Inline uses can carry
`(intent := "auxiliary")` or `(intent := "technical")`; metadata-only uses use
the parallel `(uses_intent := "...")` option.

Dependency use metadata options are string-valued:

- `intent` / `uses_intent`: one of `"regular"`, `"auxiliary"`, or
  `"technical"`; omitted values default to `"regular"`
- `origin` / `uses_origin`: one of `"manual"` or `"automatic"`; omitted values
  default to `"manual"`

These metadata options are accepted only by dependency-bearing uses: inline
`uses` roles and block-level `(uses := ...)` entries. `bpref` is link-only and
does not accept `origin` or `intent`.

Rendered statement and proof headers include separate `uses` chips that preview
their own declared dependencies. Statement-level `(uses := ...)` options and
inline statement uses stay on the statement chip; proof-level options and inline
proof uses stay on the proof chip for the same label. Non-default dependency
metadata such as `automatic`, `auxiliary`, and `technical` is shown in those
previews.

Proof directives accept the same dependency options, so proof-only
prerequisites can stay attached to the proof header:

```lean
:::proof "addition_right_identity" (uses := "induction_setup, zero_simplifier") (uses_intent := "auxiliary")
Induct on `n`, then discharge the zero case with the simplifier.
:::
```

If a role such as `{uses "addition_spec"}[]`, `{bpref "addition_spec"}[]`, or a
citation has an empty payload, Blueprint can generate the visible text
automatically, for example `Theorem N`.

## Minimal Project Shape

The starter template in [project_template/](../project_template/) uses this
layout:

```text
ProjectTemplate/
  Blueprint.lean
  Chapters/
    Addition.lean
    Multiplication.lean
    Collatz.lean
  Formalization/
    Addition.lean
ProjectTemplate.lean
ProjectTemplateMain.lean
lakefile.lean
```

The role of each file is:

- `ProjectTemplate/Chapters/Addition.lean`: a chapter with Blueprint blocks
- `ProjectTemplate/Formalization/Addition.lean`: ordinary Lean declarations
  tagged with `@[blueprint]` and included as a generated module chapter
- `ProjectTemplate/Chapters/Multiplication.lean`: another chapter with the same
  pattern
- `ProjectTemplate/Chapters/Collatz.lean`: a separate chapter for an
  intentionally unfinished open problem
- `ProjectTemplate/Blueprint.lean`: the Blueprint top-level file
- `ProjectTemplateMain.lean`: the renderer entry point
- `lakefile.lean`: the package definition

## The Blueprint Top-Level File

The Blueprint top-level file assembles the rendered document.

Example:

```lean
import Verso
import VersoManual
import VersoBlueprint
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary
import ProjectTemplate.Chapters.Addition
import ProjectTemplate.Chapters.Collatz
import ProjectTemplate.Chapters.Multiplication
import ProjectTemplate.Formalization.Addition

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Starter Blueprint" =>

This small Blueprint tracks a few basic arithmetic facts on natural numbers,
then ends with a separate Collatz chapter that is intentionally unfinished.

{include 0 ProjectTemplate.Chapters.Addition}
{includeBlueprintModule 0 ProjectTemplate.Formalization.Addition (title := "Compiled Addition Results")}
{include 0 ProjectTemplate.Chapters.Multiplication}
{include 0 ProjectTemplate.Chapters.Collatz}

{blueprint_graph}
{blueprint_summary}
```

This file decides:

- which chapter modules are included
- whether the dependency graph is rendered
- whether the summary page is rendered
- whether other global pages such as the bibliography are rendered

## A First Chapter

The following chapter example uses descriptive labels and a real mathematical
story about addition.

````lean
import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Addition" =>

:::group "addition_core"
Core statements about addition on natural numbers.
:::

:::author "project_author" (name := "Project Author")
:::

:::definition "addition_spec" (parent := "addition_core")
We write $`a + b` for the result of adding $`b` to $`a`.
This Blueprint starts with the most basic sanity checks around that operation.
:::

:::theorem "addition_right_identity" (parent := "addition_core") (owner := "project_author") (tags := "starter, arithmetic") (effort := "small") (priority := "high")
For every natural number $`n`, adding zero on the right leaves it unchanged:
$`n + 0 = n`.
This is the first sanity check for {uses "addition_spec"}[].
:::

:::proof "addition_right_identity"
Induct on $`n`. The base case is immediate and the inductive step unfolds one
successor on each side.
:::

```lean "addition_right_identity"
theorem nat_add_zero_right (n : Nat) : n + 0 = n := by
  simp
```

:::theorem "addition_assoc" (parent := "addition_core") (lean := "Nat.add_assoc")
For all natural numbers $`a`, $`b`, and $`c`, addition is associative:
$`(a + b) + c = a + (b + c)`.
This is another consequence of {uses "addition_spec"}[].
:::

:::proof "addition_assoc"
Lean already provides this theorem as `Nat.add_assoc`, so this Blueprint entry
links to an existing declaration instead of restating the code locally.
:::
````

This example shows the core pattern:

- define an informal mathematical object
- attach later statements to it with `uses`
- point to related entries without adding dependencies with `bpref`
- keep informal proofs close to the statement
- connect to Lean either locally or through an existing declaration

## Core Block Forms

Blueprint chapters commonly use:

- `:::definition "label_1"`
- `:::proposition "label_2"`
- `:::lemma_ "label_3"`
- `:::theorem "label_4"`
- `:::corollary "label_5"`
- `:::proof "label_4"`

`:::proof "label_4"` attaches to the earlier statement with the same label.

## Connecting Blocks to Lean

Statement-like blocks can connect to Lean in three main ways.

### Inline Lean code

Attach a labeled Lean code block to the same Blueprint label:

````md
:::theorem "addition_right_identity"
For every natural number $`n`, $`n + 0 = n`.
:::

```lean "addition_right_identity"
theorem nat_add_zero_right (n : Nat) : n + 0 = n := by
  simp
```
````

This is the clearest way to connect a Blueprint entry to local formalization
work in the same project.

### Compiled code tagged with `@[blueprint]`

Use the `@[blueprint]` attribute when a compiled definition-like
declaration or theorem should appear as a compiled-declaration-backed Blueprint
node. With no string argument, its Blueprint label is the declaration's
qualified Lean name:

```lean
/-- Associativity of addition under its qualified declaration name. -/
@[blueprint]
theorem MyProject.addition_assoc (a b c : Nat) :
    (a + b) + c = a + (b + c) := by
  simpa [Nat.add_assoc]
```

Use `@[blueprint "label"]` when the document should own a shorter or otherwise
independent label:

```lean
/--
Associativity of addition, exposed as a compiled-declaration-backed Blueprint
node.
-/
@[blueprint "addition_assoc_compiled"]
theorem addition_assoc_compiled (a b c : Nat) : (a + b) + c = a + (b + c) := by
  simpa [Nat.add_assoc]
```

This mode is useful when the formal declaration already exists as ordinary Lean
code and you want to register it as a Blueprint node.

If the declaration has a docstring, Blueprint tries to reuse it as the informal
statement body for that attribute-owned node. Plain docstrings are parsed
through the Manual Markdown path when possible. With the `doc.verso` option
enabled, standard structural content such as paragraphs, emphasis, lists,
links, code, math, quotations, and section content is converted into Manual
blocks. The same structural content is rendered inside the attached “Lean code
for…” declaration panel. If no docstring is available, the node is still
registered, but there is no imported informal statement body.

Enabling `doc.verso` does not elaborate a declaration docstring as a Blueprint
Manual fragment. Blueprint currently flattens every Lean docstring extension
node that successfully elaborates to its child content, discarding the
extension wrapper rather than looking up a Manual adapter. Custom Lean
docstring-extension semantics are therefore not preserved.

Blueprint Manual roles are a separate registry. In particular,
`{uses ...}[]` is not a Lean `doc.verso` role and is rejected during docstring
elaboration; it is neither flattened nor recorded as Blueprint dependency
metadata. Record those edges with the attribute's `(uses := [...])` or
`(proofUses := [...])` options. Blueprint deliberately does not create a
synthetic `DocElabM` context to reinterpret an imported docstring.

#### Including an attribute module as a chapter

When a regular Lean module is the primary Blueprint source, import it in the
document module's Lean header and include all of its directly tagged
declarations as one Verso part:

```lean
import MyProject.Formalization.Interpolation

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Project Blueprint" =>

{includeBlueprintModule 0 MyProject.Formalization.Interpolation (title := "Interpolation Spaces")}
```

The generated Manual part contains one materialized Blueprint node for each
distinct `@[blueprint]` label owned directly by the named module, in first
attribute-application order. If several declarations in that module use the
same label, the part contains one node with all of their Lean panels. Re-exported
or otherwise transitive modules are not folded into the part: include each
desired module explicitly. Every node follows the same docstring/code-only,
numbering, relation, preview, manifest, and cache path as an individual
placement. Its local display number is assigned in the consuming document's
traversal order; the generated placement does not retain a display number from
the provider module.

This is Blueprint's current Verso-native counterpart to
[LeanArchitect's `\inputleanmodule`](https://github.com/hanwenzhu/LeanArchitect#extracting-entire-lean-file-to-latex):
it turns tagged declarations from a regular imported Lean module into document
content. The current command includes declaration-backed nodes only. It does
not yet have LeanArchitect's ordered `blueprint_comment` equivalent for prose
interleaved among declarations; put compact prose in declaration docstrings, or
use individual `{blueprint_node "label"}` placements inside an ordinary Verso
chapter when the prose needs its own position.

Module inclusion currently materializes the statement facet only. A separate
informal `:::proof` body persisted in the defining module is not automatically
registered in the consuming document. Proof prose written and traversed in the
consuming document remains available through the ordinary proof facet. This is
separate from the compiled Lean proof: Blueprint's external-declaration panel
does not reproduce the original `:= by ...` source text.

The first positional number has the same structural role as in Verso's regular
`{include 0 Some.Document}` command. It is optional; without it, the generated
part is a child of the current part. The optional `(title := "...")` overrides
the generated title, whose default is the final component of the module name:

```lean
{includeBlueprintModule MyProject.Formalization.Interpolation}
```

The command is available only in Manual documents. It reads Blueprint metadata
from the imported `.olean`; it does not perform a Lean import from inside the
document body. If the exact named module is not available through the Lean
module's import graph, or if it directly owns no `@[blueprint]` declarations,
the command reports an error. A module include is best when declaration
docstrings are the chapter prose. To interleave longer prose between selected
declarations, use individual `{blueprint_node "label"}` placements instead.

#### Placing an attribute-owned node in a chapter

Import the module containing the tagged declaration, then write
`{blueprint_node "label"}` at the exact place where the node should appear:

```lean
import MyProject.Formalization.Interpolation

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Interpolation spaces" =>

The next result packages the formal definition used throughout this chapter.

{blueprint_node "k-interpolation-space"}

The surrounding chapter can continue with examples, motivation, or links to
later Blueprint nodes.
```

For an imported `@[blueprint]` node, this command does two jobs. It projects the
persistent Lean-side node into the current document traversal, which gives it a
number, page destination, relation metadata, and generated preview entries; it
then renders that entry through the ordinary Blueprint graft path. A docstring
becomes the statement body. A declaration without a docstring renders as a
code-only node instead of failing with “Blueprint node not found”.

This placement behavior is specific to attribute-owned nodes in Manual
documents. For ordinary `:::theorem` and related blocks, `{blueprint_node}`
continues to mean “render another view of a node already traversed in this
document”. In Slides, grafts continue to read the Blueprint site manifest/cache
passed to the Slides generator.

The usual graft options apply at the placement site, including `+compact`,
`-header`, `(displayLabel := "...")`, and `(facet := "proof")`. Compact mode
intentionally hides the attached Lean panel. For an imported attribute-owned
node, the initial placement currently materializes only its statement facet; a
proof facet is available after a matching `:::proof` has been traversed in the
consuming document. A persisted provider-module proof is not automatically
materialized, and a compiled theorem proof does not automatically become
informal proof prose.

Additional prose can simply surround the placement command. If the tagged
declaration has no docstring and the prose should live inside the numbered
statement shell, write a matching statement block instead; it fills the
attribute-created node and keeps the Lean association and dependency metadata:

```lean
:::theorem "k-interpolation-space"
An interpolation space satisfying the conditions used in this chapter.
:::

:::proof "k-interpolation-space"
The informal proof outline can be maintained separately from the Lean proof.
:::
```

Do not also use `{blueprint_node "k-interpolation-space"}` merely to create the
first occurrence in that case: the statement block is already the canonical
placement. Later `{blueprint_node}` commands may reuse it elsewhere.

Automatic dependency inference is opt-in. Enable it locally with
`(autoDeps := true)`, or set the file/section default with:

```lean
set_option verso.blueprint.autoDeps true
```

The local argument wins over the option, so `(autoDeps := false)` disables
inference for one node even when the file default is enabled.

This is LeanArchitect-style automatic dependency inference: dependency edges are
derived from Lean's compiled declarations instead of duplicated by hand.
Verso Blueprint's variant is document-first and direct. LeanArchitect expands
through untagged Lean helpers until it reaches blueprint-tagged declarations;
Verso Blueprint scans only direct constants and then maps those constants to
their associated Blueprint labels. This keeps immediate Blueprint edges
predictable while still removing the routine `uses` duplication around formal
declarations.

For a compiled declaration tagged with `@[blueprint]`, write:

```lean
/-- Associativity of addition. -/
@[blueprint "addition_assoc_compiled" (autoDeps := true)]
theorem addition_assoc_compiled (a b c : Nat) : (a + b) + c = a + (b + c) := by
  simpa [Nat.add_assoc]
```

The same local option is accepted on labeled inline Lean blocks and on informal
statement blocks that use `(lean := "...")`:

````md
:::theorem "addition_assoc" (lean := "Nat.add_assoc") (autoDeps := true)
For all natural numbers, addition is associative.
:::

```lean "addition_assoc_local" (autoDeps := true)
theorem addition_assoc_local (a b c : Nat) : (a + b) + c = a + (b + c) := by
  simpa [Nat.add_assoc]
```
````

When inference is enabled, Blueprint scans the direct Lean constants mentioned
by the declaration's type and compiled body. Declarations associated with
Blueprint labels and used directly by the type become statement dependencies;
declarations associated with Blueprint labels and used directly by the body
become proof dependencies. A Lean declaration is associated with a Blueprint
label by `@[blueprint]` or `@[blueprint "..."]`, by a labeled inline Lean code
block, or by an informal statement block with `(lean := "...")`.

Lean associations are many-to-many. One Blueprint label may be associated with
several Lean code items, and one Lean declaration may be associated with several
Blueprint labels. Automatic dependency inference emits all associated labels and
then deduplicates edges by label.

Untagged Lean constants are ignored and are not expanded to search for
transitive tagged dependencies. Use string labels for ordinary Blueprint-only
nodes. Inferred edges are stored with origin `"automatic"` so relationship
panels can distinguish them from author-written edges. If the same label is
both inferred and explicitly listed on the same axis, the edge is emitted once
with manual origin. If the same label is inferred on both axes, the statement
edge wins and the automatic proof edge is suppressed; an explicit `proofUses`
entry can still put the label on the proof axis when that is what the Blueprint
should say.

Manual attribute dependencies can be merged with or excluded from the inferred
set:

```lean
@[blueprint "addition_assoc_compiled"
  (autoDeps := true)
  (uses := ["addition_right_identity", -"addition_zero"])
  (proofUses := [nat_add_zero_right])]
theorem addition_assoc_compiled (a b c : Nat) : (a + b) + c = a + (b + c) := by
  simpa [Nat.add_assoc]
```

`uses` affects statement dependencies and `proofUses` affects proof
dependencies. Each list accepts Lean declaration names or Blueprint label
strings. Prefix an entry with `-` to remove that inferred or explicit edge from
the same axis after inference and manual entries have been resolved.

A tagged declaration can still receive a prose statement or proof block with the
same Blueprint label. If the attribute has only created dependency metadata for
that statement or proof, the later block fills in the rendered body and keeps
the inferred dependency edges.

#### Attribute-first use-case matrix

| Use case | Current behavior |
| --- | --- |
| Definitions, theorems, structures, and inductives | Supported. They become definition- or theorem-shaped Blueprint nodes. Constructors, recursors, axioms, and declarations introduced with `opaque` are not accepted as direct attribute targets. |
| Omit an explicit Blueprint label | Supported with bare `@[blueprint]`; the label defaults to the declaration's qualified Lean name. Attribute options such as `uses`, `proofUses`, and `autoDeps` remain available. |
| Direct and transitive imports | Supported. Attribute nodes, Lean associations, docstring bodies, and dependency metadata persist through imported `.olean` files. Duplicate imported Blueprint labels are diagnosed. |
| Include a regular Lean module as a Blueprint chapter | Supported in Manual documents with `{includeBlueprintModule 0 Some.Module}` after importing the module. Distinct directly owned labels are emitted in first attribute-application order; transitive modules must be named and included explicitly. |
| Place a tagged declaration on a specific Manual page | Supported with `{blueprint_node "label"}` after importing its module. The placement participates in numbering, links, relations, previews, the manifest, and the rendered-fragment cache. |
| Add chapter prose around the declaration | Supported with ordinary prose before and after the placement command. For an attribute node without a docstring, a matching statement directive can instead supply prose inside the node shell. |
| Reuse the same node in several places | Supported. The node keeps one semantic identity; later `{blueprint_node}` occurrences are presentation views and may use compact/header/display-label options. |
| Use the declaration docstring as the statement | Supported for plain Markdown and standard structural `doc.verso` content that can be converted to Manual blocks. Structural `doc.verso` markup and math are also preserved in the attached external-declaration panel. Custom docstring extension semantics are flattened to child content rather than re-elaborated. An absent docstring produces a code-only placement. |
| Infer formal dependencies | Supported with `(autoDeps := true)` or `set_option verso.blueprint.autoDeps true`. Type references become statement dependencies and body references become proof dependencies. Inference is direct, not transitive through untagged helpers. |
| Curate dependencies manually | Supported with attribute options `uses` and `proofUses`, using either Blueprint label strings or tagged Lean declaration names. Prefixing an entry with `-` excludes it on that axis. Blueprint's `{uses ...}[]` Manual role is not registered for Lean `doc.verso` docstrings and is rejected there rather than interpreted as dependency metadata. |
| Attach several labels to one Lean declaration, or several Lean declarations to one label | Supported. Associations are many-to-many and are deduplicated by canonical Lean name or Blueprint label as appropriate. |
| Add a separate informal proof | Supported with `:::proof "label"` once the node has a statement payload. For an undocumented, dependency-free attribute node, first add a matching statement directive. A proof body persisted in an imported provider module is not yet materialized by `{includeBlueprintModule}` or an initial `{blueprint_node}` placement. |
| Show the formal declaration | Supported as a highlighted external-declaration panel with its signature, kind-specific structure information, docstring, proof/completeness status, and source link when available. |
| Show the original definition body or `:= by ...` proof text | Not currently supported by the compiled-declaration renderer. The panel renders the declaration interface, not the original source body. Use the source link, or a labeled inline Lean block when the exact authored proof text must be embedded in the page. |
| Put `parent`, `owner`, `tags`, `effort`, `priority`, or `pr_url` directly on `@[blueprint]` | Not currently supported. These remain Blueprint statement-block metadata. A separate attribute-side metadata surface needs an ownership and validation design before it is added. |
| Use an unplaced attribute node in global views | The persistent node can contribute semantic graph/summary facts, but it has no page destination or rendered preview until it is placed in a Manual document. |

### Existing Lean declarations

Use `(lean := "Nat.add_assoc")` when Lean already owns the declaration and you
want an informal Blueprint node to point at it:

```md
:::theorem "addition_assoc" (lean := "Nat.add_assoc")
For all natural numbers $`a`, $`b`, and $`c`, addition is associative.
:::
```

This links the Blueprint entry to an existing Lean declaration without copying
the declaration body into the chapter.

If the same Blueprint label also has a labeled inline Lean block, Blueprint
keeps both Lean associations. External declaration references render with the
informal statement block, while inline Lean blocks render at their source
location.

Notes:

- `(lean := "Nat.add_assoc")` points at Lean-owned declaration names
- `(lean := "Nat.add, Nat.succ")` supports comma-separated declaration lists
- `@[blueprint "addition_assoc_compiled"]` registers a
  compiled-declaration-backed Blueprint node
- bare `@[blueprint]` uses the qualified declaration name as its Blueprint
  label
- `(autoDeps := true)` is accepted by `@[blueprint]`, labeled inline Lean blocks,
  and statement blocks with `(lean := "...")`
- Blueprint labels are Blueprint-owned metadata
- Blueprint label conventions do not rewrite external Lean names

## Attached Rust Code

Blueprint also supports labeled inline Rust code blocks as attached source:

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

- the `rust` block label is parsed the same way as a labeled `lean` block
- the block attaches to the Blueprint node with the same label
- the rendered page shows an associated Rust code panel for that node
- Rust rendering currently uses a small built-in syntax highlighter
- Rust attachments do not currently participate in Blueprint progress or proof
  status computation
- Rust diagnostics, hover information, and external Rust refs are not currently
  part of the supported surface

## Math, TeX, and external markup

Blueprint supports ordinary Verso math syntax inside the informal text.

Examples:

```md
Inline math: $`n + 0 = n`

Display math:
$$`\sum_{i=0}^{n} i = \frac{n(n+1)}{2}`
```

Projects can also define reusable TeX macros:

```lean
tex_prelude r#"\newcommand{\NatAdd}{\mathbin{+}}"#
```

After that, Blueprint math can use the macro in rendered pages:

```md
We write $`a \NatAdd b` for addition on natural numbers.
```

Blueprint nodes can also store raw external markup through `tex` and `md`
code blocks:

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
Imported Markdown proof sketch.
```
````

External markup attachments are intended for faithful import and comparison
workflows. They are stored on the associated Blueprint node, exported in the
Blueprint manifest, and do not replace an authored Verso body. Rendered node
headers show a small `MD` and/or `TeX` badge when external markup is attached;
the badge is only an attachment signal and does not display the raw source.

To keep an external markup witness without attaching it to a Blueprint node,
omit the label:

````md
```tex
\begin{theorem}
Unlabeled TeX witness kept in the source file while porting.
\end{theorem}
```
````

To start a port before writing the Verso statement, use a labeled standalone
witness block:

````md
```tex "raw_addition_right_identity"
\begin{theorem}\label{thm:addition-right-identity}
For every natural number $n$, adding zero on the right leaves it unchanged.
\end{theorem}
```
````

A bodyless Markdown-backed node can still keep Lean links by pairing a bodyless
Blueprint directive with a labeled Markdown witness. The directive contributes
the semantic Blueprint node and `(lean := ...)` declarations; the Markdown block
contributes the source-backed preview body:

````md
:::theorem "raw_addition_right_identity" (lean := "Nat.add_zero")
:::

```md "raw_addition_right_identity" (slot := statement)
# Addition right identity

For every natural number `n`, adding zero on the right leaves it unchanged.
```
````

The generated manifest entry is `targetKind: "externalMarkup"` with key
`externalMarkup:raw_addition_right_identity`. Its external-markup data records
the Markdown source, and its Lean preview keys and `codeData` still refer to
`Nat.add_zero`. Because the directive has no authored Verso body, rendered pages
and the HTML cache use a source-backed Markdown fragment for the visible body;
HTML-cache generation can disable that fragment with
`--external-markup-render none`.

If a label needs more than one external span, give each block a separate slot.
Common slots are `statement` and `proof`; importer-specific slots are also
allowed when they are stable and documented by the project.

````md
```tex "raw_addition_right_identity" (slot := statement)
\begin{theorem}\label{thm:addition-right-identity}
For every natural number $n$, adding zero on the right leaves it unchanged.
\end{theorem}
```

```tex "raw_addition_right_identity" (slot := "proof")
\begin{proof}
Raw proof witness kept near the imported source.
\end{proof}
```
````

External markup can also carry a project-relative file location. Locations use
LSP-compatible ranges: zero-based `line` and `character`, inclusive `start`,
exclusive `end`, and a non-empty range. The manifest stores the range using
Lean's standard `Lean.Lsp.Range` JSON shape.

````md
```md "raw_addition_right_identity" (slot := statement) (path := "imported/addition.md") (start_line := 12) (start_character := 0) (end_line := 17) (end_character := 0)
Imported Markdown statement.
```
````

Current behavior:

- unlabeled `tex` and `md` blocks are accepted as hidden source witnesses and do not
  create Blueprint nodes
- labeled external-markup block labels are parsed like labeled `lean` blocks
- a labeled block stores raw source on the associated Blueprint node
  under slot `"default"` unless `(slot := ...)` is provided
- a labeled standalone external-markup block is exported to the semantic
  manifest as `targetKind: "externalMarkup"` with key `externalMarkup:<label>`;
  by default the generated HTML cache also gets a source-backed rendered
  fragment for that key
- a bodyless statement directive with external markup uses the same
  source-backed rendering path for the ordinary generated page body
- manifest entries include `authoredLabel` alongside the canonical `label` so
  clients can display and round-trip punctuation-heavy authored labels without
  parsing Lean pretty-name quoting
- source-backed rendered fragments choose Markdown `statement`, Markdown
  `default`, TeX `statement`, then TeX `default` when multiple source slots are
  available; Markdown is rendered by MD4Lean with raw HTML disabled and falls
  back to escaped source if MD4Lean cannot render the fragment, while TeX
  sources are escaped
- if a bodyless directive for the same label carried `(lean := ...)`, the
  external-markup manifest entry keeps the corresponding Lean preview keys and
  `codeData`
- generation emits a non-fatal warning if traversal recorded Lean preview
  metadata for a bodyless/source-backed node but the exported manifest entry no
  longer carries it
- pass `--external-markup-render source` during manifest/cache generation to
  render the selected source as escaped source text, or
  `--external-markup-render none` to keep source-backed entries manifest-only with
  no HTML cache body
- if the same label also has a rendered statement or proof, the external markup
  is attached to that block's manifest entry instead of creating a separate
  external-markup entry
- uniqueness is by label, language, and slot, so `tex`/`statement` and
  `md`/`statement` can coexist
- repeating the same label/language/slot key is an error
- locations are all-or-nothing: provide `path`, `start_line`,
  `start_character`, `end_line`, and `end_character`, or omit the location
- the block is not displayed in the rendered output unless `(display := summary)`
  or `(display := source)` is provided, or the file sets
  `set_option verso.blueprint.externalMarkup.display "summary"` or `"source"`
- display and source-backed cache rendering are intentionally a preview path:
  Markdown cache fragments use MD4Lean with escaped-source fallback, while
  richer converters can still replace this path when projects need TeX or
  native Blueprint structure

### Original Source Provenance

Blueprint can record a three-level source provenance chain for audit tooling:
original source document, Verso Blueprint node, and associated Lean material.
This phase stores the source-document catalog and node-local source spans.
Generated Blueprint node shells show a compact source chip when a node has
source provenance. The chip opens a lightweight source preview with the
document id and recorded span details. Fuller source review interfaces such as
PDF page viewers, crop overlays, and side-by-side text review remain interface
work for clients or later Blueprint UI.

Declare source documents with `:::source_document`. The directive body must
contain exactly one Verso metadata block:

````md
:::source_document "paper"
%%%
title := "Representation Theory"
kind := .pdf
pdf := "source/paper.pdf"
pageRoot := "source/pages"
imageRoot := "source/pages/images"
%%%
:::
````

Attach source provenance to a Blueprint node with a leading metadata block
inside the node directive. The metadata block must be the first block in the
directive body; a later metadata block is rejected so that provenance is easy to
find and strip before rendering the visible statement.

````md
:::lemma_ "addition_right_identity"
%%%
source := {
  document := "paper"
  spans := #[
    {
      page := "12"
      text := some {
        path := "source/pages/page-12.md"
        startLine := 41
        endLine := 45
      }
      pdf := some {
        path := "source/pages/page-12.pdf"
        image := "source/pages/images/page-12.png"
      }
    }
  ]
}
%%%

For every natural number $`n`, $`n + 0 = n`.
:::
````

The generated manifest exports declared documents in `sourceDocuments` and each
manifest entry's original-source refs in `entry.sources`. Normal generated node
shells also show a compact source chip when source provenance is present; open
it to inspect the source document id, page summary, and recorded text/PDF span
details.

Manifest clients should read `entry.sources`; there is no singular
`entry.source` field. Lean code preview entries may contain multiple refs when
several sourced Blueprint nodes share the same rendered Lean preview. External
declaration previews are keyed by canonical declaration, while inline code
previews are keyed by the inline Blueprint code label and use
`targetKind: "inlineLeanCode"`. Declaration-specific inline identity is the
owning inline code label plus the declaration's position in the owning block
entry's ordered inline code metadata (`definedDefs` followed by
`definedTheorems`).
Browser clients can resolve those document ids with `loadSourceDocument` or
read the complete catalog with `loadSourceDocuments`.

Browser clients can call `resolveSourceMetadata` from `api/data.mjs` or
`api/preview.mjs` to resolve source refs for a preview key, manifest entry, or
render result. The API returns structured source-document metadata and recorded
text/PDF spans.
Manifest entries also include `sourceLocation`, a lookup result for the authored
Blueprint label/facet location or Lean declaration source. Browser clients that
start from semantic names can call `resolveLabel`, or `resolveDeclaration` for
declaration-keyed previews, from `api/data.mjs` or `api/preview.mjs` to get the
generated link and source location together. Inline code previews are keyed by
the inline Blueprint code label and should be loaded through the explicit key in
`leanCodePreviewKeys`.
Use the data API for metadata-only audit or dashboard clients; use the preview
API when the same client also renders Blueprint nodes or cached previews.
The built-in source preview is intentionally lightweight; richer PDF page
viewers and crop overlays remain Blueprint/Verso interface work.

Blueprint also supports best-effort KaTeX linting during elaboration. KaTeX is
the renderer used by the generated HTML, so this helps catch math problems
before the final site render.

## Groups, Authors, and Metadata

Use `:::group` to define reusable group metadata:

```md
:::group "group_1"
Core statements for the first chapter.
:::
```

Use `:::author` to define author metadata:

```md
:::author "author_1" (name := "Jason Example")
:::
```

Statement-like directives can carry:

- `(parent := "group_1")`
- `(owner := "author_1")`
- `(tags := "starter, arithmetic")`
- `(effort := "small" | "medium" | "large")`
- `(priority := "high" | "medium" | "low")`
- `(pr_url := "https://github.com/org/repo/pull/123")`

These fields are primarily used by rendered overview pages and project triage
views.

## Rendering Surface

### Rendered statement blocks

Rendered statement headers show related metadata chips in this order: group,
uses, used by, external-markup badge, then Lean status. The statement `uses`
chip shows statement-side dependencies; proof headers show their own `uses`
chip for proof-side dependencies on the same label. This keeps prerequisites
for the statement and prerequisites used only by the proof visually distinct.
When local or external Lean material is available, the rendered page links or
previews the associated content. Rows in the uses and used-by panels show
statement/proof badges plus any non-default dependency origin or intent badges.

Relation previews show the human title and a right-aligned concrete Blueprint
label in the preview header; the label links to the target statement. Single
uses or used-by entries use the same inline preview chrome, with relation
metadata badges shown in the preview footer.

Inline preview triggers require manifest-backed rendered fragments. A missing
or stale preview key renders the shared preview diagnostic instead of inventing
label-only fallback HTML.

When labeled inline Rust code is attached to a node, the rendered page also
shows an associated Rust code panel below the statement body.

### Dependency graph

`blueprint_graph` renders a dependency-oriented view of the current Blueprint
document.

Use it as either:

```lean
{blueprint_graph}
```

or with explicit graph layout options:

```lean
{blueprint_graph (direction := LR)}
{blueprint_graph (direction := LR) (pack := true)}
{blueprint_graph (preview := hover)}
{blueprint_graph (preview := hover) (previewPlacement := anchored)}
```

Supported directions are `LR`, `RL`, `TB`, and `BT`. When `(direction := ...)`
is omitted, the command falls back to the
`verso.blueprint.graph.defaultDirection` option.
The `(pack := true | false)` option controls Graphviz component packing for
disconnected graph components. It defaults to
`verso.blueprint.graph.defaultPack`, which is `false`.
The `(preview := pinned | hover)` option chooses the initial graph-node preview
behavior. The default is `pinned`: clicking a node opens a persistent preview
panel that stays open until closed. `hover` opens a transient preview that
disappears after the pointer leaves the node and preview panel.
The `(previewPlacement := docked | anchored)` option chooses where the preview
panel appears. The default is `docked`, so both pinned and hover previews
open in the graph corner unless `anchored` is selected to place the panel near
the active node.

The rendered graph page is interactive:

- a `View` selector switches between the full graph and any derived grouped
  views
- a `Legend` button opens the current graph legend in a popover
- a `Graph options` button exposes runtime graph options such as direction and
  component packing, plus the graph-node preview behavior and placement
- when grouped metadata produces multiple children for the same parent, the
  selector includes a synthetic group overview plus one subgraph view per group

The command-side options and the runtime graph controls are compatible:

- `(direction := ...)` chooses the initial graph direction when the page first
  loads
- the rendered `Graph options` control lets readers switch among the supported
  directions, toggle component packing, and choose between pinned and
  hover previews and docked or anchored placement without regenerating the site

Group metadata may be used to organize the presentation, but grouping does not
change dependency edges.

Graph data is also available through documented Lean, manifest, and browser APIs.
Lean callers build a semantic `GraphModel` before traversal and cross one
finalization boundary to obtain an immutable `GraphData` record after traversal,
while browser clients can read generated manifest graph records or data embedded
in a rendered graph block. See
[`API.md#graph-data-apis`](./API.md#graph-data-apis) for the full graph API
contract and examples.

The graph uses two orthogonal status tracks:

- statement border:
  `Blocked`, `Ready to formalize`, `Formalized`, `In Mathlib`
- proof fill:
  `Not ready`, `Ready to formalize`, `Lean code incomplete`,
  `Locally formalized`, `Locally formalized + dependencies complete`

This split is intentional. For theorem-like nodes, the statement can already be
formalized while the proof still remains unstarted, in progress, or complete.

Read the proof fill states as:

- `Not ready`: the proof still depends on unfinished prerequisites
- `Ready to formalize`: prerequisites are done, but there is no associated Lean
  proof code yet
- `Lean code incomplete`: associated Lean code exists, but still has gaps such
  as `sorry`
- `Locally formalized`: the node's own Lean code is complete, but some
  dependency upstream is still not complete
- `Locally formalized + dependencies complete`: both the node and its full
  dependency closure are complete

Warning markers are reserved for structural or resolution issues such as:

- unresolved Blueprint references
- missing external Lean declarations
- Lean-owned entries that have code but no informal statement body

### Progress summary

`blueprint_summary` renders a summary page for the current Blueprint document.

The default view is an overview: it highlights overall progress, current
blockers, and the next ready work items first, while keeping deeper audit and
structural sections collapsed until needed.

That page uses dependency data, metadata, and Lean status to present:

- automatic progress counts
- blockers and incomplete declarations
- next ready work and project triage information
- grouped rollups by parent, owner, and tags

For routine project work, read the summary from top to bottom:

1. Start with **Current blockers**. Missing external declarations and incomplete
   Lean declarations usually explain why apparently small tasks are not ready.
2. Use **Actionable priorities** for work that can start now and already
   unlocks downstream entries.
3. Check **Quick wins** when you want small high-priority tasks.
4. Use **Dependency insights** and **Structure and coverage** when planning a
   larger batch of work or reviewing the shape of a Blueprint.
5. Use **Metadata audit** to keep ownership, effort, tags, and linked PRs useful
   for collaborators.

Some summary sections use deliberately practical project-management terms:

- **Actionable** entries are not locally formalized yet, and their statement or
  proof status says there is work that can start now.
- **Actionable priorities** are the actionable entries that also unlock
  downstream work. The broader **Ready now** count, quick wins, and owner/tag
  rollups still include actionable leaf entries with no dependents.
- **Quick wins** are actionable entries marked with high priority and small
  effort metadata.
- **Direct uses** count immediate statement or proof dependency edges into an
  entry. **Downstream unlocks** count entries that depend on it transitively,
  with cycles ignored.
- **Group health** rolls progress, blockers, Lean gaps, and unlock counts up by
  parent or group, and points at the next ready child when one exists.
- **Proof debt** groups incomplete or missing Lean declaration snapshots by
  parent or group.
- **Metadata audit** lists entries that have PR links and entries missing owner,
  effort, or tag metadata.

Maintainer-oriented diagnostics such as external declaration render failures are
available through an explicit summary debug option so they do not appear in the
default end-user view.

### Bibliography page

`blueprint_bibliography` renders the bibliography entries
registered in the document.

Projects that do not use citations can omit this page entirely.

### Math-enabled previews

Blueprint pages support shared previews in generated HTML, including math
rendering through KaTeX.

## Metadata Export and Preview Data

Blueprint builds emit two preview-data files:

- `html-multi/-verso-data/blueprint-manifest.json`
- `html-multi/-verso-data/blueprint-html-cache.json`

Most authors do not need these files for routine writing. They are mainly
useful for:

- runtime preview support in generated sites
- tooling and integration work
- metadata export for other tools
- inspection and debugging

For informal blocks, these files are the same semantic manifest and opaque
rendered-fragment cache used by generated previews, grafts, Slides, and custom
clients. See [`API.md#generated-data-files`](./API.md#generated-data-files)
for the stable consumer contract. The manifest may also include VBP-internal
generated-data markers for stale-artifact diagnostics; those markers are not
public compatibility promises.

After building the relevant Lean targets, useful inspection flags on a
Blueprint generator are:

```bash
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --dump-schema
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --dump-manifest
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --dump-html-cache
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --help
```

- `--dump-schema` prints the JSON Schema for the manifest
- `--dump-manifest` prints the generated manifest JSON instead of writing the
  site and then reading the file
- `--dump-html-cache` prints the rendered-fragment cache JSON
- `--help` includes these manifest-related flags alongside the usual rendering
  options

## Reusing Blueprint Nodes and Previews

Blueprint has one reusable preview data model. Manual pages can graft from the
current traversal state, Slides and generated audit pages can graft from the
manifest/cache files emitted by a Blueprint site, and browser-side UI can
resolve and insert previews after the page loads. See
[`API.md#generated-data-files`](./API.md#generated-data-files) for the data
contract shared by those workflows.

### Grafting a Node

Use `{blueprint_node "label"}` when an overview, introduction, roadmap, or slide
needs to feature an existing Blueprint entry without rewriting it.

In Manual documents, an ordinary informal node resolves from the current
traversal state:

```lean
import VersoBlueprint

open Verso
open Verso.Genre.Manual
open Informal

#docs (Genre.Manual) doc "Overview" :=
:::::::
:::theorem "thm:key"
The statement to feature.
:::

{blueprint_node "thm:key" -header +compact}
:::::::
```

An imported node owned by `@[blueprint "label"]` is the other Manual case. If
the label is not yet in the traversal, the command first materializes the
persistent attribute node at that source position, then renders the same graft
shell. See [Placing an attribute-owned node in a
chapter](#placing-an-attribute-owned-node-in-a-chapter) for the attribute-first
workflow and its current code/proof limitations.

In Slides decks, the same source command is available after importing
`VersoBlueprint.Slides`, but the rendered node comes from the manifest/cache
files passed to the deck generator:

```lean
import VersoBlueprint.Slides

open VersoSlides

#docs (Slides) deck "Talk" :=
:::::::
# Key statement

{blueprint_node "addition_assoc" (siteBase := "blueprint")}
:::::::
```

The first positional argument is the Blueprint label to graft. Available options
are:

- `(facet := "statement")` or `(facet := "proof")`; statement is the default
- `(displayLabel := "...")`, which overrides the displayed label/number in the
  grafted shell without changing the semantic manifest entry
- `+compact`, which omits attached Lean-code panels
- `+header` or `-header`; headers are shown by default
- `(siteBase := "...")`, for Slides decks whose manifest links should open
  against a Blueprint site hosted next to, or below, the deck

Presentation options such as `-header` and `+compact` do not create new nodes,
dependencies, groups, or manifest entries.

### Side-by-side Grafts

Use `blueprint_side_by_side` to place grafts next to each other. Add `+boxed`
when each side should be visually framed:

```lean
:::blueprint_side_by_side +boxed
{blueprint_node "thm:key" -header +compact}

{blueprint_node "thm:key" (facet := "proof") -header +compact}
:::
```

The side-by-side directive is presentation-only. Each child remains an ordinary
`{blueprint_node ...}` command with its own label and options; the directive does
not create dependencies, groups, or new manifest entries.

### Slides Generator Setup

A Slides deck that contains `{blueprint_node}` must use the Blueprint slide
wrapper. The wrapper adds the Blueprint slide CSS/JS assets, reads the manifest
and rendered-fragment cache, renders node grafts into static slide HTML, and
copies preview data into the deck output when requested.

```lean
import VersoBlueprint.Slides
import MyTalk.Deck

def main : IO UInt32 :=
  Informal.Slides.slidesMainWithBlueprintPreviews
    { outputDir := "_out/slides" }
    (previewManifest? := some "_out/site/html-multi/-verso-data/blueprint-manifest.json")
    (%doc MyTalk.Deck.deck)
```

When `previewHtmlCache?` is omitted, the wrapper looks for
`blueprint-html-cache.json` next to the provided manifest. Pass
`previewHtmlCache?` explicitly if the cache lives elsewhere.

The slide generator also seeds the deck's Verso hover table from the cache, so
cached Lean fragments keep the usual `data-verso-hover` markup instead of
embedding duplicate hover payloads into each code token.

### Generator-side Consumers

Custom generators should follow the same manifest/cache path as Slides. This is
the right layer for audit reports, dashboards, comparison pages, and other
interfaces that create their own wrappers around Blueprint nodes.

See [`API.md#lean-graft-and-render-apis`](./API.md#lean-graft-and-render-apis)
for the reusable `Informal.Graft` data shapes, manifest/cache lookup helpers,
and lower-level block-shell rendering APIs.

### Browser-side Consumers

Browser-side custom interfaces should start through
the generated ESM modules under `-verso-data/`; use `createPreview()` from
`api/preview.mjs` when the client needs the render API object. Use
`renderPreviewInto` for body fragments,
`renderCanonicalPreviewInto` for the full generated Blueprint node wrapper, and
`loadGraphs` for standalone graph-data clients.

Use [`API.md#choosing-an-api`](./API.md#choosing-an-api) when deciding between
the generated ESM modules and Lean-side graft helpers.
See [`API.md#browser-esm-apis`](./API.md#browser-esm-apis) for ordinary
`import { ... } from ...` usage, module path rules, and copyable inline
examples. See [`API.md#browser-runtime-api`](./API.md#browser-runtime-api) for
the stable render API table.

### Troubleshooting Grafts

- `Blueprint node not found` means the label/facet pair did not match a
  rendered Blueprint preview. Check the label spelling and use
  `(facet := "proof")` when grafting a proof block instead of the statement.
  The diagnostic includes the requested label, facet, and normalized manifest
  key.
- `Preview manifest unavailable` in Slides means the deck generator did not pass
  `previewManifest?` to `slidesMainWithBlueprintPreviews`.
- `Blueprint HTML cache entry not found` means the manifest entry was found, but
  the matching rendered-fragment body was not in `blueprint-html-cache.json`.
  Keep the manifest and cache from the same Blueprint render. For source-backed
  external-markup entries generated with `--external-markup-render none`, a
  semantic manifest entry without a cache body is expected; custom renderers
  should treat those entries as metadata-only.
- `siteBase` only affects Slides link rewriting. Manual grafts resolve from the
  current document traversal state and do not need it.
- `-header`, `+compact`, and `+boxed` are presentation options only. They do not
  create new nodes, dependencies, groups, or manifest entries.

## Blueprint APIs

The detailed public API reference lives in [`API.md`](./API.md). It covers:

- the generated `blueprint-manifest.json` and `blueprint-html-cache.json` files
- [which API to use for each integration shape](./API.md#choosing-an-api)
- [finalized graph data](./API.md#graph-data-apis) from Lean, the manifest,
  and browser clients
- [`Informal.Graft` and manifest/cache rendering helpers](./API.md#lean-graft-and-render-apis)
  for custom generators
- [generated ESM modules](./API.md#browser-esm-apis) such as `api/preview.mjs`
  and `api/graph.mjs`
- [the stable browser runtime API](./API.md#browser-runtime-api) and the
  boundary around bundled helper APIs

## The Generator Entry Point

Blueprint projects normally expose a small generator `main` function.

In the commands below, `<GeneratorMain>.lean` stands for the Lean file that
defines the generator `main`, such as `ProjectTemplateMain.lean`.

Minimal example:

```lean
import VersoManual
import VersoBlueprint.PreviewManifest
import ProjectTemplate.Blueprint

open Verso Doc
open Verso.Genre Manual

def main (args : List String) : IO UInt32 :=
  Informal.PreviewManifest.blueprintMainWithPreviewData
    (%doc ProjectTemplate.Blueprint)
    args
    (extensionImpls := by exact extension_impls%)
```

This Blueprint-provided main wrapper owns the Blueprint-specific generation
layer around Verso's renderer. It injects the frontend assets required by
Blueprint-specific rendered surfaces, applies Blueprint's preview-data and
public-xref emission policy, and keeps downstream projects from needing to
remember those dependencies manually.

Blueprint does not keep broad compatibility layers for internal helper names,
read-through aliases, command aliases, or old rendering paths. Documented public
entry points that real Blueprint projects already use are different: if such an
entry point is renamed, keep the old exported name only as a deprecated thin
forwarder to the canonical function until those projects migrate. Do not add
forwarders for undocumented internals or convenience aliases. New generators
should call `Informal.PreviewManifest.blueprintMainWithPreviewData` directly.

For normal local and CI usage, prefer the project helper:

```bash
lake exe vbp build
lake exe vbp build --serve
```

It builds the Blueprint library's OLean dependency closure, prepares and runs
the generator, and optionally serves the result. When a maintainer harness or
advanced CI job must drive those stages explicitly, the equivalent lower-level
shape is:

```bash
lake build +<BlueprintLibrary>:olean
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --output _out/site
```

Keep the explicit `:olean` facet. The default `leanArts` facet also emits C and
can accidentally turn a Blueprint generation run into a native dependency
build.

The project helper can emit TeX and compile a PDF in the same run:

```bash
lake exe vbp build --pdf
```

The PDF is written to `_out/site/pdf/main.pdf`. The default engine is
`lualatex`, run with `-shell-escape` because Verso TeX output may include
assets that require it. Use `--pdf-engine <cmd>` for another
lualatex-compatible command and `--pdf-runs <n>` to change the number of LaTeX
passes. `--pdf` implies `--with-tex`; `--with-tex` alone still only writes the
TeX tree under `_out/site/tex/`.

### HTML and PDF Feature Support

PDF generation is a static TeX/PDF output path. It is useful for reading,
archiving, and print-oriented review, but it is not a replacement for the
interactive HTML site. Unless a generator disables the HTML modes explicitly,
`--pdf` still writes the usual HTML and preview-data artifacts in addition to
the TeX tree and `main.pdf`.

The table below describes the current built-in rendering behavior. The PDF
column refers to what appears in `_out/site/pdf/main.pdf`, not to data files
that may still be emitted alongside the HTML site. PDF status values mean:
`Supported` renders directly in PDF, `Static only` renders without HTML
interaction, `Partial` renders only selected static pieces, `Notice only`
renders a pointer to the HTML output, and `Not in PDF` is absent from
`main.pdf`.

| Feature | HTML site | PDF status | PDF output |
| --- | --- | --- | --- |
| Ordinary Manual prose, headings, lists, and structure | Full generated HTML pages | Supported | Static TeX/PDF via Verso's TeX renderer |
| Blueprint statement and proof blocks | Numbered headers, metadata chips, folding, relation panels, Lean status, previews, and authored body content | Static only | Static title and authored body content; no folding, chips, panels, or hover UI |
| Math and project TeX macros | KaTeX-rendered math, with best-effort KaTeX linting during elaboration | Supported | LaTeX math in the generated TeX/PDF; Blueprint inserts project TeX preludes into the generated TeX |
| Citations and bibliography | Linked citation and bibliography UI | Supported | Static citations and bibliography entries |
| `{uses ...}` and `{bpref ...}` inline references | Links, preview triggers, and dependency metadata | Static only | Static inline text, or the resolved target title when no inline text is provided |
| Attached Lean code | Code panels, Lean declaration summaries, hovers, and preview data | Static only | Static code content when present; no hovers, status widgets, or runtime previews |
| Attached Rust code | Styled and foldable Rust code panels | Static only | Static verbatim Rust code block |
| External Markdown or TeX markup attachments | Stored in the manifest; headers show attachment badges; bodyless Markdown-backed nodes can render source-backed HTML cache fragments | Partial | Explicit external-markup blocks render only when shown with `(display := summary)` or `(display := source)`; source-backed HTML cache bodies are not converted into PDF bodies |
| Source provenance and source-PDF spans | Source chips, manifest entries, and data/preview API access for source document ids and text/PDF spans | Not in PDF | Not shown as source chips or page overlays in the PDF |
| Dependency graph and progress summary pages | Interactive graph and summary views with runtime controls and previews | Notice only | Static notice pointing readers to the HTML output |
| Grafted Blueprint nodes, including `{includeBlueprintModule}` and attribute-owned `{blueprint_node}` placements | Rendered from current traversal preview data and emitted to the preview manifest and HTML cache | Partial | Inserted graft nodes render as a static notice; side-by-side authored content still renders statically |
| Browser preview runtime, relation panels, and interactive controls | Supported in generated HTML | Not in PDF | Not available in PDF |
| Preview manifest, HTML cache, and JavaScript APIs | Emitted for generated-data and browser consumers | Not in PDF | Not embedded in `main.pdf`; still emitted alongside HTML unless those outputs are disabled |
| Slides and other generator-side consumers | Supported through their own HTML/data render paths | Not in PDF | Not part of the `--pdf` output path |

## Blueprint Options

Set Blueprint options with ordinary Lean `set_option` commands in the module
that elaborates the Blueprint chapter or document:

```lean
set_option verso.blueprint.numbering global
set_option verso.blueprint.subNumberingPrefix full
set_option verso.blueprint.subNumberingCounter prefix
set_option verso.blueprint.foldProofBlocks true
set_option verso.blueprint.foldCodeBlocks false
```

Current options:

- `verso.blueprint.numbering`
  - default: `sub`
  - `sub`: prefixed numbering such as `Theorem 1.3.2`; the prefix and counter
    are controlled by the sub-numbering options below
  - `global`: document-order numbering such as `Theorem 27`
  - `local`: unprefixed local numbering without a chapter prefix
- `verso.blueprint.subNumberingPrefix`
  - default: `full`
  - `full`: use the full numbered section path, such as `1.3`
  - `first`: use only the first numbered ancestor, such as `1`
- `verso.blueprint.subNumberingCounter`
  - default: `prefix`
  - `prefix`: reset the block counter for each rendered prefix, such as
    `Theorem 1.3.2`
  - `document`: use the document-order block count after the prefix, such as
    `Theorem 1.93`

Set `verso.blueprint.subNumberingPrefix first` together with
`verso.blueprint.subNumberingCounter document` to recover chapter-only
prefixes with document-order block counts.

- `verso.blueprint.foldProofs`
  - default: `true`
  - folds proof bodies in rendered Lean code panels after `by`
- `verso.blueprint.foldProofBlocks`
  - default: `false`
  - renders proof blocks as collapsed disclosure blocks
- `verso.blueprint.foldCodeBlocks`
  - default: `false`
  - renders Lean, Rust, and external code panels as collapsed disclosure blocks,
    including panels produced by attribute-owned `{blueprint_node}` placements
    and `{includeBlueprintModule}`
- `verso.blueprint.trimTeXLabelPrefix`
  - default: `false`
  - trims TeX-style label prefixes when deriving Lean names
- `verso.blueprint.math.lint`
  - default: `true`
  - runs best-effort KaTeX validation during elaboration
- `verso.blueprint.externalCode.strictResolve`
  - default: `false`
  - upgrades unresolved or ambiguous external Lean names from warnings to errors
- `verso.blueprint.externalCode.sourceLinkTemplate`
  - default: `""` (automatic GitHub links when the source file belongs to a
    Git checkout with a GitHub `origin` remote)
  - builds source links for external declarations using `{path}`, `{relpath}`,
    `{module}`, `{line}`, `{column}`, `{endLine}`, and `{endColumn}`
- `verso.blueprint.summary.debugDiagnostics`
  - default: `false`
  - keeps maintainer diagnostics hidden from `blueprint_summary` by default
  - set to `true` when debugging Blueprint rendering or external Lean
    declaration integration; the summary then includes diagnostics such as
    external declarations that resolved and checked but could not be rendered as
    HTML
- `verso.blueprint.graph.defaultDirection`
  - default: `TB`
  - sets the fallback graph direction for `blueprint_graph` when
    `(direction := ...)` is omitted
- `verso.blueprint.graph.defaultPack`
  - default: `false`
  - sets the fallback Graphviz component packing behavior for
    `blueprint_graph` when `(pack := ...)` is omitted
- `verso.blueprint.graph.defaultPreviewMode`
  - default: `pinned`
  - sets the fallback graph-node preview behavior for `blueprint_graph` when
    `(preview := ...)` is omitted; accepts `pinned` and `hover`
- `verso.blueprint.graph.defaultPreviewPlacement`
  - default: `docked`
  - sets the fallback graph-node preview placement for `blueprint_graph` when
    `(previewPlacement := ...)` is omitted; accepts `docked` and `anchored`
- `verso.blueprint.debug.commands`
  - default: `false`
  - emits debug info logs while elaborating Blueprint graph, summary, and
    bibliography commands
- `verso.blueprint.profile`
  - default: `false`
  - enables timing logs for Blueprint directive and code-block elaboration

## Experimental Widget

The widget surface is experimental.

To enable it, import `VersoBlueprint.Widget` explicitly in the project that
wants to use it.

## Current Limits

- parent/group metadata is structural only; it does not change proof status or
  dependency edges
- group labels are metadata, not first-class reference targets
- unresolved Blueprint references currently degrade locally at the call site;
  they are not accumulated into a global diagnostics report
- Rust support currently covers only labeled inline Rust blocks with basic
  built-in syntax coloring
- Rust attachments currently do not provide diagnostics, hover data, or
  external Rust symbol references
- some rendering details and summary ranking policies are still expected to
  evolve
