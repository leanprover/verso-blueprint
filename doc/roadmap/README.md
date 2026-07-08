# Blueprint Roadmap Cards

Last reviewed: 2026-07-09

This directory tracks maintainer planning cards for scoped implementation and
upstream follow-up work. Cards are not end-user setup docs, option references,
or release notes.

## Source-of-Truth Roles

- [`../ROADMAP.md`](../ROADMAP.md) owns the narrative roadmap for
  repository-local workstreams.
- [`../UPSTREAM_BACKLOG.md`](../UPSTREAM_BACKLOG.md) owns the short index of
  upstream asks that should eventually move into `verso`, Lake, Lean, or a
  related upstream package.
- [`cards/`](./cards/) owns actionable card details: status, evidence,
  workaround, and the local code or docs that can be removed after the work
  lands.

## Card Prefixes

- `BPC`: Blueprint-local cards for repository-owned cleanup, release, UX,
  documentation, or validation work.
- `UPC`: upstream platform cards for `verso`, Lake, Lean, `verso-slides`, or
  related upstream behavior that would let Blueprint delete local workaround
  code.

## Current Cards

- [`UPC-0001 Private Xref Domain Export`](./cards/UPC-0001-private-xref-domain-export/README.md)
- [`UPC-0002 Manual HTML Extension Hooks`](./cards/UPC-0002-manual-html-extension-hooks/README.md)
- [`UPC-0003 Wide Content Page Mode`](./cards/UPC-0003-wide-content-page-mode/README.md)
- [`UPC-0004 Structured Runtime Assets`](./cards/UPC-0004-structured-runtime-assets/README.md)
- [`UPC-0005 Verso Slides Extra Head`](./cards/UPC-0005-verso-slides-extra-head/README.md)
- [`UPC-0006 Slides Quiet Hover Hooks`](./cards/UPC-0006-slides-quiet-hover-hooks/README.md)
- [`UPC-0007 Page-Level KaTeX Preludes`](./cards/UPC-0007-page-level-katex-preludes/README.md)
- [`UPC-0008 Highlighted Docstring Performance`](./cards/UPC-0008-highlighted-docstring-performance/README.md)
- [`UPC-0009 Highlighted Hover Robustness`](./cards/UPC-0009-highlighted-hover-robustness/README.md)
- [`UPC-0010 Package Runtime Asset Resolution`](./cards/UPC-0010-package-runtime-asset-resolution/README.md)
- [`UPC-0011 List-Valued Directive Arguments`](./cards/UPC-0011-list-valued-directive-arguments/README.md)

## Card Rules

1. One card owns one roadmap question.
2. Keep the index short. Put evidence, reproduction notes, decisions, and
   workaround details in the card.
3. Record the local workaround and the removal target whenever possible.
4. Link upstream issues or PRs when they already exist.
5. Do not create or mutate upstream GitHub issues or pull requests unless that
   upstream write action is explicitly requested.
6. When upstream support lands, update the card before deleting local workaround
   code.

## Migration Status

The upstream backlog is being converted gradually. New actionable upstream asks
should normally be `UPC-*` cards linked from
[`../UPSTREAM_BACKLOG.md`](../UPSTREAM_BACKLOG.md). Existing inline backlog
items can remain inline until they receive fresh review.
