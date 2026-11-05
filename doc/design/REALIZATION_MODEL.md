# Realizations, relations, and assessment

Design basis, updated 2026-11-06. Version one is a document compiler producing an immutable
assessment snapshot. Its replacement data model is not implemented yet; see the
[current implementation](REALIZATIONS_AND_TRANSLATIONS.md). Examples and planned
regressions below are not claims of newly executed validation.

## 1. Version-one contract

Given the current authored blueprint, its selected sources, and observations from
the current checking environment, produce a self-consistent snapshot of claims,
assessments and their reasons. Preserve the existing `plan → observe → evaluate`
boundary. The semantic core evaluates supplied observations; production capture
obtains them freshly. This distinction does not authenticate arbitrary supplied facts.

| Information | Authority and lifetime |
| --- | --- |
| Authored facts | Source-canonical nodes, realizations, selections, relation claims, contracts and explicit current-review selections. |
| Current observations | Source resolution, native checks, target matching and availability from this capture/context. |
| Derived assessments | Bindings, evidence eligibility, local results and prerequisite completion, computed from those inputs. |
| Indexes and consumers | Derived lookup maps, reports and presentation views of the immutable snapshot. |

Raw contributions, resolved records and indexes are legitimate representations.
They must be derived through one construction boundary, not independently writable
semantic authorities. Preserve atomic collection/admission, Lean/Lake incrementality
and safe capture-local memoization. Persist authored facts, not native validation
success. Make assessment reproducible from the same
captured input; measure before adding caching or a new incremental engine.

### Objects and supported content

| Object | Responsibility |
| --- | --- |
| Node | Stable globally labeled mathematical home, independent of language or implementation. |
| Realization | Independently addressable statement, proof or definition/account in a language/project context. |
| Source association | Exact semantic owner, source identity, selection, interpretation and context together. Shared source does not merge owners. |
| Relation | An independently keyed claim with kind/direction, exact endpoint roles, joint interpretation/mapping, assumptions/domain restrictions, contract and optional classificatory tags. |
| Validation contract | Explicit requirements for accepting a realization or relation. |
| Evidence | Supplied observations about a requirement's selected content. A proof artifact is not evidence that it establishes a statement. |

These are responsibilities, not a demand for one new record per row. Use typed
records/references; do not force source associations, mathematical claims
and validation prerequisites into one generic edge type. Role and medium differ:
Verso can contain a proof; a Lean `def` can define a proposition or contain its witness.
Role comes from explicit data/interpretation, never a name such as `lean` or `proof`.
Realization/relation keys address current objects without a cross-revision stability
promise. Source locators and unchanged keys are not content freshness.

Support exact native declaration selections and well-defined authored text selections.
Lean statement meaning includes relevant computational definitions; selected proof
implementation includes its own body and explicitly selected helpers. Authored text
is byte-bound. Other sources use documented conservative selection or report unsupported/
unavailable; there is no universal selection language. Semantic content and byte text
sharing a file remain independently selected. Retire semantic facets and
`Requirement.scope` once explicit selections carry their responsibilities.

### Assessment rules

1. **Owned content.** Multiple selections jointly constitute one assessed object;
   alternatives are separate realizations. Preserve ordered composition; canonicalize
   only set-like membership. Source reassignment cannot hide in a secondary map.
2. **Local bindings.** Bind each judgment to its own subject, selected content and
   interpretation, criterion, reviewer, coverage and validation conditions. A relation
   judgment also binds its exact mathematical claim: endpoints, mapping and assumptions.
   Changing Bob's sibling obligation to Carol's leaves Alice's unchanged judgment current.
3. **Prerequisites are gates.** Requiring another obligation does not implicitly select
   its proof body. Proof-only edits preserve a statement judgment when its selected
   content/interpretation is unchanged; `sorry` can still break dependent completion.
   Explicitly selected proof content remains bound regardless of the criterion's name.
4. **No circular binding.** Evidence records, current-review selections, lifecycle state,
   prerequisite outcomes and completion results do not enter assessed-content bindings.
   Recording or withdrawing an approval changes eligibility, not its assessed binding.
5. **Joint claims.** Grouped endpoints assert one interpreted claim, not all pairwise
   claims or automatic composition. Claim meaning is explicit even if initially textual.
   Tags such as `rocq-faithful` classify; they do not generate evidence or validation
   policy. Retagging may change a query's membership without staling mathematical evidence.
6. **Meaningful support.** Built-in `proves(P,S)` needs exact formal target matching
   and native completeness, or required mathematical review of that connection.
   Lint/testing alone cannot supply it. Enforce this in evaluation, not just constructors;
   inadequate support remains unestablished with a reason. Custom kinds report only
   contract-relative success. Every other required condition still applies: native
   success cannot override a required rejection or vice versa.
7. **Exact resolution.** Resolve the selected source or report missing, unsupported or
   ambiguous selection; never substitute another passage. Broad byte selections can
   invalidate conservatively. Structural identity conflicts reject the batch; unavailable
   material and legitimate negative judgments do not erase unrelated assessments.
8. **Explicit dependencies.** Preserve authored mathematical uses and observed native
   references, source role and local/shared scope. Select exact targets, or diagnose
   ambiguity under a documented deterministic shorthand. Completion must not choose the
   target. Alternative proofs never repair the native closure of code using an admission.
9. **Derived views.** Publish labeled realization/relation results, local evidence and
   prerequisite reasons. No universal node-completion Boolean or hidden `lean`-name
   policy. Graph filtering, significance and display grouping cannot alter validation.

### Native support boundary

Generated own-type support selects a declaration's checked proof value and its
checked proposition type in the same compatible context/parameter interpretation.
A well-typed `Nat` value is not a proof. Independent support requires kernel
conversion of the complete selected propositions; logical equivalence needs a
checked adapter. Target universes stay rigid under bound-name renaming; retain the
full term telescope and use named wrappers for specialization. Unsupported matching
must diagnose instead of silently instantiating away a general target.
Distinguish proposition definitions from proof-valued definitions consistently in
selection, fingerprints and native reporting, not by declaration command spelling.

Keep formal hypotheses, used native axioms and authored correspondence assumptions
separate. Expose native assumptions or enforce an explicit allowed-assumptions
requirement; a passed observation is not an axiom-free claim. Capture-local native
facts may be shared after checking applicability to each receiving edge and binding
its evidence locally. Bound evidence/completed results cannot be copied between edges.
A proof review includes only its declared bodies/scripts/prose/helpers; fresh native
completeness independently inspects required dependencies.

### Reviews are explicitly selected current authored state

A required-review slot specifies the reviewer and criterion. Its source explicitly
selects one current judgment identifier, or none. Competing effective selections
are unresolved. Multiple required reviewers are separate conjunctive requirements.
These are symbolic authored identities, not an authentication service.

Resolve that selection first, then check the selected judgment's reviewer, criterion,
exact subject, binding, coverage and approval outcome. A missing, stale, rejected,
unavailable or unsuitable selection supplies no approval; never search older records
for one that fits. Withdrawal selects none; supersession selects a replacement.
Neither operation resurrects an unselected judgment. Older judgments may remain as
unselected records or only in Git history. No lifecycle traversal engine, event log,
timestamp arbitration, reviewer discovery or quorum mechanism is needed.

Required-review rejection prevents completion; optional exposition rejection does not
veto unrelated mathematical obligations. Conflicting payloads for one immutable
evidence identity are structural errors, unlike well-formed disagreement. Failure
of an assessment does not generally establish mathematical falsity. A build must
never silently renew a stale human judgment.

### Conjunctive completion and reference semantics

Compute local results from current eligible evidence. Starting with no completed
requirements, add a locally successful requirement when all its prerequisites are
complete; continue to a fixed point. This gives a reference meaning, not a mandate
for an inefficient implementation or replacement of the existing graph algorithm.
Two positive local judgments in a prerequisite cycle cannot bootstrap completion.
The local judgments remain visible even when final completion fails. Such cycles
differ from legitimate semantic cycles, for example in mutually defined source.

A realization/relation completes only under a meaningful declared contract, its
kind's applicable minimum support, and all required obligations with finite
prerequisite justification. Missing contracts remain unassessed. Deleting the last
obligation cannot manufacture success. Aggregate requests are outside version one.

## 2. Examples and counterexamples

### First end-to-end milestone

Use the real authoring/import, capture, evaluation and report path:

- One Lean declaration supplies statement S and proof P; prose supplies statement T.
- `proves(P,S)` requires native mathematical support.
- Correspondence between T and S requires Alice's mathematical review and, for this
  example's contract, successful completion of `proves(P,S)`.
- The report shows Alice's local review and the proof prerequisite separately.

| Source change | Required result |
| --- | --- |
| Rewrite P without changing selected statement meaning | Alice's judgment remains current; native checking uses the current capture. |
| Replace P with `sorry` | Local review can remain current; proof and dependent completion become unfinished. |
| Change S or the correspondence mapping | The old judgment is stale. |
| Withdraw Alice's selected approval | No approval; no fallback to an older matching record. |
| Add an unfinished alternative proof | Keep individual results; invent no node-wide completion rule. |

The implementation owner makes this path work. Verification connects the production
selection/binding interfaces, original suitable evidence and finite prerequisite
justification to their laws. Keep obligations in production, not assumptions about
an ideal model. Additional abstractions must simplify this example or enable the
next concrete case. This milestone is a planned test, not completed validation.
Record resource cost under a bounded run, separating normal build/setup from capture.
Immutable snapshots simplify authority; they do not by themselves ensure scalability.

### Use-case catalog

The wider cases guide the model; they do not activate every provider or workflow
for the first milestone. Unknown providers remain explicit and non-certifying.

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
different requested outcomes. Version one has no universal node-completion rule;
aggregate requests are deferred.

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
explicit current judgments, as specified above. A review of exposition should
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
natively complete. Version one does not automatically substitute a different proof
for an exact selected prerequisite; aggregate alternative-proof requests are deferred.
Dependencies needed to formulate a statement also differ from dependencies used only
in one proof; proof-local uses must stay local.

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

### Regression controls

The following are implementation targets, not newly executed results. Extend the
first milestone with these controls as the corresponding supported path is connected.

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
| Change only a sibling review's required reviewer | Preserve unchanged local judgments; recompute the containing conjunction. |
| Record/select an approval, then withdraw it | Binding stays unchanged; eligibility and completion change. |
| Rewrite P as a prerequisite only versus explicitly selected proof content | Only the latter edit changes the otherwise unchanged judgment's binding. |
| J2 supersedes J1, then J2 becomes stale while J1 matches | No resurrection of J1; a withdrawn effective successor likewise supplies no approval. |
| Competing approval/rejection successors in either input order | Unresolved without explicit selection; ordering never arbitrates. |
| Native support passes, but another required review rejects (and conversely) | No bypass of conjunction or implicit downgrade of the contract. |
| One compatible native fact supports two edges | Recheck applicability and bind evidence separately for each edge. |
| A and B pass locally but require each other | Preserve local results; prohibit circular final completion. |

## 3. Deferred extensions

Version one does not include arbitrary completion predicates, automatic discovery
of acceptable alternative proofs, or automatic composition of correspondence.
Future aggregate requests must identify exact targets, eligibility/assumption policy
and satisfying relation IDs. “Finish P2,” “obtain a suitable proof of S,” and “finish
both developments” differ; two independent proofs additionally need an independence
criterion. Empty requests must not become vacuous success.

Defer review history/authentication services, quorums, implicit term applications,
a general source-selection or alignment DSL, transitive proof-body review policy,
new foreign checking providers, graph-library replacement and richer significance/
ordering conventions. Strategy tags and explicit claim interpretations suffice to
start; refine them against real blueprints. Publication/#499 ordering and source-
ownership repairs remain separate work, not consequences of this document.

A durable multi-project catalog or independently edited review service could later
justify storage infrastructure. Any such backend belongs behind the snapshot
boundary and must not become a second assessment interpreter. Yesterday's stored
native result does not certify today's capture. No SQL engine, generic incremental
database or rule framework is part of the first implementation.

The useful precedents are the input/derived-model boundary in
[rust-analyzer](https://rust-analyzer.github.io/book/contributing/architecture.html)
and the distinction between rebuilding and scheduling in
[Build Systems à la Carte](https://blogs.ncl.ac.uk/andreymokhov/build-systems-a-la-carte/).
They motivate boundaries, not adoption of their machinery. SQLite's documented
[application storage and querying uses](https://www.sqlite.org/whentouse.html)
are relevant only if a future storage workload calls for them. General hash
injectivity and provider authenticity remain outside the proof claims.
