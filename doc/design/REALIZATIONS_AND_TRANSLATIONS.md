# Realizations and translations

Status: frozen ontology and first-phase scope, 2026-10-23. This is an agreed
design for implementation, not a description of supported syntax or APIs.
Concrete Lean declarations and authoring syntax remain subject to implementation
review. Changes to the ontology or phase boundary require an explicit decision.

## Purpose

Blueprint should guide informal-to-formal and formal-to-formal work using one
semantic model. A node can have independent Verso, Rocq, Rust, and Lean
representations. Declaration checking and correspondence between representations
answer separate questions and have separate completion results.

The first implementation uses canonical source code and the normal build as
authority. Independently versioned artifact import, cross-toolchain evidence
packages, immutable execution-receipt infrastructure, and historical snapshot
reconciliation are out of scope. Project-qualified declaration identity remains
necessary for distinguishing declarations in different projects.

## Frozen ontology

### Node

A node identifies an authored concept, definition, specification, or result.
Its stable Blueprint label, kind, grouping, and shared descriptive metadata do
not depend on its representation language. A node has named realizations.

### Realization and facets

A realization is a particular representation of a node in a selected language
and project context. Its identity is distinct from the language: two Lean
implementations of a concept are two realizations.

Statement and proof are facets within a realization. A definition has its
appropriate declaration/body content; a theorem realization can associate its
formal statement and proof with one checked declaration. A source declaration
need not be split artificially into separate objects to expose those facets.

A facet selects its relevant source documents and references to the realization's
existing declarations. The same declaration and checked requirement can serve
statement/proof views without duplicating theorem content or proof evidence.

Independently authored informal Verso, Markdown, and TeX accounts are
realizations too. A markup slot is a component of a realization, not
automatically another realization. Rendered HTML, TeX output, highlighted source,
and hover previews are views of a realization, not new realizations.

Example:

```text
node: addition_commutes
  realization informal:
    statement: Verso prose
    proof: informal argument
  realization rocq-original:
    statement/proof: associated Rocq declarations
  realization lean-port:
    statement/proof: associated Lean declarations
```

Each realization has content and/or declaration associations plus explicit
validation requirements. Validation belongs to the realization or its selected
facets. The initial design should preserve this clear three-realization example
rather than bundle independently authored Verso and Lean accounts together.

### Declaration identity and associations

A declaration reference identifies its language, logical project context, and
source-native object identity. Preserve authored spelling separately from
resolved identity. Do not impose Lean name resolution on foreign symbols.
Locations and rendered snippets support navigation; they are not symbol identity.

Several declarations can constitute a realization. A declaration can be
associated with several nodes. Group required declarations in one realization;
put alternative implementations in separately named realizations so their
completion is not accidentally combined.

Missing, ambiguous, and unsupported resolution remain distinct from successful
resolution. LSP lookup and diagnostics do not themselves certify proof validity.
Foreign analysis is supplied by the language-tooling lane; unavailable checking
must remain visible, without inventing successful validation.

### Translation

A translation is a first-class named, directed relationship between one or more
source and target realizations. It is registered at project scope with explicit
endpoints; node views derive their incident translations. Convenient node-local
authoring may infer the current node without changing ownership.

Endpoints can belong to the same node or several nodes. This permits split and
merged decompositions without forcing an arbitrary owner or a fake theorem
counterpart. Source and target roles belong to the translation, not permanently
to a realization. A target can be the source of a subsequent translation.

A translation records a precise authored claim, selected facets, assumptions,
and completion requirements. It can require several correspondence claims,
such as statement alignment and a representation-preservation theorem. Grouped
endpoints do not assert every pairwise correspondence automatically.

The required validations of a claim must identify that claim as their subject.
External mathematical proofs or reviews remain explicit prerequisites of those
claim-local requirements; they cannot substitute for the claim's own validation.
Such prerequisites may refer to other nodes/realizations outside the endpoints.

Source and target endpoint groups are nonempty. Claims and requirements have
individual identities; group membership does not synthesize a claim or validator.

Translation links are separate from mathematical `uses` edges. A shared source
does not establish equivalence between its targets. Composition is justified
explicitly, including agreement of domains, relations, and assumptions.

### Requirements, evidence, and completion

Validation is indexed conceptually by its subject and validation kind. Suitable
evidence must concern that subject and discharge that kind of requirement.
This GADT-like relationship is a semantic constraint, not a mandate to add a
large new inductive hierarchy.

Examples:

| Subject | Requirement | Suitable evidence |
| --- | --- | --- |
| Informal statement | Prose linting | Linter result for that content |
| Informal statement | Proofreading | Explicit review of that statement |
| Informal proof | Mathematical review | Review of the argument against its statement |
| Rust implementation | Specified tests pass | Result for that implementation and test suite |
| Lean theorem | Complete checked proof | Checked proof of its actual statement with required completeness coverage |
| Translation claim | Correspondence review | Review of the selected endpoints and claim |
| Translation claim | Preservation obligation | Checked witness of the specified relation, with explicit assumptions |

Language does not prescribe all requirements. A Lean definition can require
tests and a refinement theorem. A source lookup cannot satisfy a proof
requirement. A complete unrelated theorem cannot certify correspondence.

Completion is derived from explicit requirements and suitable evidence for
current canonical content. Empty or unspecified validation requirements must
not manufacture a validated result; expose unassessed/not-applicable distinctions
where appropriate. Record what evidence establishes: tested, reviewed, or checked
are not interchangeable guarantees. A proof slot containing text establishes
authorship, not mathematical acceptance.

Required declarations within one realization combine conjunctively. A
not-applicable result cannot satisfy a requirement for a complete checked proof.

A proof completes for a particular statement in a particular realization.
Preserve the existing conservative Lean completion analysis, including reachable
holes, verification gaps, and inspectable assumptions. Formal validity and
absence of admitted holes remain separate from freedom from other axioms.
Statement changes require rechecking or reassessing the supporting proof.

A translation completes when its declared contract is met. A statement-only
translation can complete while a target proof is unfinished; a full theorem port
can require the target statement, proof, correspondence assessment, and linked
obligations. Source proof completion is required only if the contract says so.

Keep local completion separate from completion with required prerequisites.
Mathematical obligations use ordinary Blueprint nodes and explicitly selected
realizations. Completion must not accidentally consume an unrelated alternative
realization or bootstrap through a circular requirement.

For a checked-proof requirement, identify the expected proposition/relation
application independently of the candidate witness. The language checker must
check the witness against that expectation (for Lean, an elaborated expected
proposition and matching checked witness type, as well as completeness). A
requirement ID and a complete theorem name are not sufficient binding. The
connection between an informal correspondence claim and its formal obligation
remains an explicit authored/reviewed interpretation; a type check cannot infer
that connection from prose.

Do not introduce permanent manual `complete := true` fields. Reviews are explicit
evidence bound to a deterministic current-content key. Proof reviews include
the statement and argument. Correspondence reviews include selected endpoint
content, the claim, assumptions, and the specified formal obligations. A
conservative digest of the containing canonical documents plus contract content
is acceptable initially. Missing or mismatched bindings do not discharge a
requirement, and rebuilding does not renew a review. Identify the review's scope;
do not infer complete dependency coverage from a partial input list. No
historical receipt subsystem is required for phase one.

Logical project identity namespaces objects; canonical source/build context
resolves their current content. Content keys do not introduce independently
versioned artifact import. `vbp check` retains its structural generated-data
validation role and does not become a proof checker.

### Semantic keys and admission

Use semantic keys distinct from immutable producer-site contribution IDs:

| Object | Semantic key |
| --- | --- |
| Realization | Node label and realization ID |
| Facet/content subject | Realization key and facet/component ID |
| Translation | Project context and translation ID |
| Correspondence claim | Translation key and claim ID |
| Validation requirement | Subject key and requirement ID |

Evidence explicitly references its subject and requirement, validation kind, and
current-content binding. Concrete Lean key encodings remain implementation
details. Exact producer replay is harmless, but different producers defining
incompatible contracts at one semantic key must yield deterministic diagnostics
with provenance, not a partly admitted merged contract.

Separate shared node introduction/metadata from the introduction of each named
realization. Independently authored realizations can attach to one shared node;
conflicting definitions of the same realization or shared metadata still fail.
Resolve cross-record references after collection so forward references and
import order do not determine acceptance.

## Graph, queries, and rendering

Existing label-only mathematical statement/proof dependencies remain shared
node-level constraints; moving prose into the default informal realization must
not remove constraints from the default Lean planning view. Dependencies inferred
from compiled declarations belong to their producing formal realization. Scope
comes from the producer, not merely the manual/automatic origin tag.

A view resolves a label-only dependency using its explicitly configured/default
realization context. The default Lean view selects the dependency's default Lean
realization in that context, preserving current planning. Other contexts select
their declared realizations; absent or ambiguous selection is a blocker, never
permission to use any complete alternative. Translation obligations carry
explicit realization references. Exact selector syntax is an implementation
detail; a second edge family is not required for this mathematical scope rule.

A selected prerequisite also states which target requirement it needs: statement
validation, complete proof, or another named validation requirement. Existing
syntax preserves its current `nodeLocalFormalized` dependency policy, including
complete proofs for theorem-like prerequisite nodes. Do not silently weaken that
policy to statement-only validation during migration. Resolve scope before
self-edge removal or statement/proof duplicate suppression; label-only filtering
must not erase an edge between distinct realizations of the same node.

Check recursive validation requirements separately from correspondence topology.
For phase one, diagnose and reject cyclic requirement graphs without discarding
independently established local validation. Do not copy the
existing declaration-backed closure traversal's visited-node success rule into
validation evaluation. Bidirectional correspondence links are legitimate and do
not themselves introduce prerequisite edges.

Graph/planning views select a realization or translation context. Preserve
statement/proof progress for the selected realization and display correspondence
assessment separately. All surfaces consume one checked semantic derivation;
browser code must not reimplement completion.

One registry supplies distinct queries for all authored translations, unfinished
translations, and currently actionable work. Blocked work remains discoverable
with its blockers, even when absent from an actionable queue or filtered visual
graph. This is not a second inventory database. Discovering unrecorded mappings
against a whole source corpus is deferred.

Export semantic declaration associations, realization IDs, translation endpoints,
requirements, evidence kinds, and derived statuses. Join previews by semantic
identity; do not recover metadata from rendered HTML. Unsupported provider facts
must remain explicit. Plain source and links are acceptable initial foreign
presentation.

## Ownership and collaboration boundary

| Lane | Owns |
| --- | --- |
| VBP semantic refactoring | Node/realization/declaration identity, translation contracts, typed validation associations, contribution admission, completion, graph and query projections |
| Reusable Verso LSP/rendering | Contexts, document construction, source maps, lookup, diagnostics, highlighting, hover/navigation, portable analysis results, HTML/TeX presentation |
| LIRIS pilot | Canonical source inventory, exact source anchors, authored correspondence explanations, concrete bridge/consumer witnesses, expected outcomes and independent pilot review |

The LSP core must remain usable without Blueprint labels or graph state. The
VBP integration maps its analysis results into identified contributions;
transport configuration, process IDs, and server state do not define node
semantics. Share the smallest practical declaration/context/content identity
boundary and do not independently invent competing symbol identities.

LIRIS owns its project-specific source-faithfulness and axiom policies. VBP
represents explicit requirements and their evidence; it does not hardcode those
policies. Existing LIRIS graph authority and source markers remain in place until
a separately reviewed migration.

The external LIRIS handoff of 2026-10-23 is requirements input, not an API spec.
T01 is narrowed to canonical source identities: external snapshot/artifact import
is deferred. T02 and the core distinction in T04 fit phase one. T03's richer
artifact/prerequisite taxonomy and T06's task/Beam integration are deferred. T05
starts with semantic queries and one bounded three-way view.

## Implementation sequence

1. **Semantic kernel and admission.** Define qualified declaration references,
   realization IDs/facets, translation records, requirements and evidence
   associations, and one completion projection. Integrate with identified
   contributions/import conflict handling, preserving provenance and replay
   behavior. Settle concrete dependent-key and cycle handling before coding
   consumers. Add focused semantic and conflict tests.
2. **Current producer migration.** Existing prose producers populate a default
   informal realization; existing Lean producers populate a default Lean
   realization in their canonical project context. Labeled foreign blocks
   associate through the general model. Retain useful concise authoring syntax
   as producers of this model, not a parallel legacy semantic store.
3. **Vertical projection.** Carry the model through capture, traversal,
   manifest/schema, CLI, shared graph/summary completion, and previews. Update
   affected JavaScript types and clients coherently. Keep semantic work visible
   independently of an actionable work-queue filter.
4. **Pilot and migration documentation.** Exercise one node with Verso, Rocq,
   and Lean realizations plus one scoped translation. Extend to the canonical
   LIRIS MaxNat/ownership family and its explicit LIRIS/iris-lean bridges. Add
   split/merged and alternative-realization cases. Document source/schema/API
   migrations without compatibility layers.

Keep each landed slice internally coherent. Do not land dual independently
authoritative completion implementations as an intermediate architecture.

## Acceptance cases

- One node has independent Verso, Rocq, and Lean realizations and facet-specific
  content and validation. Merely rendering code does not mark it checked.
- Two Lean alternatives do not contribute to each other's completion.
- Same-name symbols in different projects/languages remain distinct; unresolved,
  ambiguous, and unsupported references retain diagnostics.
- A complete target with pending correspondence remains an incomplete full port;
  a statement-only translation can complete with a pending target proof.
- Tests, proofreading, and proof checking discharge only suitable requirements;
  a witness proves the named relation under its stated assumptions.
- A changed statement or reviewed source invalidates affected validation.
- One-to-many and many-to-one endpoint groups work across node boundaries.
- Two targets of one reference do not gain an inferred equivalence.
- Blocked translations remain queryable; actionable work excludes blocked items.
- Requirement cycles cannot create success, and incompatible imported
  contributions are diagnosed deterministically with producer provenance.
- Existing Lean no-hole/coverage guarantees and local/prerequisite completion
  distinctions survive the producer and projection migration.

## Deferred scope

Independently versioned or cross-toolchain artifacts; receipt history and generic
policy engines; non-mathematical package/notation/frontend obligation kinds and
their richer prerequisite families; task ledger lifecycle and worker launching;
interactive Beam sessions; automatic whole-corpus mapping coverage; and LIRIS
authority migration. These are not prerequisites for the first implementation.

## First internal implementation checkpoint

The first bounded implementation supplies pure Lean data and functions, tested
without connecting existing producers, environment extensions, graph/CLI exports,
or language tools. This is an internal API for review, not landed authoring syntax
or a second production completion authority.

| Module | Current responsibility |
| --- | --- |
| `VersoBlueprint.Realizations` | Logical project/language/object/document identities, node and realization/facet/declaration records, semantic subject/requirement keys, producer provenance |
| `VersoBlueprint.Validation` | Expected proof/review/named-check requirements, distinct provider observations and coverage, evidence suitability and result vocabulary |
| `VersoBlueprint.Translations` | Explicit endpoint facet selection and claims, collect-then-resolve admission, current-content bindings, prerequisite evaluation, selection and inventory queries |

`Translations.admit` rejects structural reference errors and incompatible
producer/semantic definitions with deterministic diagnostics. Identical replay is
harmless. Missing/unsupported source observations and unsuitable evidence remain
queryable unfinished work. Requirement cycles are rejected by the validation
projection, retaining independently established local results; they do not erase
the collected source facts. Correspondence topology alone does not create a
validation prerequisite.

`Registry.bindingFor` produces an exact canonical JSON encoding of participating
source documents, object/document identities and connected contracts. It excludes
evidence, producer replay order, and lookup diagnostic wording. Whole documents
and connected contracts give deliberately conservative invalidation. This is a
current-content comparison token, not an artifact/version import format.

`Registry.localResult`, `resultForRequirement`, and `resultFor` distinguish a
local matching observation, prerequisite completion, and an aggregate contract.
One current suitable observation discharges a requirement; multiple mandatory
checks or reviews must be represented by separate conjunctive requirements.
Required declarations combine conjunctively. An unrelated unavailable declaration
does not erase a current local proof result; it can still block the realization.
Declaration queries check only the selected declaration. Facet queries and
translation endpoints check their selected documents/declaration references;
an unrelated proof-only helper does not block an available statement facet.
Whole-realization queries still check all declared members. Each selected facet
must have actual source content, via documents or associated declarations; empty
or whitespace-only canonical bytes cannot be validated by a passing review.
Correspondence proof requirements also require available selected endpoints,
while the underlying theorem can remain independently checked on its own subject.
`selectRequirement` selects by identity/context/name rather than completeness.
`translations`, `unfinished`, and `actionable` have no rendered-graph or task-state
dependency. Existing default-Lean selection and automatic-dependency migration
still require their separately scoped adapters and integration tests.

### Trust boundary and test limits

`Validation.Goal` is an independently specified provider-owned proposition
description in a logical context, with canonical source references. A
language adapter must elaborate that expectation, check the submitted witness's
actual type against it, and obtain conservative completeness coverage from its
normal checking tools. The pure rules compare supplied goal descriptions; they
do not implement type checking or definitional equality. Source documents are
provenance rather than proposition equality. A successful flag without a matching
type observation is insufficient; an unavailable checker need not invent a type.

All source-resolution, proof, review, and executable-check facts in
`BlueprintRealizations.lean` and `BlueprintTranslations.lean` are explicitly mocked.
P01-P22 provide traceability for pure identity/admission/validation/planning
controls, including goal mismatch, conditional-witness mismatch, stale reviews,
alternative realizations, cycles, and replay. These tests do not certify canonical
Flag/MaxNat sources, real language-checker output, existing environment imports,
or browser/graph/CLI integration. A named Rust test result is a supplied test
observation, not a proof certificate. Project-specific axiom/fidelity policies
remain outside the pure rules.

### Opt-in connection to an accepted Lean theorem

`VersoBlueprint.Realizations.Existing` now provides an explicit read-only API for
one existing attribute-owned theorem with its own Markdown docstring. `project`
reads the accepted node through `Environment.getNode?`, keeps its canonical
qualified declaration, module and source-path association, and reads that source
file. It returns two named realizations: `lean` and `docstring`. The latter has
language `markdown`: raw Markdown from Lean's own docstring store is not a claim
that Verso processing, proofreading or correspondence review succeeded. Missing
or blank source is an explicit error. The injectable source reader is a provider
boundary for testing unavailable I/O; successful use must read canonical bytes.

`Projection.validate` takes an independently authored expected proposition as Lean
syntax. `VersoBlueprint.Validation.Lean` elaborates it in the selected current
environment, requires a closed proposition with concrete universes, kernel-checks
it and inspects its dependency closure with the canonical checker. Open terms,
free assumptions, admissions and unavailable expectation dependencies are rejected
before witness matching. Bound variables inside a closed proposition are allowed.
The witness is resolved by qualified identity in the selected Lean context.
Actual type matching uses Lean definitional equality followed by a kernel-checked
conversion, so an independently written definitionally equal alias can pass.
Goal descriptions use exact expression structure; they are never the matching
algorithm. Only after this comparison does the native observation use the
expected descriptor for the pure API's proposition comparison.

Completeness comes from canonical `Data.analyzeDeclaration`, including the landed
imported-body coverage repair. A real proof, an admitted proof, a genuine axiom,
a missing witness and hidden/unverified body have distinct reports. Hole-free
coverage does not assert absence of project axioms: observations retain the
reported axiom assumptions, and separate axiom-policy requirements remain
necessary where desired. Elaboration/checking state is restored after every
native call; transient elaborator declarations cannot establish an expectation.

The returned input shares one declaration proof requirement with the proof facet.
No review or translation is inferred. For example, the provider fixture's theorem
`∀ n : Nat, n = n` validates against that proposition and its `Reflexivity` alias,
fails against `False`, and leaves an explicitly authored docstring-to-Lean
correspondence pending without review. The informal realization is unassessed.

This is an internal explicit API, not a production graph/checker installation.
Its supported projection excludes grouped/multiple declarations, inline code,
definitions, foreign associations, own Verso-format or inherited docstrings, and
additional informal proof bodies. Unsupported cases are diagnosed without choosing
a first member or dropping associations. Universe-polymorphic *expected*
contracts are unsupported; concretely instantiated polymorphic witnesses are
tested. Witnesses are declaration constants checked against their whole declared
type; argument-applied witness terms are not supported. The caller selects the
logical project; this API does not discover or
authenticate project ownership, or accept foreign build artifacts.

Source bytes and compiled metadata must come from the current ordinary owning
build. This connection does not certify that an arbitrarily edited source file
still matches an already loaded environment, nor provide historical receipt
replay. It binds whole source files conservatively. `BlueprintRealizationAdapter`
tests the real provider/consumer path, including definitional equality, rejected
expectations, admitted and axiom controls, source-I/O failures, unchanged accepted
membership and pending correspondence. Hidden-body controls reuse the existing
same-toolchain module fixture at ordinary import visibility. These tests do not
certify the separate admission/import rewrite, Rocq/Rust checking or UI paths.

## Review and working structure

Use one semantic integration owner and a dependency-ordered implementation
series. Review the semantic kernel before parallel producer/projection changes.
After its API is fixed, delegate only disjoint file scopes in harness-created
worktrees. Keep the LSP/rendering lane independent and exchange a minimal typed
boundary rather than merging speculative monolithic branches.

An independent Astra review should challenge identity/facet ownership, validation
subject typing, non-vacuous completion, requirement cycles, alternative
realizations, default-producer migration, and the narrow first-phase scope.
Implementation and focused regression work can use Sol, with another independent
review after the first complete vertical slice. Model choices are execution
recommendations, not part of the public data contract.
