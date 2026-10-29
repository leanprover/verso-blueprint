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
does not verify every `CoreM` producer route or commit/rollback mechanism. It also does not characterize
all pending-label absence or diagnostic-reporting states. The incremental index
law deliberately describes existing entries without assuming them valid; the
coherence theorems supply the stronger invariant at their stated boundaries.
