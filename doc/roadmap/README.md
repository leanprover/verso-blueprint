# Blueprint Roadmap Cards

Last reviewed: 2026-07-08

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
