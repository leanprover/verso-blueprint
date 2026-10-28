# Validation evidence and public completion

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
cases. `tests/verification/ValidationAxiomAudit.lean` prints the public theorem
dependency sets; inspection must reject `sorryAx` or added domain assumptions.

Validation commands:

```sh
scripts/lean-low-priority lake build +VersoBlueprintTests.BlueprintValidationLaws
scripts/lean-low-priority lake lean tests/verification/ValidationAxiomAudit.lean
```

## Public completion cannot omit a selected contract

`Translations/Laws.lean` proves `Registry.complete_requires_all` about the actual
public `resultFor` query: completion implies a nonempty `requiredFor` list, and
every key in that list has a completed `resultForRequirement`. Its corollaries
exclude completion with empty requirements, an unfinished selected requirement,
or an unknown subject. The theorem quantifies over Registry values without assuming
that their cached maps are correct; it establishes how the query uses those maps.

The query canonicalizes requirements before testing them. The proof therefore
includes the actual collection path, rather than assuming it cannot drop work:

- `QSortLaws.qsort_perm` proves Lean's production quicksort preserves the input
  multiset, for any comparator and selected subrange. The small law module uses
  `import all` to prove the internal partition/sort steps for the pinned Lean
  version; no production sort is replaced or axiomatized.
- `Realizations.mem_canonical` proves exact membership through quicksort and
  adjacent deduplication. It requires lawful executable equality, but no ordering
  laws. `canonical_eq_empty_iff` proves nonemptiness is preserved as well.
- `complete_requires_all` consequently covers the original `requiredFor` list,
  not merely the canonicalized list tested by the implementation.

The normal test root also admits synthetic bound observations through the real
Registry API. It checks positive completion, repeated/reordered requirements,
empty contracts, unfinished selected versus unselected requirements, and missing
subjects. These examples rule out vacuous coverage by an always-rejecting query;
the new Registry theorems themselves are necessary-condition guarantees.

The axiom audit now covers fifteen public theorems: eight evidence laws,
three collection laws, and four public-query laws. All proof imports remain in
the law/test layer. There are no production behavior changes.

## Next boundary: admission and cached prerequisite closure

`requiredFor` is itself a derived index. The public-query theorem does not yet
prove that it contains exactly the authored requirements. Similarly, a completed
cached requirement result must still be connected to accepted local evidence and
the closure of its prerequisites. Canonical membership removes one collection
assumption from that future proof, but does not establish those cache invariants.

A next ticket should state the invariant over Registry values returned by successful
`admit`, relate requirement/local/result lookups to the same admitted input, and
then show that unmet or cyclic prerequisites prevent completion.
Do not assume correctness of the cached maps or conflate provider-reported coverage
with the Registry's own prerequisite graph. This is separate from proof of the
native provider, content-fingerprint collision resistance, and capture completeness.
