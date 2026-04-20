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
  - paired `v4.28.0` backport branch: `fix/backport-v428-backport-discipline`
  - default-dev docs branch: `docs/manual-cleanup`
  - paired `v4.28.0` docs backport branch: `docs/backport-v428-manual-cleanup`

Prefer short, descriptive slugs over opaque branch names.

## Commit Conventions

Prefer concise imperative subjects in the form:

```text
type(scope): summary
```

Examples:

- `feat(harness): add local worktree registry commands`
- `fix(preview): preserve inline proof-gap precision`
- `docs(maintainer): document worktree claim workflow`

Keep the subject line tight enough for `git log --oneline`. Avoid generic
subjects such as `Update files` or `misc cleanup`.

## Pull Request Conventions

- PR titles should usually match the intended squash-merge commit title.
- PR bodies should state:
  - the problem
  - the scope of the change
  - validation performed
  - notable risks or follow-up
- When the work came from a local worktree, include the worktree name and write
  scope in the PR body or draft notes.
- Draft PRs targeting `v4.29.0` must declare one backport plan line for each
  required backport release branch listed in `branch-policy.json`.
- Non-draft PRs targeting `v4.29.0` must replace each `pending` entry with a
  paired backport PR number or an explicit exemption reason.
- The default-development PR is the primary review surface. Paired backport PRs
  exist mainly so CI and merge state are visible on the maintenance line.
- The expected workflow is:
  - keep the `v4.29.0` PR in draft while the change is still converging
  - run `python3 -m scripts.blueprint_harness prepare-backports` and paste the
    emitted lines into the draft PR body
  - once it is ready for review, open the paired `v4.28.0` PR
  - replace each `Backport ...: pending` line with `Backport ...: #<pr>` or
    `Backport ...: exempt: <reason>`
  - wait for CI on both PRs before merging the `v4.29.0` PR
- Keep review comments and design discussion on the default-dev PR unless the
  backport itself diverges materially, for example because of a conflict or a
  release-line-specific adaptation.
- Record the pairing in the PR body using lines like:
  - `Backport v4.28.0: pending`
  - `Backport v4.28.0: #123`
  - `Backport v4.28.0: exempt: docs-only change`

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
`worktree-sync` remains available as a compatibility alias for
`worktree-list`.

By default, only clean up worktrees or branches created or landed by the
current session. Do not retire or delete unrelated local worktrees unless the
owner or the user explicitly asks for that cleanup.

Local metadata lives under ignored `.worktrees/` paths:

- `.worktrees/registry.json`
- `.worktrees/_meta/_root.json`
- `.worktrees/_meta/<name>.json`

Treat `.worktrees/_meta/*.json` as the source of truth for local coordination
fields such as owner, lock state, priority, summary, status, and write scope. Treat
`.worktrees/registry.json` as a generated dashboard snapshot that combines that
local metadata with live Git state. None of that data is tracked in Git.
