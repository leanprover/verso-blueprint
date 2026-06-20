# Blueprint Roadmap

Last reviewed: 2026-05-06

This document tracks repository-local engineering work for `verso-blueprint`.
Requests that should eventually move into upstream `verso`, Lake, or Lean live
in [`UPSTREAM_BACKLOG.md`](./UPSTREAM_BACKLOG.md).

This is not the place for operational commands, option reference material, or
architecture narrative. Those live in
[`MAINTAINER_GUIDE.md`](./MAINTAINER_GUIDE.md),
[`MANUAL.md`](./MANUAL.md), and
[`DESIGN_RATIONALE.md`](./DESIGN_RATIONALE.md).

## Working Principles

1. keep one semantic source of truth for Blueprint data and status derivation
2. keep command, traversal, generated-data, and browser-runtime paths aligned
   through shared library APIs
3. broaden regression coverage before large structural splits
4. keep the public maintainer harness small, explicit, and repository-local
5. treat upstream workarounds as temporary and name the upstream API that would
   remove them

## Active Workstreams

### Rendering and Preview Boundary

Goal: keep Blueprint's render entry point thin while making preview delivery
predictable across graph, summary, code, citation, and widget surfaces.

Current shape:

1. Blueprint generators call
   `Informal.PreviewManifest.blueprintMainWithPreviewData`.
2. Verso still owns traversal, TeX, word counts, search, page shell, and HTML
   emission.
3. Blueprint owns asset injection, public-xref filtering, preview-data
   emission, and local upstream-workaround rewrites.

Work:

1. finish consolidating callers around `PreviewSource` so graph, summary,
   citation, code, and widget previews do not decode preview payloads directly
2. merge the traversal preview cache and widget `elabStx` preview path behind a
   phase-safe representation
3. define one canonical API for preview labels and titles; avoid mixing raw
   labels, resolved titles, and local fallbacks across renderers
4. keep graph, summary, relation-panel, Slides, custom-client, and
   inline-reference behavior on shared browser helpers where the interaction
   model is genuinely shared; the current surfaces, descriptors, trigger
   binding, dismissal, popover, slide cleanup, and resize/scroll lifecycles
   already use bundled runtime helpers
5. evaluate a lighter preview delivery path so a page does not always fetch and
   decode the full shared manifest for a small number of previews
6. remove remaining browser timing workarounds only after targeted browser tests
   prove the replacement path; panel lifecycle workarounds should stay behind
   runtime helpers rather than feature-local listeners
7. split the large preview runtime only along the component-like boundaries now
   encoded in its API tiers: data/cache lookup, fragment rendering and
   hydration, template descriptors, preview surface state, lifecycle binding,
   and readiness/debug hooks

### Data Model and Status Semantics

Goal: make Blueprint state, traversal stores, and status rendering share one
model instead of recomputing similar facts in several layers.

Work:

1. revisit `Informal.Environment.InProgress` after the widget path no longer
   needs elaboration-time syntax; today it remains separate from `Data.Node`
   because it owns directive-stack state, preview blocks, and `elabStx`
2. keep `Informal.Environment.State` as the persisted semantic store and
   traversal indexes as rendered-site projections; consolidate only if the
   replacement keeps numbering, hrefs, preview ids, and HTML-cache keys
   phase-safe
3. define a shared status record derived from `Data.Node` plus external
   declaration checks, and route graph, summary, and local block badges through
   it
4. encode the intended ownership rules for `CodeRef.external`, especially the
   difference between Blueprint-owned labels and Lean-owned declaration names
5. decide whether richer group metadata belongs in the core data model, then
   either port the local `group-metadata-rendering` work or retire it
6. reject invalid nested and duplicate declarations before they mutate the
   active environment stack
7. keep imported duplicate collision checks for node labels, group labels, and
   author ids covered by sibling-import and transitive-import tests
8. revisit external declaration footer/status semantics once out-of-workspace
   declarations are represented precisely enough to distinguish declaration
   completeness from dependency completeness

### Asset and Build Reliability

Goal: make generated browser assets rebuild predictably without relying on
manual source touches or stale cached owner modules.

Current state:

1. the harness refreshes embedded asset owner mtimes and rebuilds targeted owner
   modules before reference and test blueprint generation
2. regression tests cover the mtime refresh and targeted rebuild behavior
3. direct `include_str` ownership still remains the underlying Lean/Lake
   dependency model

Work:

1. keep the harness owner-module refresh path covered while it remains the
   practical release mechanism
2. replace the mtime workaround with a durable generated-or-staged Lean
   dependency edge for browser assets
3. keep the structured embedded-asset inventory covered against discovered
   browser `include_str` references so graph, summary, bibliography, slides,
   block, and shared static-web ownership is not rediscovered per feature
4. add a build-level or generated-output check that fails when emitted browser
   assets drift from their source files

### Validation and Reference Catalogs

Goal: protect behavior before refactors and keep reference output useful as a
release signal.

Work:

1. keep targeted Lean tests for traversal indexes, preview schema, duplicate
   imports, status semantics, and rendering helpers
2. keep browser coverage for graph previews, summary previews, bibliography
   citations/backrefs, widget statement previews, and shared-manifest failure
   diagnostics
3. keep reference blueprint generation and validation distinct from small
   browser-regression fixtures
4. add direct regression coverage for preview-cache keying and JSON roundtrips
5. add low-cost Python coverage for harness manifest, path, and worktree logic
   so routine harness changes do not require full example rebuilds
6. add PR preview deployment that reuses the assembled reference `_site`
   artifact from CI instead of rebuilding the sites in a separate preview-only
   workflow

### Template and Client Delivery

Goal: give users a stable starter project and deployment path without making
client repositories depend on maintainer-only harness commands.

Work:

1. keep a local in-repo template/example as the documentation-facing source of
   truth for project shape, authoring patterns, and generator wiring
2. land the planned smaller starter example and reusable template
3. land `lake exe bp new` as the user-facing project creation command
4. keep `lake exe blueprint-gen` as the documented generation interface for
   existing projects
5. add a template-owned GitHub Pages workflow and local CI script, then test the
   template as a fresh standalone repository
6. keep the maintainer harness out of the user-facing template CI contract
7. evaluate a dedicated `verso-blueprint` GitHub Action after the template
   workflow contract settles
8. keep local smoke coverage and one real GitHub-hosted canary deployment
   separate from routine PR validation

### Harness and Release-Line Maintenance

Goal: keep repository maintenance flows reproducible while avoiding public
workflow details in user-facing docs.

Work:

1. keep `branch-policy.json` as the source of truth for release targets,
   default-development, and backport behavior
2. keep linked worktree metadata local under `.worktrees/`
3. keep shell wrappers thin; keep Python harness modules as the source of truth
   for orchestration, path logic, release checks, and project catalogs
4. keep the project catalog explicit and small, with published reference
   targets plus opt-in ephemeral GitHub checkout coverage
5. validate both root-checkout and linked-worktree flows end to end
6. stabilize output-path conventions for generation, static checks, browser
   checks, and published reference catalogs
7. add the minimum local override surface needed to test a local `verso`
   checkout or an external Blueprint project without hand-editing manifests
8. retire local workaround branches promptly once their content is either
   landed, deliberately ported, or recorded in this roadmap
9. keep PR and backport scaffolds branch-level: default-development PRs should
   pass an intentional branch title to `prepare-pr`, and paired backport
   scaffolds should read the public title of `--main-pr` instead of inheriting
   the last local commit subject

## Design Candidates

These are useful ideas, but they should not displace the active workstreams
above until the semantics are clearer.

1. split `blueprint_summary` into a user-facing overview/work-queue page and a
   maintainer-oriented audit/dashboard page
2. keep the default summary focused on progress, blockers, and next ready work;
   move owner/tag rollups, dependency insights, and metadata audit to the
   maintainer view
3. use compact status chips after the status source of truth is centralized
4. revisit graph layout with a CSS-first page architecture so canvas sizing is
   less runtime-driven
5. improve the default font family used by generated Blueprint output
6. add Blueprint-specific search affordances only if Verso's generated search
   cannot cover the needed workflow
7. support per-chapter commands if real projects need chapter-local generated
   pages or diagnostics
8. attach source metadata to nodes where it improves navigation or maintenance

## Risks to Watch

1. silent divergence between local and global status rendering
2. preview regressions that compile-only checks will not catch
3. imported duplicate collisions for labels, groups, or authors
4. workflow drift across long-lived worktrees and branches
5. tracked local-worktree bookkeeping leaking into public repository files
6. drift between the documented template, any exported external template, and
   the eventual GitHub Action contract
