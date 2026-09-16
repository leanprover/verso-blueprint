# Scoped Lean-string reuse in the checked JSON decoder

## Prototype

A research-only wrapper uses the existing VIR object converter and kernel
retain/release exports; neither SDK nor live widget is patched. A per-decode
JavaScript `Map` retains at most 256 immutable Lean strings of at most 64 UTF-16
code units. It covers repeated field keys and small payload strings without a
document-specific schema or persistent runtime cache.

Miss: normal converter creates one owned reference; the table retains another.
Hit: retain the cached object for the normal consumer. Scope exit releases every
table-owned reference, including on failure, and restores the original converter.
Result references belong to the ordinary converter/caller and can outlive the
table. Pointers belong to one runtime; no memory view is cached. Scope calls must
be synchronous; nested scopes on one runtime fail closed. This is an internal
runtime experiment, not a public pointer API or a proposed provider protocol.

## First same-input result

Full FLT response, the same checked codec and FromJson instance, same 70-member
IR package set, VIR `92d7cc91`, matched SDK, production runtime. Decoder-only
order: candidate / baseline / baseline / candidate; eight measured updates per
batch after two warmups. Counters are disabled inside these timing runs.

| Phase | Cache off median (16 updates) | Cache on median (16 updates) |
| --- | ---: | ---: |
| Native JSON parse | 14.0 ms | 13.3 ms |
| Checked graph → Lean.Json | 606.0 ms | 454.6 ms |
| Typed reconstruction and decode tail | 253.1 ms | 225.3 ms |
| Total decode | 875.8 ms | 709.5 ms |

Total decode is about 19% lower in this screening; graph copying about 25% lower.
The two batch contrasts independently improve: 914.8→677.4 ms (26%) and
845.9→744.0 ms (12%). Independent medians are not additive. There are only two
batch contrasts, not sixteen independent campaigns; noise/run-order caveats
remain. A receiver-identity guard was added between candidate batches; each
capture records the helper hash. No cross-campaign cumulative gain is claimed.

Four retained full-preview updates per variant additionally produce identical
normalized DOM/text and preserve checkbox state and unchanged paragraphs, with
zero warnings. Observed total decode-to-DOM medians are 2,175→2,051 ms (6% lower),
but this short single-order render comparison is correctness/representative
screening, not an established whole-widget speedup. RPC/LSP, paint and passive
effect waiting are excluded. Cache cleanup is included in decoder total; its
tail falls after the existing conversion marker.

## Lifetime and bounds

Separate real Chromium/Wasm controls cover `memory.grow(0)` buffer replacement,
ordinary memory growth, unchanged JSON equality, cleanup after a forced error,
original error identity, converter restoration, recovery, and a returned typed
result used after all cache roots are released.

A separate instrumented full-document decode records:

- 69,010 cache hits, 9,879 uncached short-string conversions, 4,316 bypasses.
- Exactly 256 table entries and 256 table roots released.
- The decoded document is readable after table teardown.

Counters are diagnostic only. Twenty-two JavaScript tests pass, including
explicit reference-count controls for a consumer dropping a result before a
later cache hit, bounds/bypass, invalid inputs, nested/async rejection, error
cleanup, inherited converter restoration and disposal-before-entry rejection.
The selected checked codec retains its existing malformed-data rejection gates.

Separate post-change CPU sampling (`codec-string-intern-profile-01`) resolves
1,081 Wasm frame nodes, none unresolved, with 0.215 ms clock uncertainty. Across
four conversion windows, browser `encode` self samples fall from 438 ms in the
earlier no-intern capture to 93 ms with interning (share 14.0%→4.5%); GC share
falls 9.0%→3.2%. These noisy attribution captures support the expected mechanism,
not an independently additive saving or headline elapsed-time comparison.

## Evidence and adoption

Repository-root `_out/upstream-vir-20260917/` contains
`codec-string-intern-{candidate,baseline}-{01,02}`, the two
`codec-string-intern-render-*` captures, and `codec-string-intern-controls-01`.
The controls and CPU sampling are separate from uninstrumented elapsed runs.
Each identity records SDK/IR/input/binding/helper hashes and the cache switch.

The wrapper is enabled only by `VBP_REPLAY_STRING_INTERN=1` in the existing replay
driver. `VBP_REPLAY_STRING_INTERN_CONTROLS=1` runs correctness controls instead of
timings. Live FLT demos and all producer/package pins remain untouched.

Next: ask VIR to review the generic ownership-safe short-string scope in its
actual conversion owner, rather than shipping this private-method wrapper as
VBP infrastructure. FIR needs its own physical-adapter assessment; this result
is VIR-only and says nothing about FIR string retention or performance.
