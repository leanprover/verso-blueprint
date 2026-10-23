# Verso LSP design spike

This is maintainer tooling for the design in
[`doc/design/VERSO_LSP_ADAPTER.md`](../../doc/design/VERSO_LSP_ADAPTER.md).
The optional `VersoLsp` library imports Lean and Std, with no Blueprint or Verso
dependency. It is experimental and is not imported by the Blueprint core.

Build and run the deterministic checks from this worktree:

```sh
scripts/lean-low-priority lake build verso-lsp-spike
python3 tests/lsp/run_spike.py --output /tmp/verso-lsp-mock
```

Add explicitly selected language servers to exercise real projects:

```sh
python3 tests/lsp/run_spike.py --output /tmp/verso-lsp-real \
  --rust-command rust-analyzer \
  --rocq-command /path/to/opam-switch/bin/coq-lsp
```

The runner copies fixtures into the output directory. The servers never modify
the tracked fixtures. It records the exact experiment sources and their hash,
Lean toolchain, selected server versions, raw JSON results, and stderr. The
runner invokes the Lean executable through `scripts/lean-low-priority lake exe`.
Python is needed only for this experiment and the mock server.

The mock checks run without either foreign server. They cover UTF-16, CRLF,
empty and cross-fragment ranges, generated source, multiple definition targets,
semantic-token validation, diagnostic replacement/staleness, unversioned data,
server-specific error codes, concurrent requests answered in reverse order,
unsupported server requests, chatty-server deadlines, cancellation, late
responses, server death, encoding rejection, and forced shutdown.

The real checks query both an authored-block position and a named-reference
probe in the same project scope. They retrieve available semantic tokens,
analyze an unsaved invalid fragment, map its diagnostics to authored source,
and clear the error by restoring the document. A detached Rust file provides a
separate project-membership experiment. Rust compiler checks are disabled to
isolate native language-server diagnostics. Rocq completion data is recorded
separately from diagnostics.

The protocol mode establishes no supported author syntax, snapshot cache, or
VBP attachment semantics. See its [results and limits](../../doc/design/VERSO_LSP_SPIKE.md).

## Compiled document and offline rendering experiment

`VersoLsp` is an independent Lean library whose aggregate import is
`import VersoLsp`. `VersoLspVerso` is a separate library whose aggregate import
registers the experimental Manual code block and role. The core imports only
Lean/Std; the bridge imports Verso and never VBP. Both remain in this package
while their interfaces are being designed.

The document mode builds the core in a temporary Lake package with **no package
dependencies**, compiles/collects the same requests from plain Verso and a
Blueprint node, analyzes once, and renders from the saved bundle:

```sh
scripts/lean-low-priority lake build VersoLsp VersoLspVerso verso-lsp-docs
python3 tests/lsp/run_spike.py --output /tmp/verso-lsp-docs \
  --rust-command rust-analyzer \
  --rocq-command /path/to/opam-switch/bin/coq-lsp \
  --documents
```

It also validates snapshots, rejects changed request text and duplicate
identities, checks TeX content, runs `vbp check` on the saved Blueprint site, and
compares labels/work-queue/stats with an unenriched baseline. The core analyzer
uses unsaved overlays in explicitly registered project files; only the fixture
runner creates the temporary Rust/Rocq project scaffolding.

To check browser behavior and save desktop/mobile screenshots using the existing
browser-test environment:

```sh
uv run --project tests/browser --extra test python tests/lsp/check_docs_browser.py \
  /tmp/verso-lsp-docs/documents
```

The pages require no live language server. The browser check verifies exact
source text, hovers, local navigation, authored diagnostic lines, escaped hover
markup, and mobile overflow. The [document-slice report](../../doc/design/VERSO_LSP_DOCUMENT_SLICE.md)
records current behavior and the remaining package/product decisions.
