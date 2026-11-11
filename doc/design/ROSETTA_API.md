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

The workspace-reference extension incorporates submitted commit `87792df4`
(based on `c25e9a99`). It adds workspace-symbol discovery, deferred location
resolution, exact name/container filtering, definition following, source slicing,
semantic highlighting, and a bounded notification readiness helper. The canonical
package API guide describes the author-facing operations and their limitations.

The integration keeps both package defaults on Lean 4.35.0 and retains the core's
module migration for Lean 4.36 consumers. Review fixes advertise range-token
requests, respect range/full server capabilities, accept empty token results,
and retain the latest bounded notification trace so indexing status is not
permanently hidden after 512 messages.

The extension's acceptance bundle is under
`_out/verso-lsp-design/source-definition-acceptance/`, with source SHA-256
`48870458afe0f165aef6b06304e54ae33601164e5b7441c03d8adc94d924939d`.
Standalone core tests pass on Lean 4.35.0 and 4.36.0-rc2. The 4.35 integration
also passes both standalone package tests, import-isolation and pinned local-Git
consumer builds, mock/Rust/Rocq probes, offline plain Verso and Blueprint
rendering, snapshot validation, `vbp check`, unchanged Blueprint semantic queries,
and the full VBP `lake test`. A separate live rust-analyzer probe on 4.36 resolves
and highlights a workspace definition and rejects a missing name. Browser
acceptance was not repeated for this extension; the renderer itself is unchanged.
The submitted author's Dalek lookups are additional inherited evidence, not
independent checks performed by this review.

The earlier extraction maintainer bundle is under
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
