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
