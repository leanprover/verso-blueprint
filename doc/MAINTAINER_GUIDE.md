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
[`GETTING_STARTED.md`](./GETTING_STARTED.md), [`MANUAL.md`](./MANUAL.md), and
[`API.md`](./API.md).
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

### Agent-Facing `vbp` Helper

`lake exe vbp ...` and `skills/verso-blueprint/` are maintained as the
project-facing helper surface for Blueprint generation and local coding-agent
queries. End-user docs should present `lake exe vbp build` as the normal
rendering workflow; it discovers the project generator entry point and invokes
it internally.

Treat `vbp` JSON as fully unstable. It may change within this repository as
agent workflows evolve, and should not be documented as a public compatibility
contract. Prefer in-band discovery through `lake exe vbp --help`,
`lake exe vbp discover`, and `lake exe vbp query selectors` instead of copying
selector lists or JSON shapes into long-lived docs.

The two generated artifact families serve different purposes:

- reference blueprints are the release-facing validation catalog selected from
  release targets in `branch-policy.json` and project targets in
  `tests/harness/projects.json`
- test blueprints are local rendering and browser-regression fixtures declared
  in `tests/VersoBlueprintTests/TestBlueprintRegistry.lean` and
  `tests/harness/test_blueprints.json`

Reference-project commands resolve the current checkout's release line by
default. `generate`, `validate`, and `sync` require a matching checkout release
line; switch branches instead of forcing a different release target.

Reference release metadata has two tracked sources of truth. `branch-policy.json`
owns release ids, branch names, baseline Lean toolchain refs, baseline `verso`
refs, default-development/backport policy, and the release-level Pages deploy
flag. `tests/harness/projects.json` owns project ids, external repository refs,
the `publish_reference` flag, and any per-project `rc` override. Matrix emitter
scripts derive effective per-project `toolchain` and `verso_ref` values from
those two files; release targets themselves do not carry `rc` metadata.

## Everyday Workflows

### Start Implementation Work

Create implementation work in a linked worktree and keep the root checkout as
the stable base:

```bash
python3 -m scripts.blueprint_harness create-worktree <name> --owner codex --lock --priority P1 --summary "short description"
```

For docs, Python harness, or other work that does not need synced Lake
artifacts or warmed reference clones, prefer a lightweight worktree:

```bash
python3 -m scripts.blueprint_harness create-worktree <name> --lightweight
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

PDF changes can add the optional real-engine smoke check:

```bash
./scripts/validate-test-blueprints.sh --run-real-pdf-smoke
```

The smoke check builds `project_template` with `--pdf`, verifies
`pdf/main.pdf`, and skips itself when `lualatex` is not installed.

Use browser pytest directly only when the patch changes browser runtime or
interaction behavior:

```bash
uv run --project tests/browser --extra test python -m pytest tests/browser -q --browser chromium
```

Browser tests that need the public Blueprint render API should use
`blueprint_render_api_script` or `wait_for_blueprint_render_api` from
`tests/browser/support.py`. Those helpers import
`-verso-data/blueprint-page-runtime.mjs` for regular Manual pages. Slide
fixtures should wait for `window.VersoBlueprint.slides.hydrate`, which is the
generated slide runtime's narrow rehydration hook, not a general render API.

### Embedded Browser Assets

Several browser assets are embedded into Lean modules with `include_str`, for
example the preview runtime, graph, summary, bibliography, block, slide, and
math assets. A JS/CSS-only edit can leave a focused Lean check looking at a
stale owner module if you run that check directly.

The artifact-generation and validation scripts already refresh the embedded
asset owner modules before generating reference or test Blueprint output. After
editing embedded browser assets, prefer one of these paths before relying on
generated HTML or browser tests:

```bash
./scripts/generate-test-blueprints.sh <slug>
./scripts/generate-reference-blueprints.sh
./scripts/validate-branch.sh
```

The tracked owner inventory lives in `EMBEDDED_ASSET_OWNER_PATHS` in
`scripts/blueprint_harness_utils.py`. When adding a new `include_str` browser
asset, add it to that inventory and cover the mapping in the harness tests so
artifact generation rebuilds the right Lean owner. Keep semantic asset ordering
in the Lean `BlueprintAssetBundle` definitions; the Python inventory is only
rebuild metadata.

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

Pass `--verbose` to `generate` or `validate` when you want each Blueprint
generator to print its own progress diagnostics during HTML emission.

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
python3 -m scripts.blueprint_harness prepare-backport-pr v4.30.0 --main-pr <pr>
python3 -m scripts.blueprint_harness prepare-backport-pr --all-required --main-pr <pr>
```

Use `git cherry-pick -x` for paired backport branches so the paired-backport
check can verify recorded source SHAs, commit count, and commit order. The
check intentionally does not require patch-id equality, because release-line
conflict resolution often changes the exact diff while preserving provenance.

Each paired backport PR should carry the scaffolded release label, such as
`backport-v4.30.0`, so release-specific queues remain visible when several
maintenance lines are active.

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

To bump the Lean toolchain for the root package plus the tracked in-repo
fixtures, and pin the matching `verso` release or release candidate in the root
package:

```bash
python3 -m scripts.blueprint_harness bump-toolchain 4.31-rc2
python3 -m scripts.blueprint_harness bump-toolchain v4.31.0 --skip-validation
```

That command rewrites the managed `lean-toolchain` files, rewrites the root
package's direct `require verso` pin, refreshes the committed manifests for the
root package, `project_template`, and
`tests/test_blueprints/preview_runtime_showcase/`, and by default runs the same
build/test validation pass that maintainers would otherwise do manually. Release
candidates use the official short RC name, for example `4.31-rc2`; the harness
writes the corresponding Lean and `verso` tag ref, such as `v4.31.0-rc2`.
Pass `--verso-ref <tag>` only when the Lean toolchain ref and upstream `verso`
release tag need to differ.

### Start a New Lean Release Line

When Lean opens a new release line, create the new branch from the previous
default-development branch, then let the harness do the branch-local release
setup:

```bash
python3 -m scripts.blueprint_harness start-release-line 4.31-rc2
```

Run this from the new local branch, for example `v4.31.0`. The command:

- rewrites the managed `lean-toolchain` files, the root `verso` pin, and the
  committed manifests for the root package, `project_template`, and the
  preview showcase
- updates `branch-policy.json` so the new branch is the default-development
  line, the previous default-development branch becomes a required backport
  target, and the new release target is recorded
- enables the in-repo reference projects, currently `project-template`, on the
  new release target

For release candidates, use the official short RC name such as `4.31-rc2`.
The branch name remains the stable release branch, for example `v4.31.0`, while
the command pins the managed root-package files to `v4.31.0-rc2`.

External reference projects are not auto-pinned for a new release line. Add
their release-target refs only after those repositories have been updated and
validated on the new Lean release. If one project target still needs a release
candidate, put the short RC name, for example `"rc": "4.31-rc2"`, on that
specific project target in `tests/harness/projects.json`.

Do not backport the branch-start commit to older release lines: that commit
changes the actual Lean toolchain. Instead, update only the tracked branch
policy metadata on each older release branch so the harness recognizes them as
backport-only:

```bash
python3 -m scripts.blueprint_harness set-default-dev-branch v4.31.0
```

Commit that metadata-only change separately on each older branch that still
carries `branch-policy.json`, such as `v4.30.0`. Preserve their own Lean
toolchain pins.

To remove stale harness-managed reference caches and orphaned local clones:

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

It also prints the shared reference checkout cache root, dependency package
cache root, and the current checkout's local clone root.

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
reference blueprint clones. New worktrees now base off the branch policy's
preferred default-development ref, typically something like `origin/v4.31.0`.
Pass `--base <release-ref>` explicitly for backport-only work.

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
that means draft default-development PRs must still declare one line per required
backport target. For a new public PR, generate the public-facing scaffold with:

```bash
python3 -m scripts.blueprint_harness prepare-pr
```

That helper prints the public repository, base branch, PR title, and PR body.
It keeps local worktree and write-scope notes out of the body unless they
materially help review. The generated body is intentionally reviewer-oriented:
start with a short `This PR ...` paragraph that is suitable for permanent
history, keep implementation inventory out of the opening summary, and do not
include routine validation transcripts that CI already records. For PRs that
need paired backports, use a Lean-style title of the form `type: summary`
without a type scope such as `feat(entry): ...`, and use a merge commit when
landing so the `cherry-pick -x` source commits remain in default-development
history. For an
existing PR where only the backport lines need a refresh, run:

```bash
python3 -m scripts.blueprint_harness prepare-backports
```

Paste the emitted backport lines into the draft PR body. While the PR is still draft,
each required line may remain:

- `Backport v4.30.0: pending`
- or, for documentation and repository-metadata-only changes,
  `Backport v4.30.0: exempt: <reason>`

Once the default-development PR is ready for review it must replace each `pending` line
with either:

- link the paired backport PR in the PR body with `Backport v4.30.0: #<pr>`
- or record `Backport v4.30.0: exempt: <reason>` when every changed file is
  documentation or repository metadata

Keep code-bearing release lines structurally aligned even when compatibility or a
reported maintenance-line regression is not the motivation. Changes to source,
scripts, tests, templates, package configuration, and runtime assets require paired
backports because skipping them makes later cherry-picks harder. The paired-backport
check reads the PR file list and rejects exemptions for those paths; an exemption
reason by itself is not sufficient.

Use the default-development PR as the main review surface. The paired backport
PR is primarily a maintenance-line artifact for CI, merge state, and any
release-specific conflict resolution. Unless the backport diverges materially,
keep review comments and substantive discussion on the default-development PR.

When you do open the paired backport branch, keep the same top-level branch
prefix and reuse the default-development slug with a release marker. For
example:

- default-development branch: `fix/backport-discipline`
- paired `v4.30.0` branch: `fix/backport-v430-backport-discipline`

To keep paired backport PRs consistent, scaffold them with:

```bash
python3 -m scripts.blueprint_harness prepare-backport-pr v4.30.0 --main-pr <pr>
```

That helper prints a standardized paired branch name, a title of the form
`[backport v4.30.0] ...`, a `backport-v4.30.0` release label, and a PR body
that points back to the primary default-development review. By default the
title after the backport prefix is read from the GitHub title of `--main-pr`,
which keeps multi-commit backports from inheriting the last local commit
subject. The source branch and exact commit series also come from `--main-pr`,
so the command remains correct after the default-development PR merges. Use
`--main-title '<type>: <subject>'` or `--source-branch <branch>` only when the
GitHub lookup is not available or you intentionally need to override that PR
metadata.

When several backport releases are required, use:

```bash
python3 -m scripts.blueprint_harness prepare-backport-pr --all-required --main-pr <pr>
```

That batch mode emits one scaffold block per required release, including the
paired worktree name, branch name, release label, and the exact
`git cherry-pick -x ...` series to apply. An agent can then create each
worktree, apply the series, and resolve conflicts release by release.

When populating the paired backport branch itself, use `git cherry-pick -x` so
each backport commit records `(cherry picked from commit <sha>)`. The
paired-backport check verifies those recorded source SHAs, commit count, and
commit order; it does not compare patch IDs because release-line conflict
resolution can legitimately change the exact diff.

CI keeps the `Paired Backport` check visible on draft PRs so the declared plan
is part of PR health, and once the PR is ready it additionally checks that the
paired PR targets the required backport branch and that its checks are green
before the default-development PR can merge.

To land one reviewed branch onto the active release branch safely from the root
checkout, use:

```bash
python3 -m scripts.blueprint_harness land-release feat/some-branch
python3 -m scripts.blueprint_harness land-release feat/some-branch --cleanup
```

`land-release` refuses to proceed unless the root checkout is on a clean,
in-sync local release branch such as `v4.30.0`, and it only accepts
fast-forward source refs. With `--cleanup`, it also removes the source worktree
and deletes the source branch when that can be done safely.

After creation, ordinary `generate` and `validate` runs reuse the worktree's
current `.lake/`; they do not automatically resync it from the root checkout.

The harness is worktree-aware:

- in a linked worktree it writes artifacts to `_out/<worktree>/...`
- by default it prefers reusing the root checkout's prepared package `.lake`
  artifacts and binaries
- it also keeps shared warmed reference dependency caches under
  `.worktrees/_reference-blueprints/deps/<source-ref-key>/`, with downloaded
  Lake packages under `packages/` and external path-dependency build trees under
  `path-builds/`
- those shared caches are keyed by external repository, project root, and
  selected project ref; they preserve expensive pinned dependency state such as
  Mathlib package builds, not generated Blueprint site artifacts
- disposable source checkouts for those refs live separately under
  `.worktrees/_reference-blueprints/cache/<source-ref-key>/`
- each checkout uses its own local reference blueprint clones under
  `.worktrees/_reference-blueprints/by-worktree/<checkout>/<source-ref-key>/`
- the reference CLI avoids local `lake build` and `lake test` in a linked
  worktree by default to avoid unnecessary dependency rebuilds

If you only want a bare linked checkout and plan to bootstrap it yourself, use:

```bash
python3 -m scripts.blueprint_harness create-worktree <name> --lightweight
```

When you do want to refresh a linked worktree from the root checkout and shared
reference dependency cache, prefer:

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
- after a GitHub squash merge, pass `--merged-pr <number>` so `worktree-retire`
  can verify that the merged PR head SHA, head branch, and base branch match the
  local worktree before force-deleting the local branch
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
python3 -m scripts.blueprint_harness worktree-retire <name> --merged-pr <number>
```

`worktree-list` already refreshes the local metadata before printing.

## Reference Blueprint Notes

- `ejgallego/verso-noperthedron` has a heavy dependency footprint, so linked
  worktrees should normally sync `.lake/` from the root checkout before
  external validation
- the default validation catalog mixes in-repo projects with external reference
  blueprints; the larger published reference blueprints live in external
  repositories
- the harness warms shared reference dependency caches under
  `.worktrees/_reference-blueprints/deps/<source-ref-key>/`, including Lake
  packages and `.lake/build` trees for external path dependencies such as
  formalization submodules
- the cache key is derived from the external repository URL, project root, and
  selected project ref, so one project can keep separate caches for different
  Lean/mathlib release pins
- disposable source checkouts for those keyed refs live under
  `.worktrees/_reference-blueprints/cache/<source-ref-key>/`
- each checkout gets its own local clone under
  `.worktrees/_reference-blueprints/by-worktree/<checkout>/<source-ref-key>/`,
  seeded from the dependency cache so transitive package and path-dependency
  build artifacts stay warm across worktrees
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
pull requests and pushes to release branches named like `v4.30.0`:

- `Blueprint Build`
- `Blueprint Tests`
- `Harness Tests`

On pull requests it also runs `Project Template Fresh Repo`, which materializes
the in-repo template as a fresh standalone repository and smoke-tests the
template-owned CI path.

`reference-blueprints.yml` is the shared build workflow. On pull requests,
pushes to release branches named like `v4.30.0`, and manual dispatch, it:

- resolves the current branch's release target from `branch-policy.json`
- builds only project targets for that release that set
  `publish_reference: true`
- builds the local `test-blueprints/` artifact set, including
  `preview_runtime_showcase`
- stages a branch-local site artifact under `_site/` only when the selected
  release target has `deploy_pages: true`
- uploads that assembled site as a normal workflow artifact
- generates external references from per-job local clones seeded by the keyed
  dependency cache
- restores and saves external reference dependency caches by the same
  repository/project-root/ref key used locally, caching the external project's
  `.lake/packages/` tree and `.lake/build` trees for external path dependencies
  rather than the source checkout or generated Blueprint site's own output

`reference-blueprints-deploy.yml` is the deployment workflow. It runs after a
successful `reference-blueprints.yml` run on a release branch named like
`v4.30.0`, checks out the repository default-development branch as the source
of truth for deployment policy, resolves every release target with
`deploy_pages: true`, selects project targets marked `publish_reference: true`,
rebuilds those selected blueprints in isolation, and assembles one combined
GitHub Pages artifact. The per-project target entry is the source of truth for
the project id, release, pinned ref, and publication flag. For each deploy
matrix entry, the workflow writes a small one-project manifest from that
default-development catalog and passes it to the release-branch harness with
`--manifest`; the deploy job therefore does not rely on stale branch-local
`projects.json` refs. The per-project target entry also owns any RC override,
so two projects in the same release line can deploy against different release
candidate tags when needed.

The current published project/release split is intentionally not duplicated
here. Read `tests/harness/projects.json`; every project target marked
`publish_reference: true` is part of the deployed catalog for that target's
release.

The branch-local site artifact produced by `reference-blueprints.yml` for one
release includes:

- `_site/index.html`
- `_site/reference-blueprints/<project-id>/` for each deployable reference
  target selected on that branch
- `_site/test-blueprints/index.html`
- `_site/test-blueprints/preview_runtime_showcase/`
- `_site/test-blueprints/<slug>/`

It intentionally does not include `_site/js-api/`; CI validates and uploads the
generated JavaScript API docs as a review artifact, while the deploy workflow
rebuilds the published copy for Pages.

The combined Pages artifact produced by `reference-blueprints-deploy.yml`
includes:

- `_site/index.html`
- `_site/js-api/`
- `_site/reference-blueprints/<release-id>/<project-id>/` for each selected
  reference target across all deployable release slices
- `_site/test-blueprints/index.html`
- `_site/test-blueprints/preview_runtime_showcase/`
- `_site/test-blueprints/<slug>/`

GitHub Pages deployments run through the `github-pages` environment. When the
default-development branch advances to a new release line, update that
environment's deployment branch policy to allow the new default branch before
expecting Pages to publish. If the generated site artifact is correct but the
`Deploy Pages` job fails immediately without step logs, check this policy first.

The shared staging helper understands both input shapes:

- a single-release local/CI artifact rooted at `_out/reference-blueprints/<project-id>/`
- or a deploy-time combined artifact rooted at
  `_out/reference-blueprints/<release-id>/<project-id>/`

The staging helper is:

- `python3 ./scripts/prepare_reference_blueprints_pages.py`

## External Project Validation Direction

The harness is now project-driven rather than hardcoded to one project.

- release targets, branch names, and deploy flags are declared in
  `branch-policy.json`
- the default project catalog is declared in `tests/harness/projects.json`
- catalog entries can also describe ephemeral `git_checkout` projects hosted
  outside this repository
- external `projects` entries declare the repository plus the build and
  generation commands needed after checkout
- each project target owns its release ref, optional RC metadata, and
  `publish_reference: true` marker for the release-facing published catalog
- keep each external Blueprint on its one intended current release target;
  move that target when the project advances instead of retaining published
  legacy targets for older releases
- prefer `lake exe vbp build` for package-local generation, or a build command
  that targets only the Lean library or formalization artifacts needed by the
  document followed by
  `lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean ...` when the
  harness must drive an external project explicitly
- the harness currently rewrites the cloned `lakefile.lean` dependency line so
  external test projects exercise the local `VersoBlueprint` checkout instead
  of the committed upstream dependency
- the external checkout's Lean release family must match its catalog target;
  the harness rejects cross-release combinations before running `lake update`
- the current local override injection expects a `lakefile.lean` project that
  declares `VersoBlueprint` from the official `leanprover/verso-blueprint` Git
  repository, and it tolerates different Git refs and URL spellings for that
  source
- local worktree bookkeeping is intentionally not tracked in the repository

For example, the release id may remain `v4.30.0` while a specific published
project target records `"rc": "4.30-rc2"`. That row then builds with
`leanprover/lean4:v4.30.0-rc2` and pins `verso` to `v4.30.0-rc2`, while another
project target on the same release id can use a different RC or the final
release tag.

Minimal external catalog entry shape:

```json
{
  "projects": [
    {
      "id": "some-user-project",
      "source": {
        "kind": "git_checkout",
        "repository": "https://github.com/org/some-user-project.git",
        "project_root": "."
      },
      "targets": [
        {
          "release": "v4.30.0",
          "ref": "0123456789abcdef0123456789abcdef01234567",
          "publish_reference": true
        }
      ],
      "build_command": ["lake", "build", "SomeUserProject"],
      "generate_command": ["lake", "lean", "SomeUserProjectMain.lean", "--", "--run", "SomeUserProjectMain.lean", "--output", "{output_dir}"],
      "site_subdir": "html-multi"
    }
  ]
}
```

The `lake lean <file> -- --run <file>` form is intentionally the catalog default
for reference projects. It still requires the imported Lean modules to have been
built first, but it avoids Lake's executable build path and the transitive native
compilation cost that can dominate Mathlib-heavy projects.

That override policy is now the default maintainer behavior: the external
projects keep their committed dependency pointed at an approved upstream repo,
while the harness swaps in a local path dependency ephemerally during
validation.

## Preview Data Artifacts

Each generated Blueprint site includes semantic preview data and the
rendered-fragment cache at:

- `html-multi/-verso-data/blueprint-manifest.json`
- `html-multi/-verso-data/blueprint-html-cache.json`

See [`MANUAL.md`](./MANUAL.md) for the file semantics and executable
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
3. Read [`API.md`](./API.md) for stable Lean, generated-data, and browser APIs.
4. Return here for repository-local commands, outputs, and worktree behavior.
5. Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) for branch, commit, PR, and
   local coordination conventions.
6. Read [`DESIGN_RATIONALE.md`](./DESIGN_RATIONALE.md) before touching
   architecture boundaries.
7. Read [`ROADMAP.md`](./ROADMAP.md) before starting structural cleanup.
