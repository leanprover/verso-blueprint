# Blueprint Roadmap Cards

Last reviewed: 2026-07-16

This directory tracks maintainer planning cards for scoped implementation and
upstream follow-up work. Cards are not end-user setup docs, option references,
or release notes.

## Source-of-Truth Roles

- [`../ROADMAP.md`](../ROADMAP.md) owns the narrative roadmap for
  repository-local workstreams.
- This file owns the short, maturity-grouped index of upstream asks that should
  eventually move into `verso`, Lake, Lean, or a related upstream package.
- [`cards/`](./cards/) owns actionable card details: status, evidence,
  workaround, and the local code or docs that can be removed after the work
  lands.
- [`TEMPLATE.md`](./TEMPLATE.md) is the starting point for new cards.

## Card Prefixes

- `BPC`: Blueprint-local cards for repository-owned cleanup, release, UX,
  documentation, or validation work.
- `UPC`: upstream platform cards for `verso`, Lake, Lean, `verso-slides`, or
  related upstream behavior that would let Blueprint delete local workaround
  code.

## Validated Upstream Asks

These cards have a current local pressure point and a specific workaround or
removal target.

| Area | Card | Origin | Priority |
| --- | --- | --- | --- |
| Manual pipeline | [`UPC-0001 Private Xref Domain Export`](./cards/UPC-0001-private-xref-domain-export/README.md) | Verso | high |
| Manual pipeline | [`UPC-0002 Manual HTML Extension Hooks`](./cards/UPC-0002-manual-html-extension-hooks/README.md) | Verso | high |
| Manual layout | [`UPC-0003 Wide Content Page Mode`](./cards/UPC-0003-wide-content-page-mode/README.md) | Verso | medium |
| Browser assets | [`UPC-0004 Structured Runtime Assets`](./cards/UPC-0004-structured-runtime-assets/README.md) | Verso | high |
| Slides pipeline | [`UPC-0006 Verso Slides Pipeline Hooks`](./cards/UPC-0006-verso-slides-pipeline-hooks/README.md) | verso-slides | medium |
| Highlighted code | [`UPC-0008 Highlighted Docstring Performance`](./cards/UPC-0008-highlighted-docstring-performance/README.md) | Verso | high |
| Highlighted code | [`UPC-0014 Portable Hover Fragment Transfer`](./cards/UPC-0014-portable-hover-fragment-transfer/README.md) | Verso | medium |
| Elaboration | [`UPC-0010 Package Asset Resolution During Elaboration`](./cards/UPC-0010-package-asset-resolution-during-elaboration/README.md) | Lake | medium |
| Directive parsing | [`UPC-0011 List-Valued Directive Arguments`](./cards/UPC-0011-list-valued-directive-arguments/README.md) | Verso | medium |

## Triage Candidates

These cards preserve a plausible boundary or historical issue, but need the
named decision or current reproduction before they become actionable upstream
work.

- [`UPC-0007 Page-Level KaTeX Preludes`](./cards/UPC-0007-page-level-katex-preludes/README.md)
- [`UPC-0009 Highlighted Hover Robustness`](./cards/UPC-0009-highlighted-hover-robustness/README.md)
- [`UPC-0012 Lake Update Package Overrides`](./cards/UPC-0012-lake-update-package-overrides/README.md)
- [`UPC-0013 Bibliography Formatting Boundary`](./cards/UPC-0013-bibliography-formatting-boundary/README.md)

## Release-Line Follow-up

- [`UPC-0005 Verso Slides Extra Head`](./cards/UPC-0005-verso-slides-extra-head/README.md)

## Card Rules

1. One card owns one upstream contract and its local removal target.
2. Keep the index short. Put evidence, reproduction notes, decisions, and
   workaround details in the card.
3. Record the local workaround and the removal target whenever possible.
4. Link upstream issues or PRs when they already exist.
5. Do not create or mutate upstream GitHub issues or pull requests unless that
   upstream write action is explicitly requested.
6. When upstream support lands, update the card before deleting local workaround
   code.
7. Use `open` only for a validated pressure point with enough evidence to act.
   Use `candidate` for an ownership question, historical-only repro, or proposed
   behavior that still needs a concrete failure case.
8. Merge cards when the same upstream change removes the same workaround. Keep
   related cards split when either change can land and be removed independently,
   and record that boundary in both cards.
