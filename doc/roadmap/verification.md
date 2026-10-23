# Verification lane: strengthen the production proof boundary

Owner: contribution/verification lane.
Status: V1, V2a, V2b membership, and checked producer-name admission implemented;
payload frame pending.
Foundation: [#467](https://github.com/leanprover/verso-blueprint/pull/467)
established the production identified-evidence resolver and its laws;
[#469](https://github.com/leanprover/verso-blueprint/pull/469) centralized admission
and separated node payloads from identified association and priority evidence.
V1 baseline: `fab2fc4470253bd854fca99c0530809357af5c54` on `v4.35.0`
(2026-10-23), including #469. V2a baseline:
`4943d3335ffa9221a39949e60836a8ad5dc2a456`, including
[#498](https://github.com/leanprover/verso-blueprint/pull/498).
V1 validation covers production/law builds, the full Lean/integration driver,
and the new/retained theorem axiom audit; local evidence remains untracked.

## Contract and working policy

Prove properties of production functions. Keep complete immutable evidence and
its accepted projections distinct. State every producer/coverage assumption;
do not add global API axioms to bypass an unproved adapter contract. Audit
theorem dependencies and keep proof imports outside production targets.

Each ticket records its baseline, scope, acceptance commands, proof assumptions,
and remaining boundary. Keep session allocation and approval notes in local
coordination records.

## Sequence and gates

| Ticket | Deliverable | Depends on | Scope |
| --- | --- | --- | --- |
| V1 (implemented) | Assembly acceptance, actual resolver-result bridge, input-facing priority laws | Landed #467 and #469 | `NodeAssembly/Laws.lean`; separate direct accepted-node return cleanup and regression |
| V2a (implemented) | Snapshot merge canonical union, normalization, uniqueness, and presence laws | V1 | Law module for `ExternalRef.mergeSnapshots` |
| V2b (membership implemented; frame pending) | Raw/present membership on each facet; `Node.leanDecls` union; payload frame | V2a | Assembly/data law modules |
| V3 | Semantic environment coherence and accepted index exactness | V2b; merged #469 admission boundary | Pure state transitions and their law modules; boundary regressions |
| V4 | Conservative completion through snapshot merge and `nodeCodeHealth` | V2a; agreed status/coverage contract | Status/health law modules; coordinate with axiom-analysis owner |
| V5 | Evidence persistence and rendering projection correspondence | Relevant V2/V3 results | One serializer/import or rendering boundary per ticket |
| V6 | Further indexed implementations refining the reference semantics | Measurements identifying a real bottleneck | One measured production query and its refinement theorem |

V3 and V4 are separate follow-ups; do not grow V1 into either. V5/V6 are queued
directions, not implementation-ready promises. Verification owns proofs of
Blueprint consumers. The axiom-analysis lane owns Lean observation APIs,
hidden-body/coverage experiments, upstream coordination, and dependency pins.

## V1: assembly acceptance and resolver-result bridge (implemented)

Behavior change: none. The admission cleanup returns the
accepted `Node` alongside `State` from `State.addNode`; `commitContribution`
consumes it directly instead of looking it up again. A direct registration
regression checks returned payloads, retained evidence, and the committed node.
The named theorems below live in
[`NodeAssembly/Laws.lean`](../../src/VersoBlueprint/NodeAssembly/Laws.lean)
and reuse [`resolverLaws`](../../src/VersoBlueprint/Contributions/Laws.lean).
No API preservation work, snapshot redesign, status policy, broader environment
refactor, or additional stored data.

1. `assemble_ok_resolve`: successful production assembly implies
   `resolve label records = .ok assembled.view`.
2. `assemble_success_iff` proves assembly success iff the actual payload reducer
   succeeds, relevant contribution identities do not collide, priorities do not
   disagree, and the selected reference-name check succeeds. The latter is the
   checked producer-admission follow-up below. The theorem uses the complete
   record set. Authored-origin
   validity remains an environment obligation, not an invented assembler premise.
3. `assemble_ok_priority_none_iff` proves node priority `none` iff there is no
   input priority claim; `assemble_ok_priority_some_iff` proves node priority
   `some value` iff that value is claimed and all claims agree.
   Records without priority remain neutral.
4. Support and input-facing priority laws reuse the resolver bridge and
   `resolverLaws`; priority laws also reuse `assemble_ok_priority`. Existing
   theorem guarantees are preserved.

Acceptance commands (run from a harness-created worktree on the merged base):

```sh
python3 -m scripts.blueprint_harness require-branch-role default_dev
scripts/lean-low-priority lake build VersoBlueprint +VersoBlueprint.Contributions.Laws:olean +VersoBlueprint.NodeAssembly.Laws:olean
scripts/run-lean-tests.sh
scripts/lean-low-priority lake lean tests/verification/AssemblyAxiomAudit.lean
git diff --check
```

The tracked audit imports `VersoBlueprint.NodeAssembly.Laws` and prints axioms
of the new bridge, acceptance theorem, both priority corollaries, and retained
collector/resolver laws. It prints dependencies for review, rather than enforcing
an automated allowlist. Accept no `sorryAx`, new axioms, `sorry`, or `admit`.
Check production import closure remains independent of law modules. Existing CI
runs the broader tests; a proof-only change does not need new tests mirroring
the proof scripts. Any further production behavior change needs a separately
scoped fix with a counterexample; it is outside these laws.

Exit statement: production assembly succeeds exactly when its payload reducer,
identified-evidence resolver, and selected-name check accept. The returned node's
priority agrees with the original identified evidence. This does not yet prove actual node declaration membership, producer
correctness, environment coherence, or whole-database confluence.

## V2a: snapshot canonical union and presence (implemented)

Behavior change: none. The proof-only
[`ExternalRef/Laws.lean`](../../src/VersoBlueprint/ExternalRef/Laws.lean)
proves properties of the production `ExternalRef.mergeSnapshots` loop by showing
it equals the same indexed fold. Its local index-comparator laws and loop
invariants leave production imports unchanged and add no API axioms. Both `current` and
`incoming` are arbitrary arrays, including duplicates and missing references.

1. `mergeSnapshots_canonical_union`: output canonical fields are exactly the
   union of input canonical fields after one `eraseMacroScopes` application.
   This is raw membership, independent of presence.
2. `mergeSnapshots_normalized`: each output canonical field equals a one-pass
   erased input canonical field.
3. `mergeSnapshots_canonical_nodup`: output canonical fields have no duplicates.
4. `mergeSnapshots_present_iff`: a canonical name has a present output iff some
   input with that one-pass erased key is present.
   `mergeSnapshots_ref_present_iff` states the same fact for each output's
   actual `present` field.
5. `mergeSnapshots_normalized_fixed`: output canonical fields are erasure-fixed
   under the explicit premise that every input's one-pass erasure is stable.
   This premise is necessary: for arbitrary `Name` values, nested `_@` / `_hyg`
   suffixes can erase to a prefix that still has macro scopes. No repeated
   erasure or change to production canonicalization is part of this ticket.

Acceptance commands:

```sh
python3 -m scripts.blueprint_harness require-branch-role default_dev
scripts/lean-low-priority lake build VersoBlueprint +VersoBlueprint.Contributions.Laws:olean +VersoBlueprint.NodeAssembly.Laws:olean +VersoBlueprint.ExternalRef.Laws:olean
scripts/lean-low-priority lake lean tests/verification/AssemblyAxiomAudit.lean
git diff --check
```

CI builds the new law module explicitly and the tracked audit prints the six
new theorem dependencies alongside the existing assembly and contribution laws.
No facet, payload, environment, producer, status, or completion claim follows
from V2a alone. Missing references remain useful evidence in the raw union.

## V2b: facet and node membership (implemented); payload frame pending

Membership baseline: `66172fea6d05474b615b4a37b2c5936a9a562443` on `v4.35.0`.
The initial membership slice changed no runtime behavior. Its subsequent checked
producer-admission boundary is described below. The proof modules are
[`ExternalRef/FoldLaws.lean`](../../src/VersoBlueprint/ExternalRef/FoldLaws.lean),
[`Node/MembershipLaws.lean`](../../src/VersoBlueprint/Node/MembershipLaws.lean),
and [`NodeAssembly/MembershipLaws.lean`](../../src/VersoBlueprint/NodeAssembly/MembershipLaws.lean).

`mergeSnapshots_fold_membership` is one principle over the actual
`List.foldl (fun acc input => ExternalRef.mergeSnapshots acc (select input)) #[]`.
Its Boolean argument selects raw membership (`false`, including missing
observations) or present membership (`true`). Both use one-pass erased input
keys. The same fold has unique output canonical fields without a naming premise.

Repeated merges erase accumulated keys again. The fold principle therefore
requires, explicitly for every selected input reference including missing ones,
`eraseMacroScopes (eraseMacroScopes ref.canonical) = eraseMacroScopes ref.canonical`.
`mergeSnapshots_fold_normalized` proves the resulting fields are erasure-fixed.
The generic fold keeps this premise. Assembly-facing facet and node theorems now
derive it from the executable admission check, so callers do not supply a
producer-name assumption. Raw and present membership have separate corollaries.

`Node.mem_leanDecls` describes arbitrary nodes with the projection's exact names:
present external snapshots contribute `ref.canonical.eraseMacroScopes`;
literate blocks contribute another erasure of each `Code.definedDeclNames`
entry. The expanded `assemble_ok_leanDecls_literate` result keeps the accepted
payload literate disjunct, without assuming literate-name stability. The final
`assemble_ok_leanDecls` states the literal union
`Association records label name ∨ name ∈ base.leanDecls`, where `base` is the
actual successful empty-seeded payload reducer result. Its view corollary uses
the actual accepted resolver declaration projection.

The literal accepted-base union also uses the narrow two-field preservation
`Node.applyContributions_externalRefs` proof beside the private payload reducer
in `NodeAssembly.lean`. It preserves only `externalRefs` and
`proofExternalRefs`. The declaration is in that file
because Lean's non-module private boundary prevents ordinary law imports from
naming the reducer internals; no helper is exposed and no law import or runtime
code is added. The remaining proofs stay outside production import closure.

Acceptance commands:

```sh
python3 -m scripts.blueprint_harness require-branch-role default_dev
scripts/lean-low-priority lake build VersoBlueprint +VersoBlueprint.Contributions.Laws:olean +VersoBlueprint.NodeAssembly.Laws:olean +VersoBlueprint.ExternalRef.Laws:olean +VersoBlueprint.NodeAssembly.MembershipLaws:olean
scripts/lean-low-priority lake lean tests/verification/AssemblyAxiomAudit.lean
git diff --check
```

CI builds the new membership law root and the tracked audit prints its public
theorem dependencies, including the payload preservation bridge. Local evidence
and the macro-scope counterexample remain untracked.

### Checked producer-name admission (implemented)

Baseline: `0d77511cfefa3bb50be7081e10315e00137d7bdd`. The behavior change is a
shared rejection check in `NodeAssembly.assemble` after payload reduction and the
complete identified-evidence resolver succeed. `referenceNameErrors` checks both
facets of records for the selected label, including missing references, without
rewriting names or filtering evidence. Each failing observation produces a
label/name diagnostic. Payload, identity-collision, and priority diagnostics keep
their existing precedence. Unrelated labels are not rejected by this name check.

`referenceNameErrors_isEmpty_iff` proves the actual checker is equivalent to
`StableReferences records label`. `assemble_ok_stableReferences` proves this
property for every successful production assembly. `assemble_success_iff`
includes the check, and the accepted facet and node membership theorems consume
the proved result. They no longer carry a caller-supplied stability premise.

Directive records reach this boundary through `InProgress.selectedFact?` and
`contributeRecord`; attributes call the same registration API. Local `State.addNode`
and imported `State.reassembleImported` both use `NodeAssembly.assemble`. Imported
collection still retains raw complete records. A malformed imported record
therefore prevents its label from being accepted, remains available as evidence,
and cannot be bypassed by a later valid local registration for that label.

This verifies checked acceptance, not a claim that Lean name-resolution APIs
always produce valid names. `ExternalRef.ofName`, the parsed/resolved wrappers in
`Informal/ExternalCode.lean`, and `ExternalRefSnapshot` capture apply erasure, but
that alone is not a proof of stability on arbitrary `Name` values. The gate
checks their eventual records instead of axiomatizing those APIs or repeatedly
normalizing a key until its identity changes.

The tracked `ReferenceNameAdmission` regression exercises actual attribute and
statement/proof directive acceptance, atomic malformed local rejection for both
facets and both presence values, retained malformed imported evidence, rejection
of later resurrection, and identity-collision diagnostic precedence. Its import
provider deliberately injects raw malformed evidence to simulate an external or
older producer; this bypass exists only in the test fixture. Acceptance also runs
`scripts/run-lean-tests.sh` and the tracked axiom audit.

The broader payload frame remains a separate, unimplemented follow-up: bodies,
dependencies, numbering, literate/Rust code, markup, and unrelated metadata.
Preserve explicit kind and allow documented association-based inference when
kind is not explicit. Do not claim equality of order-sensitive snapshot or
support arrays under arbitrary permutations. Environment and completion policy
remain in their own later tickets.

## V3: coherent states and rejection

Scope the invariant to labels with retained contributions. Accepted nodes exist
exactly when authored-origin validity and assembly permit them, and equal that
accepted assembly. Index entries exist exactly for canonical declarations of
accepted nodes. Authored-origin conflicts prevent both nodes and index entries,
including after later local registration.

Prove initialization and preservation by supported registration and import
transitions. Rejection atomicity compares semantic stores; diagnostics and
`importedConflictsReported` may change legitimately. Use the merged #469
admission boundary, including the direct accepted-node return from
`State.addNode`; do not independently rewrite admission.

## V4: completion and evidence coverage

Lift `ProvedStatus.mergeConservative_isProved` through snapshots and actual
`nodeCodeHealth`, initially proving that an accepted non-proved observation
cannot become certified complete. Include both facets, literate overlap,
external-status overrides, and the nonempty-code requirement.

Stronger missing-status laws require the producer invariant
`present = false → provedStatus = .missing`. Retained supporting records and
aggregate status have different roles: absorbing statuses need not retain each
observation in the aggregate value. Any completion theorem over Lean observations
must expose soundness and coverage assumptions; cached absence is not coverage.

## Deferred persistence, rendering, and performance

For V5, choose one boundary and prove that semantic facts survive while resource
availability and occurrence presentation may vary. Include snapshot/document
pairing and serialization freshness when those are relevant; avoid promising
all generated-output correctness from a single projection theorem.

For V6, measure first, then prove refinement of the optimized production query
against the existing specification. Timing evidence and kernel proofs establish
different claims. No general database engine or persistent cache is authorized
by this plan.
