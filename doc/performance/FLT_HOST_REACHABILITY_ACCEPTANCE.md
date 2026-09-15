# Full-FLT acceptance: reachability-owned callbacks

2026-09-15. Successor to the [leaf-only acceptance](FLT_HOST_LEAF_ACCEPTANCE.md).

## Contract and decision

PR189 successor `03ffaa13324804c922eb6df979cea1f91fbb8a90` removes all argument
callback-registry scans, the leaf classifier, and the failed-call callback Set.
Under Emilio's explicitly approved contract, a callback retained by JavaScript
survives a host exception. Unretained callbacks become eligible for collection;
collection timing is GC-owned. Accidental runtime retention is still a bug.
Host-effect transactional rollback, temporary Lean-object cleanup and explicit
runtime disposal remain. Mixed-heap cycle collection is not added.

The isolated JS successor passes the full-FLT normal-path consumer gate. Fresh
profiles show the intended bridge reduction. Two order-paired timing comparisons
suggest modest improvements, with overlapping individual observations. These
results neither adopt a new SDK nor independently qualify GC behavior on 4.34.

## Isolation and identity

As in the preceding report, producer base `41b00f5b` has a `host-state.js`
byte-identical to our pinned VIR `36d26bc224f0c2a52cd586587b2c3e1b1ade70d6` SDK.
Only the successor of that file is substituted into an isolated browser bundle.
All other runtime source hashes, the shell, JSON bridge, math assets, SDK and
Wasm match the control. The producer's 4.33 Lean/Wasm artifacts are not consumed.

| Identity | Value |
| --- | --- |
| VBP harness commit | `3577b7b3c751e11eb80aa02ef3a51726f0b9f243` (clean during captures) |
| Toolchain | `leanprover/lean4:v4.34.0-rc2` |
| Candidate host-state SHA-256 | `84c591a04118005502da266b08416222ee0ed528132642ff074733ddbea068bb` |
| Candidate bundle SHA-256 | `798a305fb8e7d876cc5abe529f1b118cb355fdeaf394cb787e8a5cc3535f91e5` |
| Control/live bundle SHA-256 | `a8d19c2c50208fca3d3708f10c6db5130f229a7dad10cf41928bc2d62d168111` |

SDK/Wasm, root source and client-package identities are unchanged from the
preceding acceptance and recorded in every new capture. The source stays
`e2d3a07251fe93f0659d1f8a16a14d5997b70f676b2e199ceb810e37e4a79f66`;
the single client package stays
`fc7d7b3137d81e0e1371c2cb1892fa2f9fc2d0c73a6d65b891864786293c2074`.
No live demo, pin, SDK, Wasm, producer or FLT source changes were made.

## Normal full-FLT measurements

Same root prose edit, endpoint and harness as the preceding report: edit at
`upstream formalization checkout.` in `FLTBlueprint.lean`, render the whole
assembled blueprint, observe accepted-version DOM commit (not VS Code paint).
AMD Ryzen AI 9 HX 370, React production, highlighting/debug/census/profiling off.
Each block has a fresh LSP worker/browser over warm built dependencies, one
excluded warmup and three measured in-memory edits. Order: A–B–B–A.

| Block | Median edit-to-DOM | Range | Median reply-to-DOM |
| --- | ---: | ---: | ---: |
| Control 1 | 2547 ms | 2491–2653 ms | 2143 ms |
| Candidate 1 | 2421 ms | 2421–2566 ms | 2102 ms |
| Candidate 2 | 2544 ms | 2293–2546 ms | 2188 ms |
| Control 2 | 2738 ms | 2664–2965 ms | 2306 ms |

Paired block-median reductions are 126 ms (4.9%) and 194 ms (7.1%). This is a
small exploratory campaign, not a precise general speedup estimate: observations
overlap and the machine's one-minute load varied roughly 2.5–6.8. The control is
the original pinned dispatcher, **not** the previous leaf-only candidate; do not
add this improvement to the earlier campaign's result.

All seven normal/profile/debug campaigns complete with one identical client
package and no warnings. Source/effective-source identities remain equal.
Payload byte equality was not tested; response server timings vary each run.

## Separate sampled attribution and checks

Fresh candidate and control browser profiles each cover one measured edit after
one warmup. Sampling is enabled; debug/census are off. Matched unstripped Wasm
provides symbols after checking equal executable sections: zero unresolved Wasm
frames in both captures.

| Sampled weight | Control | Candidate |
| --- | ---: | ---: |
| `callObjectsImpl`, self across capture | 353 ms | 63 ms |
| Its self weight below React rendering (subset above) | 278 ms | 29 ms |
| Whole React-render caller group, inclusive | 1560 ms | 1348 ms |
| Interpreter dispatch/evaluation below React, self category | 499 ms | 494 ms |
| Symbol/constant/name lookup below React, self category | 198 ms | 175 ms |

The bridge shrinks as predicted while React-side interpreter work is nearly
unchanged. These are noisy sampled weights, not headline elapsed measurements;
caller groups are not chronological phases, and inclusive/self weights overlap.
Full captures include RPC idle and profiling controls.

The minimal Node reproducer passes on exact successor source: three resources,
56 retained roots, zero registry traversals, zero callbacks created. This is a
mechanism check with mocked Wasm exports, not a GC test.

The separate debug capture passes nine-phase accounting and effect-before-
verification checks. Its bar reports 2573 ms to passive effect; the harness
reports 2388 ms to DOM, with the effect 188 ms later. Endpoints differ and neither
is React internal commit duration. No debug timing enters the normal table.

Producer evidence in `build/callback-reachability/README.md` reports Node and
Chromium real-Wasm retained-callback, dropped-reference, partial-lift GC,
disposal, rollback and reentry checks. We reviewed these tests and their scope;
they remain producer 4.33 evidence, not independently rerun 4.34 GC acceptance.
VBP production renderer code has no direct `liveCallbacks`/`releaseCallback`
dependency. The old diagnostic census intentionally targets the old dispatcher
and is disabled; it must not be applied to this scan-free successor.

## Evidence and continuation

Repository-root `_out/browser-pr188/host-reachability-acceptance/` retains exact
control/candidate bundles and sidecars, four `ab-*` campaigns, candidate/control
profiles (raw, symbolicated, summaries and SVGs), `candidate-debug/`, and
`producer-repro.json`. Reuse the preceding report's commands with this evidence
root and the new candidate hash; no harness modifications were needed.

Disposition: normal full-FLT JS consumer gate passes; producer owns the reviewed
GC policy/tests. A future matched 4.34 SDK update and its lifecycle acceptance
remain separate. No push, pin adoption, or producer write in this acceptance.
