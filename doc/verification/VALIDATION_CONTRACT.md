# Supplied evidence acceptance

`Validation/Laws.lean` proves the contract of production
`Evidence.mismatch?`. This is the suitability gate used by
`Registry.computeLocalResult` before it can mark a requirement locally complete.
The law module is imported by the test suite, not by production consumers.

`Evidence.mismatch?_eq_none_iff` characterizes acceptance in both directions:

- Evidence identifies the exact requirement and a current, nonblank binding.
- Proof observations identify the expected witness and report its actual goal
  with the same formal context and fingerprint. They must report successful
  dependency-closure checking, even for a subject-only requirement.
- Reviews identify the criterion and a nonanonymous reviewer, cover the requested
  scope, and report acceptance.
- Checks identify the validator, cover the requested scope, and report success.
  Native declaration checks additionally identify the exact declaration subject.
  Generic checks may deliberately omit a declaration.
- Observation kinds cannot substitute for one another.

`Observation.Satisfies` and `Evidence.Fits` express this contract propositionally,
without diagnostic strings or rejection order. The iff theorem connects them to
actual execution; it rules out an implementation that simply rejects everything.
The law layer also proves the executable identity comparisons lawful, so the
corollaries conclude logical equality of identities, not just successful Boolean
comparisons.

The corollaries expose exact requirement identity, binding freshness, invalidation
on a changed binding, independent proof coverage, identified human review, and
native declaration ownership. Prerequisite lists do not affect this local gate:
`mismatch?_prerequisites` makes the separation from Registry closure explicit.

## Trust and remaining boundary

These laws concern **supplied observations**. They do not run a provider, prove
that a witness has its claimed type, authenticate a reviewer, or establish hash
collision resistance. Equality of fingerprints is the production contract; it is
not a theorem about Lean definitional equality. Source documents remain provenance,
not part of goal equality.

Neither the equivalence nor the closure-coverage field proves Registry prerequisite
closure, source availability, completeness of capture, or correctness of its cached
indexes. Those are separate proof obligations. In particular, passing this local
gate is necessary but not sufficient for a completed public realization.

`BlueprintValidationLaws` is a normal Lake test root with explicitly synthetic
observation examples. It checks successful proof/review/native/generic contracts
and stale, cross-project, wrong-kind, missing-object, and insufficient-coverage
cases. `tests/verification/ValidationAxiomAudit.lean` prints all eight public theorem
dependency sets; inspection must reject `sorryAx` or added domain assumptions.

Validation commands:

```sh
scripts/lean-low-priority lake build +VersoBlueprintTests.BlueprintValidationLaws
scripts/lean-low-priority lake lean tests/verification/ValidationAxiomAudit.lean
```

The next bounded proof should connect completed Registry results to nonempty
required contracts and their completed prerequisite closure. That needs an explicit
relationship between admitted input and the derived requirement/result indexes;
no correctness of those indexes is assumed here.
