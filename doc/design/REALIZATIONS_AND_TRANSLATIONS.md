# Realizations and translations

Status: frozen ontology, 2026-10-23; canonical migration milestone amended by the
user on 2026-10-24. This is an agreed design for implementation, not a description
of all currently supported syntax or APIs.
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
one existing attribute-owned theorem with its own Markdown or Verso docstring. `project`
reads the accepted node through `Environment.getNode?`, keeps its canonical
qualified declaration, module and source-path association, and reads that source
file. It returns two named realizations: `lean` and `docstring`. The latter has
language `markdown` or `verso`, selected from the direct own native docstring
metadata. Neither doc registration nor source parsing establishes proofreading,
mathematical review, all deferred Verso checks or correspondence acceptance. Missing
or blank source is an explicit error. The injectable source reader is a provider
boundary for testing unavailable I/O; successful use must read canonical bytes.

Ordinary attribute proof dependencies do not make an informal proof body. The
projection accepts either no proof slot or the dependency-only slot assembled
with missing syntax and no retained preview blocks or elaboration syntax. An
authored nonmissing placeholder remains unsupported even without a body; retained
preview or elaboration content remains unsupported even with missing syntax.
Accepted uses remain in the Blueprint environment, without duplicate storage,
generated proof prose or installed validation prerequisites. This support does
not change source, native identity, association or range checks.

Canonical prose comes from the original declaration's direct modifier comment,
not a rendering, elaborated-tree representation or fallback children. Parse the
accepted source file without elaborating its commands, require one declaration
matching both the full native declaration range and the selected name range, and
extract its original `/-- ... -/` body. The body convention removes just those
ASCII delimiters and retains every other byte, including initial/final whitespace,
native-reference syntax, mathematical markup and supplementary Unicode. This
also means Markdown uses original source whitespace rather than Lean's normalized
docstring-store text. Whole-source bindings remain conservative.

Attribute application can precede Lean's range registration, leaving the accepted
association's snapshot ranges empty. The adapter resolves current ranges through
the public native reader for the accepted canonical declaration, requires the
same native owning module, and rejects disagreement with any stored snapshot
ranges. The owning source `FileMap` and `DeclarationRange.ofStringPositions`
convert original byte positions to Lean codepoint and UTF-16 columns. The
consumer's current file map is never used for imported source. Missing ranges,
synthetic or unmatched positions, competing own formats, duplicate range matches,
missing own comments and parse failures have explicit diagnostics. There is no
nearby-comment or source-spelling fallback.

Focused controls assert that an ordinary accepted attribute snapshot really lacks
both range fields while current native ranges and exact source projection succeed.
Agreeing optional snapshots pass; disagreement in either full or name selection
ranges fails. The unavailable-range control reads a real checked synthetic
declaration. The pure range-agreement helper accepts standalone comparison inputs
for negative tests and never changes an accepted record or producer fact.

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
definitions, foreign associations, inherited docstrings, and
additional informal proof bodies. Unsupported cases are diagnosed without choosing
a first member or dropping associations. This textual native-object boundary
requires lossless canonical Lean-name serialization: unsupported internal names
are diagnosed as `unsupported-identity`, not reported as missing declarations.
Ordinary escaped names remain supported. Universe-polymorphic *expected*
contracts are unsupported; concretely instantiated polymorphic witnesses are
tested. Witnesses are declaration constants checked against their whole declared
type; argument-applied witness terms are not supported. The caller selects the
logical project; this API does not discover or
authenticate project ownership, or accept foreign build artifacts.

Source extraction supports direct ordinary declarations and option-wrapped
declarations such as `set_option doc.verso true in`. It does not elaborate newly
defined syntax, enter quoted/macro-generated declarations, or infer arbitrary
directive provenance. Inline own-comment plus `inherit_doc` is refused. A source
file containing standalone `attribute [inherit_doc ...]` commands is conservatively
refused, including quoted forms, because this adapter does not resolve those
applications into a separate provenance service. Own native metadata without a
matching original comment is insufficient, even if injected by a metaprogram.

Source bytes and compiled metadata must come from the current ordinary owning
build. This connection does not certify that an arbitrarily edited source file
still matches an already loaded environment, nor provide historical receipt
replay. It binds whole source files conservatively. `BlueprintRealizationAdapter`
tests the real provider/consumer path, including definitional equality, rejected
expectations, admitted and axiom controls, source-I/O failures, unchanged accepted
membership and pending correspondence. Hidden-body controls reuse the existing
same-toolchain module fixture at ordinary import visibility. These tests do not
certify the separate admission/import rewrite, Rocq/Rust checking or UI paths.

The native fixture also adapts the canonical two-state Flag pilot through a
normal local build. Its involution proof matches both an independently written
toggle proposition and an explicit selected-package alias. Complete proofs of
`True`, identity-package involution, or a conditional involution theorem do not
satisfy that unconditional toggle requirement. The latter two still validate
against their own full propositions: a different package is not an incomplete
proof, and an explicit premise must not disappear during matching. These are
native boundary controls; no Rocq correspondence review or external artifact
validation is implied.

The Flag fixture now retains an actual own Verso account with markup, a native
reference and a two-case explanation. Its real Lean proof completes; the Verso
realization remains unassessed, and an explicitly authored correspondence remains
pending without its own review. Exact-text tests use an option-wrapped imported
declaration with supplementary Unicode before the selected name and inside its
docstring, plus identical neighboring prose. Failure controls cover conflicting
native metadata, own/inherited comments, absent original comments/ranges, malformed
source and synthetic/ambiguous source association. Negative structural/I/O
injections supply no fabricated successful native observations.

### Combined three-realization source example

`BlueprintRealizationThreeWay.lean` composes the accepted Flag projection with
one authored `rocq-reference` realization on the same node. Existing `docstring`
and `lean` identities/checking remain unchanged. The Rocq source and `_RocqProject`
are ordinary local test adaptations of the existing Flag family, not replacement
authorities for LIRIS/Rocq or imported compiled artifacts. They are actual tracked
source/config bytes. The qualified symbol spelling
`TranslationHarnessReuse.Flag.toggle_involutive` and its project context are
explicit authored references, never parsed as Lean names or reported as resolved.
Readable source, a matching filename/config prefix and `Qed` establish no foreign
checking. Resolution is explicitly `unsupported`, with the provider gap retained.

The typed query outcomes are:

| Item | Result |
| --- | --- |
| Independently expected native Lean toggle-involution proof | Complete through actual checking |
| Actual Verso account | Unassessed |
| Explicit Verso-to-Lean statement correspondence | Pending its own review |
| Explicit Rocq-to-Lean statement correspondence | Blocked on unsupported declaration resolution |

Both correspondences have distinct claim-local review requirements. Only actual
native proof evidence is supplied. The selected Rocq statement facet includes its
declaration association as well as source/config documents, so readable text cannot
silently bypass unavailable resolution. Both links remain in unfinished inventory;
the blocked Rocq link is excluded from actionable work. This does not erase the
independent Lean proof or infer correspondence between any pair of realizations.

Synthetic in-memory source/config/claim changes invalidate the Rocq correspondence
binding while preserving native proof evidence. Empty/missing source, wrong project
and an unselected readable alternative stay explicit. These controls supply no
successful foreign resolution, proof or human review, and mutate no accepted node.

The two fixture files are content-tracked Lake inputs wired to the existing test
library, a deliberately coarse test-only dependency. The new focused root embeds
their bytes and compares them with current files during actual elaboration. Normal
builds after bounded reversible source/config byte edits verify that the example
re-elaborates; no module mtime, output deletion or artifact restoration is used.
Production library dependencies/toolchains are unchanged. This is an opt-in typed
acceptance example, not a new authoring service, production graph/CLI/browser view,
Rocq compiler invocation or foreign correspondence certification.

### Inspectable supplied-contract report

`Realizations.Report.ofRegistry` is an opt-in pure Registry-to-JSON projection.
It reports only the supplied admitted contracts and existing evaluator results;
it does not establish project readiness, omitted Blueprint dependency closure,
provider authenticity or external source/tool freshness. There is no overall
ready/completed flag, new assessment rule, mutable cache or import/replay path.

The report retains full authored node, object-resolution, realization,
translation, claim and requirement inventories. Document entries contain keys,
not source bytes. Realization entries retain qualified identities and original
facet/declaration associations, with existing whole/facet/declaration results.
Translation endpoints retain their exact selected facets; claims retain authored
interpretations and assumptions. Requirements expose `localResult` separately
from prerequisite-aware `result`. Existing `unfinished` and `actionable` queries
produce key selections alongside the full authored translation inventory, so a
blocked translation stays discoverable.

Evidence entries retain identifier, exact requirement reference and typed provider
observation, including outcome, assumptions and coverage. Their separate
`suitability` delegates to `Evidence.mismatch?` using that exact requirement and
the registry's current binding. `matchesCurrentRequirement` and `mismatch` concern
that individual observation, independently of other evidence or the requirement's
aggregate result. A provider outcome of `passed` may still have `stale-content`;
another suitable item does not endorse it. Suitability is a contract/binding
check, not provider authentication or proof that all subject content is available.
Bindings remain internal; no raw contribution dump or full source bytes are
exported. This output cannot serve as an imported validation receipt.

The existing actual Flag composition tests structured JSON parsing, qualified
identities, source resolution explanations, selected facets and four independent
outcomes: native proof complete, prose unassessed, Verso correspondence pending,
Rocq correspondence blocked. Existing source/config/claim and alternative controls
exercise the report without erasing the independent native proof. A labeled
synthetic native-source change leaves its actual `passed` observation present but
unsuitable and its requirement pending. A mixed inventory retains the stale item
as unsuitable even when a current item completes that requirement. Identical
producer replay and top-level contribution reordering preserve output without
reordering authored contracts. Empty registries produce empty inventories;
reporting changes neither supplied contributions nor accepted Blueprint state.
Production graph, manifest, CLI/browser, registration and dependency traversal
remain separate work.

### Opt-in accepted dependency selection

`Realizations.Dependencies.selectUses` reads a supported accepted attribute theorem
and returns its effective statement and proof uses separately. Each result retains
the full `UseRef`, its existing order and either a selected requirement key or a
diagnostic. Manual/automatic origin and intent remain metadata; origin does not
select a producer scope. Shared labels across axes stay separate. The adapter does
not filter self edges, merge axes or traverse dependencies. Missing or unsupported
source/view is an outer error, distinct from a supported source with no uses;
unresolved targets remain individual edges.

For a single accepted attributed theorem, the explicit Lean project context,
realization `lean` and requirement `proof` are passed to the existing registry
selector. The selected subject must be exactly that realization's accepted
canonical declaration. Its expectation must be either the native
`lean.declarationCompleteness` check or an independently expected proof with the
same witness and goal context. Both require `dependencyClosure` coverage and
membership in that declaration's requirements.
The default realization must associate exactly that one declaration. Missing or
ambiguous defaults, reviews or arbitrary checks named `proof`, statement-only
native checks, another declaration
or witness, mismatched context and insufficient coverage stay diagnostic. Native
names that cannot round-trip losslessly retain the existing unsupported-identity
boundary. Definitions, grouped declarations and other association forms are
outside this first adapter.

Selection never consults completion, tries a complete alternative, rewrites
prerequisites or manufactures proof/review observations. The existing evaluator
answers completion for the returned key. In particular, matching contract identity
does not certify an arbitrary goal description as the native theorem's type;
independent expected-proposition checking remains the native provider's job.
Explicit same-node cross-realization prerequisites remain unchanged.

`BlueprintRealizationDependencies` uses actual accepted manual/automatic uses and
imported native theorem checks. A clean theorem completes; a clean statement with
an admitted proof selects its declaration proof and remains pending despite a
genuinely checked complete alternative. Removing evidence preserves selection;
actual wrong-proposition and unavailable-environment checks cannot supply proof
completion. In-memory contract corruptions are labeled synthetic and contribute
no mock successful validation. Its actual source theorem now uses the same
`project`/`validate` path despite its dependency-only proof slot. Tests assert
exact own Verso raw bytes, canonical identities and owning source bytes. An actual
consumer selects that source's default native proof. Local native checking
completes while the source's admitted Blueprint dependency remains pending and
its prose unassessed; this is not aggregate dependency closure/readiness. Synthetic
proof-body and placeholder injections are rejected and restore the environment
on success and failure. Accepted state is not mutated.
Graph/CodeHealth comparisons cover only the supported theorem-local policy. No
transitive readiness, cycle semantics, legacy-wide parity, production graph
connection or verification-v1 admission change is included.

### Direct accepted-use report

`Realizations.DependencyReport` adds `Report.ofSource registry context source`, a
read-only composition of the unchanged selector, evaluator and pure report. Its
outer `Except` preserves source/view failures. Successful JSON names the accepted
`source` and explicit logical `context`, nests exactly `Report.ofRegistry` under
`registry`, and reports direct `uses.statement` and `uses.proof` arrays. A supported
source without uses has two empty arrays, not a source failure.

Each entry retains the complete effective `use` and its position on that axis.
Its `selection` contains either the exact selected `requirement` plus existing
`Registry.resultForRequirement` result, or the exact selector `diagnostic`. Failed
selection does not invent a blocked validation status or remove the edge. Shared
targets across axes remain separate. There is no producer-scope inference,
alternative fallback, self-edge filtering or recursive inspection.

The accepted source's presence establishes only the source of direct edges. It
does not establish that the supplied registry includes its validation: a sparse
registry remains sparse, missing target contracts remain selection diagnostics,
and no unrelated requirement is borrowed as a source proof. No source completion
or aggregate ready flag is synthesized. All supplied-contract evidence suitability
and inventory distinctions remain inside the unchanged nested report; source
bytes, bindings and raw contributions are not exported.

The actual dependency fixture shows its local native proof complete, prose
unassessed and selected admitted dependency pending together, with unresolved
targets still visible on both axes. It checks exact metadata/order/keys/results,
source/context, nested report identity, real consumer selection, sparse inventory,
empty versus failed source/view, a genuinely complete alternative, one ambiguity
and actual native unavailability. Reporting preserves accepted state, supplied
contributions and explicit prerequisites. This is direct-edge inspection, not
recursive Blueprint closure, project readiness, provider authentication or a new
prerequisite/traversal installation. Production graph/CLI/browser paths remain
separate work.

### Ordinary source authoring and import (opt-in)

`Realizations.Authoring` connects the accepted theorem/docstring adapter to
ordinary modules. A module explicitly chooses its logical project before its
attribute declarations and source attachments:

```lean
run_cmd liftCoreM <| Informal.Realizations.Authoring.configureProject `myProject

/-- Independently authored prose for this theorem. -/
@[blueprint "my.result"] theorem result : True := True.intro

def expectedResult : Prop := True
run_cmd liftCoreM <| Informal.Realizations.Authoring.expectNative
    `resultContract (Name.mkSimple "my.result") `MyModule.expectedResult
```

The independently authored expected proposition must be a safe checked definition
or abbreviation owned by the specification module, with a unique original
declaration/source-range association. An axiom is not a specification definition.
The existing native provider checks closedness, proposition typing, admissions,
actual definitional equality and proof completeness. Expected goals are never
copied from witness types. A specification may be staged before its definition;
checking waits for the query after normal owning-module elaboration/build.

Configuration is exact-module-local and not inherited by importers. Within a
configured module the default producer supports a new single attribute theorem
with its own docstring, using the same accepted canonical association. It stages
the exact complete `ContributionId`, not another editable copy of its identity.
Unconfigured attributes retain their existing behavior. Existing nodes and
unsupported default shapes reject explicitly; accepted legacy-node presence
alone never enrolls a default. Every enrolled default gets its actual native
statement and complete-body checks. A clean theorem without an independent
expectation can therefore have complete native proof validation; its prose stays
unassessed. Docstring presence creates neither proofreading nor completed
correspondence.

`Authoring.stage id batch` retains additional source documents, authored object
references, realizations, translations, claims and requirements. It installs no
node, observation or validation result. Authored references currently resolve as
unsupported, even when their original source/configuration bytes are readable.
This supports a Rocq attachment without manufacturing foreign symbol/proof facts.
Stable site IDs have structured module/name boundaries: module `M` with site
`N.x` differs from module `M.N` with site `x`. Exact replay is idempotent; different
complete envelopes from the same producer identity reject as collisions.

One existing Environment extension stores these raw records. Only locally
authored records are exported; imports collect all variants, preserve their
original specification origins, and permit forward references. Staging success
means retained input, not semantic admission. The attribute transaction computes
eligibility from the pre-state, runs the shared reducer, plans raw enrollment and
catalogs on the returned candidate, then publishes once. Planning failures,
exceptions and newly logged errors publish no candidate. An enclosing directive
transaction restores all the new fields along with its existing stores.

A normal consumer imports Owner/Attachment modules and calls
`Authoring.registry : TermElabM (Except (Array Diagnostic) Registry)`. It does not
assemble `Input` or call `admit`. The query resolves exact default IDs against all
retained facts and accepted associations; missing, colliding and unsupported
associations fail explicitly. Only then does it project current canonical source,
using the existing native-range timing rules. Each physical source is read once
per attempt, with its owning FileMap and original association checks intact.

`NativeSource.PreparedModel.prepareValidation` returns evidence-free source/contracts
and a fresh native observation, without admission or binding. Its optional extra
goal documents include the independent specification source. Existing `validate`
delegates with unchanged defaults. Authoring collects *every* default,
specification and attachment, admits the complete evidence-free batch, binds the
observations to that same admitted snapshot, then admits the complete final
batch. No fragment Registry or silently accepted subset escapes. Competing
expectations retain all original specification origins and reject together;
equivalent expectations retain both origins and fresh observations. The native
`proof` requirement remains separate from the independent `expectedProof`
requirement: a wrong independent expectation cannot erase the theorem's own
native validity. Declaration-wide completion includes both when both are
required; the native proof facet and ordinary selected theorem prerequisite use
the native body check without duplicating the expected specification. Queries
restore Environment and elaborator state on success, rejection and exception.
No observation, binding, Registry, status or completion bit is persisted/imported.

`BlueprintRealizationAuthoring` imports an ordinary Owner/Attachment diamond,
including a forward Rocq endpoint and exact replay. Its actual Flag theorem is
complete, its Verso prose is unassessed, its Verso correspondence is pending and
its Rocq correspondence is blocked. An independent consumer-owned expected
definition can validate another imported default. Tests cover original source
bytes/current bindings, attribute-before-range timing, project isolation, lossless
module/site identity, producer collisions, competing/invalid specifications,
complete-fact/accepted-association mismatch and deterministic batch rejection.
Labeled synthetic inputs test candidate/default/catalog rollback and enclosing
directive failure/exception restoration; they supply no successful provider facts.

This is a bounded opt-in source connection on landed #498. Pending #499's exact
selected-name gate remains a mandatory separate combined-tree validation/landing
dependency; it has not been imported into this checkpoint. The shared reducers,
selected-evidence laws and their test root remain independently owned. Production
graph/CLI/browser integration, Blueprint dependency-closure/prerequisite
installation, foreign checking and authority migration remain outside this step.

### FIR evaluation follow-up

The theorem dependency selector accepts the exact native complete-body check
described above. It retains the same default realization, declaration, context,
required-membership and coverage rules; it does not consult completion or try
another implementation. Actual imported controls cover a complete native-only
theorem, an admitted default with a genuinely complete alternative, and a wrong
independent expectation alongside a complete native proof.

An owner-run regression confirmed that a second declaration could previously
require its sibling's declaration-local native check and borrow its completion.
Admission now rejects that association. Native observations also retain their
checked declaration, and suitability requires an exact match with the native
requirement's declaration subject. Relabeling a real observation and binding it
afresh cannot make it validate another declaration. One declaration's check can
still serve its own statement/proof facets. Joint realization/facet reviews and
cross-node mathematical prerequisites remain legal; they do not become native
declaration checks. Native check observations retain their actual assumptions
separately from conservative no-hole coverage.

Current correspondence bindings include transient provider semantic inputs as
well as canonical source bytes and contracts. For native Lean, these capture the
reachable checked declaration types, available bodies, declaration kinds and
reduction rules, the compiler version/commit, effective options, and the compiled
native provider/checker source. Independent expected-goal checks additionally
capture the witness and independently elaborated proposition's semantic roots;
each requirement has its own expected-context input. Missing/hidden semantic
inputs leave correspondence or independent-goal validation explicitly blocked.
An unchanged local name or source document cannot substitute for imported meaning.

Both subject-scoped and dependency-closure-scoped correspondence reviews include
the native semantic closure needed to interpret their selected declarations.
`dependencyClosure` additionally requests the explicitly linked validation
prerequisites; it does not discover omitted Blueprint edges or certify project
readiness. Bindings remain conservative over connected contracts and containing
documents, so irrelevant local changes can invalidate a review too. Prose-only
content binds its authored bytes; arbitrary prose mentions, external runtime/FFI
state and test environments require explicit inputs from their owning provider.
No foreign semantic capture or general environment-authentication guarantee is
claimed by this native adapter.

These inputs and derived binding/evidence caches belong to one immutable admitted
snapshot. `Registry.contributions` is read-only; changed input must pass complete
admission and recompute its derived bindings. No semantic snapshot, completion or
review evidence is persisted by import. Reports expose suitability separately
from provider outcomes and do not export raw semantic inputs, source or bindings.
Caching the derived values avoids repeatedly encoding large semantic closures
during a single report/query; this is not a scaling certification.

`BlueprintRealizationSemantics` and
`tests/test-realization-semantic-binding.py` exercise ordinary imports/builds.
The test saves explicitly mocked current review bindings, changes only an imported
runtime definition, rebuilds normally, and requires both review scopes to become
stale while fresh native proof checking stays complete. It restores the exact
bytes, rebuilds again and checks the original bindings are current. The theorem,
prose and consumer source stay unchanged. Native observations are real; the saved
reviews are temporary test controls, not human assessments or a receipt feature.

The FIR consumer cases remain acceptance requirements for the canonical cutover:
partial progress must not complete a parent package; conditional theorems must
not discharge unconditional instances; direct/inherited gaps retain their axis
and actual cause; definitions keep their mathematical homes and grouped
declarations remain conjunctive; descriptive mentions do not create proof
associations or uses; stable labels do not preserve stale reviews after content
changes; examples, general theorems and later corollaries keep their distinct
statements and checked instantiations. The typed-mention query gap remains the
existing BP-VBP-20261020-001 request. No additional historical receipt system or
`generalizes` relation is needed. Agent updates remain ordinary source edits,
normal builds and read-only queries. These bounded tests do not claim that the
ordinary production graph/CLI/API can run those FIR cases yet.

## Canonical migration required before publication

The opt-in checkpoints above establish the rules and adapter behavior. The user
requires the existing representation to be replaced before this refactoring is
published. An additive authoring path or another report wrapper does not satisfy
this milestone. Existing authoring, imported data, graph/query behavior and
rendering must consume the realization model; the superseded representation and
completion path must be deleted. This section is the migration target, not a claim
that the cutover has already happened.

### One authoritative representation

Keep labels, kind, ordering, grouping, authorship and other shared concept metadata
on nodes. Store statement/proof source as named facets of named realizations.
Keep source-language/project identity on realizations and native object identities
on declarations. Preserve original source, compiled presentation payloads and
navigation metadata as source/provider data for those realizations, with explicit
keys; they must not become a second editable semantic model.

Replace the existing node-level statement/proof body fields, external statement/
proof reference arrays, literate Lean blocks, Rust attachment and markup slots
with realization/facet contributions. Existing markup authoring remains a frontend
to this representation. A theorem declaration may serve both facets without two
copies of its proof. Mathematical uses retain their authored metadata, order and
statement/proof axes; translations remain distinct relationships. Required
declarations and alternative realizations retain their different combination
rules.

The existing Environment entry/collection/transaction boundary remains the single
source of raw imported input. Producers write ordinary realization contributions
directly, and the complete collected batch is admitted together. The temporary
legacy-node-to-realization/default enrollment bridge must disappear. Views may
derive rendering/index data from accepted realizations; compatibility storage,
legacy fallback and independently authoritative registries are not part of the
target.

### Native checking and optional prose assessment

The user confirmed that a Lean theorem's native proof check is independent from
assessment of its prose. A checked native theorem can have complete native proof
validation while its informal statement and correspondence remain unassessed.
Prose lint/proofreading and correspondence contracts are explicit and optional;
their absence does not erase or manufacture native proof validity.

The native checker can report checking of the declaration's own canonical source
statement/body as a named native check. This is distinct from proving an
independently specified proposition: existing proof requirements still require
the independently authored expected goal, checked witness conversion and current
binding. Do not synthesize an expected goal from the witness to claim statement
alignment. Reachable holes, unknown body coverage and assumptions remain visible
under the existing conservative native analysis.

`NativeLean.checkDeclaration` supplies this provider primitive as distinct named
checks (`lean.declarationStatement`, `lean.declarationCompleteness`). Its result
retains the exact declaration identity, statement/body observations, conservative
native status and inspectable assumptions. It supports the declaration's own
universe parameters, restores query state and leaves independent-goal `check`
semantics intact. Hidden/unavailable coverage is explicit and supplies no complete
closure certificate. This primitive still needs the normal canonical source
association and same-snapshot requirement binding at the production capture
boundary; an unbound provider result is not migrated graph acceptance.

### Native owning-source boundary

`Realizations.NativeSource` extracts source preparation from the temporary
`Existing.project` bridge. It imports no Blueprint Environment and never reads a
node or enrollment record. Its `Request` contains an explicit logical project,
typed canonical Lean name, owning module/path and optional original range
snapshots. The caller establishes that this metadata belongs to its selected
producer; source lookup does not establish a Blueprint association.

`prepare` returns the original full document, exact native full/name ranges,
typed declaration identity and available current semantic inputs. It supports
ordinary undocumented declarations and definitions. `prepareDocumented`
additionally requires direct own native format metadata and returns the original
modifier-comment body. It preserves the existing unique-association, owning
FileMap/Unicode, snapshot-disagreement, inheritance, synthetic/unavailable range
and no-nearby-comment rules. Missing checked identities are explicit, distinct
from source or metadata failures. Neither operation checks a proof, supplies an
expected proposition, admits a model or persists evidence.

The parser/range/comment operations now live only at that boundary. An
own-documented source can `realize` caller-supplied concept metadata and distinct native/prose
names with the owning producer's origin, returning evidence-free `PreparedModel`
input. `Prepared.realizeNative` also prepares a native-only model without
fabricating prose; definitions expose a body facet, while theorems expose proof.
Preparation of independent-goal validation also lives there. Ordinary authoring uses this direct source/model
API with its retained producer origin; only `Existing.request`, the temporary
old-shape eligibility gate, still reads old node fields. The transitional
`Existing.project` consumer delegates to the same operations and stores no second
model. Independently owned goal definitions also use the shared range check.
The bridge retains its existing theorem/docstring shape policy until
the canonical collector replaces it; it is not a compatibility target. Actual
adapter controls prepare unenrolled theorems, an undocumented proposition
definition and an own-documented definition/Verso declaration directly, with
identity/owner/range/I/O negatives. This extraction removes the source provider's
dependency on old node layout; it does not complete the node/consumer cutover.

### Consumer cutover and deletion

Build the accepted model and fresh validation once at the project capture/query
boundary. Graphs, summaries, headings, widgets, manifests and CLI queries consume
the same selected realization/facet results. Display selection cannot choose a
complete alternative, erase unresolved endpoints or infer correspondence.
Preserve the distinction between local native completion and explicitly required
mathematical prerequisites. Any graph status policy is a projection of these
results, rather than another completion evaluator.

Delete the old node-language storage, legacy projection bridge and direct
node-CodeHealth completion authority after their producers/consumers have moved.
Source-native analysis, rendering and useful aggregate display counts remain
provider/view responsibilities; deleting the old layer does not require replacing
the Lean checker or pretending foreign checking exists. Port the checked admission
guarantees and relevant laws to the new representation, preserving complete raw
evidence, selected-name stability and atomic rejection/import replay.

The migration is complete only when ordinary authoring/import and the public
graph/query/render flows use realizations, obsolete authoritative fields and
fallbacks are absent, representative reference blueprints still build, and tests
cover independent native/prose/correspondence outcomes through those ordinary
flows. The earlier opt-in fixture alone is insufficient acceptance evidence for
this milestone. Publication remains on hold during this cutover.

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
