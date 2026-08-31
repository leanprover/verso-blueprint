# `scripts/`

This directory contains repository-local maintainer tooling for
`verso-blueprint`.

For package-facing usage, use `lake exe vbp build` or the project's Blueprint
generator entry point, not the Python harness here. CI and Mathlib-heavy
projects can run
`lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --output ...`
when they need to drive the generator explicitly; Lake builds the generator's
imports as part of that command. Start with the top-level
[`README.md`](../README.md) and [`doc/MANUAL.md`](../doc/MANUAL.md).

For repository maintenance, the canonical workflow document is
[`doc/MAINTAINER_GUIDE.md`](../doc/MAINTAINER_GUIDE.md). This README is
intentionally narrower: it tells you which files under `scripts/` are normal
entry points, which ones are implementation details, and where to look next
for the full workflow.

## Workflow Entry Points

Use the shell wrappers for day-to-day maintenance:

- `./scripts/validate-branch.sh`
  Full pre-merge validation: Lean tests, harness tests, reference blueprints,
  test blueprints, and configured regressions.
- `./scripts/generate-review-artifacts.sh`
  The usual artifact set for patch review: full reference catalog plus all or
  selected local test blueprints.
- `./scripts/generate-reference-blueprints.sh`
  Rebuild the release-selected reference catalog.
- `./scripts/generate-test-blueprints.sh`
  Rebuild local HTML-producing test fixtures.
- `./scripts/validate-reference-blueprints.sh`
  Rebuild and validate reference projects.
- `./scripts/validate-test-blueprints.sh`
  Rebuild and validate local test-blueprint fixtures.

Use the Python CLIs when you need selection, status, lifecycle, or worktree
operations:

```bash
python3 -m scripts.blueprint_harness --help
python3 -m scripts.blueprint_reference_harness --help
python3 -m scripts.blueprint_test_blueprints --help
```

Common starting points:

```bash
python3 -m scripts.blueprint_harness create-worktree <name> --owner codex --lock --priority P1 --summary "short description"
python3 -m scripts.blueprint_harness create-worktree <name> --lightweight  # docs/Python-only work
python3 -m scripts.blueprint_harness release-status --require-sync
# On the new default-development release branch:
python3 -m scripts.blueprint_harness start-release-line 4.34-rc1 --keep-maintenance 1
# On each retained maintenance checkout, using the exact ref printed above:
python3 -m scripts.blueprint_harness set-default-dev-branch v4.34.0-rc1
python3 -m scripts.blueprint_harness paths
python3 -m scripts.blueprint_reference_harness compose /path/to/source --project-root blueprint
python3 -m scripts.blueprint_reference_harness projects
python3 -m scripts.blueprint_reference_harness status
python3 -m scripts.blueprint_reference_harness sync
python3 -m scripts.blueprint_test_blueprints list-json  # standalone fixtures only
```

Reference blueprints and test blueprints are distinct artifact families:

- reference blueprints are known Blueprint projects built and published as
  release validation examples; they are selected from release targets in
  [`branch-policy.json`](../branch-policy.json) and
  `publish_reference: true` project targets in
  [`tests/harness/projects.json`](../tests/harness/projects.json)
- test blueprints are local rendering/browser fixtures selected from
  [`tests/VersoBlueprintTests/TestBlueprintRegistry.lean`](../tests/VersoBlueprintTests/TestBlueprintRegistry.lean)
  and [`tests/harness/test_blueprints.json`](../tests/harness/test_blueprints.json)

The maintainer workflow, release policy, and Pages behavior live in
[`doc/MAINTAINER_GUIDE.md`](../doc/MAINTAINER_GUIDE.md). Keep this README as a
script map, not a second command reference.

## What Lives Here

- `generate-reference-blueprints.sh`
  Thin wrapper for `python3 -m scripts.blueprint_reference_harness generate`.
- `generate-review-artifacts.sh`
  Thin wrapper for patch-review artifact generation: always rebuilds the full
  reference blueprint catalog and then generates all or selected local test
  blueprints.
- `generate-js-api-docs.sh`
  Generate the Docdash JavaScript API reference and run the generated-docs
  smoke check used by CI and Pages assembly.
- `generate-test-blueprints.sh`
  Thin wrapper for the local test-blueprint generator.
- `validate-test-blueprints.sh`
  Thin wrapper for `python3 -m scripts.blueprint_test_blueprints validate`.
- `validate-branch.sh`
  Full pre-merge validation entry point: all tests plus both artifact families.
- `validate-reference-blueprints.sh`
  Thin wrapper for `python3 -m scripts.blueprint_reference_harness validate`.
- `lean-low-priority`
  Small wrapper that lowers scheduler priority for long Lean/Lake commands and
  runs them through the shared Blueprint Lake artifact-cache environment.
- `check-incremental-module-boundaries.py`
  Deterministic warm-build check for private implementation, runtime-renderer,
  and public shared-data invalidation boundaries. It records rebuilt jobs and
  restores the synthetic source edits before returning.
- `with-blueprint-lake-cache`
  Resolve the nearest `lean-toolchain`, initialize the repository-shared
  toolchain-scoped Lake cache, default to cache-in-place artifacts, and execute
  a command while preserving explicit Lake cache overrides.
- `blueprint_harness.py`
  Worktree, branch-landing, and coordination CLI.
- `blueprint_reference_harness.py`
  Editable external Blueprint composition plus reference-blueprint generation,
  validation, and reference-checkout CLI.
- `reference_build_metrics.py`
  Tee and persist verbose Blueprint phase timings, aggregate reference-project
  measurements, compare them with the deployed baseline, and emit the Actions
  summary/public build-data report used for regression visibility.
- `blueprint_harness_composition.py`
  User-provided Blueprint composition, Lake-configuration preservation,
  toolchain validation, and mandatory Mathlib-cache retrieval.
- `blueprint_test_blueprints.py`
  Local test-blueprint fixture catalog, generation, and validation CLI.
- `blueprint_harness_cli.py`
  Shared argparse helper functions used by the harness CLIs.
- `blueprint_harness_manifest.py`
  Shared JSON manifest loading, path resolution, and field validators used by
  the harness catalog loaders.
- `blueprint_harness_releases.py`
  Lean release-ref and release-candidate normalization helpers shared across
  branch policy, toolchain, and reference-project code.
- `blueprint_harness_branches.py`
  Branch-policy loading, checkout role checks, and release-branch ref
  resolution.
- `blueprint_harness_projects.py`
  Project-manifest loader and schema checks for
  [`tests/harness/projects.json`](../tests/harness/projects.json), including
  branch-policy release-target inheritance, per-project RC resolution, shared
  reference/deploy matrix serialization, and each external project's shared
  source identity and canonical CI dependency paths.
- `blueprint_harness_references.py`
  Reference-blueprint checkout, editable-clone setup, local override,
  copy-owned dependency package/path-build cache warm-up, and prune helpers
  shared by the reference CLI. The canonical path and ownership model is in
  [the maintainer guide](../doc/MAINTAINER_GUIDE.md#external-reference-cache-ownership).
- `blueprint_harness_utils.py`
  Shared process-launch helpers used by the harness modules.
- `blueprint_harness_validation.py`
  Shared panel/browser regression command builders.
- `blueprint_harness_paths.py`
  Worktree-aware path resolution for `_out/` and reference-blueprint
  directories, including the shared relative roots consumed by CI matrices.
- `blueprint_harness_worktrees.py`
  Local worktree-coordination helpers for ignored metadata under `.worktrees/`.
- `prepare_reference_blueprints_pages.py`
  Helper used by the Pages publication flow to stage a combined site artifact
  from generated reference blueprints, test blueprints, and optional generated
  JavaScript API docs.
- `__init__.py`
  Package marker for `python3 -m scripts ...` entry points.

## Useful Inspection Commands

If you want to inspect the current harness state instead of reading code, start
with:

```bash
./scripts/generate-test-blueprints.sh
python3 -m scripts.blueprint_reference_harness projects
python3 -m scripts.blueprint_reference_harness status
python3 -m scripts.blueprint_harness paths
```

The active release policy lives in
[`branch-policy.json`](../branch-policy.json), and the active project catalog
lives in [`tests/harness/projects.json`](../tests/harness/projects.json). The
current workflow and flag semantics live in
[`doc/MAINTAINER_GUIDE.md`](../doc/MAINTAINER_GUIDE.md).

The local HTML-producing test fixtures use two metadata sources:

- curated doc fixtures in
  [`tests/VersoBlueprintTests/TestBlueprintRegistry.lean`](../tests/VersoBlueprintTests/TestBlueprintRegistry.lean)
- standalone test package fixtures in
  [`tests/harness/test_blueprints.json`](../tests/harness/test_blueprints.json)

The Python `list` and `list-json` commands report only the standalone manifest
and do not invoke Lean. Full test-blueprint generation reads and validates the
curated Lean registry once before rendering either fixture family.

## Read Next

- [`../README.md`](../README.md) for the package overview and end-user entry
  points
- [`../doc/MANUAL.md`](../doc/MANUAL.md) for Blueprint authoring and rendering
  semantics
- [`../doc/MAINTAINER_GUIDE.md`](../doc/MAINTAINER_GUIDE.md) for the canonical
  repository maintenance workflow
- [`../doc/CONTRIBUTING.md`](../doc/CONTRIBUTING.md) for branch, commit, PR,
  and local worktree conventions
