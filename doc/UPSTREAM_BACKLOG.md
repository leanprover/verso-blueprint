# Verso Upstream Backlog

Last reviewed: 2026-07-08

This file is the repository's local "Verso upstream backlog" index: a queue of
changes that would be better solved in upstream `verso`, Lake, Lean, or a
related upstream package once the Blueprint split stabilizes.

Actionable upstream asks should normally live as `UPC-*` cards under
[`roadmap/cards/`](./roadmap/cards/). Keep this file as the short index while
older inline items are migrated.

When a maintainer or agent says "add this to the Verso upstream backlog" or
"register this in the Verso upstream backlog", the default meaning is:

- add or update a `UPC-*` card under [`roadmap/cards/`](./roadmap/cards/)
- link that card from this index

That phrase does not authorize opening or editing upstream GitHub issues or
pull requests unless that upstream write action is explicitly requested.

## Triage Rules

1. Keep concrete upstream asks here or in linked `UPC-*` cards; keep
   Blueprint-local implementation work in [`ROADMAP.md`](./ROADMAP.md).
2. Prefer one item per upstream API or behavior change.
3. Record the local workaround that can be removed when the upstream work lands;
   migrated items should record that detail in their card.
4. Link an upstream issue or PR when one exists, but do not create or mutate
   upstream GitHub state unless explicitly asked.

## Manual Rendering and Cross-References

- [ ] [Support private or filtered xref-domain export for Manual HTML
  output.](./roadmap/cards/UPC-0001-private-xref-domain-export/README.md)

- [ ] [Add Manual HTML extension hooks around traversal and
  emission.](./roadmap/cards/UPC-0002-manual-html-extension-hooks/README.md)

- [ ] [Add a generic wide-content page mode for Manual
  pages.](./roadmap/cards/UPC-0003-wide-content-page-mode/README.md)

## Runtime Assets and Browser Rendering

- [ ] [Add first-class structured runtime assets, including ESM module
  scripts.](./roadmap/cards/UPC-0004-structured-runtime-assets/README.md)

- [x] [Add module-script/head injection support to Verso
  Slides.](./roadmap/cards/UPC-0005-verso-slides-extra-head/README.md)

- [ ] [Expose Verso Slides hooks for quiet rendering and initial hover
  state.](./roadmap/cards/UPC-0006-slides-quiet-hover-hooks/README.md)

- [ ] [Decide whether page-level KaTeX preludes belong in core
  `verso`.](./roadmap/cards/UPC-0007-page-level-katex-preludes/README.md)

- [ ] [Upstream the `Verso.Code.Highlighted` docstring rerender performance
  fix.](./roadmap/cards/UPC-0008-highlighted-docstring-performance/README.md)

- [ ] [Upstream the separate `Verso.Code.Highlighted` hover robustness
  guards.](./roadmap/cards/UPC-0009-highlighted-hover-robustness/README.md)

## Elaboration and Directive APIs

- [ ] Provide an upstream way to resolve package-owned runtime assets during
  elaboration.
  - current Blueprint workaround:
    `MathLint.lean` walks upward from module source or `.olean` locations to
    recover package roots for `static-web/katex-lint.mjs` and Verso's vendored
    KaTeX module
  - desired upstream behavior:
    expose stable package-root/package-asset lookup in the elaboration context,
    or provide a Verso-owned helper entry point that hides vendored asset
    layout from downstream packages
  - local coverage already in place:
    fresh consumer smoke tests cover root checkouts, dependency checkouts, and
    non-default Lake `packagesDir`

- [ ] Support list-valued directive arguments in Verso.
  - current Blueprint workaround:
    `DirectiveArgParsing.splitCommaSeparatedList` splits directive-string
    options such as `(lean := "...")`, `(uses := "...")`, and
    `(tags := "...")` by comma
  - desired upstream behavior:
    directive parsers can accept real list-valued arguments without downstream
    packages inventing ad hoc string splitting

## Lake and Package Management

- [ ] Honor package overrides during `lake update` bootstrap.
  - confirmed locally on Lean `v4.29.0`
  - current limitation:
    `loadWorkspace` passes `packageOverrides` only to `materializeDeps`, while
    `updateManifest` calls `updateAndMaterialize` without threading overrides
  - practical effect:
    `.lake/package-overrides.json` and `lake --packages ... update` do not stop
    an initial upstream clone when a fresh external project has no manifest yet
  - desired behavior:
    `lake update` should apply workspace and CLI package overrides during the
    initial dependency-resolution/materialization path
  - current Blueprint workaround:
    the harness rewrites cloned `lakefile.lean` dependencies before running
    `lake update`

## Manual Content Cleanup

- [ ] Revisit bibliography formatting in `VersoManual/Bibliography.lean`.
  - current Blueprint question:
    decide whether the local bibliography formatting cleanup belongs upstream
    or should remain Blueprint-specific
  - desired outcome:
    either upstream a general formatting improvement or document why Blueprint
    should keep a local presentation layer
