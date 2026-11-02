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

All proof imports remain in the law/test layer. There are no production behavior
changes.

## Admission connects public completion to original evidence

`Translations/AdmissionLaws.lean` now proves the cache-construction bridges from
successful production `admit`, rather than requiring callers to assume them.
`admit_sources` preserves the original contributions and characterizes all nine
canonical source arrays. Membership corollaries preserve whole requirement,
evidence, realization, translation, and claim records.

The required-cache laws connect known subjects to their selected authored records:
realization contracts include their own, facet, and declaration requirements;
translation contracts include claim requirements. The conflict-check laws prove
that accepted same-key source records agree, and the lookup iff laws establish
exact membership against original contributions. The reference-check proof shows
that authored realization contracts have collected definitions. Consequently,
`admit_requiredFor_facet_mem_iff` proves that the facet cache preserves every
authored requirement, despite its implementation using a lookup intersection.

`admit_local_complete_evidence` connects a cached local success to an original
input requirement and evidence record satisfying `Evidence.Fits` at the current
binding. `admit_complete_requirement_local` proves that prerequisite evaluation
cannot create local success. This latter result holds for any component list,
so it does not assume correctness of the opaque Tarjan traversal.

Together, `admit_complete_selected_evidence` gives the admission-to-query result:
every contract selected by a completed public subject has original fitting
evidence. `admit_stale_evidence_incomplete` shows that stale evidence cannot
become complete through reindexing or completed prerequisites.

`admit_complete_authored_realization_evidence` combines these guarantees for every
original authored realization record: its own, facet, and declaration requirements
all have fitting original evidence when the realization is complete. This does
not depend on which same-key record happened to be inserted last.

`admit_bindings_evidence` proves that changing only evidence preserves every
content binding when both full inputs are admitted. Evidence cannot affect its
own digest. This is equality of the actual computed bindings, with no hash
injectivity or collision-resistance assumption.

`admit_complete_proof_sources` follows the independent-proof availability gate:
completion requires an original resolved witness observation, its original
nonblank source document, and the exact expected-goal semantic-input identity.
These are supplied records; the theorem does not assert that their text was read
from a particular file or that the semantic input was produced by a trusted checker.

The production admission module predates Lean's module system. A law-local
name-resolution scope opens its imported private declarations for proofs; it
exports no aliases and changes no production visibility. Proof terms reference
the original declarations and remain kernel checked. The audit covers all public
theorems, including these admission laws.

## Prerequisite soundness without an SCC assumption

The stronger `admit_complete_induction` proves a rule for actual completed results:
any property preserved by local success plus already justified prerequisites holds
for every completed requirement. Its proof follows the production evaluator's
two loops and checks, for an arbitrary component sequence. A component may certify
a member only when it is a singleton without a self-edge and all prerequisites
already have completed entries. Other branches insert blocked results.

This gives kernel-checked consequences about the actual admitted dependency graph:

- `admit_complete_accessible`: completion has a well-founded prerequisite
  justification (`Acc`), without assuming the graph is acyclic in advance.
- `admit_complete_prerequisites_evidence`: every transitive prerequisite has its
  own fitting original evidence at its own current binding.
- `admit_cycle_incomplete` and `admit_reachable_cycle_incomplete`: a cycle cannot
  certify itself or a consumer, even with individually suitable observations.

The graph traversal remains a `partial` definition, opaque to kernel reduction.
No theorem about its output or termination is assumed in these soundness proofs.
They constrain what the consumer can certify regardless of the traversal's result.

## Capture and rendering assessments

`Realizations/Capture/Laws.lean` connects the real pure producer entry point to
these laws. `evaluate_admitted` proves that successful `Capture.evaluate` returns
a registry admitted from exactly its retained contributions. The proof follows
the actual final admission in `finish`; it does not introduce another evaluator.

The consumer bridge `evaluate_assessment_evidence` reaches the rendering
`Snapshot.assessmentFor` view: its `requiredComplete` flag implies original fitting
evidence for every selected requirement. A completed native assessment also
requires a native realization with at least one declaration.

The separate `evaluate_native_statement_evidence` and
`evaluate_native_proof_evidence` theorems establish fitting observations for every
selected declaration, with the exact statement/body validator and dependency
coverage. These flags describe local native checks, not independent-goal proof or
completion of Blueprint prerequisites. The distinction is retained in the proofs.

`evaluate_valid_handles` proves successful evaluation checks all seven observation
families for in-range, unique handles. Even repeated equal payloads are rejected
when their handles repeat. The plan's type parameter alone does not enforce these
properties; the proof covers the actual insertion checks. This is batch shape,
not authenticity or completeness of the provider inventory.

The observation-table boundary now has positive and exact guarantees as well:
`indexResults_success_iff` accepts precisely in-range, unique-handle batches;
`indexResults_lookup_iff` preserves exactly their original handle/result pairs.
`lookupResult_success_iff` transfers that guarantee through the actual provider
adapter, ruling out a fabricated default for a missing handle. Permutation laws
preserve acceptance and every lookup, without asserting equality of the internal
hash-table layout. These proofs cover the real `indexResults` and `lookupResult`
functions used by `evaluate`, for every result type and plan family.

“Original” evidence at this capture boundary means the contributions retained by
the captured registry. These theorems do not yet prove that every assembled record
comes from a particular entry in the supplied observation batch. The real-provider
capture tests exercise that connection, but it is a separate proof obligation.

## Provider observations through the collection recipe

`Realizations/Capture/RecipeLaws.lean` follows the actual ordinary, authored,
dependency-wiring, and finalization functions. Its loop invariants establish that
retained native checks come from successful provider results, and that collection
does not inject pre-bound evidence into the input. Authored independent-proof
observations, generated dependency-selection checks, and unavailable native
fallbacks remain distinct cases.

`evaluate_nativeChecks_source` reaches the public snapshot: each retained native
check is exactly an original successful `observations.checks` result at an in-range
handle. Both constituent observations identify the plan request's witness and use
the exact statement/body validators. Whole checked records are preserved, including
kind, status, coverage, assumptions, and explanations; the theorem does not merely compare
outcome flags. `finish_nativeChecks` separately proves that dependency wiring and
final admission preserve the complete native-check inventory.

`evaluate_native_evidence_source` closes the native recipe-to-evidence connection:
a passed native statement/body observation in the final registry's retained
evidence is an unchanged field of an original successful check-batch result.
Generated policy checks and unavailable fallbacks cannot supply such evidence.
Combined with the earlier assessment and suitability laws, this connects native
completion claims to supplied provider results, without authenticating those results.

The theorem's plan is the exact value supplied to `evaluate`. It does not prove
that every plan field was produced correctly or that a provider honestly executed
Lean. The planner laws below establish exact raw node/use inventory preservation;
request construction and other source-coverage guarantees remain separate. No
collector, provider adapter, or data store is duplicated in production for these proofs.

`evaluate_proof_evidence_source` traces every admitted independent-proof observation
to an original successful expected-goal result. The whole proof observation is
preserved, including its reported actual type, coverage, assumptions, and
explanation. The actual adapter checks tie the result to its selected witness,
document inventory, and formal context. The specification handle comes from that
same plan request; its original specification-batch result succeeds, and its
document is included in the expected goal's document inventory. This theorem applies
to failed proof observations too: successful provider execution alone does not
imply proof completion.

`evaluate_complete_proof_provider` composes that lineage with production admission
and completion. A completed independent-proof requirement has an original successful
expected-goal result whose unchanged observation satisfies the selected requirement.
In particular, it reports the required witness, matching actual-goal context and
fingerprint, passed outcome, and dependency-closure coverage. This is an end-to-end
guarantee about the pure evaluator and its supplied observations, not proof of the
reported mathematical proposition.

The goal and observation in a supplied checked result are distinct fields.
`AuthoredProofProjection` now relates the observation to a retained requirement
with that same result's expected goal, witness, and closure coverage. Their origins
share one authored site and index; generated observation, requirement, and context
identities remain separate. Any `semanticContext` payload reported by that result
is retained unchanged under the requirement's semantic-input identity. The invariant
survives later requirement additions and prerequisite wiring without requiring the
prerequisite array to stay frozen.

Consequently, `evaluate_complete_proof_provider` also identifies the exact expected
goal and witness of the selected requirement, not merely an observation that happens
to satisfy it. It proves retention of the same result's semantic context when one
was supplied. It does not assert that every supplied result contains a context:
`semanticContext` is optional, and the pure batch boundary does not authenticate it.
The separate availability theorem establishes that completed proof requirements
have a retained semantic input; it does not by itself make that optional field
present in every associated provider result.

## Generated dependency-selection checks

`evaluate_dependency_selection_source` proves that every admitted check with
validator `blueprint.dependencySelection` comes from the actual wiring pass over
`snapshot.uses`. It preserves the generated origin, requirement identity, nonempty
edge scope, complete check payload, outcome, and diagnostic explanation. Native
provider results and their unavailable fallbacks cannot impersonate these checks:
the proof follows the actual adapter validator checks, rather than trusting a name
on an arbitrary supplied observation. `finish_uses` ties the public edge inventory
to the exact inventory used by final wiring.

The law-only `DependencySelection.Source` states the generation contract, and
`mem_edges` exposes its scope as logical equalities: exact source node and context,
any explicit realization restriction, and statement-only edges for a statement
gate versus both facets for a proof gate. `mem_failures` relates each diagnostic
to an original selected-edge failure. The full ordered diagnostic array is used
in the exact explanation retained by `Source`; no JSON injectivity is assumed.

`Source.outcomes` characterizes both outcomes for that scope: passed iff every
edge's `selected` result is successful, unavailable iff some edge has a concrete
error. `evaluate_complete_dependency_selection` connects this to actual public
requirement completion: the gate has a nonempty scoped edge set and every edge
selected successfully.

Selection success is not completion of the selected target requirements. Their
validation and prerequisites remain covered by the separate completion-soundness
laws. The selector's returned inventory is now characterized below. We have not yet
proved every intended authored use reaches `selectUses` or every generated gate
is reachable from a native requirement. Those remain subsequent selection/wiring
obligations; no alternate selector or data store was introduced.

## Exact native target selection

`Realizations/Capture/TargetLaws.lean` characterizes the production `selectTarget`
function in both directions. `selectTarget_ok_iff` succeeds exactly when the target
node exists, its ordinary native realization has one distinct canonical payload
in the requested context, its selected declaration list is nonempty, and each
declaration retains its exact native body-proof requirement with closure coverage.
An always-rejecting selector would not satisfy this equivalence.

The returned array is exactly the canonical concatenation of the selected
declarations' `required` lists. This preserves additional authored declaration
requirements. It does not aggregate arbitrary realization-level or facet-level
requirements; the theorem follows the existing selector's declaration-contract
policy. `selectTarget_membership` exposes both directions of membership, and
`selectTarget_nonempty` rules out successful empty selections.

`selectTarget_native_requirements` connects the selected model and every required
native proof contract to original input contribution records. Their exact key,
body validator, and dependency-closure coverage are retained. The proof keys belong
to the returned array. `selectTarget_models_agree` also proves that all matching
original model payloads agree when selection succeeds; their contribution origins
may differ. Duplicate identical contributions are permitted.

These laws do not assume global admission of the supplied input, completion of a
target, or provider authenticity. The requested context is a parameter: the theorem
proves exact context equality. The laws concern the real private selector, opened
only in the law module; no production visibility or behavior changes were needed.

## Successful dependency edges use the exact target contract

`selectUses_success_source` follows the production selector's nested loops.
Every emitted edge with a successful result has a nonmissing context constructed
from an original source realization: its language is Lean, its project is the
source model's project, its node is the edge's source, and any explicit realization
restriction matches the source model's name. The edge's result is the actual
`selectTarget` call on that context and its exact reference label. An edge emitted
without a source context cannot count as successful selection.

`selectUses_success_contract` composes this provenance with `selectTarget_ok_iff`:
the target satisfies the native contract and the returned keys are exactly its
canonical declaration requirements. `selectUses_success_nonempty` excludes an
empty successful result. `selectUses_success_native_requirements` traces every
target declaration's body-proof key to an original requirement contribution with
the native validator and dependency-closure coverage; each such key is in the
edge's returned array.

`finish_use_success_contract` reaches the public snapshot's edges through the
existing exact `finish_uses` equation. Its target-contract statement is still about
the collection **before dependency wiring**. No global admission premise is added
for that collection. The following results extend this connection to the final
registry. These selector laws alone are forward guarantees for emitted edges,
not an edge-inventory completeness theorem.

## Selected contracts survive wiring and final admission

`finish_preserves_selection` strengthens the existing wiring-loop invariant.
Finalization preserves the complete original node and realization contributions,
including origins. For every original requirement, the final retained sources
contain a requirement with the same origin, key, expectation and coverage, retaining
every original prerequisite. Prerequisites may have been extended, so whole-requirement equality is deliberately
not part of this statement. The earlier observation-provenance proof reuses the
same per-step preservation argument.

`TargetSelection.Retained` describes a contract using the final registry's actual
`realization?` and `requirement?` lookups. `finish_use_target_retained` and the public
`evaluate_use_target_retained` establish it for every successful emitted edge:

- The ordinary target model is present in the edge's exact Lean context, with a
  nonempty declaration inventory.
- The returned keys are exactly the canonical declaration requirements of that
  retained model.
- Every returned key has a definition in the final registry, including additional
  authored requirements beyond the native body-proof keys.
- Each declaration's body-proof key belongs to the returned inventory and resolves
  to a requirement with the native body validator and dependency-closure coverage.

The third guarantee uses **final admission**. Raw target selection alone does not
establish definitions for arbitrary additional keys. No global admission premise
is imposed on the collection before wiring, and no alternate lookup or store is
used to state the result.

`evaluate_complete_dependency_targets` composes retention with the generated-gate
soundness theorem: a completed dependency-selection gate has a nonempty, precisely
scoped edge set, and every edge's target contract remains available in the same
final registry and context. This does not assert that those target requirements
are themselves complete. The wiring guarantees for actual generated gates are
described next; completeness of the intended edge and gate inventories remains
separate.

## Generated gates are wired to their native owner

`evaluate_dependency_selection_wired` reaches every dependency-selection observation
in the final retained evidence, whether passed or unavailable. Each observation is
generated at one exact source/context/realization/facet scope, and its collector-owned
native parent retains the gate key and every successfully selected target key as
prerequisites. Statement gates use statement edges; proof gates use both facets.

The proof follows the production ownership-index lookup and the existing wiring
loops. Ownership requires the collector's complete origin, dependency-closure
coverage, and the matching native validator. An authored check does not acquire
this guarantee merely by reusing a validator or requirement name. Lawful equality
of origins is derived in the law layer, without an added domain assumption.

`DependencySelection.GeneratedAt` is the shared specification for the observation's
identity, exact edge scope, outcome and explanation. `Source` existentially selects
that scope; `Wired` keeps the **same scope** alongside the parent and its prerequisites,
including a retained model witness for that scope's context. The earlier provenance theorem now follows from the stronger wiring theorem, so
the provider-adapter exclusion argument is not duplicated.

`evaluate_complete_dependency_wiring` connects completion to the final registry's
actual parent lookup. Its nonempty scoped edge set selected successfully, and both
the gate and all selected keys occur in that parent's prerequisites. This is still
not a claim that the parent or targets are complete. The preservation invariant
also establishes that later wiring iterations cannot remove previously retained
prerequisites.

## Eligible native contracts produce their gates

`Realizations/Capture/CreationLaws.lean` adds the positive direction.
`evaluate_native_dependency_gate_created` starts from an accepted snapshot's native
model, one of its declarations, and a collector-owned statement/proof contract with
dependency-closure coverage. If the exact selected edge scope is nonempty, the final
registry contains the corresponding dependency-selection requirement and retained
observation at its current binding. Gate existence is a conclusion, not a premise.

The observation satisfies `DependencySelection.GeneratedAt` for that same model,
declaration and facet: successful selection produces a passed check; any failed
selection produces an unavailable check. An unavailable edge therefore cannot
silently become an absent gate. This does not certify the native parent or targets,
and an empty edge scope does not require a gate.

The proof follows the actual ownership-index fold and nested model/declaration/facet
loops. `finish_original_expectations_agree` derives the consistency needed by the
index from successful final admission; it does not require the raw collection to
be admitted before wiring. `finish_closure_contract_source` proves that every final
closure contract comes from the original collection with origin, identity and
expectation preserved. Newly generated gates have subject coverage, so they cannot
satisfy that source premise accidentally. These facts lift the creation theorem
through the real `evaluate` call without exposing private loop witnesses to callers.

`DependencySelection.CollectorOwned` names the existing complete-origin test; it
adds no runtime state or alternative identity scheme. The lower-level
`finish_native_dependency_gate_created` remains available for finalizer reasoning.
The proof test composes the public evaluator theorem with a failed scoped edge to
obtain actual unavailable evidence, without assuming that any gate already exists.

Creation coverage starts at the selected edge inventory. The collected-use laws
below establish that every collected use reaches that inventory, and the collection
laws connect those uses to accepted ordinary plan entries. The planner laws then
preserve the raw node/use inventory. Provider request correctness and positive
ordinary-contract coverage remain separate. The composition below
combines creation and wiring with prerequisite evidence soundness,
keeping selection success distinct from completion of the selected targets.

## Completed native contracts justify their dependency obligations

`Realizations/Capture/DependencyLaws.lean` composes the public laws without accessing
private collector functions. Its main theorem,
`evaluate_native_dependencies_justified`, starts with a completed collector-owned
native statement/proof contract and its accepted model/declaration. For a nonempty
selected edge scope it establishes:

- An actual generated gate lookup, with the gate in **that parent's** prerequisites.
- Successful selection for every edge in **that model, context and facet**.
- Each target's exact retained model and requirement inventory.
- Every returned key in the parent's prerequisites, with an original requirement
  and fitting original evidence at **that key's** current binding.

Matching the parent and context is essential. `DependencySelection.Wired.for_contract` uses
retained model and requirement contributions plus admission coherence to align the
wiring witness with the requested parent and context. Gate identities distinguish
the two supported facets; the proof does not assume general cancellation for Lean
names with macro scopes. The loop invariant now retains its original model witness
instead of discarding that provenance.

`evaluate_local_dependency_selection_for_contract` extracts selection success from
a gate's **local validation**, which is what prerequisite soundness establishes.
The main theorem does not assume a gate exists, or that a prerequisite has a
completed entry in the final result cache. It obtains the gate from the positive
creation theorem and derives its local validation from the completed parent.

`evaluate_failed_native_dependency_incomplete` makes the negative consequence
explicit: a failed edge in the matching scope blocks that native contract. Proof
consumers also check that successful selection cannot conceal a selected target
obligation with no fitting original evidence. All returned keys matter, including
additional authored obligations alongside native body-proof requirements.

This is a conditional soundness theorem for the real pure evaluator and its accepted
selected-edge inventory. It does not prove authored-use inventory completeness,
provider authenticity, mathematical truth of reported proofs, or final cached
completion of every prerequisite. Production behavior and stores are unchanged.

## Every collected use reaches selection

`Realizations/Capture/UseLaws.lean` proves positive coverage through the production
`selectUses` loops. `useRef_mergeByLabel_labels` establishes exact target-label
union: reference merging can replace automatic metadata with manual metadata,
but cannot lose a target or add an unrelated one. This is a label-membership law,
not a promise to retain every duplicate reference payload.

`selectUses_in_context` starts with a member of the original collected-use array.
For every matching source model's project it yields an actual selected edge with
the same node, optional realization restriction, facet, and target label. Its
result is exactly the production `selectTarget` result, including failures. Scope
deduplication and context canonicalization cannot erase this coverage. The context
is explicitly the source model's **project projected into Lean**; it need not be
the source model's original language context. `UseSelection.ContextFor` records
that policy and the optional realization restriction.

`selectUses_without_context` proves that a use with no matching source model still
emits an edge, with no context and the exact `missing-source-context` diagnostic.
The tests exercise duplicate automatic/manual references, duplicate scopes and
projects, two distinct projects, a non-Lean source language, realization/facet
restrictions, target failure, and missing source context.

`finish_use_in_context` and `finish_use_without_context` retain these edges in the
successful final snapshot. Model matching may be checked against that snapshot;
the selection result remains the original pre-wiring selector result. The proof
does not silently rerun selection against the finalized input.

`finish_use_in_native_scope` places a collected use in the exact edge scope of an
accepted native contract. Statement scopes consume statement uses; proof scopes
consume both facets. `finish_collected_use_justified` composes this existence result
with `evaluate_native_dependencies_justified`: if that native parent is complete,
the use has a successful, retained target selection and every returned obligation
is a prerequisite of that parent with fitting original evidence at its current
binding. It assumes neither an emitted edge, a nonempty selected scope, nor an
existing gate. It relates successful finalization of the supplied collection to
the actual successful pure evaluator's output.

These selector laws start with **collected** uses. The following collection laws
connect that boundary to accepted ordinary plan entries. No production store,
evaluator, identity scheme, or behavior was added for these proofs.

## Ordinary source uses survive collection

`Realizations/Capture/CollectionLaws.lean` proves that successful `collectOrdinary`
returns a use array equal to `p.ordinary.flatMap (·.accepted.uses)`. This is array equality:
order, duplicates, metadata, realization restrictions and facets survive the real
collection pass. It is stronger than saying every returned use came from somewhere
in the plan. Successful document/native/check-provider branches preserve the use
array, including branches recording unavailable checks and source diagnostics.

`collectAuthored_uses` proves that authored enrichment preserves this array, even
as it adds source documents, models, contracts and observations. `assemble_uses`
combines both recipe stages. `evaluate_use_collection` supplies the actual
pre-finalization collection from successful public evaluation, so downstream
proofs no longer need callers to assume or exhibit it.

`evaluate_use_in_context` and `evaluate_use_without_context` lift positive
selection coverage to uses in accepted ordinary plan entries. Source contexts
are matched against the finalized registry, so authored models added after
ordinary collection participate. Target errors remain edges; a missing source
context remains an explicit diagnostic. Tests exercise both node orders, retained
duplicate metadata before selection, an authored document/model, and independent
missing-target and missing-source-context outcomes through the real evaluator.

`evaluate_ordinary_use_justified` is the resulting completion statement: for each
ordinary plan use in a completed eligible native parent's scope, selection yields
a retained target contract, and every returned obligation is a prerequisite of
that parent with fitting original evidence at its own current binding. It derives
collection and selected-edge existence, gate creation and wiring. It does not
assume any of those intermediate witnesses from the caller.

These collection laws start with accepted source records **inside the supplied
plan**. The following planner laws connect them to raw accepted records. Supplied
provider observations are not authenticated by these laws, and completion still
does not claim mathematical truth of reported proofs or final cached prerequisite
completion.

## Raw accepted nodes survive planning

`Realizations/Capture/PlanLaws.lean` proves `plan_ordinary_nodes`: mapping the actual
planner's ordinary entries to `(label, acceptedRecord)` yields exactly `raw.nodes`.
The statement keeps each label paired with its entire record, including sources,
uses, metadata and module provenance. It preserves input order and multiplicity,
without assuming the input is already valid or labels are unique. `plan_raw`
retains the full raw input, including facts, pending registrations, authored
records and initial diagnostics; planning cannot erase later rejection evidence.

The proof follows the real ordinary-node, realization, source, declaration and
authored-request loops. Inner loops preserve the joint raw/node projection while
updating request arrays. It introduces no replacement planner. These projection
laws do not establish that every generated provider handle or request is correct.

`plan_ordinary_uses` derives exact use-array preservation. `Raw.ofState_use_iff`
connects it to the actual accepted-node map: a raw use comes from a record returned
by `state.data.get?`, and every use of such a record is included. Pending entries
absent from that lookup do not contribute uses. This uses the proved structural
NameMap enumeration law, with no name-hash injectivity assumption.

`evaluate_raw_use_in_context` and `evaluate_raw_use_without_context` therefore
start from raw accepted uses and execute the actual planner. The composed
`evaluate_raw_use_justified` reaches retained target obligations and fitting
original evidence when the eligible native parent is complete. Callers no longer
assume the planner produced the right node/use inventory. The public proof test
starts directly from an accepted-node lookup; executable tests cover reordered and
duplicate raw entries, complete record preservation, missing/exact/ambiguous prose
owners, native and inline requests, authored expected goals, and evaluator output
from the generated plan.

Positive ordinary native-contract creation remains separate: the completion
theorem still assumes the eligible native model, declaration and parent contract
exist in the admitted output. Provider-request correctness, provider authenticity
and the actual environment transaction interpreter also remain outside this claim.

## Prerequisite selection is independent of completion

`Translations/SelectionLaws.lean` gives the authored identity contract as
`Selection.Matches`: exact node and formal context, validation name, and any
explicit realization/facet restriction. Successful `selectRequirement` picks the
unique matching collected requirement. `admit_selection_matches` transfers this
to original input records; repeated identical contributions may share a match,
but distinct matching requirements cannot be silently ranked.

`admit_selection_sources` proves the selection result is unchanged when requirement
and realization contributions are unchanged and both inputs are admitted. All
other families—including evidence—and derived completion caches may differ.
The equality includes failed selections: a complete alternative cannot make an
ambiguous request succeed. No admission validity or source-index assumption is
hidden in this statement; both follow from the actual successful admissions.

## Pure environment admission

`Environment/AdmissionLaws.lean` connects the environment's actual `State.addNode`
transition to the existing proved assembler:

- `addNode_success_iff` adds authored-origin validity to assembly acceptance,
  in both directions. An always-rejecting transition would not satisfy this law.
- `addNode_no_resurrection` proves that a retained authored-origin conflict blocks
  every later registration, including compatible payloads.
- `addNode_assembled` proves the stored and returned node is the assembler result
  for the retained pending registrations and complete selected evidence.
- `addNode_records` preserves exact whole-record membership in both complete and
  module-local evidence. `addNode_nativeAssociations` carries this through to the
  actual returned node's associations, including facets and provenance.
- `addNode_other_labels`, `addNode_frame`, and `addNode_count` describe the update's
  scope: other labels and all fields outside the six admission stores are unchanged;
  numbering reserves the returned node without decreasing the prior count.
- `addNode_declaration_index` characterizes incremental index membership exactly:
  retained entries plus this node's declarations under the insertion function's
  macro-scope erasure. It does not assume erasure is idempotent or that preexisting
  index entries were already correct.

`Util/NameMapLaws.lean` supplies the missing laws for Lean's real `Name.quickCmp`:
transitivity and exact comparison equality. The proof relates its structural
fallback to a lexicographic component sequence and then handles the hash prefix.
No hash injectivity or map-correctness axiom is added. Standard TreeMap laws then
establish exact NameMap lookup after insertion. The component sequence exists
only in proofs; production still uses the original comparator and NameMap.

These are proofs about the logical Lean implementations. They do not separately
verify the compiler, runtime pointer-equality optimization, or persistence/IO
mechanisms. As elsewhere, proof dependencies stay out of production imports.

## Complete imported-state reconstruction

The environment law module also covers the actual `State.reassembleImported`
loop. `reassembleImported_node_iff` characterizes stored nodes in both directions:
there is a retained pending entry with valid authored origins, and the production
assembler accepts it against the complete selected evidence. The stored origin
and contributing modules match that entry as well. Labels without pending entries
are absent; assembling empty input does not invent arbitrary labels.

`reassembleImported_declaration_index` establishes a full invariant at this
boundary: an index entry exists iff an accepted node contains a declaration whose
macro-scope erasure is the queried name. Unlike the incremental local-update law,
this theorem allows arbitrary stale nodes or index entries in the input state;
reassembly discards them. Origin-conflicted labels have neither accepted nodes
nor index entries. `reassembleImported_no_resurrection` composes this with later
local admission, using preservation of the retained pending evidence.

The decoding laws show that individual imported entries preserve complete selected
records and append raw registrations without exporting them as local registrations.
`collectImportedEntries_unpublished` covers the actual nested module/entry fold:
accepted nodes, their index, numbering, and local selected records remain untouched
until the full-evidence assembly pass. These are proofs of the pure callbacks'
operations, not assumptions about Lean's persistent-extension replay machinery.

`State.DeclarationIndexCoherent` names this exact relation between the existing
node and index stores. Reassembly establishes it unconditionally. For subsequent
local updates, `addNode_index_coherent_iff` identifies the exact remaining condition:
every name previously indexed for the updated label must remain in the returned
node. The theorem proves both necessity and sufficiency, assuming a coherent
prior state. The source-accumulation laws below now discharge that condition for
nodes which match their retained-input assemblies.

## Source accumulation and the local coherence induction step

`NodeAssembly/SourceLaws.lean` proves the real payload reducer preserves the exact
source array: the old inventory followed by each registration's source records.
The proof follows the production `StateM` loops while separating accumulated
diagnostics from source values. Successful assembly therefore retains exactly
its original payload sources. No parallel evaluator or source store is introduced.

`assemble_ok_leanDecls_input` connects the actual declaration inventory directly
to original selected associations and inline sources in original registrations.
It removes the need for a caller to supply an intermediate payload-node premise.
`assemble_leanDecls_monotone` then proves that accepted growth of registrations
and selected evidence cannot remove a declaration.

`State.NodesMatchAssembly` states that each stored node agrees with assembly of
its retained registrations and complete evidence. Import reconstruction establishes
this property and the exact declaration-index invariant. Successful label-local
registration preserves both (`addNode_coherent`), giving the induction step for
supported registration sequences. The proof of the other-label frame accounts
for cross-label identity collisions: a new collision involving an incoming record
would also reject the registering label. It does not assume collisions are absent
by construction or ignore other labels' identity buckets.

The explicit producer premise is that every incoming selected record has the
label being registered. There is no source-accumulation or declaration-monotonicity
premise left. `addNode_after_import_index_coherent` gives a direct import-to-local
index guarantee without a caller-supplied prior-state invariant.

## Finalization preserves observation provenance and current bindings

`finish_binding_basis` proves the real finalizer admits the complete candidate
before binding observations, and that every candidate binding equals the final
registry's binding. It uses `admit_bindings_evidence`; no assumption about hash
collision resistance or a separate binding evaluator is needed.

`finish_sources` states exactly what changes after prerequisite wiring: only
input evidence, by appending the collected observations in order. Whole origins,
requirement identities, observations, and multiplicity are preserved. The
law-layer `boundObservation` record describes this projection; it does not run an
alternative finalizer. `finish_evidence_iff` gives both directions of membership,
including any evidence already present in the candidate.

`finish_observation_current` proves every appended observation has an actual
binding in the final registry, equal to the binding stored in its evidence. The
specification's empty fallback cannot be used for an accepted observation. These
laws concern the actual `finish` called by `evaluate`. Their input boundary is the
collected recipe output after dependency wiring, not the original provider batch;
the native check and authored proof observation paths are now covered above.
The joint authored requirement/semantic-input projection is preserved across this
boundary. Generated dependency-selection provenance, outcomes, wiring, and positive
gate creation and ordinary-plan-use collection/selection coverage are covered above.
Provider-request construction and positive ordinary native-contract collection
remain separate; raw node/use preservation is covered above.

## Exact admission across registration histories

`State.AdmissionCoherent` strengthens accepted-node agreement: for every label,
node lookup is exactly admission of its retained pending entry against the whole
evidence set. `AdmissionCoherent.node_iff` exposes the input-facing contract,
including authored-origin validity, actual successful assembly, and exact stored
origin/contributing-module provenance. Unknown and rejected labels are absent.
The predicate describes the existing state; it adds no runtime store or certificate.

Import reconstruction establishes this stronger invariant from arbitrary prior
published data. A successful label-local registration preserves it. The proof
covers both directions for unrelated labels: accepted evidence growth cannot
resurrect a previously rejected unrelated entry, and success for the registering
label prevents a new cross-label collision from invalidating another entry.

`State.admission_sequence_coherent` combines this with exact declaration-index
coherence for any finite successful registration history starting from import
reconstruction, including the empty history. `State.LocalAdmission` names an actual
successful `State.addNode` call with label-local facts; it is a proposition about
the production transition, not a replacement evaluator. The stronger invariant
implies the earlier `NodesMatchAssembly` property.

## Main theorem targets

The main statements should describe production boundaries that users rely on,
with the implementation lemmas serving those statements. Three theorem families
provide a useful structure:

| Contract | Current formal result | Remaining connection |
| --- | --- | --- |
| **Coherent admitted database**: accepted nodes are exactly the permitted assemblies of retained evidence, and declaration indexes are exact. | `State.admission_sequence_coherent`, with `AdmissionCoherent.node_iff`, proves this after import reconstruction and any finite successful label-local registration history. | Show actual producer routes and persistent-extension/transaction execution satisfy the history premises. |
| **Justified public completion**: every selected obligation, and every reachable prerequisite, has fitting original evidence at its own current binding; circular justification cannot certify completion. | `evaluate_assessment_justified` covers selected obligations and accessibility in rendering assessments; `evaluate_native_dependencies_justified` connects native dependency selection, gate creation, wiring to the same parent, and fitting target evidence; `evaluate_raw_use_justified` starts from raw accepted source uses through the actual planner. | Positive ordinary native-contract coverage, provider-request correctness, final-cache closure and the converse completeness direction remain separate. |
| **Capture preserves evidence provenance**: completion evidence comes from the appropriate original provider result or an explicitly characterized generated check, with identities and binding preserved. | `evaluate_native_evidence_source`, `evaluate_proof_evidence_source`, `finish_observation_current`; `evaluate_complete_proof_provider` composes authored provenance with completion suitability. | Provider-request construction, positive ordinary-contract coverage and the real provider interpreter; raw node/use preservation, collection/selection, exact targets, wiring and gate creation are included. |

These are complementary contracts, not one claim that the entire database is
permutation-invariant or that all reported propositions are true. The first has an
exact admission characterization. The second currently establishes soundness,
not completeness. The third is relative to supplied observations and an exact
supplied plan, with raw node/use preservation proved for plans from `plan`.

A later semantic-soundness theorem should expose a provider correctness hypothesis
as an explicit premise and discharge it for each supported interpreter where
possible. It should not install a new global axiom saying that Lean APIs or all
providers are trustworthy. For example, proving a reported witness type corresponds
to the environment used by `observe` is a different task from proving that `evaluate`
preserves that report. Keep those theorem boundaries visible.

`evaluate_assessment_justified` is the main pure-capture soundness statement: a
completed rendering assessment selects a nonempty contract; each selected key has
an accessible prerequisite relation; and the key itself plus every transitive
prerequisite has original fitting evidence at its own current binding. It does
not assert that every prerequisite still has a completed final cache entry or that
the graph traversal recognizes every satisfiable contract.

Successful emitted edges are now connected to the target-selector contract and
its retention in the final registry; generated gates and their selected keys are
wired into native-parent prerequisites. Eligible native contracts now produce gates
for every nonempty selected edge scope. Their completed parents now justify every
selected target obligation by fitting original evidence. Every ordinary plan use
survives collection and reaches its matching selection contexts or an explicit
missing-context diagnostic. The actual planner now preserves raw accepted nodes
and their uses. Next, prove positive ordinary contract coverage and account for
provider-request correctness and actual provider/transaction routes.
Preserve the joint authored projection as those routes evolve. Growing a list of local lemmas without strengthening one of these
three contracts is not the objective.

## Remaining boundary

We have not proved completeness: every well-founded, locally satisfied contract
is eventually recognized as complete. Nor have we proved that every prerequisite
of a completed result retains a completed **final cached result**, as opposed to
the established prerequisite evidence soundness. Those properties need facts about
the component sequence, including coverage, ordering, and absence of repeated
members. Proving the actual traversal total/correct remains a separate task.

The source-index laws cover requirements, realizations, translations, and claims;
they do not yet characterize every source-resolution or reference diagnostic.
No theorem authenticates a provider, proves fingerprint collision resistance, or
establishes completeness of source capture. Provider-reported closure coverage
remains distinct from the Registry prerequisite guarantees proved above.

The environment laws cover local admission, raw import decoding, and complete
imported-state reconstruction. Lean persistent-extension serialization/replay and
CoreM commit/rollback remain separate. The local coherence induction step requires
incoming selected records to belong to the label being registered. The pure theorem
does not verify every `CoreM` producer route or commit/rollback mechanism. Exact
pending-label admission and absence are now covered by the history theorem;
diagnostic-reporting states remain outside that invariant. The incremental index
law deliberately describes existing entries without assuming them valid; the
coherence theorems supply the stronger invariant at their stated boundaries.
