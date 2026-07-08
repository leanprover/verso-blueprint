# Contributing

This repository keeps local parallel work simple:

- one linked worktree per feature or fix branch
- `.worktrees/` metadata as the local, untracked coordination layer for you and
  Codex
- pull requests as the durable review and merge artifact

## Branch Conventions

- `branch-policy.json` is the tracked source of truth for the repository's
  default development branch.
- If a checkout's `lean-toolchain` release line differs from
  `branch-policy.json.default_dev_branch`, treat that checkout as backport-only
  and keep changes scoped to backports or explicit branch-policy maintenance.
- Use `python3 -m scripts.blueprint_harness require-branch-role default_dev`
  when you want automation to block non-backport work on backport-only lines.
- Use `feat/<slug>` for user-facing or architectural changes.
- Use `fix/<slug>` for bug fixes.
- Use `docs/<slug>` for documentation-only work.
- Use `chore/<slug>` for maintenance and cleanup.
- Use `wip/<slug>` only for local-only exploratory branches that are not ready
  for review.
- For paired backport branches, keep the same top-level prefix and reuse the
  default-dev slug with a release marker in front of it.
  Examples:
  - default-dev branch: `fix/backport-discipline`
  - paired `v4.30.0` backport branch: `fix/backport-v430-backport-discipline`
  - default-dev docs branch: `docs/manual-cleanup`
  - paired `v4.30.0` docs backport branch: `docs/backport-v430-manual-cleanup`

Prefer short, descriptive slugs over opaque branch names.

## Commit Conventions

Follow Lean upstream's commit convention for public commit and PR titles. Use
concise imperative subjects in the form:

```text
type: summary
```

Use the Lean title types `feat`, `fix`, `doc`, `style`, `refactor`, `test`,
`chore`, and `perf`. Do not add a type scope such as `feat(entry): ...`; put
the affected area in the subject instead.

Examples:

- `feat: add local worktree registry commands`
- `fix: preserve inline proof-gap precision`
- `doc: document worktree claim workflow`

Keep the subject line tight enough for `git log --oneline`. Use imperative,
present tense; do not capitalize the first letter; do not end the subject with
a period. Avoid generic subjects such as `Update files` or `misc cleanup`.

## Verso Upstream Backlog

This repository tracks eventual upstream work in
[`doc/UPSTREAM_BACKLOG.md`](./UPSTREAM_BACKLOG.md).

When a maintainer or agent says "add this to the Verso upstream backlog",
"register this in the Verso upstream backlog", or similar, that means:

- add or update an item in `doc/UPSTREAM_BACKLOG.md`

It does not mean:

- open an upstream GitHub issue
- comment on an upstream pull request
- otherwise mutate the upstream `leanprover/verso` repository

Do those upstream write actions only when they are explicitly requested.

## Pull Request Conventions

- PR titles should follow the same Lean-style `type: summary` format and should
  usually match the intended final commit title.
- Avoid generator/tool prefixes such as `[codex]`; the title should describe
  the change, not who or what drafted it.
- For a draft default-development PR, generate the public-facing title/body
  scaffold with `python3 -m scripts.blueprint_harness prepare-pr`.
- PR title and body are used as the final public commit message when the PR is
  squashed, and should still be suitable for permanent history when the PR is
  merge-committed.
- Start the PR body with a short paragraph beginning `This PR ...`; include the
  motivation and contrast with previous behavior there.
- Use extra paragraphs or bullets only when they help explain the main
  user-visible or maintainer-visible change. Do not make the body a
  module-by-module implementation inventory.
- If the PR includes measurements, explain what changed and why the numbers
  matter before listing the raw before/after values.
- Do not add a routine validation transcript. CI is the default validation
  record. Mention manual checks only when they add information CI cannot show,
  or mention skipped checks when that changes the review risk.
- Put questions, local notes, and extra review coordination in comments rather
  than the PR description.
- When the work came from a local worktree, include the worktree name and write
  scope in local draft notes only when it helps coordination; do not require
  public reviewers to understand local worktree bookkeeping.
- Draft PRs targeting the default-development branch must declare one backport
  plan line for each required backport release branch listed in
  `branch-policy.json`.
- Non-draft PRs targeting the default-development branch must replace each
  `pending` entry with a paired backport PR number or an explicit exemption
  reason.
- Exemptions are limited to changes whose files are all documentation or
  repository metadata. Source, scripts, tests, templates, package
  configuration, and runtime assets require paired backports so maintenance
  lines remain structurally aligned for future cherry-picks.
- Backported default-development PRs should normally be landed with a merge
  commit rather than squash or rebase, so the source commits recorded by
  `git cherry-pick -x` remain present in default-dev history.
- Squash merge remains appropriate for changes with no required paired
  backports, or when every required backport is explicitly exempt.
- The default-development PR is the primary review surface. Paired backport PRs
  exist mainly so CI and merge state are visible on the maintenance line.
- Paired backport branches should be built with `git cherry-pick -x` so every
  backport commit records the source commit SHA from the default-development PR.
- The paired-backport check verifies the paired PR target branch, non-draft
  status, source commit SHAs, commit count, and commit order. It deliberately
  does not compare patch IDs, because normal release-line conflict resolution
  can change the exact diff while preserving the reviewed cherry-pick series.
- The expected workflow is:
  - keep the default-development PR in draft while the change is still converging
  - run `python3 -m scripts.blueprint_harness prepare-pr` and use the emitted
    public title/body scaffold
  - use `python3 -m scripts.blueprint_harness prepare-backports` only when you
    need to refresh just the backport plan lines in an existing PR body
  - once it is ready for review, open the paired backport PRs
  - use `python3 -m scripts.blueprint_harness prepare-backport-pr v4.30.0 --main-pr <pr>` to scaffold one paired backport PR branch name, title, and body
  - apply the scaffolded release label, for example `backport-v4.30.0`, to the
    paired backport PR
  - when several releases are required, use `python3 -m scripts.blueprint_harness prepare-backport-pr --all-required --main-pr <pr>` to emit one scaffold block per release, then let the agent apply the `git cherry-pick -x` series and resolve conflicts in each backport worktree
  - replace each `Backport ...: pending` line with `Backport ...: #<pr>`, or
    use `Backport ...: exempt: <reason>` only for documentation/metadata-only
    changes
  - wait for CI on the default-development PR and required paired PRs before
    merging the default-development PR
- Keep review comments and design discussion on the default-dev PR unless the
  backport itself diverges materially, for example because of a conflict or a
  release-line-specific adaptation.
- Record the pairing in the PR body using plain lines like:

```text
Backport v4.30.0: pending
Backport v4.30.0: #122
Backport v4.30.0: exempt: docs-only change
```

See the repository PR template for the preferred structure.

## Local Worktree Coordination

For local maintainer automation, keep the CLI split in mind:

- use `python3 -m scripts.blueprint_harness ...` for worktree management,
  branch landing, and local coordination metadata
- use `python3 -m scripts.blueprint_reference_harness ...` for reference
  project generation, validation, cache sync, and editable reference clones

Use the harness commands to manage local coordination metadata:

```bash
python3 -m scripts.blueprint_harness worktree-list
python3 -m scripts.blueprint_harness create-worktree <name> --owner <name> --lock --priority P1 --summary <text> --scope <path>
python3 -m scripts.blueprint_harness worktree-claim --lock --priority P0 --summary <text>
python3 -m scripts.blueprint_harness worktree-status
python3 -m scripts.blueprint_harness worktree-release
```

`worktree-list` already refreshes local metadata before printing the dashboard.
For exact output paths, metadata-file roles, retire conditions, and reference
cache behavior, see
[`MAINTAINER_GUIDE.md#parallel-worktree-coordination`](./MAINTAINER_GUIDE.md#parallel-worktree-coordination).

By default, only clean up worktrees or branches created or landed by the
current session. Do not retire or delete unrelated local worktrees unless the
owner or the user explicitly asks for that cleanup.
