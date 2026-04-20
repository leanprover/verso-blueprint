## Summary

Describe the user-visible or maintainer-visible outcome in 1-3 sentences.

## Problem

What was wrong, missing, or confusing before this change?

## Scope

- What changed
- What intentionally did not change

## Validation

- Commands run
- Manual checks performed
- External projects or worktrees exercised

## Primary Review

For paired backport PRs:

- Primary review: #<default-dev-pr>
- Keep discussion there unless this backport diverges materially.

## Backports

Draft `v4.29.0` PRs should declare one line per required backport target as
soon as the draft exists. While the PR is still draft, `pending` is allowed:

- `Backport v4.28.0: pending`
- `Backport v4.28.0: exempt: <reason>`

Once a `v4.29.0` PR is ready for review, replace each `pending` line with:

- `Backport v4.28.0: #123`
- `Backport v4.28.0: exempt: <reason>`

## Backport Delta

For paired backport PRs:

- No intentional release-specific changes
- Or describe the release-line-specific adaptation

## Risks and Follow-Ups

- Known limitations
- Cleanup that should happen in a later PR

## Coordination

- Issue:
- Worktree:
- Write scope:
