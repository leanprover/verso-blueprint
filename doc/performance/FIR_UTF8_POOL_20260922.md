# FIR UTF-8 buffer-pool experiment

This report isolates one consumer-side FIR adapter cost on the retained full-FLT
renderer workload. It is an experimental result, not a live demo pin or a FIR
package release.

## Producer-package acceptance (2026-09-23)

FIR returned diagnostic package `b5b3a053e4135f913504a376` implementing the
same mechanism in its generic adapter. Its Wasm is byte-identical to the
accepted baseline; only the JavaScript adapter and package metadata differ.

A fresh diagnostics-off A-B-B-A Chromium replay used the same frozen full-FLT
response, production React, two warmups and eight measured retained updates per
run. A is accepted package `1c3b87b3f270114a3a56eeb7`; B is the producer
candidate.

| Phase | Baseline mean | Producer candidate mean | Change |
| --- | ---: | ---: | ---: |
| JSON parse | 12.75 ms | 12.74 ms | unchanged |
| FIR codec / typed construction | 124.2 ms | 75.6 ms | **-39.1%** |
| Parse + typed construction | 136.9 ms | 88.4 ms | **-35.4%** |
| Decoded value to observed DOM | 311.9 ms | 292.0 ms | -6.4% |
| Total to observed DOM | 448.9 ms | 380.4 ms | **-15.2%** |

The pooled total median was 406.3 ms for A and 373.3 ms for B; the pooled codec
median was 123.4 ms and 71.3 ms respectively. Means are shown above because the
phase means preserve the measured total decomposition; phase medians are not
additive.

Every run produced 109,954 elements, the same DOM and text hashes below, zero
warnings, and retained checkbox and paragraph identities. FIR's producer gates
also cover forced memory growth, nested allocator/provider reentry, conversion
failure, independent retained sessions and disposal rejection.

A separate 1 ms CDP diagnostic confirms the mechanism: the baseline sampled
profile contains 128.9 ms of `TextEncoder.encode` self time in the checked-codec
window; the producer candidate contains no sampled `encode` frame and 52.0 ms
of `encodeInto`. Sampling perturbs the workload, so these durations are
attribution evidence rather than headline timing. FIR internal frames remain
unnamed for this release Wasm.

Producer identities:

- candidate `BUILD.json` SHA-256:
  `2997668b91ee23d67bee4cafc156e247e222ff575842621758780d88d3258382`
- candidate `SHA256SUMS` SHA-256:
  `ff9a5b8507d85b37816b02e18dcb5943512faf8e54ec90c6e91f1ca46e62855e`
- byte-identical baseline/candidate Wasm SHA-256:
  `b70d5b37c7954883a7e456821b7f6d4d31e0ef5903f77ff25c240a9b9f077d87`
- FIR handoff SHA-256:
  `5d6694da8108ee890a1c4895d8ee1824fcf0f325ba38e9268aac8c130eebd392`
- compressed VBP raw acceptance bundle:
  `_out/native-jsx-qualification/fir-utf8-producer-acceptance-20260923.tar.gz`,
  SHA-256
  `33cf7e35548b4d5ed0c38d92f4ba9c33cc655f2972f7f647f911026e08b82fbc`

Disposition: **accepted for producer integration**. This does not authorize a
VBP live-pin move or publication. Once FIR ships the adapter in the official
4.34 package, VBP should remove its consumer transformer and repeat the compact
correctness gate rather than maintaining two implementations.

## Initial VBP prototype result

The original package adapter converts every JavaScript string with
`TextEncoder.encode`, allocates the corresponding Lean string, and then copies
the temporary byte array into Wasm memory. The initial VBP transformer replaced
that path with `TextEncoder.encodeInto` and a depth-indexed reusable buffer
pool. It reduced the coarse typed-construction interval by about **19%**; the
producer-package acceptance above supersedes this screening estimate.

| Adapter | Runs × updates | Total to observed DOM, mean | Typed construction, mean | Render to observed DOM, mean |
| --- | ---: | ---: | ---: | ---: |
| Package adapter | 2 × 8 | 430.0 ms | 119.5 ms | 310.5 ms |
| Reentrant UTF-8 pool | 2 × 8 | 374.0 ms | 96.7 ms | 277.3 ms |
| Change |  | -13.0% | **-19.1%** | -10.7% |

The total and render-to-DOM intervals include browser scheduling and React DOM
work, so their apparent improvement is supporting evidence rather than an
isolated renderer claim. The typed-construction interval is the primary result.

All four runs rendered 109,954 elements with identical text and DOM hashes,
zero warnings, and retained checkbox and paragraph identities:

- text SHA-256:
  `d9cad458f14637b81d3ba78d230130414fea63ff1f1507a85b4a4c0365252ceb`
- DOM SHA-256:
  `e2f8fc9599a51fc4e471aab2fc6b3833ebea42f648f7c0f5b4a8c736cd4ba056`

## Why the pool is reentrancy-safe

A single shared scratch array is not sufficient. `fir_heap_alloc` crosses into
Wasm and may reenter a host conversion before the outer call copies its bytes.
The candidate therefore leases `stringScratch[stringScratchDepth]` until the
complete conversion returns. A nested conversion increments the depth and uses
a different slot. The depth is restored in `finally`, including allocation
failure.

The destination `Uint8Array` is acquired only after allocation returns. Thus a
Wasm memory growth cannot detach a destination view retained across the call.
The pool contains only JavaScript memory; no Wasm view, pointer, or header is
cached.

An alternative candidate scanned the JavaScript string to compute its UTF-8
length and then encoded directly into final Wasm memory. It was rejected: the
second pass raised typed construction to roughly 134 ms, slower than the
unmodified adapter.

## Sampled attribution

Sampling was performed separately from the timings above with a 1 ms CDP
interval. The capture clock uncertainty was 0.325 ms. FIR internal symbols were
not available for this package, so no internal Wasm attribution is claimed.

| Sampled window | Package adapter | Buffer pool |
| --- | ---: | ---: |
| FIR checked-codec callback | 425.8 ms | 346.3 ms |
| Browser parse + decode | 470.0 ms | 397.3 ms |
| UTF-8 builtin self time | `encode`: 128.9 ms | `encodeInto`: 42.9 ms |
| Decoded document to elements | 1093.2 ms | 1094.9 ms |

The unchanged document-to-elements sampled duration is useful: this change
targets JavaScript-to-Lean string construction rather than the compiled
renderer. Sampled durations are attribution evidence and are not combined with
the unsampled headline timings.

## Exact inputs

- VBP base commit: `e32f8b0f8a152ff8509183e38adcef36f666ccec`
- VIR commit recorded by the capture:
  `cddcc35a46fd4683d2437369072d4ecc5a5a84be`
- FIR package id: `1c3b87b3f270114a3a56eeb7`
- FIR commit recorded by the package:
  `d03b655efb547023cb90d0d4898bfe1562ccfda1`
- FIR Wasm SHA-256:
  `b70d5b37c7954883a7e456821b7f6d4d31e0ef5903f77ff25c240a9b9f077d87`
- FIR package `BUILD.json` SHA-256:
  `0d8e63fc792486ba42091197095338384f71b2fcd6b45f2d09748d4415b3ee17`
- FIR package manifest SHA-256:
  `dfa13acc5d0f3ea7a8fc7cfb8e0ed8c3b02862f9be8cc4e49d17606ece166615`
- frozen response SHA-256:
  `a051cbe264e2df997b5e70f4b3382fd9134e65e836fb81d5334fdb89fe717f3b`
- toolchain recorded by the package: Lean `4.34.0-rc2`

Unsampled captures:

- `_out/native-jsx-qualification/current-fir-baseline-02`
- `_out/native-jsx-qualification/fir-utf8-pool-screen-01`
- `_out/native-jsx-qualification/fir-utf8-pool-screen-02`
- `_out/native-jsx-qualification/current-fir-baseline-03`

Sampled captures and derived report:

- `_out/native-jsx-qualification/current-fir-profile-01`
- `_out/native-jsx-qualification/current-fir-profile-summary-01`
- `_out/native-jsx-qualification/fir-utf8-pool-profile-01`
- `_out/native-jsx-qualification/fir-utf8-pool-profile-summary-01`

## Disposition

The VBP transformer is intentionally fail-closed against the exact producer
source boundary. The durable form belongs in FIR's generic JavaScript adapter,
with its allocator reentry, forced-memory-growth, malformed-input, retained
callback, and disposal gates. VBP should then delete this source transformer and
qualify the released adapter package on the same frozen input.
