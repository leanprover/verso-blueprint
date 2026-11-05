# BPC-0001 Visual Polish Within the Manual Style

Status: open
Kind: ux
Priority: medium
Origin: local
Last reviewed: 2026-11-05
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: none
Related cards: UPC-0003, UPC-0022

## Summary

Fix the largest visual problems in generated Blueprint pages while staying close
to the Verso Manual style: sans prose, Manual page shell, and Blueprint chrome
that reads as part of the same document. This card owns the ranked problem list
below. It does not own a new visual identity, serif prose, or a page shell of
Blueprint's own.

## Impact

Readers of every generated Blueprint see these problems. They are most visible
on large projects: FLT has 238 entries and its dependency graph has 243 nodes.
Several are correctness problems, not taste: blank graphs, clipped headers, and
status signals that disagree with each other.

## Roadmap Decision

Do now, in priority order, the open items marked P1 to P4 below. Defer dark
mode, serif prose, a Blueprint-owned landing page, and realization display.
Revisit the deferred items after P1 to P4 land.

## Reproduction Status

Current repros are the starter `project-template` reference blueprint, the
`preview_runtime_showcase` test blueprint, and the published v4.35.0 FLT
reference blueprint. Unless noted, measurements come from the
`feat/visual-design` build at 8d4269f6 in headless Chromium at 1440x900.

## Preliminary Analysis

Fixed on `feat/visual-design`:

| Problem | Fix |
| --- | --- |
| Blueprint chrome rendered in the browser's serif default, because Verso sets fonts only on specific elements | `body` uses Verso's structure font |
| Editing one stylesheet reordered every block in the cascade, so specificity ties resolved by hash order | Blueprint CSS re-emitted last in a fixed order (UPC-0022 removes the duplication) |
| The `bold` style clipped kind labels (`DEFINITIC`) under the label number | `modern` and `bold` removed |
| The floating style switcher covered code at phone width | Switcher removed |
| Proof rows aligned with statement rows only under Times metrics | Shared minimum code column; test measures baselines |

Open, ranked:

| Rank | Problem | Evidence | Likely fix |
| --- | --- | --- | --- |
| P1 | The dependency graph is unreadable when it opens on large projects | FLT's 243 nodes fit to width as a thin strip | Open at a readable zoom; related to UPC-0003 |
| P2 | The graph page is blank, with no message, when jsDelivr is unreachable | Reproduced with the network blocked: `d3` and `d3-graphviz` fail to load | Show an error state; later, bundle the libraries |
| P3 | A heading warns while its Lean panel shows complete | Starter Theorem 1.2 (`addition_right_identity`) shows a warning above a full green bar | One mapping from the captured assessment to heading, panel, and graph visuals |
| P4 | Block headers are noisy | Six zero-count chips on the starter Addition page; fixed columns reserve space for absent slots | Hide `bp_relation_chip_empty` and let columns collapse |
| P5 | Side-by-side cards overflow and clip | Six header classes overflow the card on Side-by-Side Views; Lean code is clipped | Let the header wrap inside narrow cards |
| P6 | The graph legend covers the sidebar and the left of the graph | Legend popover on the starter graph page | Anchor the popover inside the graph area |
| P7 | Too many type sizes | 16 font and size combinations in non-code text on the starter Addition page | A small type scale as tokens |
| P8 | Pages carry Blueprint CSS twice | Starter Addition page grew from 210 KB to 268 KB | Remove the re-emission once UPC-0022 lands |
| P9 | Summary wording exposes internal terms | "native checks complete, requirements incomplete" in the starter overview | Reader-facing status names |
| P10 | The front page leads with commit hashes and repeats the sidebar contents | Published FLT front page | Lead with progress, which the Summary already computes |

Deferred:

- Dark mode. Verso has none, and graph colors are hard-coded in
  `src/VersoBlueprint/Graph.lean`.
- Serif prose. Changing `--verso-text-font-family` is one line, but a bundled
  face, math glyph coverage, hovers, previews, and slides are untested.
- Realization display. Headings show one Lean badge even when a node has
  several realizations, and no rendered fixture uses realizations yet.

## Scope Boundary

This card does not own the Summary page split or compact work-queue chips
(`doc/ROADMAP.md` design candidates), the wide page mode (UPC-0003), or the
ordered stylesheet contract in Verso (UPC-0022).

## Expected Behavior

Generated pages read as one Manual-style document. The graph is usable on first
view at FLT scale and explains failures. Every surface shows the same status
for the same node. No Blueprint chrome overflows its container at desktop or
phone width.

## Evidence

- `feat/visual-design` commits 915dad9c and 8d4269f6.
- A computed-style diff of 21 starter and showcase pages after the fixed items
  shows only the intended font change and the auto-margin shifts it causes.
- The browser suite has no new failures against the unmodified base.

## Current Workaround

None.
