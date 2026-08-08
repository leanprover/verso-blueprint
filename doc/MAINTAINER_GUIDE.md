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
Planned cleanup and follow-up work live in [`ROADMAP.md`](./ROADMAP.md) and the
card index under [`roadmap/`](./roadmap/).

## Scope

This is a maintainer document for this repository. It is not the end-user guide
for starting a Blueprint project or learning every Blueprint directive.

## Command Model

The shell wrappers are the normal front door for day-to-day work. The Python
modules are the canonical source for flags, path resolution, and orchestration:

- `blueprint_harness` handles worktrees, branch/release checks, PR scaffolds,
  landing, toolchain bumps, and local coordination
- `blueprint_reference_harness` composes editable user-provided Blueprints and
  handles reference-project generation, validation, status, sync, editable
  checkouts, pin bumps, and pruning
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

`lake exe vbp check` is an audit of an already-generated artifact boundary, not
a repair phase or a required second half of normal generation. Production
generation constructs the manifest and rendered-fragment cache together and
finalizes their preview references before emission. Use `check` when validating
persisted, copied, or externally supplied output; it deliberately performs
stricter cross-artifact and graph-projection checks than ordinary semantic
queries. The graph-backed `work-queue` selector also retains strict graph
decoding; graph-free selectors avoid materializing graph projections. Query
arguments are parsed into a validated plan before any generated file is read,
so unknown or malformed selectors fail without paying manifest-decoding cost.

Treat `vbp` JSON as fully unstable. It may change within this repository as
agent workflows evolve, and is not part of the documented integration API.
Prefer in-band discovery through `lake exe vbp --help`,
`lake exe vbp discover`, and `lake exe vbp query selectors` instead of copying
selector lists or JSON shapes into long-lived docs.

The two generated artifact families serve different purposes:

- reference blueprints are known Blueprint projects built and published as
  release validation examples; release targets in `branch-policy.json` and
  project targets in `tests/harness/projects.json` decide which projects are
  built and published for each Lean release line
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
the `publish_reference` flag, and the exact `reference_toolchain` when an
external project is behind VBP within the same release family.
Matrix emitter scripts derive effective per-project `toolchain` and `verso_ref`
values from those two files. A project-target `rc` is reserved for VBP's own
in-repository fixtures, which move in lockstep with VBP. External reference
projects never select the VBP/Verso ref: their `reference_toolchain` controls
only the effective compiler, while the release target continues to control
VBP/Verso.

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

The tracked owner inventory lives in `EMBEDDED_ASSET_OWNERS` in
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

To work on this package together with an editable user-provided Blueprint,
compose the external checkout directly rather than registering it in the
reference catalog:

```bash
python3 -m scripts.blueprint_reference_harness compose /path/to/source-checkout \
  --project-root blueprint \
  --id local-blueprint
```

The command builds the editable source against the current `VersoBlueprint`
checkout, writes `_out/.../reference-blueprints/local-blueprint/`, and runs
`vbp check`. Each run replaces that generated output so removed pages cannot
survive from an older composition. A custom output root must remain disjoint
from the source checkout; `compose` rejects output directories that contain or
sit inside that checkout. The command temporarily overrides either an official
Git dependency or a relative `verso-blueprint` path and restores the source
checkout's lakefile and manifest afterwards. The nearest `lean-toolchain`
inside the source checkout must select exactly the same Lean release as this
`VersoBlueprint` checkout; `compose` reports a mismatch without rewriting
either toolchain.

When the composed Lake graph contains Mathlib, the harness requires a
successful `lake exe cache get` before starting the build. This guarantees that
cache retrieval succeeds at command level before composition. Mathlib treats
individual remote-cache misses as warnings, however, so the harness cannot
currently prohibit Lake from compiling an unavailable artifact afterwards.

`compose` is intentionally independent of `tests/harness/projects.json`.
Projects belong in that manifest only when they are maintained release
validation or publication inputs.

Pass `--verbose` to `compose`, `generate`, or `validate` when you want each
Blueprint generator to print its own progress diagnostics during HTML
emission.

Pass `--record-build-metrics` to `generate` or `validate` when the phase
timings need to be retained. This option also enables generator `--verbose`
output, tees the normal build log unchanged, and writes `build-metrics.json`
beside each generated project artifact. The record contains the total
generator-command duration plus every canonical
`Blueprint: finished <phase> in <milliseconds>ms` measurement emitted by the
generator. In particular, single-page and multi-page HTML traversal remain
separate measurements rather than being inferred from the surrounding Lake
build time.

Reference Blueprint CI enables this recording by default. It aggregates the
per-project files into the Actions job summary and the published
`/build-data/reference-blueprints.json` report. The report retains the latest
50 snapshots and compares a run with the currently deployed baseline when the
reference source revision and Lean toolchain match. A total-command or phase
increase is marked as a regression warning only when it exceeds both 20
percent and one second; warnings are initially advisory so ordinary
hosted-runner variation cannot block a release. Full command and phase data
remains available in JSON even when a value does not cross the warning
threshold.

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

`python3 -m scripts.blueprint_test_blueprints list-json` reports the standalone
fixture manifest without invoking Lean. Curated-document metadata comes from
the Lean registry and is validated once, before `generate-test-blueprints.sh`
starts rendering artifacts.

### Prepare or Land PRs

Use the harness to generate public PR/backport scaffolds:

```bash
python3 -m scripts.blueprint_harness prepare-pr
python3 -m scripts.blueprint_harness prepare-backports
python3 -m scripts.blueprint_harness prepare-backport-pr v4.32.0 --main-pr <pr>
python3 -m scripts.blueprint_harness prepare-backport-pr --all-required --main-pr <pr>
```

Use `git cherry-pick -x` for paired backport branches so the paired-backport
check can verify recorded source SHAs, commit count, and commit order. The
check intentionally does not require patch-id equality, because release-line
conflict resolution often changes the exact diff while preserving provenance.

Each paired backport PR should carry the scaffolded release label, such as
`backport-v4.32.0`, so release-specific queues remain visible when several
maintenance lines are active.

A change limited to `tests/harness/projects.json` updates release-specific
catalog metadata and may use an explicit backport exemption; do not recreate
that catalog target on older release branches. If the same PR changes scripts,
other tests, templates, or runtime files, it still requires the normal paired
backport.

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
python3 -m scripts.blueprint_harness bump-toolchain 4.32-rc2
python3 -m scripts.blueprint_harness bump-toolchain v4.32.0 --skip-validation
```

That command rewrites the managed `lean-toolchain` files, rewrites the root
package's direct `require verso` pin, refreshes the committed manifests for the
root package, `project_template`, and
`tests/test_blueprints/preview_runtime_showcase/`, and by default runs the same
build/test validation pass that maintainers would otherwise do manually. It
also synchronizes the current release target's RC metadata for in-repo
reference projects; external project RC overrides remain explicit. Release
candidates use the official short RC name, for example `4.32-rc2`; the harness
writes the corresponding Lean and `verso` tag ref, such as `v4.32.0-rc2`.
The requested toolchain must belong to the checkout's current release line.
Pass `--verso-ref <tag>` only when the Lean toolchain ref and upstream `verso`
release tag need to differ.

### Start a New Lean Release Line

When Lean opens a new release line, create the new branch from the previous
default-development branch, then let the harness do the branch-local release
setup:

```bash
python3 -m scripts.blueprint_harness start-release-line 4.33-rc2
```

Run this from the new local branch, for example `v4.33.0`. The command:

- rewrites the managed `lean-toolchain` files, the root `verso` pin, and the
  committed manifests for the root package, `project_template`, and the
  preview showcase
- updates `branch-policy.json` so the new branch is the default-development
  line, the previous default-development branch becomes a required backport
  target, and the new release target is recorded
- adds the new release target to in-repo CI fixtures such as
  `project-template` and records their RC override while the root package is on
  a release candidate; fixtures remain explicitly selectable for validation
  but are not added to the public reference catalog

For release candidates, use the official short RC name such as `4.33-rc2`.
The branch name remains the stable release branch, for example `v4.33.0`, while
the command pins the managed root-package files to `v4.33.0-rc2`.

External reference projects are not auto-pinned for a new release line. Add
their release-target refs only after those repositories have been updated and
validated on the new Lean release. If an external project still uses a release
candidate while VBP has moved further within that release family, record its
exact compiler, for example `"reference_toolchain": "v4.33.0-rc1"`, on that
project target in `tests/harness/projects.json`.

Do not backport the branch-start commit to older release lines: that commit
changes the actual Lean toolchain. Instead, update only the tracked branch
policy metadata on each older release branch so the harness recognizes them as
backport-only:

```bash
python3 -m scripts.blueprint_harness set-default-dev-branch <new-default-dev-toolchain>
```

Use the exact command printed by `start-release-line`. For version 2 policies,
`set-default-dev-branch` also adds the new branch's baseline release target when
the older checkout does not have it yet and adds the corresponding target to
in-repo project metadata. Passing the printed RC ref preserves its target-level
RC pin. The command preserves the older checkout's own Lean toolchain, existing
release targets, and required-backport list.

Commit that metadata-only change separately on each older branch that still
carries `branch-policy.json`, such as `v4.32.0`. Preserve their own Lean
toolchain pins.

When retiring old maintenance lines from an existing release branch, use
`Backport ...: release-line retirement` for each removed line. The check
accepts this only when the default Lean toolchain and branch stay fixed, the
removed branches are the oldest contiguous suffix of the maintenance sequence,
and all remaining release targets are unchanged. This makes the policy
transition self-validating without constructing obsolete backport projects
solely to satisfy the policy being removed.

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

## External Reference Cache Ownership

Every selected external git-checkout project source has one
`reference_source_identity`. Its readable prefix comes from the catalog project
id, and its digest is derived from the repository URL, project root, and
selected source ref. The identity
intentionally does not include the current Verso Blueprint checkout or release
label: all paths below represent the same pinned external source. The reference
and deploy CI matrices serialize this identity together with its canonical
dependency paths so local and CI cache layouts agree.

| Role | Path | Ownership |
| --- | --- | --- |
| Disposable source checkout | `.worktrees/_reference-blueprints/cache/<source-identity>/` | Shared; refreshed by `sync` and safe to prune |
| Warmed dependencies | `.worktrees/_reference-blueprints/deps/<source-identity>/{packages,path-builds}/` | Shared; remains resident while consumers are seeded |
| Validation checkout | `.worktrees/_reference-blueprints/by-worktree/<checkout>/<source-identity>/` | Owned by one root checkout or linked worktree |
| Generated site | `_out/.../reference-blueprints/<project-id>/` | Output artifact; never stored in a dependency cache |

Dependency packages and path-dependency build trees are copied from the shared
cache into each validation checkout. The harness never moves them or lends
their ownership to a consumer. Consequently, multiple worktrees can seed from
one warmed cache, and a failed or interrupted generation does not have to move
packages back to make the cache usable again. Cache warm-up may refresh shared
contents with `rsync`; this ownership rule does not yet provide transactional
publication for simultaneous writers.

Maintainer `sync`, `generate`, and `validate` operations involving external
git-checkout projects require `rsync` on `PATH`. The harness checks this before
starting external checkout or cache work and reports a focused diagnostic when
it is unavailable.

After warm-up, the disposable source checkout's duplicate `.lake/packages/`
tree is removed once it has been copied into the dependency cache. This deletes
only the source checkout's copy, not the shared dependency cache. CI likewise
keeps the shared dependency tree resident while a per-job checkout uses its own
copy. The additional peak disk use is an intentional tradeoff for predictable
ownership and failure behavior.

## Working from Linked Worktrees

For implementation work, create a linked worktree under `.worktrees/` and keep
the root checkout as the stable base:

```bash
python3 -m scripts.blueprint_harness create-worktree <name>
```

After `git worktree add`, that command syncs the root checkout's `.lake/` and
prepares the shared and per-worktree reference blueprint clones without running
external reference project builds. New worktrees now base off the branch policy's
preferred default-development ref, `origin/<default-dev-branch>`.
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

PR title/body, backport, and landing policy lives in
[`CONTRIBUTING.md`](./CONTRIBUTING.md#pull-request-conventions). This section is
only the maintainer command reference for producing the scaffolded text and
checking the generated backport plan.

For a new default-development PR, generate the public-facing scaffold with:

```bash
python3 -m scripts.blueprint_harness prepare-pr
```

The helper prints the public repository, base branch, PR title, and PR body. Use
that output as the source of truth for the public PR description; keep local
worktree notes and routine validation transcripts out of the body unless they
change review risk.

For an existing PR where only the backport lines need a refresh, run:

```bash
python3 -m scripts.blueprint_harness prepare-backports
```

Paste the emitted backport lines into the PR body. `CONTRIBUTING.md` owns which
lines may remain `pending`, when to replace them with paired PR numbers, and when
an exemption is acceptable.

To create one paired backport scaffold, run:

```bash
python3 -m scripts.blueprint_harness prepare-backport-pr v4.32.0 --main-pr <pr>
```

That helper prints a standardized paired branch name, a title of the form
`[backport v4.32.0] ...`, a `backport-v4.32.0` release label, and a PR body
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

The `Paired Backport` CI check consumes those scaffolded links and
`git cherry-pick -x` provenance. It verifies the paired PR target branch,
non-draft status, source commit SHAs, commit count, commit order, and paired PR
check state; it deliberately does not compare patch IDs.

To land one reviewed branch onto the active release branch safely from the root
checkout, use:

```bash
python3 -m scripts.blueprint_harness land-release feat/some-branch
python3 -m scripts.blueprint_harness land-release feat/some-branch --cleanup
```

`land-release` refuses to proceed unless the root checkout is on a clean,
in-sync local release branch such as `v4.32.0`, and it only accepts
fast-forward source refs. With `--cleanup`, it also removes the source worktree
and deletes the source branch when that can be done safely.

After creation, ordinary `generate` and `validate` runs reuse the worktree's
current `.lake/`; they do not automatically resync it from the root checkout.

The harness is worktree-aware:

- in a linked worktree it writes artifacts to `_out/<worktree>/...`
- by default it prefers reusing the root checkout's prepared package `.lake`
  artifacts and binaries
- external reference projects follow the shared-source and per-worktree
  ownership model described in
  [External Reference Cache Ownership](#external-reference-cache-ownership)
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
- if an interrupted retirement removed the checkout directory but left Git's
  worktree metadata behind, rerun it with `--merged-pr <number>`; the harness
  verifies the merged PR, prunes the stale worktree entry, and finishes branch
  and reference-cache cleanup
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
- shared cache and validation-checkout paths obey
  [External Reference Cache Ownership](#external-reference-cache-ownership)
- editable reference-project clones live separately under
  `.worktrees/_reference-blueprints/edit/<checkout>/` and are not touched by
  `sync`, `generate`, or `prune`
- `prune` cleans up stale project caches and local clones when worktrees or
  manifest entries disappear
- the Python harness rewrites the cloned project's `lakefile.lean` locally so
  `VersoBlueprint` resolves to the checkout under test before running
  `lake update`
- external reference repositories should commit `lake-manifest.json`; when that
  tracked manifest is present, the harness runs a full update from those
  committed pins, so fixed direct inputs remain pinned while the local
  `VersoBlueprint` dependency and its transitive graph are refreshed
- the selected package and external project's `lean-toolchain` files are
  immutable harness inputs; external-project flows reject missing toolchains,
  cross-release pairs, and catalog/toolchain mismatches instead of rewriting
  either file
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
pull requests and pushes to release branches named like `v4.32.0`:

- `Blueprint Build`
- `Blueprint Tests`
- `Harness Tests`

`Harness Tests` is intentionally Python-only: ordinary `unittest` discovery
must not invoke Lean or Lake. `Blueprint Tests` owns explicit Lean execution
smokes, while the Lean-backed curated-document registry is exercised and
checked against the shared test-blueprint category/tag vocabulary by `Build
Test Blueprints` before it generates the artifact catalog.

On pull requests it also runs `Project Template Fresh Repo`, which materializes
the in-repo template as a fresh standalone repository and smoke-tests the
template-owned CI path.

`reference-blueprints.yml` is the shared build workflow. On pull requests,
pushes to release branches named like `v4.32.0`, and manual dispatch, it:

- resolves the triggering branch's release target from `branch-policy.json`
- uses the triggering checkout's catalog on the default-development line, but
  reads the default-development branch's controller catalog for maintenance
  lines so stale branch-local targets cannot recreate retired Blueprint builds
- builds only project targets for that release that set
  `publish_reference: true`
- passes each selected target to the release-branch harness through an exact
  generated one-project manifest, preserving the controller ref and effective
  reference toolchain
- builds `pdf/main.pdf` for those reference targets, using the workflow's
  installed TeX toolchain
- builds the local `test-blueprints/` artifact set, including
  `preview_runtime_showcase`
- stages a branch-local site artifact under `_site/` only when the selected
  release target has `deploy_pages: true`
- uploads that assembled site as a normal workflow artifact
- generates external references from per-job local clones using the same
  [source identity and ownership model](#external-reference-cache-ownership)
  as local worktrees

`reference-blueprints-deploy.yml` is the deployment workflow. It runs after a
successful `reference-blueprints.yml` run on a release branch named like
`v4.32.0`, checks out the repository default-development branch as the source
of truth for deployment policy, resolves every release target with
`deploy_pages: true`, selects project targets marked `publish_reference: true`,
rebuilds those selected blueprints in isolation, and assembles one combined
GitHub Pages artifact. The per-project target entry is the source of truth for
the project id, release, pinned ref, and publication flag. For each deploy
matrix entry, the workflow writes a small one-project manifest from that
default-development catalog and passes it to the release-branch harness with
`--manifest`; the deploy job therefore does not rely on stale branch-local
`projects.json` refs. The per-project target entry also owns the exact external
reference toolchain, so two projects in the same release family can use
different compilers while sharing the release target's VBP/Verso ref. Deploy
one-project manifests append `--pdf` to the
selected generator command only for the default-development release target, so
the current published catalog includes PDFs while archived release targets stay
HTML-only unless their deploy policy is deliberately expanded.

All runs of the deploy workflow share one repository-wide concurrency group
because every run replaces the same combined Pages site. A deploy matrix entry
first computes an exact generated-site identity from the release id, project
id, complete generated one-project manifest, and checked-out release-branch
commit. The workflow restores only the cache key for that exact identity; it
does not use prefix or stale fallback keys. On a cache miss, normal generation
runs and installs the identity metadata before saving the generated site. On a
cache hit, toolchain installation, dependency restoration, external checkout,
and generation are skipped.

Before assembling Pages, the staging job independently recomputes the expected
identities from the current catalog and fetched release-branch heads. It rejects
missing, unexpected, tampered, or non-matching artifacts and removes the
identity metadata from the public site. This permits a trusted last-known-good
generated site to cover a temporary upstream outage only while every relevant
pin and generator revision remains exactly unchanged.

The current published project/release split is intentionally not duplicated
here. Read `tests/harness/projects.json`; every project target marked
`publish_reference: true` is part of the deployed catalog for that target's
release.

The branch-local site artifact produced by `reference-blueprints.yml` for one
release includes:

- `_site/index.html`
- `_site/reference-blueprints/<project-id>/` for each deployable reference
  target selected on that branch
- `_site/reference-blueprints/<project-id>/pdf/main.pdf` for each deployable
  reference target selected on that branch
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
  reference target across all deployable release targets
- `_site/reference-blueprints/<release-id>/<project-id>/pdf/main.pdf` for each
  selected reference target whose deploy matrix entry enables `publish_pdf`
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

For either input shape, it copies `pdf/main.pdf` next to the staged HTML and
adds an index link only when that PDF exists.

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
- prefer `lake exe vbp build` for package-local generation; if the harness must
  drive an external project explicitly, build only the Blueprint library's OLean
  dependency closure with `lake build +<BlueprintLibrary>:olean`, followed by
  `lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean ...` when the
  harness must drive an external project explicitly; do not use Lake's default
  `leanArts` facet because it also emits C
- the harness currently rewrites the cloned `lakefile.lean` dependency line so
  external test projects exercise the local `VersoBlueprint` checkout instead
  of the committed upstream dependency
- the external project's top-level `lean-toolchain` selects its compiler; the
  harness validates that it exactly matches the project target's
  `reference_toolchain` (or the release baseline when that field is omitted),
  belongs to the same Lean release family as VBP, and is not newer than VBP;
  the harness never promotes an RC project or rewrites dependency toolchains
- the current local override injection expects a `lakefile.lean` project that
  declares `VersoBlueprint` from the official `leanprover/verso-blueprint` Git
  repository, and it tolerates different Git refs and URL spellings for that
  source
- local worktree bookkeeping is intentionally not tracked in the repository

The compatibility rule is monotonic within one Lean release family. If VBP's
subversion is older than the reference project's subversion, validation fails
and the VBP maintainers must bump VBP. If VBP is equal or newer, the reference
project's exact toolchain remains the effective compiler. For example, a
`v4.33.0` VBP release may build an external project with
`"reference_toolchain": "v4.33.0-rc1"`; VBP/Verso stay on `v4.33.0`, while the
wrapper, formalization, Mathlib artifacts, and build all stay on `v4.33.0-rc1`.
Cross-family combinations such as VBP `v4.34.0` with a `v4.33.0` reference are
always rejected.

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
          "release": "v4.32.0",
          "ref": "0123456789abcdef0123456789abcdef01234567",
          "publish_reference": true
        }
      ],
      "generate_command": ["lake", "exe", "vbp", "build", "--output", "{output_dir}"],
      "site_subdir": "html-multi"
    }
  ]
}
```

`lake exe vbp build --output <dir>` is the catalog default for external
Blueprint projects. The project-owned `vbp` configuration is the source of
truth for its generation instructions; the harness must not replace it with a
guessed generator entry point or a separate broad build command.

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
3. Read [`API.md`](./API.md) for documented Lean, generated-data, and browser APIs.
4. Return here for repository-local commands, outputs, and worktree behavior.
5. Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) for branch, commit, PR, and
   local coordination conventions.
6. Read [`DESIGN_RATIONALE.md`](./DESIGN_RATIONALE.md) before touching
   architecture boundaries.
7. Read [`ROADMAP.md`](./ROADMAP.md) and [`roadmap/`](./roadmap/) before
   starting structural cleanup.
