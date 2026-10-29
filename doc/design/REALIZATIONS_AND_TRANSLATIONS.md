# Realizations and translations

## Current model

Blueprint uses one model for concepts represented in different languages. A node
has a stable label and shared metadata. It can have multiple named realizations,
each in a language and logical project context. A translation is an explicit,
directed relation between selected realizations; it is not inferred from shared
labels or declarations.

For example:

```text
node: toggle_involutive
  realization verso:
    statement: authored Verso prose
  realization rocq-original:
    statement/proof: authored Rocq source reference
  realization lean:
    statement/proof: checked Lean declaration
translation versoToLean:
  claim: relate the prose statement to the Lean theorem
translation rocqToLean:
  claim: relate the Rocq development to the Lean theorem
```

This layout permits one node to have several representations without treating
them as one source or proof. In the current example the Lean proof can be
complete while prose proofreading is unassessed and Rocq correspondence is
blocked because Rocq resolution is unsupported.

## Concepts, realizations, and translations

### Node and realization

A node identifies the mathematical concept, not a particular file or language.
Its label, kind, grouping, and shared metadata belong to the node. The node label
is the stable global identifier within a Blueprint, independent of the language
or current implementation; agents and external cross-references should anchor to it.

Realization keys are scoped to a node and identify its current representations.
They have no cross-revision stability promise. A representation can be replaced
without renaming the mathematical node. Within a capture its key must still be
unambiguous: authored translations must resolve their current endpoints, and
validation must match the current bindings. Reusing a name does not make old
evidence valid for a replacement. This does not introduce historical identities,
redirects, or a second identifier store.

A realization has a name, a source-language/project context, facets, documents,
and declaration associations. Two Lean implementations of the same concept are
different realizations. A declaration can support more than one node or facet;
its native check should be represented once and referenced where needed.

Statement and proof are common facet names, not global node fields. Each facet
selects documents and declarations relevant to that part of the realization.
Definitions may use a different set of facets. A source or markup payload is
stored at its named realization/facet destination. A rendered page, highlighted
snippet, or hover preview is only a view of that source.

Independent Verso prose can be a realization. A markup format or document slot
is not automatically a new realization: use a separate realization when it is
an independent account or port. Source provenance, such as a paper citation or
page span, remains distinct from the source of a realization.

### Translation and claim

A translation is a named, directed, project-level record with one or more source
and target endpoints. Endpoints may belong to the same node or different nodes,
so a translation may describe a split or merged formalization. A target
realization may be the source of a later translation.

A translation can contain named claims. Each claim states the correspondence
being asserted and selects the facets and assumptions relevant to it. A
translation's endpoints do not imply that every source/target pair corresponds.
A shared node or declaration does not establish equivalence, and two
translations do not compose automatically.

Translation links are separate from mathematical `uses` dependencies. An
external mathematical result may be a prerequisite of a correspondence claim,
but its proof does not discharge that claim's own requirement. The claim-local
requirement must be assessed against the claim.

## Requirements and completion

A requirement has a typed subject, an expected validation kind, and optional
prerequisites. Subjects include realizations, facets, declarations,
translations, and claims. Validation kinds include native checks, proofs of an
independently specified proposition, human reviews, and named executable
checks. Requirements compose conjunctively. Put alternatives in separate
realizations instead of letting one successful alternative silently satisfy
another realization.

### Native Lean results

Canonical capture performs fresh checks against the owning Lean environment.
It reports a declaration's own native statement and body completeness separately
from its explicit Blueprint requirements and dependencies.

A theorem's native proof check establishes that its checked body is complete
under the supported Lean completeness analysis. It does not establish
correspondence with prose or prove an independently authored expected
proposition. Definitions include their values in the native statement-side
check. Admitted, unavailable, hidden, open, or otherwise unverified source
remains unfinished or unavailable; it is never converted into a passing result.

Ordinary Blueprint dependency selection reuses the target declaration's existing
native proof requirement. It does not create a duplicate specification or
overwrite the local native result. Thus a theorem can have a complete local
proof while its selected prerequisite is unfinished. The report shows both
facts and identifies unresolved edges.

Automatic statement/proof prerequisite wiring applies only to the native
contracts generated by ordinary capture, identified by their producer identity,
exact subject and native validator. An authored alternative can name a review
`proof` or `proofReview` without acquiring implicit sibling requirements. Authored
checks likewise retain their explicit prerequisite lists, even when they use a
native validator; a conventional name is not an enrollment mechanism.

### Independent expected propositions

A project may author a separate proposition and associate it with a checked
witness. The expected proposition must be an owned, checked Lean definition of
a closed proposition, with no admission or unverified dependency. The native
provider elaborates it, checks it with Lean's kernel, compares the witness's
actual type by definitional equality, and checks completeness. The provider
records a structural fingerprint of the independently checked proposition as
its descriptor. Fingerprint equality is not the equality test and is never a
substitute for Lean's definitional-equality and kernel checks.

A docstring or other prose body does not create this requirement. If no
independent expectation or review requirement is authored, prose assessment is
optional and reported as unassessed. Native proof completion remains visible
separately.

### Reviews, evidence, and supplied observations

Evidence is selected by exact subject, requirement, and current content binding.
A passed observation for another claim, witness, context, or input is
unsuitable. Missing and unavailable observations remain explicit; they do not
become success.

The pure `Validation` and `Translations` APIs validate model structure,
requirement relationships, bindings, and whether supplied observations fit
requirements. They do not authenticate who supplied an observation and do not
run Lean or a human review. A caller that fabricates a passed observation can
therefore satisfy a pure model if it also supplies a matching current binding.
Use `Realizations.Capture.capture` for the ordinary Lean provider path, which
runs the native checks against the current build inputs. Foreign checkers will
need their own trusted provider boundary before their observations can be
treated as checked.

No total project-readiness claim is implied by a report. It evaluates the
requirements represented in the supplied admitted model; it does not discover
omitted obligations or infer an unrecorded correspondence.

## Canonical source layout and authoring

### Ordinary Blueprint sources

`Informal.Data.Node` stores three keyed inventories:

- `sources`: typed source payloads with realization/facet destination,
  language/project context, document identity, and source location;
- `uses`: dependencies retaining facet, optional realization scope, origin,
  and intent;
- `nativeAssociations`: typed Lean declaration associations retaining their
  destination, context, facets, and declaration snapshot.

The fixed statement/proof body and external-reference fields are gone. The
presentation helpers `proseView`, `usesOn`, and `nativeRefsOn` derive views
from these inventories; they are not semantic storage. Custom producers must
write the keyed records, not update a derived view.

Existing Blueprint attributes, directives, inline code, and attached markup
enroll through the ordinary environment registration path. They do not require
a separate opt-in registration mode. Source identity does require a configured
logical project, using `set_option verso.blueprint.project` or the package's
weak Lake option. The selected project is stored with the owning source; a later
query module cannot relabel it.

### Explicit authored contracts

Use `Informal.Realizations.Authoring` for independently authored realization,
translation, claim, requirement, or expected-proposition records. Configure the
exact module that calls this API:

```lean
import VersoBlueprint
run_cmd liftCoreM <| Informal.Realizations.Authoring.configureProject `MyProject
```

`configureProject` sets the source project for that module; it does not
configure importers and is not needed as a separate switch for ordinary
attributes or directives. `Authoring.stage id batch` retains one identified
authored batch. `Authoring.expectNative id label expectedDefinition` records
an independently written proposition definition for a label. That definition
is checked when the owning modules have been built and capture runs.

Authored batches and ordinary registrations use the existing Blueprint
environment extension and import/assembly boundary. They do not create a second
authoritative store. The complete local and imported input is checked before
capture publishes an admitted registry. Conflicting producer identities,
destinations, or contracts reject the complete candidate; no partial registry
is returned. Imported authoring records carry source claims only: they do not
persist completion, validation observations, or proof evidence.

## Capture, graph, and query

Run capture only after the modules that own the Blueprint source and Lean
declarations have been built. `Realizations.Capture.capture` collects the
ordinary keyed registrations and explicit authoring records, plans the native
checks, runs the current Lean provider, admits the complete model, and binds
fresh observations to that model. If structural admission fails, the caller
gets diagnostics and no partial snapshot. Public node labels and dependency targets
must round-trip through Lean name JSON and have unambiguous readable CLI spellings;
parent groups are checked in their own namespace. Pure registries retain arbitrary
typed names, while ordinary capture rejects unsupported or ambiguous public labels.

`Snapshot.assessmentFor` is the shared projection used by graph, summary,
heading, manifest, and CLI consumers. The status query distinguishes:

- `nativeStatementComplete`: own native statement-side checks;
- `nativeProofComplete`: own native body-completeness checks;
- `requiredComplete`: the default Lean realization's explicit requirements and
  their prerequisite closure;
- `statementDependenciesComplete` and `proofDependenciesComplete`: selected
  dependency edges for the two facets of the default Lean realization;
- `details`: assessed subjects, requirements, observations, diagnostics, and
  unresolved selected edges.

The `sourceDeclarationSnapshots` field is display inventory, not validation
evidence. A preview without capture reports validation as unavailable rather
than deriving completion from snapshots. Graph colors summarize status; clients
that need exact contract outcomes should read the assessment and its details.

For agents and local inspection:

```sh
lake exe vbp query status <label>
```

Build the current owning sources before relying on the result. A generated
capture describes the build from which it was produced; the query does not
recheck source files.

## Freshness and trust boundary

Content bindings are versioned SHA-256 Merkle fingerprints. Native semantic
fingerprints cover the checked declaration shape, types, available bodies, and
transitive dependencies, so a changed imported definition or type invalidates
dependent evidence even when local source bytes are unchanged. Missing or hidden
bodies fail closed. Authored source documents bind their current bytes, and
changes to a witness, expected goal, endpoint, assumption, interpretation,
selected requirement, provider, or compiler identity invalidate the connected
binding.

Expression fingerprints preserve semantic constructor data and sharing without
including allocation addresses. Expression metadata is ignored because it is
definitionally irrelevant; original source bytes are bound separately. Merkle
memoization is scoped to one capture. Native checks are rerun on every capture;
there is no persisted proof-success cache or historical receipt store.

Freshness relies on SHA-256 collision resistance. Fingerprints are not proof
certificates, do not authenticate provider observations, and do not replace
Lean's kernel or definitional-equality checks.

## Current language and migration limits

The data model can describe multiple languages, but native source resolution and
proof checking are currently provided for Lean. Authored Rocq references can be
retained and reported as unsupported or unresolved; readable source/config
bytes do not establish Rocq proof validity. Rust blocks do not currently
establish proof or correspondence completion. No cross-language symbol mapping
or correspondence is inferred.

The canonical migration removes the old fixed node slots and their completion
fallbacks. Downstream APIs and graph payloads should consume keyed sources and
the captured assessment. The current graph data uses schema version 4. Rebuild
generated sites and update clients that previously read the old node fields or
reconstructed completion from declaration snapshots.

The focused test fixtures cover independent Verso/Lean/Rocq realizations,
native proof versus optional prose assessment, explicit correspondences,
dependency selection, atomic source/import rejection, semantic binding freshness,
and Merkle cycles/sharing. These exercise the supported paths; they do not
certify foreign-language checking or a general project-readiness analysis.

## Consumer pilot contracts and pending extensions

The Rocq-to-Lean pilot motivates the following contracts. These specify the
intended boundaries before choosing additional schemas or UI. They do not adopt
the pilot's receipt adapters, requirement-query patch, or its validation claims
as production Blueprint behavior.

### Document identity and relocation

Today `DocumentKey` contains a language/project context and a path. That entire
key participates in bindings. Relocating a selected path therefore invalidates
old evidence even with identical source bytes. This means the evidence no longer
matches the current binding; it does not establish a semantic regression.

The intended extension separates a project/package-scoped logical source identity
from its filesystem locator. Moving only the checkout root should preserve
correspondence acceptance when logical identities, bytes, semantic dependencies,
contracts and provider/compiler identities are unchanged. A renamed or replaced
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
