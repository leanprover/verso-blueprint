# FLT document runtime-artifact experiment

This experimental code measures Blueprint generation without loading the full
FLT and Mathlib OLean environment into the generator. It is a prototype, not a
supported VBP interface.

The producer computes the erased compiler-IR closure rooted at
`FLTBlueprint.«the canonical document object name»` and writes a synthetic,
non-module `ModuleData` with no imports. The generic compiled host loads that
artifact, evaluates the document constant, and passes it to the normal VBP
renderer.

The experiment was validated with:

- Lean `v4.34.0-rc2`;
- Verso PR #971 at `6c2483eefb453d783ae858142a927bb4bd0bb8c9`.
  This branch pins its fetchable merged commit
  `99e9df791e46ec647f81d98b109965f166b9b6b4`;
- SubVerso `fda188f7329fa18ce4b2e8cc96c9b0a8f0c78c46`, as recorded by that
  merged Verso commit;
- FLT Blueprint `bdba3568faf918df1aa3024c1e69df98e26b7e5d`;
- FLT `79af2058f653d9a20f75ed8b6c2ad3f35bf90e7b`;
- Mathlib `f006b2eec1c31dc47043ca1aff5b670b2d25db0f`.

## Produce the artifact

Prepare an FLT Blueprint checkout using the versions above and this VBP
checkout as its `VersoBlueprint` dependency. From that FLT Blueprint checkout,
run:

```bash
VBP_RUNTIME_BUNDLE_OUT=/tmp/FLTBlueprint.runtime.olean \
  lake lean /path/to/verso-blueprint/experiments/runtime-artifact/RuntimeBundleProducer.lean
```

The producer must run in the FLT Blueprint Lake environment because it imports
`FLTBlueprint` to obtain the document constant and its compiler IR.

To record the closure analysis as JSON as well as produce the artifact, run:

```bash
VBP_CONSTANT_CLOSURE_OUT=/tmp/FLTBlueprint.closure.json \
VBP_RUNTIME_BUNDLE_OUT=/tmp/FLTBlueprint.runtime.olean \
  lake lean /path/to/verso-blueprint/experiments/runtime-artifact/RuntimeClosureProbe.lean
```

## Build and run the generic host

The host subproject depends only on the surrounding VBP checkout:

```bash
cd experiments/runtime-artifact
lake update
lake build runtimeBundleHost
lake exe runtimeBundleHost \
  /tmp/FLTBlueprint.runtime.olean \
  --output /tmp/FLTBlueprint-site
```

For the measured FLT input, the artifact contains 8,733 IR declarations from
79 modules and is 12.13 MiB. The compiled host contains no FLT or Mathlib native
code.

## Implementation status

The prototype directly constructs `ModuleData`, stores entries for
`Lean.IR.declMapExt`, imports the synthetic artifact through
`Lean.ImportArtifacts`, and calls `evalConst` with `checkMeta := false`. These
are version-sensitive implementation details rather than a supported artifact
contract.

The associated measurements and Lake/module-system analysis are recorded in
the [Verso PR #971 follow-up](https://github.com/leanprover/verso/pull/971#issuecomment-5438159244).
