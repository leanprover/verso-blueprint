# Direct typed document decoding: first feasibility probe

The target supersedes inspect-many as the preferred next experiment:

```
parsed RPC JavaScript object → typed Lean Preview/Document → renderer
```

No intermediate `Lean.Json`, per-node `Internal.inspect`, or interpreted
`FromJson` traversal in the candidate. Preserve the existing wire semantics;
do not silently replace custom instance behavior with generic record lowering.

## Existing VIR machinery

Consumer VBP `84ce7170`, VIR `92d7cc91`, Lean 4.34.0-rc2.
VIR's descriptor-guided object ABI remains present. Its interface descriptors
cover structures, custom inductives, recursive references, arrays, options and
scalar types. `ObjectValueRuntime.makeObjectValue` dispatches to layout-guided
constructors; `makeObjectCtorFromLayout` creates owned child objects and
releases its temporary ownership in `finally`. This is a reusable construction
mechanism, not an existing guarantee that an arbitrary RPC JSON representation
is the ABI's structural JavaScript representation.

## First actual classifier result

Lean Beam speculative probe in the existing DecodeProbe module, version 1,
line 208, character 0; no Lean source modification:

```lean
run_elab do
  let type := Lean.mkConst ``VersoBlueprint.Experimental.VirPreview.Document
  match ← Vir.Interface.interfaceType type with
  | .ok _ => Lean.logInfo "DIRECT_DOCUMENT_ABI_SUPPORTED"
  | .error error => Lean.logInfo m!"{error.toMessageData}"
```

The probe successfully executed and reported the first unsupported type chain:

```
Document.document
→ Verso.Doc.Part Manual.title
→ Array (Inline Manual.Inline)
→ Inline.other.container
→ Manual.Inline.id
→ Option InternalId
→ InternalId.id: no projection declaration
```

`MultiVerso/InternalId.lean` defines both constructor and field as private.
The classifier uses `env.find?` on the projection declaration; that declaration
is not available in this importing environment. This is a first classifier
blocker, not proof that all remaining document types are supported or that
runtime construction itself would fail with a complete descriptor.

Its explicit `ToJson`/`FromJson` instances encode/decode a natural number.
Therefore even obtaining its constructor layout does not by itself specify
how RPC JSON maps to the typed object. Other custom codecs need the same review.

## Next bounded work

1. Obtain complete authoritative type/layout descriptors through supported
   owner-environment handling, with one coordinator-assigned VIR writer for
   any generic classifier repair. Do not unprivate Verso fields or hardcode
   constructor layouts in VBP.
2. Identify the wire-to-structural mapping for each reachable type, including
   custom codecs, defaults, constructor tags, null/option behavior and numeric
   validation. Prefer explicit reusable codec rules/generated adapters over
   a handwritten document-schema decoder.
3. Use VIR's existing owned-object construction machinery and scoped reuse;
   qualify failure cleanup, retained results, growth and disposal before
   balanced full-FLT timing in the existing replay harness.

The intended first backend is VIR. No FIR package retarget, live demo pin,
generic VIR source edit, speedup claim or batching implementation was made.

The installed Beam wrapper uses `serve lean`/`stop`, whereas the installed skill
still names `ensure --hold`/`shutdown`; the wrapper's reported current command
surface was used for the owned session. This probe is feasibility evidence,
not a clean batch build or runtime acceptance.

## Local prototype and matched screening

The user subsequently authorized a local VIR-first prototype. No VIR producer
source or live preview was edited. `DirectCodecProbe.lean` now extracts tags,
field slots, scalar offsets and trivial-wrapper information with the pinned
compiler's `getCtorLayout`. A test-only `meta import all MultiVerso.InternalId`
exposes the private owner for this extraction. This bypasses the need for full
public interface classification; it is not a generic classifier repair.

`direct_typed_decoder.mjs` constructs actual typed Preview/Document, Part,
Inline, Block, list/description items and Manual extension records directly.
Constructor-specific writers are resolved at setup. Extension `data` genuinely
has type `Lean.Json`: only those fields construct JSON objects, directly from
JS, without node inspection or interpreted traversal. The entire document does
not become an intermediate JSON tree.

Common short strings use the existing 256-entry scoped string experiment on
both measured paths. A separate conversion-local table retains up to 256 names
and the empty property map; each returned reference is retained for its caller,
and table roots are released in `finally`. Typed names are produced with their
existing Lean codec once per distinct cached name, avoiding guesses about hash
fields. Non-null metadata, server timing and nonempty property maps still use
their original small Lean codecs. This is not yet wholly generated decoding.

The experimental JSON-field adapter builds a balanced raw map from sorted unique
keys, comparing Unicode scalar values rather than UTF-16 code units. Layouts
come from Lean, but the raw-map algorithm and wire-to-constructor rules remain
pinned implementation knowledge. Do not ship this as a public generic codec.

### Decode timing

Diagnostic-off full-FLT replay, two warmups and eight measured decodes per fresh
runtime batch, order C/B/B/C. Same package, layouts, source hashes, SDK, input,
string reuse and untimed setup controls independently verified across batches.
Package: 71 members, 2,776 declarations, 16 interface exports. Build passed via
the public `+VersoBlueprintVirTests.NativeSession.DirectCodecProbe:vir` facet;
Beam sync reported zero errors. This was not a clean repository-wide build.

| Batch | Decoder | Median parse + decode |
| --- | --- | ---: |
| candidate-03 | Direct typed prototype | 307.3 ms |
| baseline-01 | Checked JSON + FromJson | 898.9 ms |
| baseline-02 | Checked JSON + FromJson | 974.6 ms |
| candidate-04 | Direct typed prototype | 376.8 ms |

| Pooled median, 16 samples per path | Baseline | Prototype |
| --- | ---: | ---: |
| JSON.parse + decode | 940.0 ms | 352.3 ms |
| Decode excluding JSON.parse | 921.5 ms | 316.2 ms |
| JSON.parse | 18.5 ms | 19.6 ms |

Total median is 62.5% lower (about 2.7× faster); paired batch reductions are
65.8% and 61.3%. This is browser codec screening, not end-to-end widget latency
or a FIR comparison. Independent phase medians do not sum to total medians.
No CPU sampler, per-node counters, forced GC, RPC, DOM work or paint is included.

Captures live under repository-root `_out/upstream-vir-20260917/`, with the
prefix `direct-typed-decoder-` and batch suffixes above. Each retains raw rows,
layout JSON, source files/hashes and exact package hashes. Earlier candidate-01
is the transitional per-extension-leaf version; candidate-02 is preliminary
unbalanced screening. Neither belongs to the final C/B/B/C aggregate.

### Correctness and remaining scope

Outside timing, the actual Wasm runtime verifies full typed-value equality
against `Preview.decode` for FLT and fixtures covering all Inline and Block
constructors, Preview states, IDs, property maps, extreme safe integers and
Unicode-key ordering. Results remain usable after grow(0)/grow(1); malformed
and partially constructed inputs are rejected, and subsequent decoding works.
Both measured paths execute the same controls before warmup.

Three mock-runtime ownership tests check independently owned results/table
roots, complete partial-allocation cleanup, original allocator error identity,
recovery and rejection after disposal. These supplement real-Wasm acceptance;
they are not proof of all allocator/runtime behaviors.

The prototype is selected explicitly by the replay driver, not production RPC.
Malformed schema inputs currently throw JS errors rather than reproducing the
original `Except` diagnostics; arbitrary custom FromJson/default semantics,
unbounded-depth construction and a generic generated codec are not qualified.
Do not replace the production decoder on these results alone.

### Retained renderer check

The same real preview component produces identical normalized DOM and text
hashes for both paths: 7,011 elements, retained checkbox state and retained
paragraph identity, no React/browser warnings. Captures:
`direct-typed-render-{baseline,candidate}-01` under the same output root.

| Median, four measured edits per path | Baseline | Prototype |
| --- | ---: | ---: |
| Decode | 798.1 ms | 204.0 ms |
| Render through observed DOM commit | 1,411.9 ms | 1,338.4 ms |
| Decode through observed DOM commit | 2,191.3 ms | 1,558.5 ms |

This renderer pair is B/C only, unlike the balanced decoder campaign. Its
roughly 29% total improvement is screening, not a settled whole-widget claim.
Renderer timing has a different yielding/session-age workload from tight-loop
decoder replay; do not combine their phase numbers. RPC/LSP, server encoding,
transport, initialization, passive-effect waits and paint remain excluded.
