# Next retained-render target: unchanged sections

The representative workload is a one-paragraph edit in the frozen full-FLT
response, followed by a retained Chromium/React update. The accepted FIR
UTF-8-pool package renders 109,954 elements. The diagnostics-off A-B-B-A
acceptance measured 380.4 ms on average from JSON parse to observed DOM
mutation, including 88.4 ms for parse and typed construction and 292.0 ms from
the decoded document to that observation. These are noisy browser times;
the complete run identities and output checks are in
[FIR_UTF8_POOL_20260922.md](FIR_UTF8_POOL_20260922.md).

## What the browser profile identifies

A separate 1 ms CDP capture of that package recorded four updates. Its
callback brackets averaged 295.2 ms for `decoded-document-to-elements` and
39.1 ms for the two `document-session` calls together. The remaining
render-to-DOM interval averaged 13.9 ms. Those numbers belong only to the
sampled capture; they are not added to the diagnostics-off result.

In the 1,180.9 ms sampled across the four content callbacks, mutually
exclusive self-time buckets were 59.1% FIR Wasm, 28.4% FIR JavaScript adapter,
4.8% host UTF-8 decoding, 2.7% author host bindings, 1.1% shared JS/Wasm
transitions, 0.9% GC and 0.2% React element/hooks JavaScript. The adapter's
largest resolved self frames were resource lookup (116.6 ms across four
updates) and allocation (64.5 ms). The samples establish where work executes;
they do not turn either frame into an elapsed-time saving estimate.

The exact release Wasm, SHA-256
`b70d5b37c7954883a7e456821b7f6d4d31e0ef5903f77ff25c240a9b9f077d87`,
has no surviving internal function-name map. The current capture therefore has
0 named and 1,665 unnamed FIR frames. FIR's preserved-product audit found no
safe way to reconstruct those names from this release. We requested a final
name section or exact companion from the next official 4.34 build; any names
must match every non-custom Wasm section of the executable being profiled.

An earlier projection package did have an exact companion: all 920 sampled
Wasm frames resolved. It found self time in fingerprint hints and lookups
alongside the same host resource/allocation costs. That is historical
attribution for a different executable, not a symbol map for this package.

## Selected experiment

The renderer currently traverses every `Part`, block and inline and builds
their React elements on each document update. React's stable keys retain DOM
state, but the Lean callback still reconstructs the full element tree. The
frozen input has 107 `Part` nodes. Its top-level children are a one-part intro,
the 104-part FLT Blueprint, and a one-part live-edit section. The edited marker
is only in the last section; the FLT subtree is unchanged and occupies
6,588,047 characters when compacted as JSON. This establishes a concrete
unchanged boundary rather than assuming a uniformly distributed edit.

The next bounded prototype should place a retained React component at a
section boundary in the shared `VersoReact` renderer. Its memoized calculation
should depend on the complete content of that section plus the display inputs
that affect it: focus, changed-block highlighting, styles and extension
rendering policy. Unchanged sibling sections can then reuse their element
subtrees, while the edited section and its ancestors update. Use ordinary
React component/hook semantics; keep the existing document and codec types.

The first experiment can cover just the large top-level FLT section and measure
whether its content callback is skipped on the frozen edit; only then extend
the boundary across the renderer. This avoids committing to a large component
split before verifying that the saved work exceeds the hook and comparison
cost. It also avoids comparing a new FIR renderer against an old VIR renderer.

Acceptance should use the same full-FLT response and one-paragraph edit with
diagnostics off, two warmups, retained sessions, and an order-balanced baseline
and candidate. Require identical text and normalized DOM hashes, unchanged
paragraph and checkbox identity, math and extension display, cursor focus,
highlighting, and no React warnings. A separate sampled run should show the
content callback shrinking, with no shift of equivalent work into the session
callback, React reconciliation, or GC. Repeat on the same Lean source with VIR
and FIR once both official 4.34 packages support the component boundary.

This choice has a larger plausible ceiling than another string-conversion
micro-optimization: the content callback occupies most of the current browser
render interval. The actual saving remains unknown until the section boundary
is tested. Server elaboration and transport are separate end-to-end costs.
