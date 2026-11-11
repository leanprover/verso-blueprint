# Rosetta

Rosetta analyzes foreign-language code and named references through LSP. Its
core provides owned server sessions, versioned document handles, source
projection, typed failures, and portable analysis snapshots. It imports only
Lean and Std and has **no Lake package dependencies**.

This is an unreleased prototype. The directory currently lives under
`packages/rosetta/` in verso-blueprint and is the complete unit intended for
extraction into its own repository. No remote repository or release is assumed.

| Directory | Lake package | Lean library | Direct package dependencies |
| --- | --- | --- | --- |
| `.` | `rosetta` | `Rosetta` | None |
| `verso/` | `verso-rosetta` | `VersoRosetta` | `rosetta`, `verso` |

The bridge references the core through `..`, so both packages share one source
checkout. Core-only consumers do not fetch Verso. Neither package depends on
Blueprint. The standalone core targets Lean 4.36.0-rc2. The separate Verso bridge
still pins its Lean 4.35.0 dependency stack.

## Build and test

From this directory:

```sh
lake build
lake test
```

`lake test` runs the deterministic protocol, source-mapping, deadline,
cancellation, and cleanup tests. Tests need Python 3 for the stdio mock peer;
the library does not. Real-server probes expect the supplied fixture structure;
first copy `tests/lsp/projects/rust` and `tests/lsp/projects/rocq` to temporary
directories, then run them explicitly:

```sh
lake exe rosetta-spike probe rust /path/to/rust-analyzer /path/to/copied-rust-fixture
lake exe rosetta-spike probe rocq /path/to/coq-lsp /path/to/copied-rocq-fixture
```

The client uses stdio transport and UTF-16 LSP positions. Process-group cleanup
is currently validated on Linux and uses the standard Unix `kill` utility for
forced termination. Server commands and project configuration are caller-owned.

## Consume locally

A Lean Lake configuration can depend on this package directly:

```lean
require rosetta from "/path/to/rosetta"
```

Then use `import Rosetta`. The main generator operation is
`Rosetta.analyze : Array ContextProfile → Array Request → EIO ClientError Bundle`.
For named workspace references, `client.sourceDefinition languageId reference separator`
searches workspace symbols, follows the LSP definition result, and highlights
the returned source range with semantic tokens. It requires a unique exact name
and, when supplied, a matching server-reported container. It never chooses an
arbitrary fuzzy result. Server initialization and readiness remain caller-owned.

See the [API guide](doc/API.md) for sessions, handles, error constructors, and
conversion to an application's `IO` boundary.

For Verso authoring and rendering, use the separate
[VersoRosetta package](verso/README.md).

The package is licensed under [Apache 2.0](LICENSE).
