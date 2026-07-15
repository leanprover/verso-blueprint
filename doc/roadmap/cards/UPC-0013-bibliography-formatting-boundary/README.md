# UPC-0013 Bibliography Formatting Boundary

Status: candidate
Kind: cleanup
Priority: low
Origin: upstream-verso
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: none until ownership is decided
Related cards: none

## Summary

Specify the desired bibliography entry-formatting change before deciding
whether it belongs in `VersoManual/Bibliography.lean` or in Blueprint-specific
presentation code.

## Impact

Bibliography presentation affects generated Manual output, but this item is not
yet a concrete upstream API request. Keeping the ownership question explicit
prevents the cleanup from becoming stale inline roadmap clutter.

## Roadmap Decision

Keep this as a candidate. Do not open upstream work until the expected output
delta is stated and reviewed as either a general Verso Manual improvement or a
Blueprint-only presentation choice.

## Reproduction Status

No concrete before/after formatting example or standalone repro is linked.

## Preliminary Analysis

Blueprint delegates each entry's core HTML and TeX formatting to upstream
`Citable.bibHtml` and `Citable.bibTeX`, then owns the Blueprint bibliography
page shell and citation-backlink UI. That existing division gives a useful
ownership test once the requested formatting change is made concrete.

## Scope Boundary

This card owns only a possible change to general bibliography-entry formatting.
Blueprint's bibliography page shell, entry grouping, and citation-backlink UI
remain local unless a separate reusable upstream contract is identified.

## Expected Behavior

The card records a concrete before/after example. General entry formatting is
proposed upstream; Blueprint-only page-shell or backlink presentation remains
local.

## Evidence

- Upstream formatting owner: `VersoManual/Bibliography.lean`
- Local presentation owner: `VersoBlueprint/Commands/Bibliography.lean`
- Missing evidence: a concrete formatting delta.

## Current Workaround

No formatting workaround is currently identified. Blueprint calls upstream
`Citable.bibHtml` and `Citable.bibTeX` for entry formatting and wraps that output
with its local bibliography and backlink presentation.
