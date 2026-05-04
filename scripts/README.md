# `scripts/`

This directory contains repository-local maintainer tooling for
`verso-blueprint`.

For package-facing usage, the preferred entry point is still
`lake exe blueprint-gen`, not the Python harness here. Start with the
top-level [`README.md`](../README.md) and [`doc/MANUAL.md`](../doc/MANUAL.md).

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
python3 -m scripts.blueprint_harness release-status --require-sync
python3 -m scripts.blueprint_harness paths
python3 -m scripts.blueprint_reference_harness projects
python3 -m scripts.blueprint_reference_harness status
python3 -m scripts.blueprint_reference_harness sync
python3 -m scripts.blueprint_test_blueprints list-json
```

Reference blueprints and test blueprints are distinct artifact families:

- reference blueprints are the release-facing validation catalog selected from
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
- `generate-test-blueprints.sh`
  Thin wrapper for the local test-blueprint generator.
- `validate-test-blueprints.sh`
  Thin wrapper for `python3 -m scripts.blueprint_test_blueprints validate`.
- `validate-branch.sh`
  Full pre-merge validation entry point: all tests plus both artifact families.
- `validate-reference-blueprints.sh`
  Thin wrapper for `python3 -m scripts.blueprint_reference_harness validate`.
- `lean-low-priority`
  Small wrapper that lowers scheduler priority for long Lean/Lake commands.
- `blueprint_harness.py`
  Worktree, branch-landing, and coordination CLI.
- `blueprint_reference_harness.py`
  Reference-blueprint generation, validation, and reference-checkout CLI.
- `blueprint_test_blueprints.py`
  Local test-blueprint fixture catalog, generation, and validation CLI.
- `blueprint_harness_cli.py`
  Shared argparse helper functions used by the harness CLIs.
- `blueprint_harness_projects.py`
  Project-manifest loader and schema checks for
  [`tests/harness/projects.json`](../tests/harness/projects.json).
- `blueprint_harness_references.py`
  Reference-blueprint checkout, editable-clone setup, local override, cache
  warm-up, and prune helpers shared by the reference CLI.
- `blueprint_harness_utils.py`
  Shared process-launch helpers used by the harness modules.
- `blueprint_harness_validation.py`
  Shared panel/browser regression command builders.
- `blueprint_harness_paths.py`
  Worktree-aware path resolution for `_out/` and reference-blueprint
  directories.
- `blueprint_harness_worktrees.py`
  Local worktree-coordination helpers for ignored metadata under `.worktrees/`.
- `prepare_reference_blueprints_pages.py`
  Helper used by the Pages publication flow to stage a combined site artifact
  from generated reference and test blueprint output.
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

The active project catalog lives in
[`tests/harness/projects.json`](../tests/harness/projects.json). The current
workflow and flag semantics live in
[`doc/MAINTAINER_GUIDE.md`](../doc/MAINTAINER_GUIDE.md).

The local HTML-producing test fixtures use a second metadata source:

- curated doc fixtures in
  [`tests/VersoBlueprintTests/TestBlueprintRegistry.lean`](../tests/VersoBlueprintTests/TestBlueprintRegistry.lean)
- standalone test package fixtures in
  [`tests/harness/test_blueprints.json`](../tests/harness/test_blueprints.json)

## Read Next

- [`../README.md`](../README.md) for the package overview and end-user entry
  points
- [`../doc/MANUAL.md`](../doc/MANUAL.md) for Blueprint authoring and rendering
  semantics
- [`../doc/MAINTAINER_GUIDE.md`](../doc/MAINTAINER_GUIDE.md) for the canonical
  repository maintenance workflow
- [`../doc/CONTRIBUTING.md`](../doc/CONTRIBUTING.md) for branch, commit, PR,
  and local worktree conventions
