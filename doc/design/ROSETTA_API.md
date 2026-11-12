# Rosetta integration and API index

The core and Verso bridge now belong to the independent
[ejgallego/rosetta](https://github.com/ejgallego/rosetta) repository.
See its [API guide](https://github.com/ejgallego/rosetta/blob/main/doc/API.md),
[package README](https://github.com/ejgallego/rosetta),
[bridge README](https://github.com/ejgallego/rosetta/blob/main/verso/README.md),
and [migration notes](https://github.com/ejgallego/rosetta/blob/main/doc/MIGRATION.md).

## Repository boundary

VBP consumes `verso-rosetta` as a pinned Git dependency with `subDir = "verso"`.
The root `rosetta` package is resolved from the same checkout. The current pin
is `462fa57af6e058919a8d48be5fd1ba61675641e1`. The local `packages/rosetta/` copy has been removed.
The standalone repository preserves the four package commits since extraction;
its exported Lean sources match VBP `bc6c4f5a` byte for byte.

Rosetta owns the protocol client, source mapping, typed errors, analysis, mock
and real-server fixtures, Verso bridge, and package/Git-consumer isolation tests.
VBP retains the Blueprint/plain-Verso integration generators, offline rendering
checks, browser fixtures and Blueprint semantic comparisons. Existing unrelated
VBP Git dependency revisions remain unchanged.

The pinned revision is published in Rosetta's public repository and can be
fetched directly from GitHub. Package CI builds the core on Lean 4.35.0 and
4.36.0-rc2, builds/tests the Lean 4.35.0 Verso bridge, and checks fresh Git
consumers and package isolation. VBP CI separately compiles and compares the
plain Verso and Blueprint request plans without starting language servers.

The authoring integration currently uses the explicit generator-boundary API:
collect inert requests, analyze through configured server profiles, save and
validate the bundle, enrich the document, then render normally. Plain Verso and
Blueprint fixtures exercise this path and preserve Blueprint semantic queries.
A standard `vbp build` configuration interface for profiles and saved bundles
remains follow-up work; publishing the library does not add that interface.

## Evidence and history

The latest follow-up adapts lean-mirror's vendored readiness patch `8d1e2e7`
into a generic API: `ClientConfig.retainedNotificationMethods` selects general
notification methods before startup, and `Client.latestNotification` observes
their latest params independently of the bounded journal. The existing
`Client.waitForNotification` now requires configured retention and uses that
state. This prevents later unrelated traffic from evicting a loading-state
update. Rust-specific readiness semantics remain in the consuming facade.

Evidence is under `_out/verso-lsp-design/notification-retention/`, source SHA-256
`72569004f47f7deb232406a6e2ee4fe7c466875d57110cee68189b0eaebfa296`.
Core build/tests pass on Lean 4.35.0 and 4.36.0-rc2, including initialization-time
notifications, journal eviction, replacement of ready by busy, null params, and
unconfigured/session-isolated state. An isolated copy of the lean-mirror facade
at `b5fb7b6`, adapted to the generic API, builds and passes its native six-feature
editor/diagnostics/shutdown contract. The original lean-mirror worktree and PR12
are unchanged; its vendored pin can be updated separately.

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
