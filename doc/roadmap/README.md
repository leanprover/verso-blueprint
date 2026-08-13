# Upstream Collaboration Cards

Last reviewed: 2026-08-13

Verso Blueprint depends on `verso`, Lake, Lean, and `verso-slides`. Sometimes a
problem is first visible in Blueprint, but the best fix belongs in one of those
projects. This page tracks those cases so the relevant maintainers can decide
where the change belongs and how to pursue it.

Each `UPC-*` card records:

- the problem observed through Blueprint
- the evidence or reproduction behind it
- which project or API may be the right place for the fix
- the local workaround, including what can be removed if the fix lands

This is a collaboration backlog, not a general issue tracker. Routine Blueprint
bugs and refactorings should be fixed locally and, when planning is useful,
tracked in the [repository roadmap](../ROADMAP.md). Use a card when the team
needs to decide which project should own a change or agree on an upstream API.

Browse [validated asks](#validated-upstream-asks) for work ready to discuss or
act on, [triage candidates](#triage-candidates) for open ownership or evidence
questions, and [resolved cards](#resolved-cards) for previous decisions. To
raise a new concern, start from the [card template](./TEMPLATE.md) or update an
existing card that already covers the same upstream change.

## Validated Upstream Asks

These issues affect Blueprint today and have enough evidence for a useful
upstream discussion or patch.

### Manual generation

| Card | Why it matters | Upstream | Priority |
| --- | --- | --- | --- |
| [`UPC-0001 Private Xref Domain Export`](./cards/UPC-0001-private-xref-domain-export/README.md) | Let extensions keep internal cross-reference data out of public search files without rewriting generated output. | Verso | high |
| [`UPC-0002 Manual HTML Extension Hooks`](./cards/UPC-0002-manual-html-extension-hooks/README.md) | Let Blueprint add files and adjust rendering without copying Verso's top-level HTML generation code. | Verso | high |
| [`UPC-0015 Single-Owner Compact Xref Emission`](./cards/UPC-0015-single-owner-compact-xref-emission/README.md) | Build and write the large cross-reference file once instead of repeating expensive work. | Verso | high |
| [`UPC-0016 One-Pass HTML Escaping`](./cards/UPC-0016-one-pass-manual-html-escaping/README.md) | Escape HTML text in one pass to reduce string copying in large generated sites. | Verso | high |

### Pages and browser integration

| Card | Why it matters | Upstream | Priority |
| --- | --- | --- | --- |
| [`UPC-0003 Wide Content Page Mode`](./cards/UPC-0003-wide-content-page-mode/README.md) | Give graph and other wide pages more room while keeping the standard Manual navigation and layout. | Verso | medium |
| [`UPC-0004 Structured Runtime Assets`](./cards/UPC-0004-structured-runtime-assets/README.md) | Let extensions declare JavaScript modules and styles without writing their own asset pipeline. | Verso | high |
| [`UPC-0006 Verso Slides Pipeline Hooks`](./cards/UPC-0006-verso-slides-pipeline-hooks/README.md) | Let Blueprint reuse the Slides generator while adding previews and their browser data. | `verso-slides` | medium |
| [`UPC-0008 Highlighted Docstring Performance`](./cards/UPC-0008-highlighted-docstring-performance/README.md) | Avoid a slow browser text read that makes pages with many code hovers expensive to open. | Verso | high |
| [`UPC-0014 Portable Hover Fragment Transfer`](./cards/UPC-0014-portable-hover-fragment-transfer/README.md) | Make highlighted code fragments reusable in another page or preview without Blueprint rewriting hover identifiers. | Verso | medium |

### Authoring and build tools

| Card | Why it matters | Upstream | Priority |
| --- | --- | --- | --- |
| [`UPC-0010 Package Asset Resolution During Elaboration`](./cards/UPC-0010-package-asset-resolution-during-elaboration/README.md) | Give Lean code a reliable way to find files owned by a Lake package. | Lake | medium |
| [`UPC-0011 List-Valued Directive Arguments`](./cards/UPC-0011-list-valued-directive-arguments/README.md) | Support list arguments in Verso directives without each extension writing its own comma parser. | Verso | medium |

## Triage Candidates

These may become upstream work, but each still needs a clearer example or a
team decision.

| Theme | Card | What we still need |
| --- | --- | --- |
| Math rendering | [`UPC-0007 Page-Level KaTeX Preludes`](./cards/UPC-0007-page-level-katex-preludes/README.md) | Decide whether page-specific math setup needs a general Manual hook or should stay in Blueprint. |
| Browser behavior | [`UPC-0009 Highlighted Hover Robustness`](./cards/UPC-0009-highlighted-hover-robustness/README.md) | Build a small example that fails without Blueprint's defensive browser code. |
| Build tools | [`UPC-0012 Lake Update Package Overrides`](./cards/UPC-0012-lake-update-package-overrides/README.md) | Check whether the old package-override problem still occurs on a supported Lake release. |
| Bibliography | [`UPC-0013 Bibliography Formatting Boundary`](./cards/UPC-0013-bibliography-formatting-boundary/README.md) | Show the desired before-and-after output, then decide whether it is a general Manual change. |
| Code rendering | [`UPC-0017 Layout-Independent Signature Highlighting Cache`](./cards/UPC-0017-layout-independent-signature-highlighting-cache/README.md) | Decide what can be shared between wide and narrow signatures without changing links or hover behavior. |

## Resolved Cards

| Card | What was decided |
| --- | --- |
| [`UPC-0005 Verso Slides Extra Head`](./cards/UPC-0005-verso-slides-extra-head/README.md) | `verso-slides` added a way to insert the required page header, so Blueprint could use the normal release version. |
| [`UPC-0018 Deferred Manual Block Term Elaboration`](./cards/UPC-0018-deferred-manual-block-term-elaboration/README.md) | Blueprint removed the repeated work locally; no new Verso API was needed. |

## How Cards Move

| Status | Meaning |
| --- | --- |
| `candidate` | A possible upstream change that still needs a current example, a clear desired result, or agreement about which project should own it. |
| `open` | We understand the problem well enough to discuss a design or make a patch. This does not mean that work is scheduled. |
| `close-candidate` | An upstream change probably is not needed, but some local work or a final check remains. |
| `resolved` | The decision is complete: upstream support landed, a local solution was enough, or the proposal was closed. |
| `deferred` / `superseded` | Work was deliberately postponed or replaced by another card or design. |

`Owner: none` means that no one has claimed the next action. Once the team
chooses to pursue a card, the owner coordinates the next discussion,
reproduction, issue, or patch; they need not implement every part personally.

The usual path is:

1. Capture a possible upstream concern as a `candidate`, or update an existing
   card that covers the same change.
2. Record how Blueprint is affected, how to reproduce the problem, which project
   may be the right place for the fix, and which local workaround could go away.
3. Discuss it with the relevant maintainers and decide between a local fix, an
   upstream design discussion, an issue, or a direct patch.
4. Mark it `open` once the upstream target and evidence are clear, and assign an
   owner when the team commits to a next action.
5. Link any resulting upstream issue or PR. After it lands, update the card,
   remove the local workaround, and mark the card `resolved`.

Opening or modifying an upstream issue or PR is a separate write action and
requires explicit authorization; adding or discussing a card does not perform
that action.

## Performance Work

The performance cards use FLT, Carleson, and Noperthedron as representative
large projects. The individual cards contain the measurements and rejected
experiments; this page only records the next team decision.

| Stage | Cards | Next step |
| --- | --- | --- |
| Ready for a focused patch | [`UPC-0008`](./cards/UPC-0008-highlighted-docstring-performance/README.md), [`UPC-0015`](./cards/UPC-0015-single-owner-compact-xref-emission/README.md), [`UPC-0016`](./cards/UPC-0016-one-pass-manual-html-escaping/README.md) | Prepare small independent changes and attach fresh measurements. |
| Needs design discussion | [`UPC-0017`](./cards/UPC-0017-layout-independent-signature-highlighting-cache/README.md) | Agree what can be cached without changing token links or hover behavior. |

Performance results must be rerun on current Verso and Blueprint code before
they are quoted in an upstream PR. The result should include output checks as
well as timings, and should show that the expected work actually disappeared.

## Card Rules

1. One card covers one proposed upstream change and the local workaround it
   could remove.
2. Keep the index short. Put evidence, reproduction notes, decisions, and
   workaround details in the card.
3. Record the local workaround and the removal target whenever possible.
4. Link upstream issues or PRs when they already exist.
5. Do not create or mutate upstream GitHub issues or pull requests unless that
   upstream write action is explicitly requested.
6. When upstream support lands, update the card before deleting local workaround
   code.
7. Merge cards when they ask for the same change. Keep them separate when either
   change can be discussed and landed on its own, and link the related cards.
