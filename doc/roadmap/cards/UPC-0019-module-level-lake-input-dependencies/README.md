# UPC-0019 Module-Level Lake Input Dependencies

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-lake
Last reviewed: 2026-08-20
Owner: none
Issue: https://github.com/leanprover/lean4/issues/2762
PR: https://github.com/leanprover/lean4/pull/7703
Upstream timing: none
Removal target: library-wide `needs` declarations for embedded Blueprint assets
Related cards: UPC-0004, UPC-0020

## Summary

Lake should eventually support module-level input dependencies, preferably in
the module header, so an elaborator such as `include_str` can depend on an
external file or build target without invalidating every module in its library.

## Impact

Blueprint embeds CSS and JavaScript in a small set of Lean owner modules. Lake's
supported `input_file`/`input_dir` plus library-level `needs` mechanism makes
incremental and artifact-cache builds correct, but any embedded-asset change is
mixed into the dependency trace of every module in the library. Module-level
inputs would retain correctness while improving cache reuse and focused rebuilds.

## Roadmap Decision

Use the supported library-level `needs` mechanism on the maintained Lean v4.32
and v4.33 release lines for correctness and artifact-cache safety. Track a
narrowly scoped module-header or module-level dependency proposal upstream: the
validation showed that the current mechanism invalidates all 24 Blueprint
modules in the targeted `Graph` build closure when one embedded CSS file
changes.

## Reproduction Status

The missing-input bug reproduces on Lean v4.33 and v4.34.0-rc1: changing an
`include_str` asset while leaving its Lean owner unchanged can restore a stale
owner artifact. On the maintained v4.32 and v4.33 release lines, filtered
`input_dir` and `input_file` targets attached to the library with `needs`
correctly change the artifact key and restore the matching artifact contents.
The correctness fix is validated; its broad invalidation cost is the remaining
upstream pressure point.

## Preliminary Analysis

Lean issue #2762 requested extra dependencies for Lean files and explicitly used
`include_str` as its motivating example. It was closed after PR #7703 added
`input_file`, `input_dir`, and `needs` for Lean libraries and executables. RFC
#3153 separately requested module-to-custom-target dependencies and was closed as
a duplicate. In issue #13449, a Lake maintainer noted that module-header
dependency declarations remain desirable but are not currently an FRO priority.

## Scope Boundary

This card owns dependency granularity between Lake inputs and individual Lean
modules. It does not own the semantic declaration or generated-site emission of
browser assets, which remains UPC-0004, or general detection of arbitrary I/O
during elaboration. Reused traces whose declared outputs are absent belong to
UPC-0020.

## Expected Behavior

A Lean module can declare a file or target dependency before elaboration. The
dependency is built first and its trace participates in that module's artifact
key, without changing unrelated modules' keys. Whether `include_str` should add
such a dependency automatically remains a separate design choice.

## Evidence

- Lean issue: https://github.com/leanprover/lean4/issues/2762
- Lake input dependency implementation: https://github.com/leanprover/lean4/pull/7703
- Module dependency RFC: https://github.com/leanprover/lean4/issues/3153
- Recent external-input discussion: https://github.com/leanprover/lean4/issues/13449
- Local stale-cache reproduction: `VersoBlueprint.Commands.Graph` embedding
  `src/VersoBlueprint/Commands/graph.css` on Lean v4.33
- Local v4.33 `needs` validation: adding a marker to `graph.css` with no Lean
  source change invalidated and rebuilt the 24 Blueprint modules in the targeted
  `VersoBlueprint.Commands.Graph` closure; both the resulting `.olean` and C
  artifact contained the marker.
- Forced artifact restore: after deleting the local `Graph` outputs, Lake
  restored the marker-bearing `.olean`, `.ilean`, and C artifact from the cache
  in 0.52 seconds. Removing the marker selected and restored the original
  24-module artifact set in 1.14 seconds, with the original `Graph` artifact
  hashes restored byte for byte.
- Full harness bypass: without touching `Graph.lean` or deleting its outputs, an
  asset-only marker flowed through the standalone project build into the
  `.olean`, C artifact, and every generated HTML page. Removing the marker
  restored the baseline artifact hashes in a one-second project build; the
  resulting site passed `vbp check` with 90 manifest and 90 HTML-cache entries.
- Downstream project-template and FLT integrations reused the corrected
  artifacts and passed `vbp check`; UPC-0020 owns the cache-in-place performance
  measurements and external-consumer evidence.

## Current Workaround

Declare filtered asset directories and individual out-of-tree assets as Lake
inputs, then attach them to the whole `VersoBlueprint` library with `needs`.
Cache-in-place compatibility for consumers outside Lake's build graph is
tracked separately by UPC-0020.
