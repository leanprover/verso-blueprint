# Rosetta integration

[Rosetta](https://github.com/ejgallego/rosetta) analyzes foreign-language code and
references through LSP. Its Lean/Std core owns sessions, versioned documents,
source projection and saved results. The separate `verso-rosetta` package owns
Manual authoring and rendering. Neither depends on Blueprint. VBP supplies
integration fixtures and preserves its own labels, dependencies and proof status.

## Current workflow

1. Compile `lspCode` blocks and `lspRef` roles into inert requests. Compilation
   starts no server and does not require an installed foreign toolchain.
2. `VersoRosetta.collect` gathers requests from a Manual part, including extension
   children. Configure one `ContextProfile` for each context.
3. `Rosetta.analyze` opens overlays in caller-selected project files, gathers
   explicit diagnostic evidence and produces a serializable `Bundle`.
4. Save/review that bundle, then call `VersoRosetta.enrich` and render normally.
   Replay and HTML/TeX generation require no running language server.

This is an explicit generator API. Standard `vbp build` profile/snapshot
configuration is follow-up work. Production Blueprint modules do not import
Rosetta automatically. See the executable example in
[`tests/RosettaDocsMain.lean`](../../tests/RosettaDocsMain.lean) and
[reproducible acceptance commands](../../tests/lsp/README.md).

## Contract and use cases

`lspCode` analyzes authored snippets. `lspRef` queries a written expression in
that context's composed scope using a profile-supplied language wrapper.
Workspace symbol discovery and existing-source excerpts are separate core APIs;
a server's display container name is not a compiler's qualified-name resolver.

Results describe evidence with explicit diagnostic coverage. They do not certify
foreign proofs or change Blueprint proof progress. Unsupported features, valid
empty results and optional-feature server errors remain distinct. Session-fatal
failures abort analysis with typed errors, including incomplete cleanup.

Bundle revision 2 stores each diagnostic only in request coordinates and derives
its authored location from the request's source map. Live and replayed semantic
spans share strict validation. Profiles may attach caller-owned provenance for
project revision, server version or configuration. Rosetta does not check that
external dependencies are fresh. Replay matches exact compiled requests,
including authored file URIs; moving checkouts can require reanalysis.

The Manual bridge encodes logical `(context, key)` pairs without delimiter
collisions. Verso assigns occurrence IDs and page paths. Repeated inclusions
share analysis and get distinct HTML IDs; definition links select the first
occurrence in traversal order, across pages. Other genres can reuse core facts
and the generic renderer with their own link resolver. Hover text is escaped;
external filesystem targets do not become outbound browser links.

## Repository boundary and validation

VBP pins both Git packages to one URL/revision definition in `lakefile.lean`,
selecting `subDir = "verso"` for the bridge. The explicit core Git dependency
avoids inherited workspace-relative lockfile paths when VBP is itself a path
dependency. Update both packages together and regenerate saved analysis after a
schema or request-identity change.

Rosetta owns protocol/lifecycle tests, real-server sources, bridge collection
checks and fresh Git-consumer isolation. VBP owns plain/Blueprint generators,
offline HTML/TeX, browser navigation and Blueprint semantic comparisons.
The acceptance runner also renders separate definition/reference pages and a
repeated inclusion to check navigation, unique IDs and nested-page hovers.

For API signatures and migration details, use the standalone
[API guide](https://github.com/ejgallego/rosetta/blob/main/doc/API.md),
[bridge README](https://github.com/ejgallego/rosetta/blob/main/verso/README.md),
and [migration notes](https://github.com/ejgallego/rosetta/blob/main/doc/MIGRATION.md).
These are the API source of truth.

## Design provenance

The initial library export preserved VBP commit `bc6c4f5a` and its four package
commits. Subsequent fixes belong to the standalone repository. Early names
`VersoLsp` and `Parley` refer to this design's earlier stages, not additional
libraries. The [historical records](archive/rosetta/README.md) retain the original
experiments, alternatives and ownership review. Their API signatures and local
validation paths are historical evidence, not current usage instructions.

The architectural split remains deliberate: SubVerso supplies Lean elaboration
and Lean-specific highlighting; Rosetta supplies facts from external LSP servers.
Verso supplies document traversal, HTML IDs, page navigation and hover assets.
No SubVerso fork or Blueprint-specific semantic layer is needed for this path.
