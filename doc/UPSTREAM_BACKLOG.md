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

- [ ] Add a generic wide-content page mode for Manual pages.
  - current Blueprint workaround:
    graph pages carry Blueprint-local page-shell CSS/runtime behavior to escape
    the normal `.content-wrapper` / `main section` max-width assumptions
  - desired upstream behavior:
    a page-level or section-level opt-in that widens the content frame while
    preserving the shared Manual shell and ToC semantics
  - removable Blueprint code:
    graph-specific page-shell overrides that are not about graph layout itself

## Runtime Assets and Browser Rendering

- [ ] Add first-class structured runtime assets, including ESM module scripts.
  - current Blueprint workaround:
    Blueprint package assets are embedded through package-owned Lean modules and
    emitted through Blueprint-local `-verso-data/` writers; regular Manual
    pages and slide decks inject their ESM entrypoints with `extraHead`
  - desired upstream behavior:
    downstream packages should be able to declare emitted runtime assets with
    stable output URLs, explicit asset kinds such as stylesheet, classic script,
    and `type="module"` script, and dependency/order metadata that lets ESM
    entrypoints import package-owned modules without string-concatenated
    bundles
  - removable Blueprint code:
    ad hoc `include_str` asset assembly, `extraJs` compatibility wrappers, and
    local owner-module invalidation rules whose only job is keeping embedded
    browser assets fresh

- [x] Add module-script/head injection support to Verso Slides.
  - upstream status:
    leanprover/verso-slides#59 added `Config.extraHead` on the upstream
    `verso-slides` main line.
  - Blueprint status:
    Blueprint slide decks now write the normal preview ESM support files, load a
    slide-specific `blueprint-slide-runtime.mjs` entrypoint, pass the preview
    renderer explicitly to slide hydration, and no longer build a de-ESMified
    `blueprint-slides.js` bundle. The slide runtime tag is supplied through
    Slides `extraHead`.
  - release-line note:
    the current `v4.30.0` release-line pin does not yet include Slides
    `extraHead`, so Blueprint temporarily pins `ejgallego/verso-slides` to the
    v4.30-compatible slide pin plus a minimal `extraHead` commit. Once a
    supported `verso-slides` release line contains `extraHead`, replace the
    temporary fork pin with the normal upstream release pin.

- [ ] Expose Verso Slides hooks for quiet rendering and initial hover state.
  - current Blueprint workaround:
    `VersoBlueprint.Slides.slidesMainWithBlueprintPreviews` supplies a local
    `GenreHtml Slides IO` instance so slide graft blocks elaborated through
    `{blueprint_node}` render from the Blueprint manifest/cache data before the
    HTML document is serialized; because `VersoSlides.slidesMain` owns both
    rendering and file emission, Blueprint also mirrors the small config-asset
    plan and write loop
  - desired upstream behavior:
    downstream packages should be able to elaborate a slide block to an
    already-rendered HTML body, while reusing the upstream `slidesMain` asset
    validation and output writer
  - removable Blueprint code:
    local `SlideAssetPayload`, `recordSlideAsset`, `collectSlideAssets`, and
    the copied `slidesMain` output loop in `VersoBlueprint.Slides`

- [ ] Decide whether page-level KaTeX preludes belong in core `verso`.
  - current Blueprint workaround:
    Blueprint owns page-level math assets and prelude injection for Blueprint
    math surfaces
  - desired upstream behavior:
    either a generic Manual hook for page-level math preludes or an explicit
    decision that downstream packages should continue owning this layer

- [ ] Upstream the `Verso.Code.Highlighted` docstring rerender performance fix.
  - current Blueprint workaround:
    `PreviewManifest.patchHighlightedDocstringStartupJs` rewrites generated
    highlighted-code JavaScript to read docstring source via `textContent`
  - desired upstream change:
    use `textContent || ""` instead of layout-sensitive `innerText` when
    reading `code.docstring, pre.docstring` before `marked.parse`
  - rationale:
    these nodes contain raw markdown source and often live under hidden
    `.hover-info` containers; `innerText` can be slow and can return empty text
    for hidden payloads
  - observed Blueprint impact:
    the Noperthedron `The-Local-Theorem` reference page dropped from a roughly
    14 second highlighted-code startup task to under 0.5 seconds after the
    local rewrite
  - upstream code points at Verso commit
    `7ae82ac2ae54ae5dcc9948a701669e9b596e5cae`:
    - `src/verso/Verso/Code/Highlighted.lean#L1377-L1384`
    - `src/verso/Verso/Code/Highlighted.lean#L1460-L1467`

- [ ] Upstream the separate `Verso.Code.Highlighted` hover robustness guards.
  - current Blueprint pressure point:
    Blueprint generated pages exercise hidden and dynamically hydrated hover
    payloads more heavily than normal pages
  - desired upstream behavior:
    highlighted-code hover rendering should tolerate missing or delayed DOM
    nodes without downstream packages patching the emitted asset

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
