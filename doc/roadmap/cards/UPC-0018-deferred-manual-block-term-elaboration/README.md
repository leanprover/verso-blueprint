# UPC-0018 Deferred Manual Block Term Elaboration

Status: resolved
Kind: performance
Priority: high
Origin: upstream-verso
Last reviewed: 2026-08-09
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: duplicate Blueprint directive-body elaboration during final document assembly
Related cards: UPC-0017

## Summary

Blueprint now reuses the elaborated directive-body work already performed for
preview evaluation instead of embedding the same body syntax in a deferred block
term that Lean elaborates again when the document closes. The Blueprint-local
representation requires no Verso queue contract.

For an adopted or attribute-owned docstring, `Docstring.statementBlocks`
converts the compiled documentation directly to typed Manual blocks. The
registration retains that body for previews and placement. Document assembly
uses a closed term that reconstructs the same blocks.

## Impact

Carleson's 15,763-line owner module queues 1,001 document blocks. In a stable
low-load prefix sequence, `finishDoc` took 12.63s, or 26.0% of the 48.65s full
elaboration, at full size. The deferred block batch accounted for 12.01s, and
elaborating its individual block terms accounted for 11.20s.

Source attribution in a separate full run assigned 81.1% of the term batch to
Blueprint directives. Proof directives alone accounted for 52.2%, and their
time correlated strongly with body size. An intentionally invalid probe that
removed directive bodies only from the final deferred terms saved 7.40s of
directive term elaboration. This is an upper bound for reuse, not an acceptable
implementation.

A behavior-preserving Blueprint implementation retains each accepted directive's
elaborated body in an internal compiled array definition, evaluates that same
definition for preview data, and refers to it during final document assembly.
In a bracketed candidate/baseline/candidate comparison, mean candidate user CPU
was 92.66s versus 139.60s for the baseline. Mean wall was 84.43s versus 122.82s,
but the two candidate wall times differed by 24s under changing host load, so
the elapsed percentage is supporting evidence rather than a regression
threshold.

## Roadmap Decision

Resolved by the retained-body implementation in Blueprint. It uses existing
Lean elaborator facilities and does not require a Verso deferred-queue change.
Reopen upstream design only if later evidence demonstrates a general queue
contract that cannot be expressed at the Blueprint directive boundary.

## Reproduction Status

Reproduced by directly elaborating warm, valid prefixes of
`CarlesonBlueprint/Chapters/Main.lean` in the pinned `verso-carleson` reference
project with Lean `v4.33.0-rc1`. Dependency compilation, native executable
generation, traversal, and HTML rendering were excluded. Prefixes ended only at
complete top-level block boundaries and all elaborated successfully.

The behavior-preserving implementation was then measured on Blueprint base
`1ff5697c`, Carleson revision `15f3cc5552342b78a399043c88f581168dabfd1a`, and
the same pinned Lean `v4.33.0-rc1` reference environment. Package regression
tests used the current `v4.33.0-rc2` development toolchain.

## Preliminary Analysis

The 25%, 50%, 75%, and 100% prefixes contained 271, 528, 757, and 1,001
deferred blocks. Full wall time and finalization were both close to linear in
block count. At full size, the deferred batch was 95.1% of `finishDoc`, and
term elaboration was 93.2% of that batch.

The duplicated Blueprint path is concrete:

1. A directive expander elaborates its body blocks.
2. Preview evaluation elaborates and evaluates the resulting terms.
3. The evaluated values are retained, but the elaborated expressions are not.
4. The returned document-block syntax embeds the same body terms.
5. Final document assembly elaborates those deferred terms again.

The retained-body implementation replaces steps 2--5 at accepted Blueprint
directives: it elaborates the body array once, adds and compiles a fresh internal
definition, evaluates that definition for preview state, and returns syntax
that references the same definition in the final `Block.other` wrapper. The
general Verso deferred-block representation remains unchanged.

The prefix study rejects the earlier giant-generated-term hypothesis.
`FinishedPart.toSyntax` took at most 2.2ms, reconstruction JSON less than
0.2ms, and the outer generated definition 0.36s at full size. The suspected
quadratic `saveRefsInEnv` path took 49ms cumulatively, about 0.1% of full wall.
Moving deferred elaboration earlier would shorten the visible end-of-file pause
but would not reduce whole-module time.

## Scope Boundary

This card owns the now-resolved ownership question around reuse of Blueprint
directive-body elaboration between preview evaluation and final document
construction. The implementation demonstrates a Blueprint-local boundary and no
current Verso queue requirement. UPC-0017 owns external-declaration signature
conversion during incremental directive elaboration. Syntax assembly,
reconstruction JSON, the outer `VersoDoc` definition, `saveRefsInEnv`, math
lint, native generator runtime, and HTML rendering are measured non-targets for
this card.

## Expected Behavior

- Directive bodies are not elaborated twice merely to support preview data and
  final document construction.
- Document reconstruction hygiene, diagnostics, source information, and
  generated output remain equivalent.
- The resulting `.olean` is reproducible and the complete owner module still
  elaborates successfully.
- Peak RSS and `.olean` size are compared with the same warmed baseline, and any
  regression is reported and justified.
- Acceptance is based on reduced complete owner-module time, not only moving
  work away from `finishDoc`.
- No upstream API is proposed unless later evidence demonstrates a requirement
  outside Blueprint's directive boundary.

## Evidence

The valid-prefix sequence measured:

| Prefix | Deferred blocks | Full wall | Deferred batch | `finishDoc` | Finish share |
| --- | ---: | ---: | ---: | ---: | ---: |
| 25% | 271 | 13.16s | 2.576s | 2.709s | 20.6% |
| 50% | 528 | 23.56s | 5.179s | 5.432s | 23.1% |
| 75% | 757 | 35.29s | 7.775s | 8.169s | 23.1% |
| 100% | 1,001 | 48.65s | 12.012s | 12.628s | 26.0% |

The separate source-attribution run partitioned deferred term elaboration:

| Source block | Count | Term elaboration | Batch share |
| --- | ---: | ---: | ---: |
| `proof` directive | 159 | 7.217s | 52.2% |
| `lemma_` directive | 149 | 3.515s | 25.4% |
| Ordinary paragraph | 180 | 1.894s | 13.7% |
| TeX provenance block | 502 | 0.713s | 5.2% |
| `theorem` directive | 11 | 0.474s | 3.4% |

The implementation comparison bracketed the baseline with two candidate runs:

| Variant | Wall | User CPU | System CPU | Peak RSS | `.olean` bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Candidate 1 | 72.43s | 79.19s | 2.80s | 5,163,944 KiB | 41,129,256 |
| Baseline | 122.82s | 139.60s | 4.57s | 5,478,516 KiB | 42,529,592 |
| Candidate 2 | 96.43s | 106.13s | 3.64s | 5,164,444 KiB | 41,129,256 |
| Candidate mean | 84.43s | 92.66s | 3.22s | 5,164,194 KiB | 41,129,256 |

Relative to the bracketed baseline, mean candidate user CPU was 33.6% lower,
peak RSS was 314,322 KiB (5.7%) lower, and the `.olean` was 1,400,336 bytes
(3.3%) smaller. Both candidate `.olean` files were byte-identical, with SHA-256
`01cef9777771525e06a75cb717821d48019fa99c3e2677206a525eea989e7e0b`.

A matched structured-profiler comparison isolated the finalization effect:

| Structured trace | Complete traced span | Final block | Final share | Peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Baseline | 236.17s | 67.69s | 28.7% | 6,062,788 KiB |
| Candidate | 237.76s | 53.02s | 22.3% | 5,499,224 KiB |
| Difference | +1.58s | **-14.67s** | -6.4 points | **-563,564 KiB** |

The 21.7% final-block reduction came from the expected elaborator leaves:
application arguments fell by 8.96s and `let` terms by 6.07s, while unrelated
final-command residual time remained stable.

Compiling only the affected owner-module translation unit checked the native
artifact consequence without rebuilding 8,306 cached Mathlib C files and 117
Carleson C files. Generated C grew by 366,379 bytes (1.6%) and the object file
by 222,208 bytes (1.2%) because the implementation adds one retained definition
per accepted directive. Loadable object sections nevertheless fell by 18,921
bytes (0.15%), including 21,473 fewer bytes of executable text.

The complete candidate Carleson site passed `vbp check` with 531 manifest and
531 HTML-cache entries. Baseline and candidate trees contained the same 176
files; their raw differences reduced to the live timestamp, Lean per-run
`_uniq` identifiers in declaration markup, and reversed order for two otherwise
identical independent find-page scripts. A focused elaborator regression
asserts that an accepted Blueprint directive body is elaborated exactly once,
and the full 446-job Lean package test suite passes.

Absolute workstation wall times varied with host load. The useful evidence is
the within-run phase partition, valid-prefix curve, source distribution, and
controlled body-elision delta. The implementation's user CPU, memory, artifact
size, reproducibility, and semantic output validation support landing, while
its wall-time percentage remains explicitly non-normative. The raw Carleson
profiling bundle remains maintainer-local and untracked; the tables above are
the durable summary.

## Current Workaround

None. Blueprint retains reusable elaborated body references locally, and no
upstream Verso change is required by the validated design.
