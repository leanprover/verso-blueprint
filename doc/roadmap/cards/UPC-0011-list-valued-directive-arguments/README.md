# UPC-0011 List-Valued Directive Arguments

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-verso
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: `DirectiveArgParsing.splitCommaSeparatedList`
Related cards: none

## Summary

Verso directive parsers should support list-valued arguments directly instead
of forcing downstream packages to encode lists as comma-separated strings.

## Impact

Blueprint directives currently accept options such as `(lean := "...")`,
`(uses := "...")`, and `(tags := "...")` as strings that are then split locally.
That makes quoting, whitespace, diagnostics, and future extension behavior more
fragile than a structured directive argument would be.

## Roadmap Decision

Track as an upstream Verso directive API request. Keep the local string-splitting
helper until Verso offers a structured list argument shape.

## Reproduction Status

No standalone upstream repro is linked. Blueprint directive parsing exercises
the workaround through normal authoring and validation paths.

## Preliminary Analysis

The local helper is intentionally narrow, but every downstream package that
needs list-like directive arguments would otherwise have to invent similar
string parsing and diagnostics.

## Scope Boundary

This card owns structured list syntax and parsing in Verso directives. The
meaning and validation of Blueprint's `lean`, `uses`, and `tags` values remain
Blueprint concerns.

## Expected Behavior

Directive parsers can accept real list-valued arguments, including useful
syntax errors, without downstream packages splitting comma-separated strings by
hand.

## Evidence

- Local workaround: `DirectiveArgParsing.splitCommaSeparatedList`
- Current string options include `(lean := "...")`, `(uses := "...")`, and
  `(tags := "...")`.

## Current Workaround

`DirectiveArgParsing.splitCommaSeparatedList` splits directive-string options by
comma.
