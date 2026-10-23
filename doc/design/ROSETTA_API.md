# Rosetta extraction and API index

The current API guide is owned by the extracted package:
[`packages/rosetta/doc/API.md`](../../packages/rosetta/doc/API.md).
The [package README](../../packages/rosetta/README.md) describes the standalone
build and runtime requirements; the
[bridge README](../../packages/rosetta/verso/README.md) covers Verso integration.

## Current local boundary

`packages/rosetta/` is one proposed standalone repository containing two Lake
packages. The `rosetta` package has no package dependencies and owns the core,
protocol tests, mock peer, and real-server fixture projects. The nested
`verso-rosetta` package depends on that core through `..` and on pinned Verso.
It owns an authoring/collection smoke test that requires no Blueprint import.

VBP consumes the bridge through a local path dependency. Its Rosetta libraries
are no longer declared in the VBP lakefile, and the implementation sources no
longer live under VBP's `src/`. VBP retains its cross-project rendering fixtures
and end-to-end maintainer harness. Existing VBP Git dependency revisions are
preserved. A pinned remote dependency can replace the local path after
repository ownership and release policy are settled.

The extraction is local and unreleased. It does not create a remote repository
or establish multi-release support. The initial package toolchains match the
current VBP Lean 4.35.0 checkout.

## Evidence and history

The current maintainer bundle is under
`_out/verso-lsp-design/rosetta-packages/`. The harness copies the entire package
unit outside the VBP sources, builds/tests both packages, checks forbidden
imports, and creates a test-owned local Git repository. Fresh consumer projects
then use pinned Git dependencies, including `subDir = "verso"` for the bridge.
This exercises the intended publication layout without publishing a repository.

The same run checks Rust/Rocq, saved bundles, plain Verso and Blueprint HTML/TeX,
and Blueprint semantic queries. Browser acceptance remains a separate command
listed in [`tests/lsp/README.md`](../../tests/lsp/README.md).

Validation passed: the clean VBP/consumer build, both standalone package test
drivers, the forbidden-import checks, both pinned local-Git consumer builds,
mock/Rust/Rocq probes, offline rendering and snapshot checks, `vbp check`,
unchanged Blueprint semantic queries, browser acceptance, and the full VBP
`lake test` suite. The final bundle preserves source SHA-256
`682684e01960001623cb2812720900ce740c186309d4aa7f949b076909b4f913`.

Earlier bundles remain historical evidence:

- `_out/verso-lsp-design/parley-errors/` validated structured errors under the
  former name; source SHA-256
  `5702696d082387286a312e16f31d7d4ace79ee70cb0a8215566136577286a95c`.
- `_out/verso-lsp-design/rosetta-rename/` validated the rename; source SHA-256
  `373fc31a9f42b614688ca29307fab7788f3b4f2a3e8f3477c978fbcfb890b3fe`.
- The [Parley lifecycle review](PARLEY_LIFECYCLE_REVIEW.md) records the earlier
  ownership/deadline work; its superseded signatures are identified there.
