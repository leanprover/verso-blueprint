# Project Notes

## Scope

- Repository root: `/home/egallego/lean/verso-blueprint`
- This repository is the standalone `verso-blueprint` package root.
- Primary work areas:
  - `src/VersoBlueprint`
  - `tests`
  - `tests/browser`
  - `scripts`
  - `doc`
- The tracked default-development branch is stored in `branch-policy.json`.

## Branch Policy

- `branch-policy.json` is the tracked source of truth for the repository's
  default development branch.
- The current checkout's release line comes from `lean-toolchain`.
- If the current checkout's release line differs from
  `branch-policy.json.default_dev_branch`, treat the checkout as backport-only.
- In a backport-only checkout, do not do new feature or cleanup work unless the
  user explicitly asks for a backport or branch-policy maintenance.
- Use `python3 -m scripts.blueprint_harness release-status` when you need the
  resolved branch policy for the current checkout.
- Use `python3 -m scripts.blueprint_harness require-branch-role default_dev`
  before non-backport implementation work when you want an explicit machine
  check.

## Worktree Policy

- Start new implementation work in a linked worktree under `.worktrees/`, not in
  the root checkout.
- Treat the root checkout as the stable base used to seed worktrees, sync
  shared `.lake` artifacts, and host shared preview output.
- If a task starts in the root checkout and requires code changes, stop before
  editing and move the work into a linked worktree unless the user explicitly
  asks to work on the root checkout itself.
- Create linked worktrees only via `python3 -m scripts.blueprint_harness create-worktree <name>`.
- Do not create sibling checkouts or ad hoc `git worktree add` paths unless you
  are debugging the harness itself.
- Worktree preview output should be written to the repository-root
  `_out/<worktree>/`.
- Do not keep a tracked worktree dashboard at the package root.
- Keep local coordination state untracked under `.worktrees/`.
- Preferred local coordination files:
  - `.worktrees/registry.json`
  - `.worktrees/_meta/_root.json`
  - `.worktrees/_meta/<name>.json`
- `/home/egallego/lean/verso-blueprint-old/WORKTREE_DASHBOARD.md` is archival
  only; do not update it unless the user explicitly asks for archival work.
- Feature and legacy worktree branches are local-only by default. Do not push
  any branch to `origin` unless the user explicitly asks for that push.

## Pull Request Submission

- Before opening or editing a default-development PR, run
  `python3 -m scripts.blueprint_harness prepare-pr` and use the emitted public
  PR title/body scaffold as the source of truth.
- Before opening a paired backport PR, run
  `python3 -m scripts.blueprint_harness prepare-backport-pr <release> --main-pr <pr>`
  and use the emitted paired title/body scaffold.
- `Backport <release>: pending` placeholders from `prepare-pr` are only
  acceptable while the default-development PR is draft. Before marking a
  default-development PR ready for review, replace every pending backport line
  with either `Backport <release>: #<pr>` or
  `Backport <release>: exempt: <reason>`.
- Use exemptions only when every changed file is documentation or repository
  metadata. Source, scripts, tests, templates, package configuration, and
  runtime assets require paired backports so later backports do not accumulate
  avoidable structural conflicts.
- For changes that need paired backports, open the paired backport PRs before
  the default-development PR leaves draft, then wait for the paired-backport CI
  check to pass before merging.
- `prepare-backport-pr --main-pr <pr>` derives the source branch and commit
  series from the PR, including after merge. Use `--source-branch` only as an
  explicit fallback when GitHub metadata is unavailable.
- Do not hand-roll PR descriptions from local status notes or validation
  transcripts. Keep routine validation details in local/final reports unless
  they change review risk or CI cannot show them.
- Do not add generator or tool prefixes such as `[codex]` to public PR titles.
- Keep local worktree names, write-scope notes, and coordination details out of
  public PR bodies unless they materially help review.

## Release Status

- The code is near release.
- The external reference blueprints live in their own repositories:
  `ejgallego/verso-noperthedron`, `ejgallego/verso-sphere-packing`,
  `ejgallego/verso-flt`, and `ejgallego/verso-carleson`.
- A smaller starter example, a reusable template, and `lake exe bp new` are
  planned but not landed yet.
- Published reference-blueprint project/release targets are declared in
  `tests/harness/projects.json`; use
  `python3 -m scripts.blueprint_reference_harness projects` instead of
  hardcoding the active catalog.
- End-user docs should treat `lake exe vbp build` as the preferred Blueprint
  generation interface.
- End-user docs should not require Python helper scripts or a system Graphviz
  installation for normal package usage.
- End-user docs should also explain the current standard Verso workflow
  honestly: a Blueprint project owns both the Blueprint source modules and a
  generator entry point that writes `_out/` when invoked by `vbp build`.
- When editing docs or agent guidance, distinguish clearly between current
  behavior and planned release behavior.

## Commands

- Run long `lake`, `lean`, `elan`, and `.lake/build/bin/*` commands via
  `scripts/lean-low-priority ...`.
- Preferred user-facing interface:
  - `lake exe vbp build ...`
- Main build/test commands:
  - `scripts/lean-low-priority lake build`
  - `scripts/lean-low-priority lake test`
  - `./scripts/generate-reference-blueprints.sh`
  - `./scripts/validate-reference-blueprints.sh`
  - `./scripts/validate-reference-blueprints.sh --run-lean-tests`
- Harness commands:
  - `python3 -m scripts.blueprint_harness --help`
  - `python3 -m scripts.blueprint_harness sync-root-lake`
  - `python3 -m scripts.blueprint_harness paths`
  - `python3 -m scripts.blueprint_harness worktree-list`
  - `python3 -m scripts.blueprint_harness worktree-status`
  - `python3 -m scripts.blueprint_harness worktree-claim`
  - `python3 -m scripts.blueprint_harness worktree-release`
  - `python3 -m scripts.blueprint_harness worktree-prune-candidates`
  - `python3 -m scripts.blueprint_harness worktree-retire`
  - `python3 -m scripts.blueprint_reference_harness --help`
  - `python3 -m scripts.blueprint_reference_harness projects`
  - `python3 -m scripts.blueprint_reference_harness generate`
  - `python3 -m scripts.blueprint_reference_harness validate`
  - `python3 -m scripts.blueprint_reference_harness sync`
  - `python3 -m scripts.blueprint_reference_harness edit <project>`
  - `python3 -m scripts.blueprint_reference_harness prune`
- The Python harness is maintainer tooling for this repository's in-repo
  own tests plus ephemeral checkout validations, not the preferred end-user
  interface.
- Harnessed artifact-generation flows now proactively refresh the owner-module
  mtimes for embedded package assets such as `open-target-details.mjs`,
  `preview-ready.mjs`, `blueprint-graph-core.mjs`, `blueprint-preview-core.mjs`,
  `preview-runtime-base.mjs`, `preview-runtime-data.mjs`,
  `preview-runtime-render.mjs`, `preview-runtime-source-metadata.mjs`,
  `preview-runtime-hydration.mjs`, `preview-runtime-lifecycle.mjs`,
  `preview-runtime-surface.mjs`, `preview-runtime-template.mjs`,
  `preview-runtime-api.mjs`, `inline-preview.mjs`,
  `graph.css`, `graph-runtime-core.mjs`, `graph.mjs`, `summary.css`,
  `bibliography.css`, `relation-panel.mjs`,
  `blueprint-slides.css`, `blueprint-slides.mjs`, and `static-web/math.js` before build
  steps run, remove those owner modules' cached build outputs, and then run a
  targeted root `lake build` for those owner modules. This keeps downstream
  generator projects from silently serving stale embedded assets when only the
  asset files changed.
- Keep the two generated artifact families distinct:
  - Reference blueprints are the release-facing validation catalog built by
    `./scripts/generate-reference-blueprints.sh`,
    `./scripts/validate-reference-blueprints.sh`, or
    `python3 -m scripts.blueprint_reference_harness {generate,validate}`.
  - Test blueprints are the in-repo rendering and browser-regression fixtures
    built by `./scripts/generate-test-blueprints.sh`,
    `./scripts/validate-test-blueprints.sh`, or the browser pytest flow under
    `tests/browser`.
- `preview_runtime_showcase` is a test blueprint, not a reference blueprint.
- When the user asks for `_out` artifacts, do not guess blindly:
  - requests such as "build `_out`", "let me inspect it", "show me the
    output", or "I want to have a look" default to the reference-blueprint
    catalog under `_out/.../reference-blueprints/...`
  - requests about "reference blueprints", "validation catalog", or
    "validation output" mean `_out/.../reference-blueprints/...`
  - requests about browser regressions, fixture iteration, or a named test
    blueprint such as `preview_runtime_showcase` mean
    `_out/.../test-blueprints/...` unless the user explicitly asks for the
    reference-blueprint catalog instead
  - for UI review on a real deliverable, prefer reference blueprints even if a
    smaller test-blueprint fixture also exists
- Default reference-project selection follows the active checkout release:
  - `v4.32.0`: `noperthedron`, `verso-flt`
  - `v4.31.0`: `spherepackingblueprint`, `verso-carleson`
- Validation output lives under `_out/reference-blueprints/` in the root
  checkout and `_out/<worktree>/reference-blueprints/` in a linked worktree.
- `project-template` is an explicitly selectable CI fixture for every
  maintained release, not a default or published reference-catalog entry.
- Default test-blueprint output in the root checkout:
  - `_out/test-blueprints/{<slug>,preview_runtime_showcase,state-showcase}/`
- Default test-blueprint output in a linked worktree:
  - `_out/<worktree>/test-blueprints/{<slug>,preview_runtime_showcase,state-showcase}/`
- Shared warmed source checkout cache for external git-checkout projects:
  - `.worktrees/_reference-blueprints/cache/<source-ref-key>/`
- Shared warmed dependency cache for external git-checkout projects:
  - `.worktrees/_reference-blueprints/deps/<source-ref-key>/packages/`
  - `.worktrees/_reference-blueprints/deps/<source-ref-key>/path-builds/`
- Current-checkout local reference blueprint clones for external git-checkout projects:
  - `.worktrees/_reference-blueprints/by-worktree/<checkout>/<source-ref-key>/`

## Mathlib and Worktree Reuse

- `ejgallego/verso-noperthedron` is Mathlib-heavy and should be handled
  carefully.
- In linked worktrees, prefer `python3 -m scripts.blueprint_harness sync-root-lake`
  before allowing local rebuilds.
- If Lake starts repopulating Mathlib artifacts unnecessarily, try
  `scripts/lean-low-priority lake exe cache get`.

## Approval Policy

- Avoid approval/escalation requests unless they are actually required.
- Do not request approval for routine local reads, repo-local edits, `git
  status`, `git diff`, or sandbox-safe local build/test commands.
- Prefer repo-local scripts and already-approved command prefixes over alternate
  commands that trigger avoidable auth prompts.
- Documentation work, local code edits, and ordinary repo inspection should
  stay fully local.
- Do not push branches, install global tools, or write outside the workspace
  unless the user explicitly asks or the task genuinely requires it.

## Documentation Map

- `README.md`: user-facing overview and getting-started guide
- `doc/CONTRIBUTING.md`: branch, commit, PR, and local worktree coordination
  conventions
- `doc/MANUAL.md`: feature semantics, options, and rendering notes
- `doc/MAINTAINER_GUIDE.md`: maintainer-oriented harness workflow
- `doc/DESIGN_RATIONALE.md`: architecture rationale
- `doc/ROADMAP.md`: planned cleanup and follow-up work
- `doc/UPSTREAM_BACKLOG.md`: the local backlog of items that should eventually
  be upstreamed to `verso`, Lake, or Lean; requests to add something to the
  "Verso upstream backlog" mean updating this file unless the user explicitly
  asks to open or update an upstream GitHub issue

## General Recommendations

- Avoid duplication strongly.
- Keep one source of truth for each data point.
- Prefer descriptive names over abbreviations.
- Do not introduce new inductives unless strictly necessary.
- When adding or updating file authorship headers, prefer the name of the human
  driving the work, not the AI assistant name.
- Prefer the documented public harness entry points over ad hoc internal command
  sequences.
- Prefer branch names of the form `feat/<slug>`, `fix/<slug>`, `docs/<slug>`,
  `chore/<slug>`, or local-only `wip/<slug>`.
- Prefer commit and PR subjects of the Lean upstream form `type: summary`.
- Use Lean's public title types: `feat`, `fix`, `doc`, `style`, `refactor`,
  `test`, `chore`, and `perf`.
- Do not add type scopes such as `feat(entry): ...` to public PR or commit
  titles; put the affected area in the subject instead.
