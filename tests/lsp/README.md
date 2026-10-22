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

No public syntax, renderer, snapshot cache, or VBP attachment semantics is
established by these tests. The next slice must exercise real Verso authoring
and generation. See the [results and remaining limits](../../doc/design/VERSO_LSP_SPIKE.md).
