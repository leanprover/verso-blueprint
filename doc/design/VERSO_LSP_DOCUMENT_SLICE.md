# Independent LSP library and offline Verso document slice

Date: 2026-10-23. This extends the [protocol experiment](VERSO_LSP_SPIKE.md)
with real authored documents and saved-result rendering. The libraries and
author syntax remain experimental.

## Library boundary

The analysis library is now exposed through `import VersoLsp`. It contains
source projection, protocol normalization, an owned client, request/snapshot
data, and context analysis. It imports only Lean and Std.

`import VersoLspVerso` is a separate `lean_lib` for Manual authoring, request
collection/enrichment, HTML, and TeX rendering. It imports Verso but never VBP.
Blueprint itself does not import either library by default. Its fixture opts
into the bridge and passes the existing captured rendering model through.

| Layer | Dependencies | Role |
| --- | --- | --- |
| `VersoLsp` | Lean/Std | Analyze explicit document contexts and produce portable facts |
| `VersoLspVerso` | Core data and Verso | Compile inert requests and render accepted facts |
| Blueprint consumer | Verso bridge and VBP | Enrich a document before the normal Blueprint generator |

The test runner builds the core from the same sources in a fresh temporary Lake
package with no package dependencies. Its manifest has an empty `packages`
array and the build passes. This tests the dependency boundary beyond merely
declaring a second library in the VBP lakefile.

Keep both libraries in this repository during interface development. Moving
the core into its own package is now structurally possible; deciding its name,
repository, release/toolchain policy, and supported client lifecycle should
precede publishing it. There is no compatibility wrapper for #63's old model.

## Staging that works

The fixture compiles code blocks and named references into JSON-backed document
extensions containing authored intent. Compilation and plan collection start
no server. The analyzer then composes each registered context, opens an unsaved
overlay in a valid project file, gathers facts, and writes a bundle.

An explicit offline operation validates that bundle and attaches results to the
compiled document tree before ordinary traversal/rendering. Request text,
context, identity, and source-line maps must match. Duplicate snapshot/context
identities and malformed saved ranges are rejected. This is accepted-artifact
replay, not a cache that claims external project inputs are still current.

The plain document is also included inside a Blueprint definition through a
fixture directive. Both document trees produce exactly the same ordered plan.
Nested block and inline extension children are visited. Blueprint's semantic
model is passed unchanged to the existing generator; no field is assigned to
`Node`, no contribution admission is bypassed, and no proof evidence is invented.
The fixture introduces `lsp.background` and `lsp.shared`, with the single
statement dependency `lsp.shared -> lsp.background`; enrichment changes none of
these labels or edges.

This establishes an acyclic path:

```text
compiled document containing inert requests
  -> collect explicit requests
  -> analyze registered contexts once
  -> validate and attach saved snapshots
  -> ordinary Verso / Blueprint generation
```

The application still owns its generator entry point, as in the current Verso
workflow. The experimental executable is maintainer tooling, not a new required
end-user command or a landed `vbp build` option.

## Authoring and profile scope

The experimental `lspCode` block takes a stable request key and an explicit
context. The `lspRef` role takes a key, written name, and context. Contexts supply
language ID, command/environment, a real project-member file, reference syntax,
and readiness/diagnostic collection. Process configuration stays outside
authored node data and published HTML.

The fixture has five requests in three contexts: Rust code plus a reference,
Rocq code plus a reference, and an invalid Rocq code fragment. The same code
and reference share scope. Source origins are derived from exact authored line
slices; mapped diagnostic line numbers are checked against the Lean source.
Generated wrapper diagnostics remain context diagnostics.

These examples use an owned project overlay composed from the requests. They
do not yet establish a high-level existing-file/excerpt author interface,
general Rust type/macro/method probes, or branching context semantics. Those
must be designed explicitly instead of adding universal name lookup assumptions.

Rust readiness uses its registered
[server-status extension](https://rust-analyzer.github.io/book/contributing/lsp-extensions.html#server-status)
before a fresh pull
diagnostic report. Rocq uses document processing plus versioned push diagnostics.
Coverage is shown in an expandable context panel. Rust compiler checks remain
disabled in this fixture and are identified as such. Processing and diagnostics
remain separate from theorem/proof completeness.

## Rendering and the SubVerso decision

The renderer consumes exact source text and range overlays. It never encodes
foreign identifiers as Lean constants or variables. Rust gets supported semantic
styles and bounded eager hover/navigation queries. Rocq code remains plain when
semantic tokens are unsupported; its explicit reference still has a hover and
navigation. Diagnostics are visible with authored source lines. Local definition
targets link to the relevant code block when the result is unambiguous; local filesystem URIs are not published
as browser links. TeX preserves code, diagnostics, and coverage text.

Verso's hover deduplication table, generated hover JSON, and Tippy assets are
reused. Its existing JavaScript binds `.hl.lean` selectors, so a small separate
binder attaches Tippy to neutral `.hl.lsp` spans. Server hover content is escaped
as text; Markdown format is retained in the snapshot but is not interpreted as
HTML in this slice. The browser test includes markup-shaped documentation and
verifies that it creates no image element or script dialog.

No SubVerso or Verso fork was required for this slice. The concrete upstream
opportunity is a neutral hover-binding entry point in Verso, allowing the local
binder to be removed. A broader SubVerso token/goal abstraction should be driven
by further shared requirements, not by the transport layer.

## Evidence

The maintainer-local bundle is under
`_out/verso-lsp-design/lsp-docs/final/`. It preserves experiment sources,
toolchain/server identities, protocol results, the plan, saved analysis, build
logs, baseline/enriched sites, semantic comparison, browser results, and four
screenshots. Rerun `tests/lsp/run_spike.py --documents` to create independent
evidence elsewhere.

The recorded experiment source SHA-256 is
`c08c63c23548777faf4f2940da54301b35e63bef30384272342b90638db966e2`.

Validation passed:

- Targeted builds of both libraries and the experiment executables.
- A clean independent-core package build with no package dependencies.
- Existing mock, Rust, and Rocq protocol tests.
- Compiled plan equality, exact source-origin checks, saved snapshot validation,
  changed-text rejection, and duplicate-identity rejection.
- Offline plain Verso and Blueprint HTML/TeX generation.
- `vbp check` of the persisted Blueprint output.
- Unchanged Blueprint labels, work queue, and stats against the unenriched
  baseline, including the existing mathematical dependency.
- Browser checks for exact source, Rust/Rocq hovers, local navigation, escaped
  markup, authored diagnostics, and mobile overflow. Desktop/mobile screenshots
  were also inspected.
- The complete existing `lake test` suite. Existing module-system and deliberate
  `sorry` fixture warnings remain.

## Remaining work

The transport limitations in the first report remain: synchronous pipe writes,
SIGTERM-only bounded cleanup, incomplete lifecycle admission, and no guarantee
for concurrent close/request. This slice does not make that client production
ready.

Before a supported release, settle profiles and external-project inputs,
context/source identity, artifact input fingerprints, editor feedback, richer
hover presentation, occurrence-level anchor handling for repeated includes,
and scaling of source indexing/eager queries. Opaque document trees embedded
inside another extension's JSON need an explicit visitor hook; the generic
walker only visits the public document children.

VBP node attachments and foreign validation/proof-status policy remain separate
design work. This slice proves that the generic document path can be used inside
a node without changing its existing semantic facts. It does not revive #63's
language-specific attachment fields.
