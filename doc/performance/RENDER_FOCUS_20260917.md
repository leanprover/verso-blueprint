# Rendering focus after direct-converter screening

Decoder work is paused at approximately 70 ms for the full captured FLT input.
Cross-update subtree reuse remains deferred. The next target is the roughly
1.4-second render-to-DOM interval, not another codec experiment.

## FIR handoff request

`VBP-FIR-20260917-RENDER-REFRESH-001` was queued to FIR's root owner (receipt
`01a0acea-70a9-7a63-a20b-4310e40638e2`). Preserve package
`2171673f37a8b83aa924ed97`: its configured factory and checked codec remain
usable baseline candidates, subject to consumer qualification, not live adoption.
The VIR-only direct constructor experiment is not a FIR heap-construction API.

Complete frozen source: 2,574 files, clean VBP `99caaacb`, VIR `92d7cc91`,
Lean `v4.34.0-rc2`, resolved dependencies and the existing dirty Verso parser
patch. Identity `bc9685f9c8cb8231b22edb36dc303a53e6c923f779f32cf1ec30a641a66a5392`;
archive SHA256 `b3e65b1a5deba919c6cac96e1f3819583ecb6813eedfe127cd5e7a542d39de14`.
Source/archive live under `.worktrees/_meta/widget-source-snapshots/`.
The later rendering-profile harness guard is not in that frozen snapshot.

Request the current configured factory and checked
`browserParsed/createView/renderDecoded` using the existing same-session opaque
token contract. Decoder time stays separate from isolated rendering time. No
raw pointer API, mutable capture, producer runtime scope expansion, publication
or live pin change is requested. FIR should audit whether the existing package
can be reused before rebuilding. `git diff f66cd04f..99caaacb` is empty for
`packages/verso-react`, `src/VersoBlueprintVir`, `NativeSession.lean` and
`NativeSession/DecodeProbe.lean`; newer probe/helpers need not imply a changed
renderer closure. FIR owns complete producer closure/setup validation.

## Fresh sampled profile

`_out/upstream-vir-20260917/render-focus-profile-01` runs the current direct
converter and actual retained preview, debug/highlighting off, two warmups and
two sampled updates. Sampling is separate from uninstrumented wall-time results.
The existing replay harness now permits direct-decoder sampling only with the
qualified coarse decode/render windows, not decoder-only phase subdivision.

The existing summarizer verifies SDK hashes and equality of all executable Wasm
sections between release and named artifacts. All 5,833 sampled Wasm frame nodes
resolve. Clock uncertainty is 0.133 ms, below the unchanged 5 ms threshold.
Raw input/source/package/SDK/bundle/profile hashes and samples are retained.

Within the two render-to-DOM windows (2,543 samples, 2,684.2 ms interval-weighted
sample coverage):

| Disjoint sampled self-time bucket | Share |
| --- | ---: |
| Interpreter dispatch/evaluation | 38.5% |
| Symbol/constant/name lookup | 14.1% |
| JavaScript/browser | 27.3% |
| Other Wasm | 13.5% |
| Allocation/refcount/vector storage | 6.7% |

Inclusive host-boundary coverage is 23.2%; inclusive `commitRoot` coverage is
0.67%. These overlap self buckets and must not be added to them. About 97.4%
of sample coverage lies under the Lean `virCallback` during `renderWithHooks`:
this includes identity, element construction and descendant host work, not just
React's own processing. JavaScript/browser self time is not all React time.
Paint and passive effects, RPC/LSP and server work are excluded.

Prominent self frames include interpreter `eval_body` (23.4%), interpreter
`call` (12.0%), symbol-cache hash lookup (9.9%), `readObjectArgv` (6.1%), and
`memcmp` (5.3%). This supports targeting interpreted construction and boundary
work ahead of DOM commit, but does not yet attribute a style-specific percentage.

## Next focused renderer experiment

Create immutable constant style objects once per component factory, rather than
executing the existing `Style.* : ReactM (Js Props)` builders per node/update.
Keep theme responsiveness via existing CSS variables, keep per-node attributes
separate and do not mutate shared styles. Reuse the same real retained-FLT
acceptance and balanced timing boundary; preserve the current source as baseline.
Do not replace React, introduce another transport layer, or assume sampled
interpreter percentages translate directly into a FIR speedup.

This slice establishes request/input authority and fresh attribution; no renderer
optimization or new VIR/FIR comparative performance claim is made yet.
