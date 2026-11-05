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

Do now the open items below, in rank order. Defer dark mode, serif prose, a
Blueprint-owned landing page, and realization display. Revisit the deferred
items once the open items land. P5 needs a design for the side-by-side feature
before implementation; do not polish the current layout.

## Reproduction Status

Current repros are the starter `project-template` reference blueprint, the
`preview_runtime_showcase` test blueprint, and the published v4.35.0 FLT
reference blueprint. Unless noted, measurements come from the
`feat/visual-design` build at 8d4269f6 in headless Chromium at 1440x900.

The `visual_inspection` test blueprint is the primary repro: each chapter
isolates one part of the generated pages and lists what to check.

## Preliminary Analysis

Fixed on `feat/visual-design`:

| Problem | Fix |
| --- | --- |
| Blueprint chrome rendered in the browser's serif default, because Verso sets fonts only on specific elements | `body` uses Verso's structure font |
| Editing one stylesheet reordered every block in the cascade, so specificity ties resolved by hash order | Blueprint CSS re-emitted last in a fixed order (UPC-0022 removes the duplication) |
| The `bold` style clipped kind labels (`DEFINITIC`) under the label number | `modern` and `bold` removed |
| The floating style switcher covered code at phone width | Switcher removed |
| Proof rows aligned with statement rows only under Times metrics | Shared minimum code column; test measures baselines |
| Headings showed the same ⚠ for unfinished code, code waiting on prerequisites, and a missing declaration, and an error-like ✗ for blocks with no Lean code yet | Distinct marks with plain-language tooltips: ✓ complete, ◐ own code complete with requirements open, ⚠ unfinished, ! declaration not found, A axiom, ○ no Lean code yet |
| Empty relation chips such as "uses 0" added noise to every header | Hidden, keeping their column so other chips stay aligned; undeclared-group warnings stay visible |
| The dependency graph opened unreadable on large projects: labels were 3px on the 240-node `visual_inspection` graph | Opens zoomed to readable labels, anchored at the graph's top-left, with a control to show the whole graph |
| The graph page stayed blank, with no message, when its libraries could not load | The canvas explains the failure |

Open, ranked:

| Rank | Problem | Evidence | Likely fix |
| --- | --- | --- | --- |
| P5 | Side-by-side cards overflow and clip | Six header classes overflow the card on Side-by-Side Views; Lean code is clipped; two `visual_inspection` pages scroll horizontally at phone width | Redesign the side-by-side feature; overflow and clipping are symptoms, so patching them alone is not enough |
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
- `tests/browser/test_visual_inspection.py` pins the heading marks, the hidden
  empty chips, the readable initial graph zoom, and the graph's load error on
  the `visual_inspection` test blueprint. The zoom is verified on the
  `visual_inspection` and showcase graphs, not yet on external reference
  blueprints.

## Current Workaround

None.
