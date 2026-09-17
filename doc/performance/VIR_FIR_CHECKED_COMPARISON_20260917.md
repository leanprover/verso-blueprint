# Matched checked-codec VIR/FIR FLT replay

This screening comparison uses the same checked codec and frozen pre-style-reuse
renderer on both backends. FIR is not established as equally fast: rendering
is close relative to the observed variation, while checked decoding is slower.
The contrast includes each backend's physical adapter and allocation policy;
it is not isolated Wasm instruction throughput.

## Matched workload

- Lean 4.34.0-rc2; VIR `92d7cc91`; production React 19.2.7.
- Frozen source `bc9685f9`, VBP `99caaacb`; no `239e423c` style reuse.
- VIR consumes the retained `styles-baseline-ir/DecodeProbe.irpkg-set.json`,
  not the newer module set in `.lake/build`.
- FIR consumes provisional package `23dfd8ab282aa8b5b0b7d90b`, root-accepted
  locally in `ROOT-W7-20260917-010`, without live adoption or publication.
  Wasm SHA256:
  `fa24e89b608d63b08c3c683f95f97d992862e3b756cc14827d96a4df1c4df5aa`.
- Both use JS JSON.parse, the checked native JS graph provider, Lean.Json
  reconstruction and FromJson Preview. The provider source matches the frozen
  bc9685f9 archive byte-for-byte: SHA256
  `fdc0b922c81552b888986af98cb8e2111b8fb596562fca591f1f7707674394a6`.
  VIR-only direct conversion, interning and scratch optimizations are disabled.
- Renderer.lean and Component/Content.lean match between FIR's original compiled
  source snapshot and bc9685f9 (SHA256 `2cfb6ac8...` and `d202f018...`).
- Same captured full-FLT input, 6,598,356 bytes; SHA256
  `6ae2daf7641f9d8ae76d48a0bf57bc63a0d25c886c299643b487bfbf8fe6e2c3`.
- Initial mount, follow-cursor control change and two warmup updates precede
  four measured edits per fresh browser/runtime session. Debug/highlighting off;
  default view, no configured native math. CPU sampling and callback probes off.

The existing Chromium harness is reused. Input construction and correctness
checks are outside timing. Four coarse browser-clock timestamps separate parse,
checked codec and decoded Preview to MutationObserver acceptance after React DOM
commit. The final observation is not paint or an isolated VDOM timer. Excluded:
RPC/LSP, server encoding, transport, package loading, instantiation, initial mount,
paint and passive-effect waiting. Independent phase medians must not be summed.

## Results

Order is VIR → FIR → FIR → VIR (AB/BA). Two sessions and eight measured updates
per backend. Pooled medians below retain all samples, including the FIR outlier.

| Observed boundary | VIR | FIR |
| --- | ---: | ---: |
| JS JSON.parse | 19.0 ms | 15.4 ms |
| Checked graph → Lean.Json → typed Preview | 901.7 ms | 1,122.6 ms |
| Parse plus checked decoding | 922.7 ms | 1,137.3 ms |
| Decoded Preview → accepted DOM | 1,503.0 ms | 1,580.1 ms |
| Parse start → accepted DOM | 2,443.5 ms | 2,797.3 ms |

Session medians, milliseconds:

| Sequence | Capture | Checked codec | Preview → DOM | Total |
| --- | --- | ---: | ---: | ---: |
| 1 | checked-balanced-vir-01 | 859.4 | 1,421.7 | 2,304.5 |
| 2 | checked-balanced-fir-01 | 1,102.2 | 1,575.7 | 2,713.0 |
| 3 | checked-balanced-fir-02 | 1,263.5 | 1,651.8 | 3,033.5 |
| 4 | checked-balanced-vir-02 | 987.5 | 1,613.9 | 2,589.6 |

FIR-minus-VIR differences of session medians are +242.9/+275.9 ms for the codec,
+154.0/+37.9 ms for render-to-DOM, and +408.5/+443.9 ms for total, for the two
order-reversed pairs. These are descriptive pair differences, not confidence
intervals. Update-level render ranges overlap: VIR 1,341.6–1,785.6 ms;
FIR 1,232.9–3,491.4 ms. Total ranges are VIR 2,199.2–2,777.2 ms and
FIR 2,346.3–4,746.3 ms. There is visible session drift on both backends.

Decision: codec overhead is the clearer differential target. The pooled render
gap is about 5%, but this small campaign does not establish a reliable rendering
advantage. The earlier FIR content-callback timing must not be compared directly
to VIR's whole render-to-DOM interval.

## Output and retention

All four captures produce exactly the same final DOM hash:
`4678d8b39055efd4f805b38025dc8c9a36bcbc77d9375ad8685b186a9e327213`.
The text hash, 7,011 elements, checkbox identity/state and unchanged paragraph
are also preserved; no warnings. This qualifies this slice, not every branch.

Session age is matched, but retention policy is not interchangeable. FIR's
monotonic arena/resources remain session-owned until unmount/dispose. Its
measured frontier rises from 125,604,112 to 211,173,072 bytes, and resources
from 1,260,777 to 2,061,228 (266,817 per update), identically in both sessions.
Those existing adapter stats are read outside timing. Growth is not by itself
evidence of a leak. FIR bootstrap also creates the configured factory before
the default view; that startup is excluded, but its retained resources remain.

## Evidence and symbols

Captures live under `_out/upstream-vir-20260917/` at the repository root.
Each named directory retains result.json with every raw sample and full DOM,
identity.json, source copies, generated driver, input and artifact checksums;
FIR directories additionally retain the verified complete package copy.
Logs are `/tmp/<capture-name>.log`.

Reproduction from the `upstream-vir-20260917` worktree:

```bash
env VBP_REPLAY_RENDER=1 VBP_REPLAY_UPDATES=4 \
  VBP_REPLAY_CHECKPOINT_COMPARISON=1 \
  VBP_REPLAY_PACKAGE_SET=/home/egallego/lean/verso-blueprint/_out/upstream-vir-20260917/styles-baseline-ir/DecodeProbe.irpkg-set.json \
  node tests/vir_preview/decode_browser_smoke.mjs \
  /home/egallego/lean/verso-blueprint/_out/browser-pr188/widget-baseline-inputs \
  /home/egallego/lean/verso-blueprint/_out/upstream-vir-20260917/<fresh-capture-name>
```

For FIR add `VBP_REPLAY_FIR_PACKAGE` pointing to the immutable package documented
in [the frozen FIR profile report](FIR_FROZEN_REPLAY_20260917.md). Run sequentially
in the recorded AB/BA order; do not enable sampling for headline timing.

FIR's current Wasm has no name section. Root-reviewed `ROOT-W7-20260917-012`
establishes that internal names are unavailable from preserved products: all
eight audited binaries are stripped, no final function map survives, and native
merge/metadce/optimization did not preserve raw encoder identity. The exact
index space is 37 imports followed by 3,245 definitions. Declaration or closure
order is not an index map. Existing sampled captures remain internally unresolved.

Audit: `FUNCTION-ORIGIN-AVAILABILITY.json`, SHA256
`b2a9225eaa81eee8a9c7421ca8d35c01930026d6b9ea9042e5df759c7d8e482f`,
under FIR's `.worktrees/wasm-generation-4.34/.deps/native-session-probe/`.
The audit recipe SHA256 is
`c052fb7a07f891b60b9ae0bb1935a5b817ee6dc9596b52ba92e1ef37b60550f6`.
The first bounded diagnostic attempt (`ROOT-W7-20260917-013`, closed in `-014`)
also found missing private ConfiguredSdk/CodecSdk/compiler-context products.
Replaying the prior recipe would compile those private products, forbidden in
that slice. The shared consumer owner subsequently authorized only the exact
frozen private SDK/context replay (queue receipt
`01a0ae95-b1db-73c2-8526-6872ece02a00`), not source-closure recapture or retargeting.
Raw/resident bytes must match authenticated prior stages before name transport;
release artifacts and live pins remain unchanged. Producer root owns disposition.

The offline summarizer now accepts `--fir-named-wasm=FILE --out=FRESH_DIR`.
It rejects names unless **all non-custom sections** equal the captured FIR Wasm,
records both hashes and resolution counts, and writes a separate profile/report.
Synthetic-name integration controls pass exact-match acceptance, mismatched
module rejection, missing-name rejection and output-overwrite rejection. These
are parser guardrails, not real FIR symbols. No new capture is needed for a
matching named artifact. A differing diagnostic artifact instead requires its
own diagnostic capture; its names must never be applied to the old profile.

```bash
node tests/vir_preview/summarize_replay_profile.mjs \
  /home/egallego/lean/verso-blueprint/_out/upstream-vir-20260917/fir-bc968-profile-03 \
  --fir-named-wasm=<verified-producer-artifact> \
  --out=<fresh-report-directory>
```

Real internal symbol attribution remains pending the producer handoff.
