# Realizations, relations, and assessment

Design seed, 2026-11-05. This describes the intended model and the use cases that
should determine its remaining rules. Completion and dependency policies are
still under discussion. The [current implementation](REALIZATIONS_AND_TRANSLATIONS.md)
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

A negative mathematical review can prevent this relation from completing when
its contract requires that review to pass. Which reviewers are required, and how
conflicting or withdrawn judgments are handled, remain policy questions. A review
of exposition should not silently veto unrelated mathematical validation.

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

### 8. Dependencies and alternative proofs

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

## Decisions and invariants

- Replace semantic facets with direct owned content and explicit relation endpoints.
  Role comes from data/provenance, never names such as `lean` or `proof`.
- Retire `Requirement.scope` when selecting statement versus proof content fully
  determines assessment. A proof edit must not invalidate a statement review.
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
- Source provenance, attachment, alignment and validated correspondence are
  distinct. Relations may cross nodes and connect selected groups of realizations;
  neither three-language layouts nor one-to-one translation are imposed.
- Relation tags identify authored strategies and classifications. They do not
  manufacture requirements, evidence, or completion merely by their spelling.

## Decisions to make from these cases

1. What is the smallest contract language for relation completion and requested
   aggregate outcomes? Identify actual needs before choosing fixed combinators,
   extension points, or any programmable predicate API.
2. How do required, negative, conflicting, stale and withdrawn reviews affect a
   contract? Keep the criterion and assessed content explicit.
3. How does an authored `uses` reference select its target and validation needs,
   especially across languages, definitions and alternative proofs?

The first model should support relation kinds, tags, explicit endpoints and validation
requirements. Refine strategy vocabulary, richer alignment conventions and examples
against the real blueprints after that model lands. A complete strategy taxonomy or
specialized mapping language is not a prerequisite for the first model. Mappings and
assumptions that affect a current claim must still be stated explicitly; their later
refinement must not introduce a second authoritative mapping store.

Implementation acceptance must cover universe-polymorphic target matching, exact
witness/target identity, explicit helper coverage in proof reviews, source-content
reassignment, and proof-only versus meaning-changing edits. This document records
no new test results. Graph redesign, new presentation groups, foreign checking
providers, and publication/integration ordering are separate work.
