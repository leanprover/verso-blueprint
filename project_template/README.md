# Project Template

This folder is a copyable starter Blueprint project.

To inspect the generated output, copy this folder and run the local workflow
below; it writes the site to `_out/site/html-multi/`.

The goal is not to show every feature. The goal is to give you one small
project that already has the right moving parts:

- a GitHub Pages workflow under `.github/workflows/`
- chapter files with real Blueprint blocks
- a Blueprint top-level file
- a generator entry point
- a local CI script for build-and-render checks
- rendered graph and summary pages

## File Layout

```text
project_template/
  .github/
    workflows/
      blueprint-pages.yml
      pages.yml
  .gitignore
  lakefile.lean
  lean-toolchain
  ProjectTemplate.lean
  ProjectTemplate/
    Blueprint.lean
    Chapters/
      Addition.lean
      Multiplication.lean
      Collatz.lean
    Formalization/
      Addition.lean
  ProjectTemplateMain.lean
  source/
    addition-source.pdf
  scripts/
    ci-pages.sh
```

The important files are:

- `ProjectTemplate/Chapters/Addition.lean`: the first chapter
- `ProjectTemplate/Formalization/Addition.lean`: an ordinary Lean module whose
  tagged declarations become a generated chapter through
  `{includeBlueprintModule}`
- `ProjectTemplate/Chapters/Multiplication.lean`: the second chapter
- `ProjectTemplate/Chapters/Collatz.lean`: a separate exploratory chapter with
  the intentionally unfinished conjecture
- `ProjectTemplate/Blueprint.lean`: the Blueprint top-level file
- `ProjectTemplateMain.lean`: the rendering entry point
- `source/addition-source.pdf`: a tiny committed source-document fixture used
  by the addition chapter's source chip and preview
- `lakefile.lean`: the package definition
- `.github/workflows/blueprint-pages.yml`: copyable reusable Pages workflow
  used by the template
- `.github/workflows/pages.yml`: thin caller into the local reusable workflow
  that builds and deploys the generated HTML to GitHub Pages
- `scripts/ci-pages.sh`: the local command that the Pages workflow runs

## What the template demonstrates

- labels that identify Blueprint nodes
- `:::definition`, `:::proposition`, `:::theorem`, and `:::proof`
- local Lean code attached to a Blueprint label
- local Rust code attached to a Blueprint label
- a statement linked to an existing Lean declaration
- an imported Lean module whose `@[blueprint]` declarations are included as a
  source-ordered Blueprint chapter
- source-document metadata attached to one theorem
- group and author metadata
- rendered progress summary and dependency graph pages
- a separate Collatz chapter with one intentionally unfinished theorem so the
  first graph render shows an in-progress proof state
- basic math rendering in the informal text

## Recommended workflow

1. Copy this folder into a new repository.
2. Rename `ProjectTemplate` to your project name.
3. Keep the generator entry point and top-level file structure.
4. Replace the addition, multiplication, and Collatz chapters with your own
   content.

Typical commands:

```bash
lake update
./scripts/ci-pages.sh
```

Run `lake update` once after copying the template. After that, use
`./scripts/ci-pages.sh` whenever you want the same local build-and-render check
that the included GitHub Pages workflow runs. The script delegates to the
project helper:

```bash
lake exe vbp build
```

`vbp build` discovers the generator, then uses Lake to build its imports and
execute it without requiring a separate generator executable target.

To build a PDF locally, run:

```bash
lake exe vbp build --pdf
```

This writes `_out/site/pdf/main.pdf` and requires a `lualatex`-compatible
command on `PATH`.

## GitHub Pages

The template includes `.github/workflows/pages.yml`.
It also includes `.github/workflows/blueprint-pages.yml`.

- on pull requests, it builds the Blueprint site and uploads the Pages artifact
- on pushes to the repository default branch and on manual dispatch from that
  branch, it deploys `_out/site/html-multi` to GitHub Pages
- a manual run on another branch or tag builds a preview artifact in its own
  concurrency group

Allow the default branch in the `github-pages` environment's deployment
rules. Before publishing, the deploy job verifies that the artifact's commit
is still the default-branch head. This also applies when retrying that job.
Only the deploy job receives Pages write and OIDC token permissions.

PR builds can upload preview artifacts before Pages is enabled. Before the first
deployment, open **Settings → Pages** and select **GitHub Actions** as the
publishing source.

## Next step

Continue with [doc/GETTING_STARTED.md](../doc/GETTING_STARTED.md).
