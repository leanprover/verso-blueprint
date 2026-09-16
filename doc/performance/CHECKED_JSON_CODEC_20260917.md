# Checked native-JSON codec investigation

## Scope and decision

Keep the explicit native JSON → `Lean.Json` → author-selected `FromJson` path.
No document-specific JavaScript decoder, alternate wire format, hidden checked
object cache, or production runtime patch was introduced. Develop here before
sending a consolidated request to VIR. Live demo pins are unchanged.

The profiling skill owner received `01a0ac73-cef3-7281-a461-55c86924992d`
with browser/Wasm reference suggestions. The profiling skill guides separation
of focused timings, representative replay and sampled attribution.

The active replay no longer times the plain Lean JSON parser. It uses only the
checked codec; untimed JSON/schema equivalence checks still use the parser as
an oracle. Existing historical captures and the parser API itself remain.

## Implemented local candidate

- Validation uses linked diagnostic paths, formatted only for errors.
- The validation walk no longer constructs conversion views, child payload
  arrays, field tuple wrappers or BigInts.
- Conversion no longer repeats graph validation per node. The private Lean
  `Internal.inspect` is called synchronously only after `Internal.check` has
  accepted the whole graph. It reads checked dense arrays directly and uses
  ordinary-object keys, avoiding a second descriptor/prototype/string pass.

Entry validation still rejects accessors without invoking them, cycles, sparse
arrays, extra array properties, symbols, non-enumerable fields, wrong prototypes,
unsafe numbers, negative zero, invalid UTF-16 and SDK-owned Lean handles.
Proxies and concurrent mutation remain outside the ordinary-data contract;
external inspection errors are reported without invoking coercion hooks.
There are no awaits or user callbacks between checking and copying.

Real Chromium acceptance covers seven valid values, fourteen invalid values,
three exact error paths and a depth-2,000 iterative validation case. Full FLT
replays retain the checkbox state and unchanged paragraph. The final baseline
and candidate both use six updates and have identical normalized DOM/text
hashes, with no warnings. Eight additional valid JSON cases, four source-domain
rejections, ten invalid JS/handle cases and malformed typed payloads pass through
the real decoder. Twenty existing JavaScript unit tests and syntax/diff checks
pass. No Lean source or IR package changed for this candidate.

## What the measurements establish

Same Lean source/IR set, VIR `92d7cc91`, SDK, response bytes and production React.
All raw captures are under `_out/upstream-vir-20260917/` in the repository root.
The copied original binding file is `codec-bindings-baseline.mjs`; the replay
records the selected binding path and SHA256 separately from its own sources.

Eight decoder-only measured updates after two warmups give:

| Phase | Original binding median | Candidate median |
| --- | ---: | ---: |
| JavaScript parse | 15.7 ms | 16.0 ms |
| Checked graph → Lean.Json | 814.9 ms | 778.4 ms |
| FromJson typed reconstruction | 302.3 ms | 298.7 ms |
| Total decode | 1,124.3 ms | 1,091.3 ms |

These are independent medians. Captures are
`codec-checked-phases-{candidate,baseline}-01`, collected in that order.
The modest difference is screening evidence, **not a demonstrated speedup**:
short render-inclusive batches vary substantially, and the candidate's final
six-update decode median was 1,127 ms versus the following baseline's 1,072 ms.

Focused graph-validation-only batches, original/candidate/candidate/original,
have medians 42.9 / 43.3 / 36.4 / 48.8 ms (16 samples each). Validation is a
small fraction of total decoding; this cleanup alone cannot remove the main
cost. The first allocation-only candidate likewise did not show a clear win.

## Attribution and next target

Separate CDP 1ms capture `codec-checked-phases-profile-01` has accepted clock
uncertainty 0.459 ms and 1,241 resolved Wasm frame nodes, zero unresolved.
Release and named Wasm executable sections match.

In the **conversion** window, sampled self time is 62.3% JavaScript/browser,
17.1% interpreter evaluation, 4.7% name lookup, 6.2% allocation/refcount and
9.7% other Wasm. The inclusive host-boundary share is 57.7%; it overlaps the
self buckets. Hot self frames include `encode` (14.0%), browser GC (9.0%),
`makeObjectCtorFromLayout` (4.2%), `readObjectArgv` (3.6%) and `withWasmString`
(3.2%). This is string/object ABI copying, not another JSON stringify operation.

Typed **reconstruction** is mostly interpreted Lean: evaluation 52.6%, name
lookup 17.8%, allocation/refcount 12.0%, other Wasm 17.3%. JavaScript is 0.2%.
FIR compilation may help this part; no current same-source FIR claim is made.

The captured native tree has 73,192 nodes: 30,423 objects, 6,847 arrays,
25,815 strings, 6,343 nulls, 2,121 numbers and 1,643 booleans. The current Lean
reader invokes the inspect boundary once per node. Object keys have 57,390
occurrences but only 102 distinct values; string payloads comprise about
5.34 MB of UTF-8. This gives concrete targets: fewer per-node boundary calls,
less generic structural-ABI allocation, and reduced repeated string-key copying.

Any batching or string sharing must remain a generic checked JSON operation
with explicit ownership, not a VBP document schema decoder. Do not introduce a
runtime-wide cache or new protocol merely to improve the small validation
bucket. First qualify the shared FIR codec roots, then choose the smallest
generic boundary experiment from this evidence before informing VIR.

## Replay controls

`VBP_REPLAY_UPDATES` selects measured checked-codec updates (default 16).
`VBP_JSON_BINDINGS_FILE` selects an explicit baseline/candidate binding file.
`VBP_REPLAY_VALIDATION_ONLY=1` selects the focused JS validation boundary.
`VBP_REPLAY_RENDER=1` includes retained React/DOM acceptance; otherwise the
decoder-only run reports parse/conversion/reconstruction separately.
`VBP_REPLAY_PROFILE=1` takes a separate sampled capture in either full mode.
Focused validation cannot be mixed with CPU sampling. No extra phase hooks were
added to the live widget.
