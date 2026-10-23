# Verso LSP adapter: first protocol and mapping experiment

Date: 2026-10-22. This follows the
[round-one design](VERSO_LSP_ADAPTER.md). The work is a tested experimental core,
not the completed Verso/VBP integration.

The [follow-up document slice](VERSO_LSP_DOCUMENT_SLICE.md) now adds independent
library imports, compiled requests, and offline Verso/Blueprint rendering. The
limits below describe the first experiment at its recorded date.

The core is now named `Parley`; the module paths below retain the working names
used by this archived experiment and its recorded source hash.

## What now exists

- `src/VersoLsp/Client.lean`: an owned stdio session with one receiver, concurrent
  request routing, server-request responses, absolute response deadlines,
  cancellation, full/incremental synchronization, diagnostic version tracking,
  bounded stderr retention, and bounded shutdown attempts.
- `src/VersoLsp/Source.lean`: exact-slice composition and checked UTF-16 mapping,
  retaining generated regions and splitting cross-source diagnostics.
- `src/VersoLsp/Protocol.lean`: definition targets, diagnostic observations, and
  full semantic-token normalization. No language enumeration or VBP state.
- `tests/VersoLspSpike.lean` and `tests/lsp/`: deterministic protocol checks and
  small Rust/Rocq projects, with a reproducible evidence runner.

None of these modules imports Blueprint, Verso, or SubVerso. The library and
executable are optional Lake targets; Blueprint's existing imports and data
model are unchanged. Python is test orchestration only.

## Observed results

The targeted Lean native build and all three experiment modes passed. The
maintainer-local evidence bundle is under the root checkout's
`_out/verso-lsp-design/lsp-spike/final/`. It contains source copies,
`identity.json`, and the raw results/stderr. That ignored bundle is local
evidence; rerun the checked-in runner to reproduce it elsewhere. The recorded
experiment source SHA-256 is
`dcefd437630403aa6108e096a9d5491a5003e403abe7390c19be20c63ffc1364`.

| Environment | Observed version |
| --- | --- |
| Lean | `leanprover/lean4:v4.35.0` |
| rust-analyzer | `1.89.0 (2948388 2025-08-04)` |
| coq-lsp | `0.2.4`, reporting Rocq `9.1.0` |

| Check | Mock | Rust | Rocq |
| --- | --- | --- | --- |
| Definition query at code-block and named-probe positions agrees | Response-routing cases | Passed, including UTF-16 position after an emoji | Passed in `VersoSpike.Probe` |
| Hover | Not a rendering test | Markdown signature and docs returned | Markdown type and qualified path returned |
| Semantic tokens | Invalid ranges, indexes, modifiers and tuple shapes rejected | 26 normalized spans | Not advertised; no tokens requested |
| Invalid fragment | Stale/replacement checks | Three syntax errors | One unresolved-reference error |
| Map error to authored fragment | Multiple source regions and generated text | Passed, including empty error ranges | Passed |
| Restore valid text and clear errors | Versioned replacement | Passed | Passed |
| Synchronization | Full | Incremental whole-document range edit | Full |
| Diagnostics | Push, stale versions, clear and unversioned sets | Fresh pull reports | Versioned push sets |

The mock also passed reversed concurrent response routing, a legal server error
code outside Lean's enum, rejected capability registration, late responses after
cancellation, server death, incompatible encoding rejection, and termination of
a server ignoring shutdown/exit. The 100 ms response deadline completed in
101 ms despite a continuous stream of notifications in this run. This timing
is evidence of the exercised path, not a real-time scheduling guarantee.

## Design consequences

**Reuse Lean framing, with an open response envelope.** Lean's typed
`JsonRpc.ErrorCode` decoder accepts a closed set. The mock's `-32097` error must
remain observable. The client therefore uses `readLspMessageAsString`, JSON
decoding, and the existing framed writer. Protocol types remain useful for
positions, ranges, and diagnostics.

**Project membership needs a profile contract.** The Rust probe in `src/lib.rs`
resolved `step`. An unsaved `Detached.rs` using the same crate's `step` returned
an empty definition result. A root directory and arbitrary file URI are not
enough to establish the intended crate context. Generated-document placement
must be explicit and tested for each profile.

**Processing completion and errors are independent.** Rocq's `coq/getDocument`
returned `completed.status = ["Yes"]` for both the valid document and the
document containing an unresolved reference. Completion means the server
processed the document; diagnostics remain a separate observation. Neither
fact establishes theorem trust or proof completeness.

**Validation coverage must be explicit.** In an earlier run, a syntactically
valid Rust fragment referring to `missing_name` produced no native error with
compiler checking disabled. A syntax error exercised the native diagnostic
path successfully. This experiment does not establish compiler validation of
Rust blocks. A profile must say whether compiler checks ran and what evidence
they provide.

**Capabilities can remain independent.** Rocq supplied useful lookup, hovers,
and diagnostics without semantic tokens. Rust supplied full and selection
ranges separately. The neutral model preserves these differences without
inventing a Lean constant or collapsing a feature gap into lookup failure.

## Build staging: proposed next experiment

Use authored directives to compile inert analysis requests into the document
value. A generator then collects those requests, composes and analyzes contexts,
attaches results, and hands the enriched document to ordinary rendering:

```text
Verso source -> compiled document containing requests
             -> collect requests and analyze explicit contexts
             -> portable analysis artifact and enriched document
             -> ordinary genre traversal and rendering
```

This avoids making document compilation depend on an analysis artifact that
itself requires the compiled document to discover its requests. It also keeps
external processes out of repeated Verso traversal passes.

Source inspection supports this direction: Verso has
`Inline.rewriteOtherM`/`Block.rewriteOtherM`, and `manualMain` accepts a `Part
Manual` value. Blueprint's generator similarly receives document text and its
captured model. The next experiment must prove collection/enrichment on real
authored documents, including nested extension content and captured Blueprint
state. This staging design is not validated merely by the protocol tests.

A generator integration preserves the normal `vbp build` interface. Live editor
feedback will need a separate request path sharing the same composition and
normalization. Source/configuration invalidation must be resolved before
introducing persistent analysis reuse; this spike deliberately has no result
cache.

## Remaining limits before a supported adapter

- The public configuration/profile/request/snapshot APIs remain undecided.
  These are experiment APIs and may change freely.
- Pipe writes and mutex admission are synchronous. The tested deadline bounds
  response waiting under notification traffic, not a blocked pipe write. Choose
  an async writer/transport contract before promising end-to-end deadlines.
- Cleanup uses Lean's SIGTERM process-group API and reports failure if the child
  is not reaped within the bound. A server ignoring SIGTERM needs a stronger
  platform runner. Concurrent close/request is outside this spike's contract.
- Open/close capability admission, typed operation outcomes, per-document stale
  query rejection, and full lifecycle-state validation need hardening.
- Push diagnostics without a version retain unknown freshness. Generic push
  completion is not inferred from silence. Pull-report caching and server
  refresh workflows are not implemented.
- The trace is bounded and reports drops. Source indexing is simple and needs
  reuse of a prepared index before whole-document enrichment at scale.
- No Verso renderer or SubVerso adaptation has been implemented. The protocol
  results justify a neutral analysis model but do not settle renderer ownership.
- No VBP contribution admission, preview/export integration, author syntax, or
  editor feedback has been added. The complete first product milestone still
  includes both authored blocks and named external references.

The next shared slice should exercise inert request collection and offline
rendering in a plain Verso document and VBP. Compare the actual renderer changes
with a focused SubVerso/Verso extension before choosing a fork.
