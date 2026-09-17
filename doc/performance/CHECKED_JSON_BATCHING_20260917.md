# Checked JSON batching opportunity

Read-only consumer investigation at VBP `84ce7170`, VIR `92d7cc91`, Lean
4.34.0-rc2. This does not implement a codec or claim a measured speedup.
The existing VIR RPC owner `01a04305-c1b0-7361-8504-7c002e8d7766` was
contacted once (queue receipt `01a0aca9-cfe2-7d11-b147-970771a6297c`);
generic conversion and array/props implementation remain with that owner.

The owner's subsequent scope response
`VIR-VBP-DECODER-BATCHING-SCOPE-20260917-001` confirms no inspect-many/codec
batching design in their current widget-construction lane. This is not a global
ownership transfer. It requests inventory/mechanism requirements before code
changes and coordinator assignment of any generic VIR implementation to one
writer. The inventory and requirements below were returned; no implementation
was started.

## Deterministic inventory

Input: repository-root `_out/browser-pr188/widget-baseline-inputs/response.json`.
SHA256: `6ae2daf7641f9d8ae76d48a0bf57bc63a0d25c886c299643b487bfbf8fe6e2c3`.
Size: 6,598,356 bytes. Parsed JSON is a tree; counts include its response wrapper.
An iterative walk counts each value occurrence and each container's immediate
children (`Object.values`). No runtime instrumentation or live demo changes.

| Inventory | Count |
| --- | ---: |
| Values / current private `inspect` calls | 73,192 |
| Containers | 37,270 |
| Nonempty containers | 32,612 |
| Empty containers | 4,658 |
| One-child containers | 17,872 |
| Containers with 2–4 children | 13,480 |
| Containers with 5–16 children | 959 |
| Containers with at least 17 children | 301 |
| Maximum immediate children | 186 |

For a hypothetical generic sibling-view batch, inspect the root once and then
inspect each nonempty container's children in chunks. Predicted calls are
`1 + sum(ceil(childCount / batchSize))`; this excludes the unchanged graph check.

| Maximum sibling batch | Inspection calls | Reduction |
| --- | ---: | ---: |
| Current single-node inspection | 73,192 | — |
| 8 | 34,295 | 53.1% |
| 16 | 33,058 | 54.8% |
| 32 | 32,723 | 55.3% |
| Unlimited | 32,613 | 55.4% |

Sixteen already captures nearly all of this particular call-count opportunity.
The many one-child containers limit sibling batching. Deeper subtree batching
would be a different mechanism and is not investigated or proposed here.

## What this does and does not save

Current `readChecked` invokes private `Internal.inspect` once per value,
then recursively builds `Lean.Json`; `decodeJs` applies the existing `FromJson`.
A sibling batch could reduce dispatch, lookup and boundary crossings while
retaining that architecture. It still lifts every returned view, copies long
strings, constructs Lean JSON containers and runs `FromJson`. An extra outer
array also costs allocation. A 55% call reduction is not a 55% decode reduction.
Existing sampled host-inclusive time overlaps descendant conversion work and
cannot be used to predict elapsed savings by multiplication.

Do not introduce a document-specific JS decoder, flat wire format, new public
pointer interface or JS implementation of Lean JSON object internals. Reuse a
supported generic mechanism from the VIR owner if one is selected.

## Consumer acceptance for a future owner checkpoint

- Keep graph validation, ordinary-data restrictions and structured failures;
  no accessor invocation or implicit coercion. Keep key and child order.
- Preserve owned references for every returned child/view, including partial
  lifting failures; no stale memory views across allocation or reentry.
- Check empty/singleton/wide containers and exact chunk boundaries; keep shared
  DAG and deep-input controls alongside malformed-input recovery.
- Keep the same input, SDK, options, codec and string-reuse policy on both sides.
  Compare retained warm updates in balanced order using the existing replay.
- Run result equivalence, retained DOM/controls, errors, growth and disposal
  outside headline timing. Collect sampling separately and check whether the
  dispatch/boundary bucket actually moves.

No competing batching prototype, new harness, producer capture, FIR retarget,
live pin change or publication was made in this slice.
