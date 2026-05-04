# Blueprint Maintainer Guide

Last updated: 2026-05-04

This document is the repository-level workflow guide for maintaining Blueprint
support in `verso-blueprint`, its in-repo validation projects, and its
published reference blueprints.

It focuses on:

- generation and validation commands
- output locations
- CI and GitHub Pages publication for the published subset of the validation
  catalog
- linked-worktree usage
- repository-local policy for the validation harness and reference-project
  tooling

End-user onboarding lives in
[`../project_template/README.md`](../project_template/README.md),
[`GETTING_STARTED.md`](./GETTING_STARTED.md), and [`MANUAL.md`](./MANUAL.md).
Architecture background lives in [`DESIGN_RATIONALE.md`](./DESIGN_RATIONALE.md).
Planned cleanup and follow-up work live in [`ROADMAP.md`](./ROADMAP.md).

## Scope

This is a maintainer document for this repository. It is not the end-user guide
for starting a Blueprint project or learning every Blueprint directive.

## Command Model

The shell wrappers are the normal front door for day-to-day work. The Python
modules are the canonical source for flags, path resolution, and orchestration:

- `blueprint_harness` handles worktrees, branch/release checks, PR scaffolds,
  landing, toolchain bumps, and local coordination
- `blueprint_reference_harness` handles reference-project generation,
  validation, status, sync, editable checkouts, pin bumps, and pruning
- `blueprint_test_blueprints` handles local test-blueprint listing,
  generation, and validation

Start from the help text instead of copying flag lists into docs:

```bash
python3 -m scripts.blueprint_harness --help
python3 -m scripts.blueprint_reference_harness --help
python3 -m scripts.blueprint_test_blueprints --help
```

The two generated artifact families serve different purposes:

- reference blueprints are the release-facing validation catalog declared in
  `tests/harness/projects.json`
- test blueprints are local rendering and browser-regression fixtures declared
  in `tests/VersoBlueprintTests/TestBlueprintRegistry.lean` and
  `tests/harness/test_blueprints.json`

Reference-project commands resolve the current checkout's release line by
default. `generate`, `validate`, and `sync` require a matching checkout release
line; switch branches instead of forcing a different release target.

## Everyday Workflows

### Start Implementation Work

Create implementation work in a linked worktree and keep the root checkout as
the stable base:

```bash
python3 -m scripts.blueprint_harness create-worktree <name> --owner codex --lock --priority P1 --summary "short description"
```

Before non-backport work, check the branch role and release sync state:

```bash
python3 -m scripts.blueprint_harness release-status --require-sync
python3 -m scripts.blueprint_harness require-branch-role default_dev
```

### Validate a Branch

For the full pre-merge check, run:

```bash
./scripts/validate-branch.sh
```

That command runs Lean tests, Python harness tests, reference blueprint
generation, test-blueprint generation, and configured panel/browser
regressions.

For rendering-specific changes, use a cheaper progression first:

```bash
scripts/lean-low-priority lake test
./scripts/generate-test-blueprints.sh preview_runtime_showcase
./scripts/validate-test-blueprints.sh --skip-generate
```

Use browser pytest directly only when the patch changes browser runtime or
interaction behavior:

```bash
uv run --project tests/browser --extra test python -m pytest tests/browser -q --browser chromium
```

### Generate Review Artifacts

For patch review artifacts without the full validation stack, run:

```bash
./scripts/generate-review-artifacts.sh
./scripts/generate-review-artifacts.sh preview_runtime_showcase summary-blockers
```

This always rebuilds the full reference catalog and rebuilds all local test
blueprints unless you pass specific test-blueprint slugs.

### Work With Reference Blueprints

Inspect the active reference catalog before generating or validating:

```bash
python3 -m scripts.blueprint_reference_harness projects
python3 -m scripts.blueprint_reference_harness status
python3 -m scripts.blueprint_reference_harness release-status
```

Build or validate the release-selected catalog:

```bash
./scripts/generate-reference-blueprints.sh
./scripts/validate-reference-blueprints.sh
```

Use `--project` on the Python CLI to narrow a reference command, and use the
CLI help for the full flag surface:

```bash
python3 -m scripts.blueprint_reference_harness generate --project noperthedron
python3 -m scripts.blueprint_reference_harness validate --project project-template --run-lean-tests
```

When editing an external reference repository, use an editable clone rather
than the disposable validation clones:

```bash
python3 -m scripts.blueprint_reference_harness edit <project-id>
python3 -m scripts.blueprint_reference_harness bump-verso-blueprint --project <project-id> --ref <ref> --generate --commit
```

### Iterate on Test Blueprints

Generate all local HTML-producing fixtures, or only selected slugs:

```bash
./scripts/generate-test-blueprints.sh
./scripts/generate-test-blueprints.sh state-showcase summary-blockers
```

Validate local fixtures and forward pytest filters when needed:

```bash
./scripts/validate-test-blueprints.sh
./scripts/validate-test-blueprints.sh -k preview
./scripts/validate-test-blueprints.sh --pytest-arg=-k --pytest-arg preview
```

The generated test-blueprint output has a browsable index:

- `_out/test-blueprints/index.html`
- `_out/test-blueprints/<slug>/`

In a linked worktree, the same tree lives under `_out/<worktree>/test-blueprints/`.

### Prepare or Land PRs

Use the harness to generate public PR/backport scaffolds:

```bash
python3 -m scripts.blueprint_harness prepare-pr
python3 -m scripts.blueprint_harness prepare-backports
python3 -m scripts.blueprint_harness prepare-backport-pr v4.28.0 --main-pr <pr>
python3 -m scripts.blueprint_harness prepare-backport-pr --all-required --main-pr <pr>
```

Use `git cherry-pick -x` for paired backport branches so the paired-backport
check can verify recorded source SHAs and patch IDs.

Land reviewed local work from the clean root checkout:

```bash
python3 -m scripts.blueprint_harness land-release feat/some-branch
python3 -m scripts.blueprint_harness land-release feat/some-branch --cleanup
```

### Maintain Toolchains and Caches

Refresh a linked worktree from the root checkout and warm shared reference
clones:

```bash
python3 -m scripts.blueprint_harness sync-root-lake
python3 -m scripts.blueprint_reference_harness sync
```

Bump the Lean toolchain and matching `verso` pin through the harness:

```bash
python3 -m scripts.blueprint_harness bump-toolchain v4.29.0
python3 -m scripts.blueprint_harness bump-toolchain v4.29.0 --verso-ref v4.29.0
```

Prune stale harness-managed reference caches and clones:

```bash
python3 -m scripts.blueprint_reference_harness prune --dry-run
python3 -m scripts.blueprint_reference_harness prune
```

## Output Layout

In the root checkout, generated artifacts go under:

- `_out/reference-blueprints/<project-id>/`
- `_out/test-blueprints/<slug>/`

In a linked worktree, generated artifacts go under the shared repo-root preview
area:

- `_out/<worktree>/reference-blueprints/<project-id>/`
- `_out/<worktree>/test-blueprints/<slug>/`

To print the resolved paths for the current checkout, run:

```bash
python3 -m scripts.blueprint_harness paths
```

`paths` prints the canonical worktree-aware output, cache, and checkout
locations used by the harness.

It also prints the shared reference blueprint cache root and the current
checkout's local clone root.

To generate local test-blueprint fixtures, run:

```bash
./scripts/generate-test-blueprints.sh
```

By default that renders all local test-blueprint sites under the current
checkout's worktree-aware `test-blueprints/` output root. Pass one or more
slugs to render only a subset:

```bash
./scripts/generate-test-blueprints.sh state-showcase summary-blockers
```

Use `python3 -m scripts.blueprint_test_blueprints list-json` when you need the
current slug list and metadata.

## Working from Linked Worktrees

For implementation work, create a linked worktree under `.worktrees/` and keep
the root checkout as the stable base:

```bash
python3 -m scripts.blueprint_harness create-worktree <name>
```

That command is intentionally heavyweight by default: after `git worktree add`
it syncs the root checkout's `.lake/` and warms the shared and per-worktree
reference blueprint clones. New worktrees now base off the preferred active
release ref, typically something like `origin/v4.29.0`.

If you want to verify that the root checkout has not drifted before branching
or landing, use:

```bash
python3 -m scripts.blueprint_harness release-status
python3 -m scripts.blueprint_harness release-status --require-sync
python3 -m scripts.blueprint_harness require-branch-role default_dev
```

Use `require-branch-role default_dev` when a script or agent should refuse to
do non-backport work from a backport-only checkout.

Default-development PRs also follow a paired-backport gate. In this repository
that means draft `v4.29.0` PRs must still declare one line per required
backport target. For a new public PR, generate the public-facing scaffold with:

```bash
python3 -m scripts.blueprint_harness prepare-pr
```

That helper prints the public repository, base branch, PR title, and PR body.
It keeps local worktree and write-scope notes out of the body unless they
materially help review. The generated body is intentionally reviewer-oriented:
start with a short `This PR ...` paragraph that is suitable as the squash-merge
commit body, keep implementation inventory out of the opening summary, and do
not include routine validation transcripts that CI already records. For an
existing PR where only the backport lines need a refresh, run:

```bash
python3 -m scripts.blueprint_harness prepare-backports
```

Paste the emitted backport lines into the draft PR body. While the PR is still draft,
each required line may remain:

- `Backport v4.28.0: pending`
- or `Backport v4.28.0: exempt: <reason>`

Once the `v4.29.0` PR is ready for review it must replace each `pending` line
with either:

- link the paired `v4.28.0` PR in the PR body with `Backport v4.28.0: #<pr>`
- or record `Backport v4.28.0: exempt: <reason>`

Use the default-development PR as the main review surface. The paired backport
PR is primarily a maintenance-line artifact for CI, merge state, and any
release-specific conflict resolution. Unless the backport diverges materially,
keep review comments and substantive discussion on the default-development PR.

When you do open the paired backport branch, keep the same top-level branch
prefix and reuse the default-development slug with a release marker. For
example:

- default-development branch: `fix/backport-discipline`
- paired `v4.28.0` branch: `fix/backport-v428-backport-discipline`

To keep paired backport PRs consistent, scaffold them with:

```bash
python3 -m scripts.blueprint_harness prepare-backport-pr v4.28.0 --main-pr <pr>
```

That helper prints a standardized paired branch name, a title of the form
`[backport v4.28.0] ...`, and a PR body that points back to the primary
default-development review.

When several backport releases are required, use:

```bash
python3 -m scripts.blueprint_harness prepare-backport-pr --all-required --main-pr <pr>
```

That batch mode emits one scaffold block per required release, including the
paired worktree name, branch name, and the exact `git cherry-pick -x ...`
series to apply. An agent can then create each worktree, apply the series, and
resolve conflicts release by release.

When populating the paired backport branch itself, use `git cherry-pick -x` so
each backport commit records `(cherry picked from commit <sha>)`. The
paired-backport check verifies those recorded source SHAs and also compares the
patch IDs of the default-development and backport commit series.

CI keeps the `Paired Backport` check visible on draft PRs so the declared plan
is part of PR health, and once the PR is ready it additionally checks that the
paired PR targets the required backport branch and that its checks are green
before the `v4.29.0` PR can merge.

To land one reviewed branch onto the active release branch safely from the root
checkout, use:

```bash
python3 -m scripts.blueprint_harness land-release feat/some-branch
python3 -m scripts.blueprint_harness land-release feat/some-branch --cleanup
```

`land-release` refuses to proceed unless the root checkout is on a clean,
in-sync local release branch such as `v4.29.0`, and it only accepts
fast-forward source refs. With `--cleanup`, it also removes the source worktree
and deletes the source branch when that can be done safely.

After creation, ordinary `generate` and `validate` runs reuse the worktree's
current `.lake/`; they do not automatically resync it from the root checkout.

The harness is worktree-aware:

- in a linked worktree it writes artifacts to `_out/<worktree>/...`
- by default it prefers reusing the root checkout's prepared package `.lake`
  artifacts and binaries
- it also keeps shared warmed reference blueprint caches under
  `.worktrees/_reference-blueprints/cache/`
- those shared reference caches are the source of project-specific dependency
  state, including warmed Mathlib builds for external projects that pin their
  own Mathlib versions
- each checkout uses its own local reference blueprint clones under
  `.worktrees/_reference-blueprints/by-worktree/<checkout>/`
- the reference CLI avoids local `lake build` and `lake test` in a linked
  worktree by default to avoid unnecessary dependency rebuilds

If you only want a bare linked checkout and plan to bootstrap it yourself, use:

```bash
python3 -m scripts.blueprint_harness create-worktree <name> --lightweight
```

When you do want to refresh a linked worktree from the root checkout and shared
reference cache, prefer:

```bash
python3 -m scripts.blueprint_harness sync-root-lake
python3 -m scripts.blueprint_reference_harness sync
```

If local rebuilding is actually required, opt in explicitly:

```bash
python3 -m scripts.blueprint_reference_harness generate --allow-local-build
python3 -m scripts.blueprint_reference_harness validate --allow-local-build --run-lean-tests
```

## Parallel Worktree Coordination

The local coordination layer is now machine-readable and untracked.

- `worktree-list` refreshes local metadata under `.worktrees/` and prints the
  current dashboard view, combining local metadata with live Git state
- `worktree-sync` remains available as a compatibility alias for
  `worktree-list`
- `worktree-claim` records owner, lock state, priority, summary, status, and
  write scope
- `worktree-status` shows one worktree record
- `worktree-release` marks a worktree done or otherwise retired
- `worktree-prune-candidates` lists merged clean linked worktrees that are good
  manual prune candidates
- `worktree-retire` removes one merged clean linked worktree, deletes its local
  branch when one exists, and prunes its stale reference clones
- detached linked worktrees are also retireable once their `HEAD` commit is
  reachable from that worktree's preferred release ref
- by default, each session should only retire or delete worktrees and branches
  it created or landed itself; broader cleanup should be explicit

The live local files are:

- `.worktrees/registry.json`
- `.worktrees/_meta/_root.json`
- `.worktrees/_meta/<name>.json`

Treat `.worktrees/_meta/*.json` as the local source of truth for manual
coordination fields such as owner, lock state, priority, summary, status, and
write scope.
Treat `.worktrees/registry.json` as a generated snapshot for `worktree-list`
and `worktree-status`. These files are intentionally ignored by Git and should
not be treated as repository content.

Recommended workflow:

```bash
python3 -m scripts.blueprint_harness create-worktree harness-rework --owner codex --lock --priority P1 --summary "external harness rework" --scope scripts --scope tests/harness
python3 -m scripts.blueprint_harness worktree-list
python3 -m scripts.blueprint_harness worktree-claim harness-rework --unlock --priority P0 --status review
python3 -m scripts.blueprint_harness worktree-prune-candidates
python3 -m scripts.blueprint_harness worktree-retire <name> --dry-run
```

`worktree-list` already refreshes the local metadata before printing.

## Reference Blueprint Notes

- `ejgallego/verso-noperthedron` has a heavy dependency footprint, so linked
  worktrees should normally sync `.lake/` from the root checkout before
  external validation
- the default validation catalog mixes in-repo projects with external reference
  blueprints; the larger published reference blueprints live in external
  repositories
- the harness warms shared reference blueprint checkouts once under
  `.worktrees/_reference-blueprints/cache/`
- each checkout gets its own local clone under
  `.worktrees/_reference-blueprints/by-worktree/<checkout>/`, seeded from the
  shared cache so transitive build artifacts stay warm across worktrees
- editable reference-project clones live separately under
  `.worktrees/_reference-blueprints/edit/<checkout>/` and are not touched by
  `sync`, `generate`, or `prune`
- `prune` cleans up stale project caches and local clones when worktrees or
  manifest entries disappear
- the Python harness rewrites the cloned project's `lakefile.lean` locally so
  `VersoBlueprint` resolves to the checkout under test before running
  `lake update`
- external reference repositories should commit `lake-manifest.json`; when that
  tracked manifest is present, the harness updates only `VersoBlueprint` so
  transitive dependencies such as `verso` stay pinned to the project's tested
  revisions
- the Python harness is maintainer tooling for those validations, not the main
  package-facing authoring interface

To prepare one editable external reference checkout for manual changes, use:

```bash
python3 -m scripts.blueprint_reference_harness projects
python3 -m scripts.blueprint_reference_harness edit <project-id>
python3 -m scripts.blueprint_reference_harness edit <project-id> --branch feat/update-figures
```

Those editable clones are ordinary developer checkouts intended for local
edits and future PRs; they intentionally do not reuse the disposable cache
reset flow that the validation harness uses.

For repeated downstream dependency rollouts, prefer the dedicated bump command
instead of editing `lakefile.lean` by hand:

```bash
python3 -m scripts.blueprint_reference_harness bump-verso-blueprint --ref v1.2.3
python3 -m scripts.blueprint_reference_harness bump-verso-blueprint --project <project-id> --ref v1.2.3 --commit --push
```

## CI and Pages

The repository includes these GitHub Actions workflows:

- `.github/workflows/ci.yml`
- `.github/workflows/reference-blueprints.yml`
- `.github/workflows/reference-blueprints-deploy.yml`

`ci.yml` is the main verification workflow. It keeps the always-on checks for
pull requests and pushes to release branches named like `v4.29.0`:

- `Blueprint Build`
- `Blueprint Tests`
- `Harness Tests`

On pull requests it also runs `Project Template Fresh Repo`, which materializes
the in-repo template as a fresh standalone repository and smoke-tests the
template-owned CI path.

`reference-blueprints.yml` is the shared build workflow. On pull requests,
pushes to release branches named like `v4.29.0`, and manual dispatch, it:

- resolves the current branch's release target from `tests/harness/projects.json`
- builds only the reference projects that declare compatibility with that
  release target
- builds the local `test-blueprints/` artifact set, including
  `preview_runtime_showcase`
- stages a branch-local site artifact under `_site/` only when the selected
  release target has `deploy_pages: true`
- uploads that assembled site as a normal workflow artifact
- uses the shared reference-checkout mode in CI to avoid duplicating warmed
  `.lake/` trees on the GitHub runner

`reference-blueprints-deploy.yml` is the deployment workflow. It runs after a
successful `reference-blueprints.yml` run on a release branch named like
`v4.29.0`, checks out the repository default-development branch as the source
of truth for deployment policy, resolves every release target with
`deploy_pages: true`, rebuilds each deployable reference slice in isolation,
and assembles one combined GitHub Pages artifact.

At the moment that means:

- `v4.29.0` deploys Pages for its selected reference targets
- `v4.28.0` also deploys Pages for its selected reference targets

The branch-local site artifact produced by `reference-blueprints.yml` for one
release includes:

- `_site/index.html`
- `_site/reference-blueprints/<project-id>/` for each deployable reference
  target selected on that branch
- `_site/test-blueprints/index.html`
- `_site/test-blueprints/preview_runtime_showcase/`
- `_site/test-blueprints/<slug>/`

The combined Pages artifact produced by `reference-blueprints-deploy.yml`
includes:

- `_site/index.html`
- `_site/reference-blueprints/<release-id>/<project-id>/` for each deployable
  reference target across all deployable release slices
- `_site/test-blueprints/index.html`
- `_site/test-blueprints/preview_runtime_showcase/`
- `_site/test-blueprints/<slug>/`

The shared staging helper understands both input shapes:

- a single-release local/CI artifact rooted at `_out/reference-blueprints/<project-id>/`
- or a deploy-time combined artifact rooted at
  `_out/reference-blueprints/<release-id>/<project-id>/`

The staging helper is:

- `python3 ./scripts/prepare_reference_blueprints_pages.py`

## External Project Validation Direction

The harness is now project-driven rather than hardcoded to one project.

- the default catalog is declared in `tests/harness/projects.json`
- catalog entries can also describe ephemeral `git_checkout` projects hosted
  outside this repository
- external entries should declare release-specific refs under `targets` plus
  the build and generation commands needed after checkout
- the harness currently rewrites the cloned `lakefile.lean` dependency line so
  external test projects exercise the local `VersoBlueprint` checkout instead
  of the committed upstream dependency
- the current local override injection expects a `lakefile.lean` project that
  declares `VersoBlueprint` from the official `leanprover/verso-blueprint` Git
  repository, and it tolerates different Git refs and URL spellings for that
  source
- local worktree bookkeeping is intentionally not tracked in the repository

Minimal external catalog entry shape:

```json
{
  "id": "some-user-project",
  "source": {
    "kind": "git_checkout",
    "repository": "https://github.com/org/some-user-project.git",
    "project_root": "."
  },
  "targets": [
    {
      "release": "v4.29.0",
      "ref": "0123456789abcdef0123456789abcdef01234567"
    }
  ],
  "build_command": ["lake", "build"],
  "generate_command": ["lake", "exe", "blueprint-gen", "--output", "{output_dir}"],
  "site_subdir": "html-multi"
}
```

That override policy is now the default maintainer behavior: the external
projects keep their committed dependency pointed at an approved upstream repo,
while the harness swaps in a local path dependency ephemerally during
validation.

## Shared Preview Artifact

Each generated Blueprint site includes a shared preview manifest at:

`html-multi/-verso-data/blueprint-preview-manifest.json`

See [`MANUAL.md`](./MANUAL.md) for the manifest semantics and executable
inspection flags.

## Project-Local Option Policy

Repository-level Blueprint reference material lives in the main doc set. Project
specific option policy should stay with the project that owns it.

Current project-specific reference:

- [`ejgallego/verso-noperthedron/OPTIONS.md`](https://github.com/ejgallego/verso-noperthedron/blob/main/OPTIONS.md)

## Documentation Reading Order

1. Read [`../project_template/README.md`](../project_template/README.md) and
   [`GETTING_STARTED.md`](./GETTING_STARTED.md) for the user-facing project
   shape.
2. Read [`MANUAL.md`](./MANUAL.md) for authoring, rendering, and options.
3. Return here for repository-local commands, outputs, and worktree behavior.
4. Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) for branch, commit, PR, and
   local coordination conventions.
5. Read [`DESIGN_RATIONALE.md`](./DESIGN_RATIONALE.md) before touching
   architecture boundaries.
6. Read [`ROADMAP.md`](./ROADMAP.md) before starting structural cleanup.
