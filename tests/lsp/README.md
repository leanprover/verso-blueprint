# Verso LSP design spike

This is maintainer tooling for the design in
[`doc/design/VERSO_LSP_ADAPTER.md`](../../doc/design/VERSO_LSP_ADAPTER.md).
The independent [`rosetta` package](https://github.com/ejgallego/rosetta)
imports Lean and Std, with no package dependencies. Its separate `verso/`
package supplies the Verso bridge. Both are experimental; the Blueprint core
does not import either library by default.

Build and run the deterministic checks from this worktree:

```sh
scripts/lean-low-priority lake build @rosetta/rosetta-spike
python3 tests/lsp/run_spike.py --output /tmp/rosetta-mock
```

Add explicitly selected language servers to exercise real projects:

```sh
python3 tests/lsp/run_spike.py --output /tmp/rosetta-real \
  --rust-command rust-analyzer \
  --rocq-command /path/to/opam-switch/bin/coq-lsp
```

The runner copies the entire standalone package unit into a content-addressed
output directory and runs its own `lake test` driver there. Protocol tests,
the mock peer, and real-server fixture projects are owned by the core package.
The servers never modify tracked fixtures. The runner records exact sources and their hash,
Lean toolchain, selected server versions, raw JSON results, and stderr. The
runner invokes Lake through `scripts/lean-low-priority`.
Python is needed only for this experiment and the mock server.

The mock checks run without either foreign server. They cover UTF-16, CRLF,
empty and cross-fragment ranges, generated source, multiple definition targets,
semantic-token validation, diagnostic replacement/staleness, unversioned data,
server-specific error codes, concurrent requests answered in reverse order,
unsupported server requests, chatty-server deadlines, cancellation, late
responses, server death, encoding rejection, and forced shutdown.

The lifecycle checks additionally cover blocked stdin, pre-cancellation,
zero deadlines, outbound/pending capacity, stderr retention, stale handles and
in-flight replies across edits and close/reopen, mismatched query URIs,
unbound document requests, malformed envelopes, oversized/partial frames,
concurrent/repeated close, SIGTERM-resistant servers, and descendants retaining
stdio after their leader exits. These process-group checks currently target
Unix; the recorded validation platform is Linux. See the
[lifecycle contract and limits](../../doc/design/PARLEY_LIFECYCLE_REVIEW.md).
They now match structured `ClientError` constructors, preserve server codes and
absent/null/nested error data, distinguish successful null results, and exercise
typed action-plus-cleanup failures. See the
[current API and migration guide](https://github.com/ejgallego/rosetta/blob/main/doc/API.md).

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

`Rosetta` is a library in the independent `rosetta` Lake package; its aggregate
import is `import Rosetta`. `VersoRosetta` is a separate package/library whose aggregate import
registers the experimental Manual code block and role. The core imports only
Lean/Std; the bridge imports Verso and never VBP. VBP consumes the bridge as a
pinned Git dependency from `ejgallego/rosetta`, selecting `subDir = "verso"`.

Rosetta's own CI builds/tests its packages, checks import isolation, and builds
fresh pinned Git consumers. Those checks live in `tests/check_packages.py` in
the standalone repository. VBP's runner resolves the actual package directory
from its Lake manifest, records the pinned URL/revision and source snapshot,
and exercises its Blueprint-specific generator boundary.

It then compiles/collects the same requests from plain Verso and a
Blueprint node, analyzes once, and renders from the saved bundle:

```sh
scripts/lean-low-priority lake build @rosetta/Rosetta @verso-rosetta/VersoRosetta rosetta-docs
python3 tests/lsp/run_spike.py --output /tmp/rosetta-docs \
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
  /tmp/rosetta-docs/documents
```

The pages require no live language server. The browser check verifies exact
source text, hovers, local navigation, authored diagnostic lines, escaped hover
markup, and mobile overflow. The [document-slice report](../../doc/design/VERSO_LSP_DOCUMENT_SLICE.md)
records current behavior and the remaining package/product decisions.
