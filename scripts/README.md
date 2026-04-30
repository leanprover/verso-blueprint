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

## Start Here

The normal repository-facing entry points are:

```bash
./scripts/generate-review-artifacts.sh
./scripts/generate-reference-blueprints.sh
./scripts/generate-test-blueprints.sh
./scripts/validate-test-blueprints.sh
./scripts/validate-branch.sh
./scripts/validate-reference-blueprints.sh
python3 -m scripts.blueprint_harness --help
python3 -m scripts.blueprint_reference_harness --help
```

If you are starting new implementation work, create a linked worktree through
the harness:

```bash
python3 -m scripts.blueprint_harness create-worktree <name> --owner codex --lock --priority P1 --summary "short description"
```

That command is intentionally heavyweight by default: it creates the git
worktree, syncs the root checkout's `.lake/`, and warms the reference blueprint
clones used by the current checkout. The new worktree defaults to the preferred
active release ref such as `origin/v4.29.0`. If you only want the linked
checkout itself, use:

```bash
python3 -m scripts.blueprint_harness create-worktree <name> --lightweight
```

If you want to verify that the active local release branch is still in sync
with the preferred release ref before branching or landing, use:

```bash
python3 -m scripts.blueprint_harness release-status
python3 -m scripts.blueprint_harness release-status --require-sync
python3 -m scripts.blueprint_harness prepare-pr
python3 -m scripts.blueprint_harness prepare-backports
python3 -m scripts.blueprint_harness prepare-backport-pr v4.28.0 --main-pr <pr>
python3 -m scripts.blueprint_harness prepare-backport-pr --all-required --main-pr <pr>
python3 -m scripts.blueprint_harness require-branch-role default_dev
```

`require-branch-role default_dev` is the explicit machine check for
automation that must refuse non-backport work on backport-only release lines.

`prepare-pr` prints a public draft PR title/body scaffold for the current
default-dev work. It includes the public `leanprover/verso-blueprint`
repository, base/head branches, and required backport lines while keeping local
worktree bookkeeping out of the public body. The scaffold is reviewer-oriented:
start with a short `This PR ...` paragraph suitable as the squash-merge commit
body, then list only the main changes needed for review and avoid routine
validation transcripts that CI already records.

`prepare-backports` prints only the `Backport ...` lines for an existing draft
default-dev PR body. Draft PRs may keep those lines as `pending`; before ready
for review, replace each `pending` entry with `#<pr>` or `exempt: <reason>`.

`prepare-backport-pr` prints a standardized paired backport branch name, PR
title, local apply plan, and public PR body scaffold that points review back to
the default-dev PR and limits the paired PR to release-line-specific deltas.

With `--all-required`, it emits one scaffold block per required release plus
the exact `git cherry-pick -x ...` commit series an agent should apply while
resolving conflicts release by release.

Paired backport branches themselves should be created with `git cherry-pick -x`.
The paired-backport check validates both the recorded source SHAs and the patch
IDs of the resulting commit series.

To land one reviewed branch onto the active release branch from the root
checkout, use:

```bash
python3 -m scripts.blueprint_harness land-release feat/some-branch
python3 -m scripts.blueprint_harness land-release feat/some-branch --cleanup
```

From a linked worktree, do not treat `lake build` or `lake test` as the
default next step. Ordinary `generate` and `validate` runs reuse the current
worktree `.lake/`; they do not automatically resync it from the root checkout.

If you want to refresh the worktree from the root checkout and shared reference
cache, prefer:

```bash
python3 -m scripts.blueprint_harness sync-root-lake
python3 -m scripts.blueprint_reference_harness sync
```

If you want to bump the package Lean toolchain and pin the matching `verso`
release in the root package plus the tracked in-repo fixtures, use:

```bash
python3 -m scripts.blueprint_harness bump-toolchain v4.29.0
python3 -m scripts.blueprint_harness bump-toolchain 4.29.0 --skip-validation
python3 -m scripts.blueprint_harness bump-toolchain v4.29.0 --verso-ref v4.29.0
```

That command:

- rewrites the managed `lean-toolchain` files
- rewrites the managed `require verso from git ...` pins to the matching
  release tag
- refreshes the committed `lake-manifest.json` files for the root package,
  `project_template`, and `tests/test_blueprints/preview_runtime_showcase/`
- runs the standard build/test validation set unless you pass
  `--skip-validation`

For rendering and browser regressions, prefer the in-repo test blueprints under
`tests/test_blueprints/` over the external reference blueprints. The default
browser suite now builds and serves
`tests/test_blueprints/preview_runtime_showcase/` when you run:

```bash
uv run --project tests/browser --extra test python -m pytest tests/browser -q --browser chromium
```

Use `./scripts/validate-test-blueprints.sh` when you want the local panel and
browser regressions against `_out/test-blueprints/preview_runtime_showcase/`.

The generated `_out/test-blueprints/` tree has a directory page and individual
sites:

- `_out/test-blueprints/index.html` is the catalog for all local HTML-producing
  test fixtures
- `_out/test-blueprints/preview_runtime_showcase/` is one standalone entry in
  that catalog, focused on browser/runtime regression coverage

Use `./scripts/generate-review-artifacts.sh` when you want the local artifact
set that is most useful during patch review:

```bash
./scripts/generate-review-artifacts.sh
./scripts/generate-review-artifacts.sh preview_runtime_showcase summary-blockers
```

That command always rebuilds the full reference blueprint catalog under
`_out/.../reference-blueprints/`. By default it also rebuilds all local test
blueprints under `_out/.../test-blueprints/`; when you pass slugs, it narrows
only the test-blueprint side.

The local HTML fixture metadata now comes from two sources that are unified by
the generator:

- curated doc fixtures in
  `tests/VersoBlueprintTests/TestBlueprintRegistry.lean`
- standalone test package fixtures in `tests/harness/test_blueprints.json`

The shared primary-category vocabulary also lives in
`tests/harness/test_blueprints.json`. Individual fixtures add optional tags for
cross-cutting topics that should show up in the generated test index without
forcing more category sprawl.

Use `./scripts/validate-branch.sh` as the canonical pre-merge check when you
want all tests plus both artifact families rebuilt:

```bash
./scripts/validate-branch.sh
```

That command runs Lean tests, the Python harness/unit tests, regenerates
`_out/reference-blueprints/`, regenerates `_out/test-blueprints/`, and then
runs the local panel/browser regressions.

The shared reference cache remains responsible for warmed external-project
dependency state, including project-specific Mathlib builds.

Use `worktree-list` as the local dashboard for parallel work. It combines the
small manual records under `.worktrees/_meta/` with live Git state such as the
current branch, dirty status, and commit distance from the active release
branch. `worktree-list`
already refreshes that metadata before printing; `worktree-sync` remains only
as a compatibility alias for the same dashboard command. Locked worktrees are
the ones another active session should not touch.

When you run `generate`, `validate`, or `sync` from the root checkout while it
is on the active release branch, the reference CLI expects that checkout to
stay clean and in sync. Use `--allow-unsafe-root-release` only as an explicit
maintainer override.

The reference project manifest now declares explicit release targets and
per-project compatibility entries in
[`tests/harness/projects.json`](../tests/harness/projects.json). By default the
reference CLI resolves the current checkout's release line and only touches the
reference projects that declare a target for that release. You can inspect a
specific declared release with:

```bash
python3 -m scripts.blueprint_reference_harness projects --release v4.29.0
python3 -m scripts.blueprint_reference_harness status --release v4.29.0
python3 -m scripts.blueprint_reference_harness release-status
python3 -m scripts.blueprint_reference_harness release-status --outdated-only
```

`release-status` is the summary/drift view for the release-target catalog. It
shows which reference blueprints belong to each release line and can narrow to
stale entries with `--outdated-only`.

Current release map:

- `v4.29.0`: `project-template`, `noperthedron`
- `v4.28.0`: `project-template`, `spherepackingblueprint`, `verso-flt`,
  `algebraic-combinatorics`

Reference blueprint deployment is release-sliced:

- `generate`, `validate`, and `sync` only operate on the current checkout's
  release slice
- the branch-local CI artifact for `reference-blueprints.yml` only includes the
  selected release slice for that branch
- the Pages deployment workflow rebuilds every release target with
  `deploy_pages: true` and assembles one combined site under
  `reference-blueprints/<release-id>/<project-id>/`

`generate`, `validate`, and `sync` refuse to run a different release target
from the wrong checkout; switch to the corresponding release branch first.

If you want to make manual changes in one external reference blueprint repo,
use a separate editable clone instead of the disposable validation clones:

```bash
python3 -m scripts.blueprint_reference_harness edit noperthedron
python3 -m scripts.blueprint_reference_harness edit spherepackingblueprint --branch feat/update-figures
```

If you want to bump the pinned `VersoBlueprint` ref in those downstream repos
from this checkout, use the dedicated editable-clone workflow:

```bash
python3 -m scripts.blueprint_reference_harness bump-verso-blueprint --ref v1.2.3
python3 -m scripts.blueprint_reference_harness bump-verso-blueprint --project noperthedron --ref v1.2.3 --generate --commit
python3 -m scripts.blueprint_reference_harness bump-verso-blueprint --project spherepackingblueprint --ref v1.2.3 --commit --push
```

That command:

- reuses or creates the editable checkout under `.worktrees/_reference-blueprints/edit/...`
- rewrites the downstream `VersoBlueprint` git pin in `lakefile.lean`
- runs the same manifest-aware `lake update VersoBlueprint` policy the harness
  already uses for validation checkouts
- builds the downstream project by default unless you pass `--skip-build`
- optionally renders review output under `_out/.../reference-blueprints-edit/`
- keeps commit and push as explicit opt-ins

Use `./scripts/lean-low-priority ...` for long `lake`, `lean`, and
`.lake/build/bin/*` commands when you intentionally run them.

For non-default harness flows such as project selection, forwarded pytest
arguments, opt-in Lean tests, or `--allow-local-build`, defer to
[`doc/MAINTAINER_GUIDE.md`](../doc/MAINTAINER_GUIDE.md) or
`python3 -m scripts.blueprint_harness --help` rather than treating this README
as the full command reference.

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
  Generate and validate the local test blueprint fixtures.
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
- `blueprint_harness_cli.py`
  Shared argparse helper functions used by both CLIs.
- `blueprint_harness_projects.py`
  Project-manifest loader and schema checks for
  [`tests/harness/projects.json`](../tests/harness/projects.json).
- `blueprint_harness_references.py`
  Reference-blueprint checkout, editable-clone setup, local override, cache
  warm-up, and prune helpers shared by the reference CLI.
- `blueprint_harness_utils.py`
  Shared process-launch helpers used by the harness modules.
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
