# Realizations, relations, and assessment

Design seed, 2026-11-05. This describes the intended model and the use cases that
should determine its remaining rules. The assessment rules below specify the
initial contract; richer completion requests remain deferred. The [current implementation](REALIZATIONS_AND_TRANSLATIONS.md)
uses semantic facets; the replacement below is not implemented yet.

## Purpose and objects

Blueprint connects mathematical ideas expressed in different languages and records
what has been established about them. Source code and authored text remain canonical.

| Object | Responsibility |
| --- | --- |
| Node | Stable, globally labeled mathematical home, independent of language or implementation. |
| Realization | Independently addressable statement, proof, definition, or prose account in a language/project context. |
| Source association | Exact content selected for a realization, with its owner and semantic or byte-bound interpretation. Several realizations may reference one canonical declaration. |
| Relation | Explicit claim between realizations, with a kind, selected endpoints, and optional tags identifying strategy or other authored classifications. |
| Validation contract | Requirements for accepting a particular realization or relation. Completion follows this contract, not a node color or naming convention. |
| Evidence | Current observations supporting or rejecting specific requirements: native checks, tests, or reviews with explicit criteria and provenance. |

These are responsibilities, not a commitment to six new record types. Reuse the
existing requirement/evidence machinery and one authoritative collected model.
A proof artifact is distinct from the evidence that it establishes a statement.
A review may assess mathematical correctness, correspondence, or exposition;
those criteria are not interchangeable with one another or with kernel checking.
Mathematical role and representation medium are independent: a prose argument can
be a proof, and a Lean definition can supply either a proposition or its witness.

Relations support open-ended tags alongside their kind. For example, a translation
can be tagged `rocq-faithful` to identify a one-to-one alignment strategy. This
keeps strategy vocabulary extensible without making every strategy a new relation
kind. The tag does not itself establish faithfulness or supply validation evidence.
What is preserved remains explicit in the relation's contract.

## Use cases that determine the rules

### 1. A formal proof of a statement

A Lean proof realization P connects to a Lean statement S through `proves(P, S)`.
For an ordinary theorem, both can refer to the same declaration: its declared type
provides S and its value provides P. Native checking establishes that own-type
connection; it does not establish agreement with prose or an independent specification.
An independently selected target requires actual target matching as well as proof
completeness. Reuse fresh native observations without accepting unrelated edges.

The relation's validation result answers whether this proof establishes this
statement under the declared assumptions and checking requirements.

### 2. Two proofs of one statement

`proves(P1, S)` and `proves(P2, S)` have separate contracts and results. One may be
complete while the other contains an admission. Both facts must remain visible.
Finishing P2, obtaining a suitable proof of S, and finishing both developments are
different requested outcomes. We have not chosen a universal node-completion rule
or a representation for these aggregate requests.

An alternative proof never repairs the native dependency chain of code that still
references an admitted declaration. Mere name differences do not establish that
two proofs use independent methods.

### 3. An informal argument and its review

A Verso argument can be a proof realization for a prose statement. Its contract
might require a mathematical review. The review records a judgment about that
connection; it is not reported as kernel validation. Proofreading the statement
is a different assessment and may be optional.

A negative mathematical review prevents completion when the contract requires
that review to pass. The initial policy names each required reviewer and uses
explicit current judgments, as specified below. A review of exposition should
not silently veto unrelated mathematical validation.

### 4. Source/PDF, Verso, and Lean documents

A paper's statement or argument, its Verso account, and its Lean formalization
are separately addressable content. The PDF is a source container; document-scoped
anchors, citations and page/region locators identify the selected passage without
replacing the Blueprint's global label. A citation alone does not supply assessable
content. OCR or transcription is a derived account, not the original source.

Reviewing PDF-to-Verso faithfulness, Verso-to-Lean correspondence and a Lean proof
answers three different questions. One can succeed while another fails. There may
also be a direct PDF-to-Lean claim; the two intermediate relations do not establish
it automatically. Missing original content stays explicitly unavailable.

The alignment need not be one-to-one: one paper theorem may become several Verso
lemmas and Lean declarations. An account can correct an omission in the paper;
that correction must be explicit rather than silently certified as faithful
reproduction. Three-column display is a consumer view, not a fixed model topology.

### 5. Translation from Rocq to Lean

A translation relates selected source and target realizations under an explicit
interpretation and assumptions. A candidate full-port contract could require valid
target proof, source/target correspondence, and a review of the interpretation.
A checked Lean theorem alone does not satisfy that contract: a negative required
correspondence review can prevent completion despite native proof success.

A statement-only translation can have a different contract from a port of the
proof or proof method. We must describe which content each relation selects and
which validation it requests. Readable Rocq source is not Rocq validation;
unsupported providers remain explicit rather than supplying fabricated success.

Different alignment strategies need distinct contracts:

| Strategy | What the claim must make explicit |
| --- | --- |
| Close port | Corresponding definitions, statements and any requested preservation of proof structure. |
| Change of representation | Source/target encodings, adapters, domain restrictions, assumptions and the behavior to preserve. |
| Independent proof reconstruction | The mathematical statement being preserved; a different proof method or library organization is allowed unless separately constrained. |
| Split or merged development | Which selected source pieces jointly correspond to which target pieces; no implicit all-pairs correspondence. |

These are use cases, not a proposed strategy enum. A strategy label alone is not
a contract. Competing strategies may coexist with different endpoints, mappings
and requirements. A changed mapping or assumption changes the assessed claim,
even when the source and target code are unchanged. Validating one strategy does
not certify another or justify automatic composition of relations.
If a translation specializes or strengthens a statement, specify the intended
direction of implication and domain restrictions; do not call every alignment
an equivalence.

For example, an edge of kind `translation`, tagged `rocq-faithful`, can select a
particular Rocq statement and Lean statement. Its contract states whether the
claimed faithfulness covers the statement, assumptions, proof structure, or some
combination. One-to-one endpoints alone do not establish those properties. Edges
sharing a tag retain their own requirements and validation results.

### 6. A definition and its proved properties

A concept can have a Lean definition, a Rust implementation, and a prose account.
Their correspondence may require an explicit representation mapping and assumptions
about arithmetic or execution. Native validity, tests, and correspondence reviews
establish different facts; a proof about a Lean model alone does not establish
that the Rust implementation matches that model.

Properties such as involutivity are separate statements with proofs. A definition
does not need an invented theorem-proof task. Computational definition bodies
contribute to meaning; a definition of a proposition differs from a definition
containing a proof of that proposition.

### 7. Informal accounts with Lean and Rust attachments

Code placement does not determine a semantic relation. A prose node may have:

| Arrangement | Possible assessed claim |
| --- | --- |
| An illustrative Rust or Lean example | Only the explicitly requested example checks; attachment itself asserts no equivalence. |
| A Rust implementation of an informal specification | Agreement with the selected specification under explicit assumptions, assessed through the requested tests/reviews/checks. |
| Rust code, a Lean model, and Lean proofs | Rust-to-model correspondence, plus separate proofs of properties of the model. |
| Rust produced from a Lean development | Generation provenance and any requested semantic-preservation claim are distinct. |

Lean may formalize the prose independently of Rust, or describe the Rust program;
these arrangements must remain distinguishable. One fragment may participate in
several explicit claims. Tests establish their declared coverage, not universal
correctness. Missing language tooling remains unavailable. Display grouping and
shared node membership never manufacture validation evidence.

### 8. Authored dependencies, observed references, and alternative proofs

An authored dependency can state that an argument relies on a mathematical result.
A Lean-derived reference records that particular code uses a declaration in its
type or body, directly or through a reported dependency path. These are different
assertions, not merely competing priorities for one edge. Preserve their exact
endpoints, roles, source/provenance and scope; both can coexist between the same
displayed concepts. Origin and mathematical intent are separate dimensions.

A display may consolidate those connections, but the consolidation must not erase
their underlying assertions or become validation authority. An author-supplied
`automatic` tag or origin value is not evidence that Lean observed the reference.

Suppose a node labeled `completeness` has a proof C that uses a lemma labeled
`substitution`. Here `completeness` is a mathematical identifier, not a validation
status. A Blueprint `uses` reference currently identifies the target concept.
Resolving that reference to an exact statement, definition, or required validation
needs a stated policy; a label alone does not choose a language or a proof.

Distinguish three facts: C's authored mathematical dependency, the selected target
realization, and the exact Lean declaration referenced by C's code. If the code
uses an admitted `substitution_v1`, a complete `substitution_v2` does not make C
natively complete. Whether a Blueprint-level dependency can be satisfied by the
alternative is still open. Dependencies needed to formulate a statement also
differ from dependencies used only in one proof; proof-local uses must stay local.

### 9. Presenting a theorem gradually

An overview can begin with author-selected key results, then expand a chosen proof
or exposition into steps and finally expose supporting definitions, declarations
and assessments. FIR's conditional-return argument suggests entry conditions, step
matching and terminal extraction as one such explanatory decomposition.

Use node tags such as `key-result` initially; work-triage priority is a different
concept from editorial significance. An `is_part_of` relation can record components
of a particular argument. A component may participate in several arguments, and
alternative proofs can have different decompositions. Membership is distinct from
mathematical dependency and does not by itself specify reading order or completion.

Reader overviews can emphasize authored mathematical dependencies; proof-work views
can emphasize unfinished assessments; native-audit views can expose exact declaration
references and completeness limits. These are projections of the same richer model.
Hiding an inferred dependency from an overview must not remove it from native checks.
Graph-library choice and richer significance/order conventions can follow later.

## Decisions and invariants

- Replace semantic facets with direct owned content and explicit relation endpoints.
  Role comes from data/provenance, never names such as `lean` or `proof`.
- Retire `Requirement.scope` when selecting statement versus proof content fully
  determines assessment. An edit confined to proof content preserves a statement
  binding when selected statement content and interpretation are unchanged.
  Changes to computational meaning may invalidate dependent statement assessments.
- Preserve owner, source selection, content interpretation, and endpoint roles
  together. Moving content between semantic owners changes the assessed object;
  an invisible secondary membership map must not retain the old assessment.
  Native semantic content must not erase byte-bound prose sharing its source file.
- Proof checking and review share an assessment framework with distinct typed
  expectations, criteria, assumptions and outcomes. A passed observation alone is
  insufficient: it must satisfy the exact current obligation.
- Keep source collection and full-batch admission atomic. Persist authored facts,
  not native validation success. Reuse native observations only within the same
  fresh capture and context; source association alone establishes no validation.
- Consumers display derived views. Presentation grouping and graph layout have no
  authority over binding, admission or completion.
- Preserve authored dependency assertions and tool-observed references separately.
  Deduplicated display edges, visibility, and significance never replace their
  semantic provenance or change validation obligations.
- Source provenance, attachment, alignment and validated correspondence are
  distinct. Relations may cross nodes and connect selected groups of realizations;
  neither three-language layouts nor one-to-one translation are imposed.
- Relation tags identify authored strategies and classifications. They do not
  manufacture requirements, evidence, or completion merely by their spelling.

## Normative assessment semantics

### Owned selections and claim identity

Each association preserves its semantic owner, exact source identity, selection,
interpretation and context together. The semantic owner is the realization being
assessed, not an exclusive owner of the source artifact. Sharing a declaration
does not merge associations or transfer evidence. Multiple selections jointly
constitute one assessed object; alternatives are separate realizations. Preserve
order where composition is ordered; normalize only explicitly set-like collections.

Logical address, assessed content and source locator are distinct. Global node
labels are stable; realization/relation keys address current objects without a
cross-revision stability promise. Neither an unchanged key nor a page/range/URL
establishes freshness. Relocation may preserve content when resolution is exact.

A relation owns one unambiguous claim: kind/direction, endpoint identities and
roles, joint interpretation or mapping, assumptions/domain restrictions, and
validation contract. Identical endpoints can support different claims. Grouped
endpoints assert only that joint claim, not pairwise claims or automatic composition.
Authored interpretation text suffices initially and participates in binding. Tags
are classificatory: retagging changes tag-filtered query membership, not the
individual mathematical judgment. A semantic strategy change must edit the claim.

### Assessed content versus completion prerequisites

Requiring another obligation to succeed does not, by itself, include that
obligation's implementation content in the current assessment. Explicit assessed
content and its semantic dependencies determine freshness; validation prerequisites
gate current completion. Keep both in the same authoritative model without
recursively binding a statement review to every prerequisite's proof body.

A correspondence judgment can remain current after its required proof is rewritten,
while replacement with `sorry` makes the combined outcome incomplete. Changes to
the assessed contract, interpretation or selected computational meaning remain
binding-relevant. Local evidence and prerequisite success must be reported separately.

Whole-file byte selections conservatively include every selected byte. PDF reflow
may make a region ambiguous. Preserve the proof-edit guarantee for unchanged exact
statement selections; do not claim fine independence for broader or unresolved
selections. A native semantic selection cannot suppress unrelated prose bytes.

Proof-review coverage identifies actual content: the selected proof, optionally
named helper proofs, and semantic or authored-script/prose interpretation. Helpers'
proof bodies are not implicitly included. A transitive proof-body review needs an
explicit supported selection policy. Fresh native completeness still inspects
required dependencies, even when a human review selected narrower content.

### Mathematical support for `proves`

Built-in `proves(P, S)` requires a mathematical support route for its exact endpoints:
formal target matching and native completeness, or a required mathematical review
of that P-to-S connection. Lint, exposition or testing alone cannot establish it.
Enforce this at contract validation/evaluation, not only in authoring helpers.
An inadequate support contract remains unestablished with an explicit reason;
custom relation kinds report only their declared contract-relative result.

A generated own-type route requires P to select the checked proof value and S its
checked proposition type from the same declaration/context with compatible parameters.
Shared names/files are insufficient; a checked value of type `Nat` is not a proof.
Independent targets require kernel conversion of the complete selected propositions;
logical equivalence requires a checked adapter or another witness. Distinguish a
Prop-valued definition supplying a statement from a proof-valued definition supplying
a witness consistently in selection, fingerprinting and native reporting.

Preserve target universe parameters rigidly, allowing bound-name renaming but not
solving a general target to a concrete universe. Retain the full term-parameter
telescope. Use named wrappers for specialization initially; implicit applications
and typeclass-selected arguments are outside this first interface. Unsupported
matching must diagnose, never silently specialize the claim.

Keep proposition hypotheses, native axioms used, and authored correspondence
assumptions distinct. Expose native assumptions or apply an explicit allowed-
assumptions requirement; a passed check does not mean axiom-free. Reuse native
observations only within the same fresh capture/context and exact compatible
selection. A matching observation for one authored edge cannot certify another.

### Required reviews: initial policy

Each required review specifies the criterion, exact assessed subject/connection,
and symbolic reviewer identity. A requirement named `aliceReview` does not itself
select Alice. Two required reviewers are two conjunctive requirements; quorums and
reviewer-discovery policies are deferred. This is not reviewer authentication.

Each review obligation has one effective current judgment. Selection/supersession
and withdrawal are explicit; source order and timestamps cannot select a winner.
Competing current judgments without an unambiguous effective selection are unresolved.
Withdrawal does not revive a superseded approval. Only current, eligible evidence
matching the assessed binding can discharge the requirement.

| Effective situation | Required-review result |
| --- | --- |
| Required reviewer approves current content/criterion | Can discharge the requirement. |
| Another reviewer approves | Does not discharge this reviewer's requirement. |
| Required reviewer rejects | Unsatisfied; retain the rejection and reason. |
| No judgment, or a judgment is withdrawn | No current approval; withdrawing rejection is not approval. |
| Relevant content/contract changed | Old judgment is stale. |
| Conflicting active judgments | Unresolved until explicitly resolved. |
| Assessment cannot be performed | Unavailable, distinct from rejection. |

Optional reviews do not gate unrelated contracts. Well-formed disagreement is
assessment data, not a reason to reject the entire collected model. Incompatible
payloads for the same immutable evidence identity remain a structural conflict.
A failed requirement does not generally establish that its statement is false.

### Completion results and dependency selection

Version one reports labeled realization/relation assessments under explicit
conjunctive contracts. Absent meaningful contracts remain unassessed; deleting the
last obligation must not create success. Do not publish an unlabeled node-wide
completion Boolean or select a default policy from a realization named `lean`.
Consumer semantics must migrate even while graph layout work is deferred.

Aggregate requests are deferred. Their eventual meaning must distinguish these
cases when `R1 = proves(P1, S)` succeeds and `R2 = proves(P2, S)` is unfinished:

| Requested outcome | Meaning |
| --- | --- |
| Finish P2 | Incomplete. |
| Obtain some acceptable proof of S | Can succeed through R1 if its assurance/assumptions meet the request. |
| Finish both developments | Incomplete. |
| Obtain two independent proofs | Needs an additional independence criterion. |

Any future aggregate result identifies its request, exact target, eligibility policy,
and satisfying relation identities. Empty candidates report no candidates, not
vacuous success. Reviewed and kernel-checked support count together only if the
request explicitly permits both; unfinished alternatives remain visible.

Use exact dependency targets where possible. A label shorthand needs an explicit
deterministic resolution rule; diagnose ambiguity instead of choosing the candidate
that happens to be complete. Selecting an alternative proof never rewrites native
code dependencies. Keep proof-local uses local. Definitions needed to interpret a
statement contribute to its content dependencies. Semantic cycles such as mutual
definitions differ from validation cycles, which cannot bootstrap their own success.

### Source resolution and admission

A selector resolves the intended current content or reports missing, unsupported
or ambiguous selection. Never substitute a nearby passage or an OCR account for
the original. Conservative binding to a larger region/container plus selector is
allowed when documented; unchanged locators do not establish unchanged content.

Structural identity conflicts reject the candidate batch atomically. Unavailable
content instead leaves the affected assessment unavailable: a missing PDF does
not erase an unrelated native proof from the same admitted snapshot. Negative
judgments, unavailable observations and malformed records remain distinguishable.

## Acceptance and bounded follow-up

These are implementation targets, not newly executed results:

| Control | Required distinction |
| --- | --- |
| One declaration supplies S and P | Separate owned selections, shared canonical source. |
| Proof-only rewrite or proof prerequisite becomes `sorry` | Statement judgment can stay current; native and combined completion respond. |
| Imported computational meaning changes | Dependent statement binding responds despite unchanged local text. |
| Helper proof changes | Only explicitly covered reviews stale; native dependency checks remain fresh. |
| Native content and prose share a file; content moves between owners | Preserve byte selection and owner relationships despite equal flattened inventories. |
| Polymorphic witness/target and concrete specialization | Rigid target universes and full telescope; explicit specialization only. |
| Wrong target, missing hypothesis, or non-proposition witness | No borrowed proof support. |
| Alice required, Bob approves; withdrawal; conflicting judgments | Enforce reviewer and effective-current policy without global admission failure. |
| Mapping/assumptions change with unchanged code | Correspondence evidence stales; mere retagging is not a mathematical change. |
| PDF absent or selector ambiguous, transcription available | No substitution; unrelated assessments remain available. |
| Empty contract or future empty aggregate | No accidental completion. |

The detailed record/API shape for current-review selection and dependency shorthand
resolution must implement these rules; it must not introduce timestamp arbitration,
a second evidence store, or completion-dependent target selection.

The first model should support relation kinds, tags, explicit endpoints and validation
requirements. Refine strategy vocabulary, richer alignment conventions and examples
against the real blueprints after that model lands. A complete strategy taxonomy or
specialized mapping language is not a prerequisite for the first model. Mappings and
assumptions that affect a current claim must still be stated explicitly; their later
refinement must not introduce a second authoritative mapping store.

Graph redesign, richer presentation groups, foreign checking providers, arbitrary
completion predicates, review quorums, and publication/integration ordering remain
separate work. Binding laws concern the actual normalized representation; general
hash injectivity and provider authenticity are not claimed.
