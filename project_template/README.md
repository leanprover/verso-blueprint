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
  ProjectTemplateMain.lean
  source/
    addition-source.pdf
  scripts/
    ci-pages.sh
```

The important files are:

- `ProjectTemplate/Chapters/Addition.lean`: the first chapter
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

Each Lean source starts with `module`. A chapter or top-level Blueprint that
exports a `#doc` uses the authoring root in both phases:

```lean
module

public import VersoBlueprint
meta import VersoBlueprint

public section
```

The `public import` lets another module include the exported document. The
`meta import` loads Blueprint's directives, roles, and other authoring
elaborators. The generator follows the same two-phase pattern with
`VersoBlueprint.PreviewManifest` and meta-imports the top-level Blueprint so
`%doc` can evaluate it. Declarations written in Blueprint Lean code blocks are
public, so imported chapters retain their code panels and formalization status.

## What the template demonstrates

- labels that identify Blueprint nodes
- `:::definition`, `:::proposition`, `:::theorem`, and `:::proof`
- local Lean code attached to a Blueprint label
- local Rust code attached to a Blueprint label
- a statement linked to an existing Lean declaration
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

The repository's fresh-template smoke test also edits one chapter, rebuilds,
and checks that the changed text reaches the generated HTML without rebuilding
the two unrelated chapters.

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
- on pushes to `main`, it deploys `_out/site/html-multi` to GitHub Pages

Depending on your repository or organization settings, you may still need to
enable GitHub Pages with GitHub Actions as the publishing source once.

## Next step

Continue with [doc/GETTING_STARTED.md](../doc/GETTING_STARTED.md).
