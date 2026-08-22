# Blueprint Roadmap Cards

Last reviewed: 2026-08-22

This directory tracks maintainer planning cards for scoped implementation and
upstream follow-up work. Cards are not end-user setup docs, option references,
or release notes.

## Source-of-Truth Roles

- [`../ROADMAP.md`](../ROADMAP.md) owns the narrative roadmap for
  repository-local workstreams.
- This file owns the short, maturity-grouped index of upstream asks that should
  eventually move into `verso`, Lake, Lean, or a related upstream package.
- [`cards/`](./cards/) owns actionable card details: status, evidence,
  workaround, and any local code or docs that can be removed after the work
  lands.
- [`TEMPLATE.md`](./TEMPLATE.md) is the starting point for new cards.

## Verso Performance Collaboration Plan

The performance cards use FLT, Carleson, and Noperthedron as representative
downstream workloads for a coordinated upstream program. The cards contain the
quantitative source of truth; this index records sequencing and ownership.
The post-#391 FLT rebaseline is supporting measurement for UPC-0015 and
UPC-0016 rather than a separate upstream ask. The completed Carleson prefix and
source-attribution studies similarly refine UPC-0018 rather than creating a new
general document-assembly card. The behavior-preserving Blueprint retained-body
implementation resolved UPC-0018 without requiring a Verso deferred-queue
contract.

| Phase | Cards | Proposed collaboration |
| --- | --- | --- |
| Ready for focused upstream patches | [`UPC-0008`](./cards/UPC-0008-highlighted-docstring-performance/README.md), [`UPC-0015`](./cards/UPC-0015-single-owner-compact-xref-emission/README.md), [`UPC-0016`](./cards/UPC-0016-one-pass-manual-html-escaping/README.md) | Review small behavior-preserving changes, attach current-head measurements, and land independently where useful. |
| Needs Verso/SubVerso design | [`UPC-0017`](./cards/UPC-0017-layout-independent-signature-highlighting-cache/README.md) | Agree which highlighted-signature facts are layout-independent and how token identities remain canonical before implementing cache sharing. |

Before publishing new headline percentages, rerun the representative workload
on current Verso and Blueprint heads. Preserve raw order-balanced runs, require
semantic or byte-level output validation, and confirm that the sampled hotspot
moves as predicted. For native-generator work, treat wall time, sampled
profiles, and hardware counters as noisy evidence, with counters used only as
secondary work-reduction evidence. For elaboration work, use Lean's structured
profiler and non-overlapping phase timers instead of native-runtime counters.

The historical raw bundles named by these cards are maintainer-local profiling
artifacts under ignored `_out/` directories, not repository content. The cards
preserve their reviewable summaries and identities; any upstream implementation
PR must rerun the workload on current heads and attach or link its raw evidence.

## Measured Queue Boundaries

- Residual `String.posOfImpl` is the measured signature of UPC-0015's duplicate
  pretty-printed xref path, not a separate substring-search optimization.
- Generic fragment-array and string-accumulator HTML builders were tied with or
  slower than the existing serializer on representative Carleson render trees.
  They are rejected; UPC-0016's narrower one-pass escaping change remains
  queued.
- Compact-writer substitutions at either owner of `-verso-docs.json` were too
  small or slower. Revisit docs serialization only as a single-owner design
  that removes the intermediate write/read/full-rewrite path.
- After the ready xref and escaping patches are combined, rerun the complete
  diagnostics-off native generator before selecting another target. Aggregate
  `lean_string_push` and JSON-rendering symbols require phase and caller
  attribution first; Porter stemming and token insertion remain lower priority.

## Card Prefixes

- `BPC`: Blueprint-local cards for repository-owned cleanup, release, UX,
  documentation, or validation work.
- `UPC`: upstream platform cards for `verso`, Lake, Lean, `verso-slides`, or
  related upstream behavior that improves Blueprint's upstream foundation or
  lets Blueprint delete local workaround code.

## Validated Upstream Asks

These cards have a current local pressure point, enough evidence to act, and a
specific upstream target. They record a workaround or removal target whenever
one exists.

| Area | Card | Origin | Priority |
| --- | --- | --- | --- |
| Manual pipeline | [`UPC-0001 Private Xref Domain Export`](./cards/UPC-0001-private-xref-domain-export/README.md) | Verso | high |
| Manual pipeline | [`UPC-0002 Manual HTML Extension Hooks`](./cards/UPC-0002-manual-html-extension-hooks/README.md) | Verso | high |
| Manual emission | [`UPC-0015 Single-Owner Compact Xref Emission`](./cards/UPC-0015-single-owner-compact-xref-emission/README.md) | Verso | high |
| HTML serialization | [`UPC-0016 One-Pass HTML Escaping`](./cards/UPC-0016-one-pass-manual-html-escaping/README.md) | Verso | high |
| Manual layout | [`UPC-0003 Wide Content Page Mode`](./cards/UPC-0003-wide-content-page-mode/README.md) | Verso | medium |
| Browser assets | [`UPC-0004 Structured Runtime Assets`](./cards/UPC-0004-structured-runtime-assets/README.md) | Verso | high |
| Slides pipeline | [`UPC-0006 Verso Slides Pipeline Hooks`](./cards/UPC-0006-verso-slides-pipeline-hooks/README.md) | verso-slides | medium |
| Highlighted code | [`UPC-0008 Highlighted Docstring Performance`](./cards/UPC-0008-highlighted-docstring-performance/README.md) | Verso | high |
| Highlighted code | [`UPC-0014 Portable Hover Fragment Transfer`](./cards/UPC-0014-portable-hover-fragment-transfer/README.md) | Verso | medium |
| Lake build graph | [`UPC-0019 Module-Level Lake Input Dependencies`](./cards/UPC-0019-module-level-lake-input-dependencies/README.md) | Lake | medium |
| Directive parsing | [`UPC-0011 List-Valued Directive Arguments`](./cards/UPC-0011-list-valued-directive-arguments/README.md) | Verso | medium |

## Triage Candidates

These cards preserve a plausible boundary or historical issue, but need the
named decision or current reproduction before they become actionable upstream
work.

- [`UPC-0007 Page-Level KaTeX Preludes`](./cards/UPC-0007-page-level-katex-preludes/README.md)
- [`UPC-0009 Highlighted Hover Robustness`](./cards/UPC-0009-highlighted-hover-robustness/README.md)
- [`UPC-0012 Lake Update Package Overrides`](./cards/UPC-0012-lake-update-package-overrides/README.md)
- [`UPC-0013 Bibliography Formatting Boundary`](./cards/UPC-0013-bibliography-formatting-boundary/README.md)
- [`UPC-0017 Layout-Independent Signature Highlighting Cache`](./cards/UPC-0017-layout-independent-signature-highlighting-cache/README.md)
- [`UPC-0020 Cache-in-Place External Consumer Compatibility`](./cards/UPC-0020-cache-in-place-external-consumer-compatibility/README.md)

## Resolved Cards

- [`UPC-0005 Verso Slides Extra Head`](./cards/UPC-0005-verso-slides-extra-head/README.md)
- [`UPC-0010 Package Asset Resolution During Elaboration`](./cards/UPC-0010-package-asset-resolution-during-elaboration/README.md)
- [`UPC-0018 Deferred Manual Block Term Elaboration`](./cards/UPC-0018-deferred-manual-block-term-elaboration/README.md)

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
   behavior that still needs a concrete failure case. Use `close-candidate`
   when evidence rejects upstream action but a named local landing or final
   verification remains before resolution.
8. Merge cards when the same upstream change removes the same workaround. Keep
   related cards split when either change can land and be removed independently,
   and record that boundary in both cards.
