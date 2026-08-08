# FLT Fujisaki module build profile

Status: exploratory workstation experiment, 2026-08-08. This records target
selection and the persistent-worker result; it is not a regression threshold.

## Scope

The workload is the isolated `.olean` phase behind Lake's
`FLTBlueprint.Chapters.FujisakiProject` job. It excludes compilation of imports,
generated C, native objects, and executables. The measurements use FLT revision
`e4f1595` with `leanprover/lean4:v4.33.0-rc1`.

Local raw evidence is under the root checkout at
`_out/persistent-katex-worker/profiles/fujisaki/`. The earlier baseline evidence
is under `_out/profile-flt-traversal/profiles/flt-html-escape-016/`.

## Result

The persistent worker removes the repeated Node and KaTeX startup cost while
keeping math lint enabled. In comparable structured-profile runs, it reduced
wall time from 24.21s to 12.44s (-48.6%), runtime interpretation from 19.2s to
5.96s (-69.0%), and system CPU from 11.09s to 2.01s (-81.9%). Its wall time is
within run-to-run noise of the 13.00s lint-disabled control.

| Measurement | Original linter | Lint disabled | Persistent worker |
| --- | ---: | ---: | ---: |
| Wall time | 24.21s | 13.00s | 12.44s |
| User CPU | 14.94s | 11.38s | 11.14s |
| System CPU | 11.09s | 2.72s | 2.01s |
| Runtime interpretation | 19.2s | 4.97s | 5.96s |
| Imports | 2.75s | 4.15s | 2.93s |
| Peak RSS | 4,567,868 KiB | 4,565,448 KiB | 4,734,280 KiB |

The persistent-worker profile's first `Informal.Math.inlineMathExpand` call took
137ms, including lazy worker startup and the first KaTeX module load. Each of
the other 134 calls was below the profile's 10ms reporting threshold. With the
original linter, the 135 calls took 15.20s in aggregate.

Peak RSS was about 163 MiB higher in this candidate run. Workstation RSS and
wall measurements vary, so this observation should be checked by a dedicated
benchmark before treating it as a regression.

## Uninstrumented paired runs

Two interleaved, uninstrumented control/candidate pairs were collected while
the workstation load was falling. The absolute wall times are noisy, but the
system-CPU and page-fault reductions consistently show the removed process
startup work.

| Run | Wall | User CPU | System CPU | Minor faults | Peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original 1 | 37.37s | 23.91s | 16.34s | 985,060 | 4,523,220 KiB |
| Worker 1 | 17.67s | 16.45s | 3.48s | 137,400 | 4,699,636 KiB |
| Original 2 | 33.76s | 20.89s | 15.25s | 986,740 | 4,530,056 KiB |
| Worker 2 | 9.88s | 8.68s | 1.89s | 134,487 | 4,703,100 KiB |

The worker reduced wall time by 52.7% and 70.7% in the two pairs, system CPU by
78.7% and 87.6%, and minor faults by about 86%.

## Cause and implementation

The original exact-payload cache did not help Fujisaki's 135 mostly unique
formulas. Each miss started a fresh Node process, imported the vendored KaTeX
module, validated the shared prelude and one formula, wrote one JSON response,
and exited.

The replacement keeps one best-effort worker per Lean process:

- Node imports KaTeX once and serves sequential newline-delimited JSON requests
  over piped stdin/stdout.
- The worker caches prelude validation by trimmed prelude string.
- Lean retains the exact-payload result cache and serializes concurrent requests
  with a lazily initialized mutex.
- A spawn, transport, or protocol failure marks linting unavailable for the rest
  of the Lean process, preserving the existing non-fatal behavior without
  repeatedly trying to restart a broken worker.
- One-shot script invocation remains supported for compatibility and diagnosis.

Live process inspection during the FLT run showed one worker child of Lean. The
worker exited when Lean closed its stdin, and no Node process remained after the
compile.

## Validation

- The focused Lean math-lint test covers valid and invalid source spans, invalid
  preludes, concurrent calls, and repeated use of one invalid prelude.
- The focused test also passes with a deliberately unavailable `node` command.
- The JavaScript entrypoint passes `node --check` and direct one-shot/worker
  protocol probes.
- `VersoBlueprint` builds successfully with the FLT RC1 toolchain, and the
  isolated Fujisaki compile completes with math lint enabled.

## Remaining targets

With math lint no longer dominant, the earlier lint-disabled drill-down selects
external-declaration snapshot construction as the next Blueprint-specific
target. Configuration resolution spent 1.217s in the nested run; a diagnostic
control retaining name resolution while bypassing the full snapshot reduced it
to 0.010s. The next step is to separate name/status lookup, source and Git
provenance, and declaration-HTML rendering before choosing what to defer or
cache. Preview-value evaluation, measured at 0.647s, follows it.
