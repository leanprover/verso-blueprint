# Verso Upstream Backlog

Last reviewed: 2026-06-26

This file is the repository's local "Verso upstream backlog": a queue of
changes that would be better solved in upstream `verso`, Lake, or Lean once the
Blueprint split stabilizes.

When a maintainer or agent says "add this to the Verso upstream backlog" or
"register this in the Verso upstream backlog", the default meaning is:

- record the item here

That phrase does not authorize opening or editing upstream GitHub issues or
pull requests unless that upstream write action is explicitly requested.

## Triage Rules

1. Keep concrete upstream asks here; keep Blueprint-local implementation work in
   [`ROADMAP.md`](./ROADMAP.md).
2. Prefer one item per upstream API or behavior change.
3. Record the local workaround that can be removed when the upstream work lands.
4. Link an upstream issue or PR when one exists, but do not create or mutate
   upstream GitHub state unless explicitly asked.

## Manual Rendering and Cross-References

- [ ] Make MD4Lean Markdown rendering usable from interpreted `lean --run`
  generator mains.
  - current Blueprint pressure point:
    Blueprint's preferred generation path for reference and consumer projects is
    `lake env lean --run <GeneratorMain>.lean --output ...`; calling
    `MD4Lean.renderHtml` from that path currently fails with
    `Could not find native implementation of external declaration
    'MD4Lean.renderHtml'`
  - current Blueprint workaround:
    source-backed external-markup preview fragments avoid depending on
    MD4Lean's native HTML renderer during interpreted generation
  - desired upstream behavior:
    `MD4Lean.renderHtml` and related Markdown entry points should either work
    under `lean --run` by loading their native implementation reliably, or
    expose an interpreter-safe fallback/API that downstream generators can call
    without switching to compiled executables
  - removable Blueprint code:
    any Blueprint-local conservative Markdown rendering or source fallback that
    exists only to keep Markdown source witnesses compatible with interpreted
    generator runs
  - acceptance check:
    a Blueprint generator main run with `lake env lean --run` can emit
    source-backed Markdown preview-cache fragments without a missing native
    implementation error

- [ ] Support private or filtered xref-domain export for Manual HTML output.
  - upstream issue:
    `leanprover/verso#840`
  - current Blueprint workaround:
    `PreviewManifest.publicXrefJson` filters traversal domains after traversal,
    and `PreviewManifest.filterPublicXrefOutput` rewrites `xref.json` plus the
    generated find page after Verso HTML emission
  - desired upstream behavior:
    extensions should be able to mark domains as public xref data or private
    traversal-local storage before `xref.json` and the find page are emitted
  - secondary upstream improvement:
    emit compressed/minified `xref.json` when appropriate

- [ ] Add Manual HTML extension hooks around traversal and emission.
  - current Blueprint workaround:
    `PreviewManifest.blueprintMain` mirrors Verso's top-level single-page and
    multi-page dispatcher while still delegating to Verso traversal and HTML
    emitters
  - needed hook shape:
    a post-traversal/pre-HTML-emission transform for `TraverseState` and
    `HtmlAssets`, plus a way to customize the xref payload used by both
    `xref.json` and the find page
  - still-useful lower-priority hook:
    a post-emit extra step for downstream files such as Blueprint preview data
  - preserved branch:
    `ejgallego/verso-manual-extra-step-upstream-20260313`
  - PR shortcut:
    `https://github.com/ejgallego/verso/pull/new/verso-manual-extra-step-upstream-20260313`

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
    pages inject the page ESM entrypoint with raw `extraHead`, while legacy
    classic-script paths such as slides still need Blueprint-local wrappers
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
    the current `v4.31.0` tag does not yet include Slides `extraHead`, so
    Blueprint temporarily pins `ejgallego/verso-slides` to upstream PR 59 plus a
    one-commit toolchain revert to Lean 4.31. Once a supported
    `verso-slides` release line contains `extraHead`, replace the temporary
    fork pin with the normal upstream release pin.

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
