# Realizations and assessment snapshots

The [architectural contract](REALIZATION_MODEL.md) describes the version-one
boundaries and deferred extensions. This guide describes the implemented API.
The first snapshot example uses ordinary authoring/import and fresh native checks;
its Alice judgments are explicitly mocked test data, not certified human reviews.

## One captured authority

Blueprint compiles current source-canonical input into an immutable assessment
snapshot through `plan → observe → evaluate`. Raw module contributions, resolved
records, indexes and reports are derived representations of that input. They
cannot independently redefine ownership or completion. Native success is never
persisted in the source extension or imported as authoritative evidence.

Use capture after the owning source modules have been built. Structural conflicts
reject the complete collected candidate, including imported and explicitly authored
records. There is no admitted partial registry. Missing sources and unsuccessful
assessments instead remain diagnostics on the admitted objects they affect.

## Objects, owned content, and relations

A node is the mathematical home with a stable global label. Its realizations are
current independently addressable accounts, with no cross-revision identity promise.
Each realization carries a language/project context, an explicit mathematical role,
ordered document selections and declaration projections. Role is data: do not infer
it from a realization key or from the word `lean`.

A single Lean theorem supplies separate statement and proof realizations. Both
refer to the same canonical declaration; the statement selects its meaning, and
the proof selects its implementation. Proposition definitions and proof-valued
`def`s are classified from their checked types, not command spelling. A prose
statement or argument has its own byte-bound selection. Alternatives are separate
realizations, rather than optional members of a single assessed object.

`RealizationKey.forRole` constructs unambiguous keys for ordinary producer output.
Consumers use the stored role, not that encoding. A realization cannot list one
object twice with conflicting projections. Its explicit document bytes stay bound
even when a native declaration shares that source file. Source association alone
establishes neither proof nor correspondence.

The existing `Translation` record represents a directed relation with its own key,
kind, source and target realization endpoints, inert tags and required obligations.
Its named `Claim` records retain joint interpretation/mapping and assumptions.
Those claims are part of the relation's meaning, not an independent endpoint store.
Grouped endpoints assert the authored joint connection; they imply no pairwise
correspondences or automatic composition. Tags classify and do not supply policy.

Semantic facets and `Requirement.scope` are removed. Raw `SourceSelection`s use
`SourceDestination` roles, and authored uses carry a role. Native associations
carry presentation placements, which cannot override a checked declaration's
semantic role. Capture projects sources to directly owned realizations. Preview
facets, such as `PreviewCache.Facet`, remain presentation concepts; they are not
independently assessed subobjects of a realization.

## Requirements, native support, and local judgments

A requirement has an exact subject, typed expectation, coverage and explicit
prerequisite keys. Contracts are conjunctive; an absent contract is unassessed.
The evaluator retains local evidence results separately from final prerequisite
completion. Positive local evidence in a dependency cycle cannot establish final
completion. It does not search alternative proofs or invent a node-wide policy.

### Native observations

Ordinary capture checks current declarations against Lean's checked environment.
Statement and body checks remain separate, including native dependency coverage
and used axioms. A passed check is not an axiom-free claim. Admitted, hidden,
missing or unverified bodies do not become successful proofs. Ordinary authored
`uses` wiring applies only to the generated native requirements; merely naming an
unrelated requirement `proof` does not enroll it.

The first built-in `proves(P,S)` route is exact own-type support. Its expectation
`.proves witness` applies only to a proof-role implementation selection and a
statement-role type selection of that same proof-valued declaration, with the same
context and no additional endpoint content. The current native observation must
check that proposition-valued witness with dependency-closure coverage. Each edge
gets its own binding and applicability check even when capture reuses one native
fact. A complete `Nat` definition is not mathematical proof support.

A required named review with criterion `mathematicalProof` can instead supply the
reviewed support route for the selected connection. A nonempty lint-only `proves`
contract remains unassessed with `missing-mathematical-support`. Additional required
reviews or checks remain conjunctive; native success cannot override rejection.
An exact native `proves` relation needs no extra claim record. If claims are
attached, each needs its own assessment contract; native support does not
silently discharge an unassessed additional claim.
The first example's correspondence explicitly depends on its exact native support
requirement. General aggregate requests over relations remain deferred.

Independent expected-proposition checking remains a separate API. It requires an
owned checked proposition definition, kernel conversion of the witness type and
fresh completeness checking. Its current expected syntax must be closed with
concrete universes; universally parameterized independent targets remain unsupported.
The exact own-type route retains the declaration's native universes. No expected
proposition is fabricated from prose or duplicated merely to check a theorem.
The independent `.proof goal witness` requirement does not currently satisfy the
minimum support rule for `proves`. Coexisting Lean proofs of one selected statement
therefore lack an automated formal relation route. A future route must match the
receiving edge's exact selected statement, rather than merely accept a checked
witness against an unrelated expected goal.

### Current review selection

`.review criterion reviewer` names the required reviewer explicitly. An authored
`ReviewJudgment` contains its immutable identifier, requirement, original assessed
binding and review observation. `ReviewSelection` selects one judgment identifier
or none for that requirement. Competing selections are unresolved assessment data.
Conflicting payloads for one immutable evidence identity reject admission.

Resolve selection before checking freshness, reviewer, criterion, coverage and
outcome. A stale, missing, rejected or unsuitable selected judgment supplies no
approval; an older matching approval cannot replace it. Withdrawal selects none.
No timestamp arbitration, review-history traversal or authentication is implied.
Multiple required reviewers use separate conjunctive obligations.

The pure registry checks supplied observations but does not authenticate them or
run Lean. `Realizations.Capture.capture` obtains actual native observations; human
judgments remain explicitly authored inputs. Do not stamp an old judgment with a
new binding on rebuild. Unassessed prose does not block unrelated native proof.

## Bindings and prerequisites

The `vbp-binding-sha256-v3` encoding binds each requirement's exact owner, selected
content, interpretation and own contract. Declaration projections select the native
statement or implementation descriptor. Explicit prose/document selections bind
bytes and their document identity. Composition order is significant; set-like
prerequisite identifiers are canonicalized. A claim-local judgment binds its own
mapping and assumptions; a whole-relation judgment binds all that relation's claims.
Changing a sibling requirement's reviewer does not change an unchanged local judgment.

A declared use selects native contracts of its target's ordinary Lean
realizations in its source's project context. Two rules decide the exact set
([user summary](../MANUAL.md#dependency-graph)):

- The target label's ordinary Lean declarations form one development; the use
  requires all of them, whether theorems, data definitions or both.
- The use's authored axis decides each declaration's contract. A proof-axis use
  requires the target to be done: each theorem's proof, each data definition's
  implementation and each proposition definition's statement. A statement-axis
  use requires only what the using statement needs in order to be stated: each
  theorem's statement instead of its proof, and the same implementation and
  proposition-definition contracts.

A statement that mentions a theorem is meaningful once the theorem is stated;
its proof gates proofs. If the using statement's Lean type contains that proof
term, the using statement's own dependency-closure check observes the hole.
Missing targets and targets without ordinary Lean declarations are selection
failures; a declaration owned by several ordinary realizations of the selected
role is `ambiguous-native-contract`. Naming a target realization explicitly is
not supported.

Prerequisite identities are part of the authored requirement; their content and
outcomes are not implicitly selected. The record of which target each declared use
selected binds only the dependency-selection check that produced it. A dependency
changing shape, such as a theorem becoming a definition, therefore re-runs that
check and can change completion, but leaves judgments of the using statement
current. Rewriting a proof that is only a completion prerequisite preserves the
statement judgment. Introducing `sorry` still prevents final completion.
Explicitly selected proof content does change its binding.
Evidence, current-review selections and evaluation state do not enter the binding.

Native statement meaning includes relevant computational dependencies. Selected
proof implementation includes its own body, with theorem dependencies interpreted
through their statements; a review of helper implementations must select them
explicitly. Fresh native completeness independently inspects the required closure.
Byte-bound selections remain conservative: a whole-file selection is affected by
any byte change. A supported prose selection takes its bytes from the original
source buffer recorded in its compiled syntax, checked against its stored range;
capture reads no file for it, so a prose source edited or removed after its module
was built still yields the compiled text. A plain native declaration is likewise
taken from the compiled environment: its kind, roles, semantic descriptors and
declaration ranges come from the environment, and any recorded snapshot ranges
must agree with them. Capture reads and locates no owning file for it and gives
its object no source document, so its availability rests on the environment and
its semantic descriptor. An owning file that is unreadable, edited, deleted, or
absent from the source search path (as for a dependency shipped without sources)
yields no `source-unavailable` for it and blocks none of its native checks or
realizations, and an independent expected goal binds only its specification
document. Capture still reads the owning file where its bytes are the content: a
declaration's own doc comment, whose raw bytes the environment does not keep, and
an inline Blueprint block, whose original syntax is checked against the file.
Capture checks each inline registration's declaration membership and original
block and literal ranges before sharing a native answer. Two concepts may select
the same declaration. If one registration fails, its selection reports the source
diagnostic and stays unavailable. A genuine selection on the other concept can
still resolve and use the checked declaration.

Earlier binding versions are stale; no automatic review migration is performed.
SHA-256 fingerprints are compact content identities, not kernel certificates,
provider authentication or a proof of general hash injectivity.

## Authoring, imports, and consumers

Ordinary attributes/directives register through the existing Blueprint Environment
extension. Configure the logical project using `verso.blueprint.project` or the
package's weak Lake option. The owning module's project is preserved on import.
Public capture requires unambiguous readable labels; arbitrary typed names remain
supported by the pure registry.

Explicit contracts and review inputs use `Realizations.Authoring`:

```lean
run_cmd liftCoreM <| Informal.Realizations.Authoring.configureProject `MyProject
```

Configure each module that calls `Authoring.stage id batch`. Staging retains raw
source records; it does not admit a fragment or mutate query state. `expectNative`
names an independently authored proposition definition. Authored judgments preserve
their recorded binding through staging/import; native evidence is generated only
for the current capture. Uses are validated after the complete ordinary and authored
realization inventory is available, so forward/imported references are not rejected
merely because their producer was collected later.

`Realizations.Report.ofNode` / `ofRegistry` expose each realization, relation,
requirement, local/final result, review selection and evidence suitability separately.
They omit raw source text and bindings. Provider success and current-binding
suitability are distinct. Reports describe the represented contracts, not omitted
obligations or project readiness.

`Snapshot.assessmentFor` supplies the existing graph/summary/CLI native summary.
Its `nativeLocalSummary` describes checked native declarations, while full labeled
assessments remain in `details.assessment`. Its `requiredComplete` field is the
native-contract summary, not “some acceptable proof exists” or universal node
completion. This first slice does not redesign graph layout or aggregate requests.

```sh
lake exe vbp query status <label>
```

Build the owning sources first. Queries read a generated capture; they do not
recheck edited files. Preview declaration inventories remain display data and
cannot establish native completeness without capture.

## Migration and bounded example

Update clients from `Facet` / facet subjects to separately keyed realizations with
roles and direct documents/declaration projections. Endpoints name realizations;
requirements no longer choose scope. Add named reviewers and explicit selections
for required human reviews. Rebuild snapshots and reassess old bindings.

`BlueprintAssessmentSnapshot.Owner` is ordinary source authoring with Lean S/P and
Verso T plus an unfinished informal alternative. Its imported consumer checks actual
native support, explicitly mocked Alice input, separate local/prerequisite results,
withdrawal/conflict/no-resurrection, and per-edge evidence reuse. The reversible
`tests/test-assessment-snapshot.py` runner saves one original mock binding and tests
normal source edits/builds for proof rewrite, admission, statement/mapping/prose
changes, then restores the exact original source bytes. It must run under the
maintainer's whole-tree resource cap. Validation receipts distinguish setup from
capture time; this tiny example is not a FIR scalability certification.

Foreign Rocq/Rust resolution/checking, polymorphic independent-target matching,
aggregate completion requests and the formal proof-layer port remain separate work.
Readable foreign source/configuration does not establish foreign proof validity.

## Consumer pilot contracts and pending extensions

The Rocq-to-Lean pilot motivates the following contracts. These specify the
intended boundaries before choosing additional schemas or UI. They do not adopt
the pilot's receipt adapters, requirement-query patch, or its validation claims
as production Blueprint behavior.

### Document identity and relocation

`DocumentKey` contains a language/project context and a path. For prose,
foreign source and document-only content, that entire key participates in
bindings. Relocating a selected path therefore invalidates old evidence even
with identical bytes. Declaration-backed Lean content instead uses its native
semantic descriptor as described above. This means the evidence no longer
matches the current binding; it does not establish a semantic regression.

The intended extension separates a project/package-scoped logical source identity
from its filesystem locator. Moving only the checkout root should preserve
correspondence acceptance when logical identities, bytes, semantic dependencies,
contracts and their interpretation are unchanged. A renamed or replaced
logical source remains a binding change unless an explicit identity is preserved.
Do not infer identity by basename, content equality, or stripping path prefixes.
Use the existing owning source registration for location; no second authoritative
document database is needed. The precise field/API amendment is still pending.

Identity migration must be explicit and fail closed: existing path-based bindings
are not silently rewritten or accepted under a new encoding. Rebuild the captured
model and reassess affected reviews. Native validation is rerun normally. This
does not require a historical receipt store or a new completion status.

Acceptance cases for that extension: identical bytes at another checkout root;
changed bytes under one logical identity; equal relative names in distinct
projects/packages; multiple locator aliases resolving to one identity; conflicting
bytes for one identity; and old bindings after the encoding change. Equal repeated
contributions may still deduplicate under ordinary admission. Conflicting owners
or locator resolutions must produce diagnostics rather than choose a winner.
The existing `BlueprintTranslations` pilot controls pin the current conservative
path behavior and project separation; they do not test a locator-independent API.

### Validation, correspondence, freshness, and readiness

Keep provider outcome, current-binding suitability, local requirement completion,
and prerequisite completion separate. Native checks can all pass while a local
correspondence review is stale and pending. A second locally pending review can
be blocked by the first correspondence. Task ownership/status does not discharge
either requirement. A correspondence review does not establish a runtime result.

The pure pilot regression uses explicitly mocked evidence to test this distinction:
a path-only source relocation stales two reviews, leaves the unrelated native
proof complete, and exposes only the upstream translation as actionable. This is
not a foreign-provider or performance certification. Existing P02/P03 and P22
controls cover native/correspondence separation and prerequisite readiness.

Current binding mismatch diagnostics are conservative. Readable reasons should
identify source, target, contract or dependency changes when supported by retained
inputs; an opaque old hash alone cannot establish which component changed. Do not
invent a semantic-change explanation when only a binding mismatch is known.

### Shared blockers and typed queries

The intended query identifies an exact typed requirement, its expected evidence,
local result, prerequisite path and affected translations. Shared actionable work
should appear once per requirement identity while retaining all affected
translations. Complete and blocked requirements remain inspectable. A prose
support node links to these obligations; its presence does not certify them.

The pilot's structural identity query is a candidate, not yet an owner API.
Required controls include same-display/different-structural Names, conflicting
rows, malformed identities, obsolete report schemas and ambiguous display aliases.
Invalid graph copies must not disappear when another copy looks valid.

Distinguish a complete-capture unknown identity from an inconclusive miss in a
partial exported view. This does **not** authorize partial registry admission:
capture still admits one complete collected batch atomically. Export coverage
must be explicit and cannot be inferred from graph presence or an empty array.
An output reader inspects captured results; it does not authenticate providers,
reevaluate proofs, or certify arbitrary edited JSON. Exact identities and display
text should come from the same typed values without duplicating evaluation policy.

### Rocq dependency scope

Accept justified source/dependency scope as the criterion for future Rocq evidence
binding. A source locator map is not a dependency closure. Retain conservative
bindings until a provider can justify narrower coverage, including imported
dependencies and assumptions. Mutation tests must invalidate relevant changes;
only then may an unrelated-file change preserve a scoped claim. This work belongs
at the provider boundary and does not make readable Rocq files proof evidence.

### Natural alignment and workload comparison

A correspondence can relate native representations without making them identical:
for example Rocq positive/Z/N and Lean Positive/Int/Nat. Each authored relation
must say what happens for empty and unsorted lists, duplicates, zero/negative
coefficients, absent keys and out-of-range indices. Sorting or normalization is
not an implicit precondition. An operational adaptation such as one comparator
versus equality followed by numeric comparison is explicit.

A separate workload contract binds endpoint variants, adapters, paired inputs,
key sizes/equal-key distribution, output oracle and timing boundary. Endpoint,
adapter or workload changes invalidate its benchmark evidence. A new comparator
variant cannot inherit the baseline's result. Proof-build timing is not algorithm
runtime evidence. These are consumer-authored contracts and future provider tests,
not a reason to add benchmark policy to the core evaluator or infer performance
readiness from completed correspondence.
