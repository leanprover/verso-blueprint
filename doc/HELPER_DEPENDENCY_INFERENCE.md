# Helper-aware dependency inference

## LeanArchitect analysis

The reference implementation examined is LeanArchitect
[`819aa8e`](https://github.com/hanwenzhu/LeanArchitect/tree/819aa8e70f3d2800abf0629a29d7c35bfaafd682),
specifically
[`Architect/CollectUsed.lean`](https://github.com/hanwenzhu/LeanArchitect/blob/819aa8e70f3d2800abf0629a29d7c35bfaafd682/Architect/CollectUsed.lean)
and
[`Architect/Output.lean`](https://github.com/hanwenzhu/LeanArchitect/blob/819aa8e70f3d2800abf0629a29d7c35bfaafd682/Architect/Output.lean).
This is a source-level study, not an executed LeanArchitect test run.

`CollectUsed.collect` records visited Lean names before following them. A tagged
declaration other than the root is a terminal dependency. Untagged definitions,
theorems, and opaque declarations expand through their types and bodies.
Inductives expand through their types and constructors; constructor and recursor
types are followed. Axioms are collected as leaves; quotient primitives and
missing declarations terminate without further expansion.

`collectUsed` first walks the root type, then the root value with the visited
set retained. Statement and proof results are made disjoint except for
`sorryAx`. `NodePart.inferUses` subsequently applies explicit additions and
exclusions, maps declarations to labels, and derives `leanOk` from axiom
evidence. For nodes without a proof part, `Node.inferUses` unions the two axes
into the statement. These operations happen when output is produced, not when
the attribute's metadata is registered.

The useful boundary is the first tagged declaration on each path, not arbitrary
transitive closure of the Blueprint graph. Excluding a discovered dependency is
a filter on the result, not an instruction to expand that tagged declaration.

## Blueprint adaptation

| Concern | Verso Blueprint decision |
| --- | --- |
| Activation | `autoDeps := true` enables inference, still disabled by default. Helper expansion is independently enabled by default. |
| Expansion | `set_option verso.blueprint.expandHelpers false` selects direct-only inference; `true` follows all unassociated helpers. |
| Boundary | Stop at any Lean-to-Blueprint association, whether created by an attribute, external-Lean statement, or inline code. |
| Identity | Map each frontier declaration to every associated label; deduplicate and sort labels. |
| Timing | Infer at authoring elaboration using current associations; persist edges across imports. |
| Axes | Walk root type and body separately. A helper's type and body remain on the incoming axis. |
| Precedence | Keep the existing label-level axis suppression, manual additions/exclusions, and strict contribution validation. |
| Status | Do not collect axioms as graph nodes or replace existing status analysis. |
| Recursion | Iterative worklist, per-walk visited names, reserved root, and regular Lean interruption checks. |
| Caching | No persisted frontier cache: later association changes must be observed by later inference. |

The two walks deliberately retain independent visited sets. This preserves the
existing raw per-axis evidence until the authoring adapter applies its
label-level policy, including exclusions and explicit proof-axis declarations.
A shared visited set must not accidentally erase that evidence.

No helper code is evaluated or unfolded using a reducibility policy. Inspection
uses the available compiled expressions, including theorem and opaque bodies.
Unassociated axioms are terminal even if their types mention other declarations.
The root's own type is always analyzed, including for an axiom root.

Helper expansion uses the ordinary Boolean Lean option
`verso.blueprint.expandHelpers`, read once per inferred root. Lean supplies its
validation, command/section/namespace scoping, and document propagation. No
custom syntax, configuration encoding, or persistent environment extension is
needed. Unlike LeanArchitect's unconditional expansion, users may request
direct-only inference; selective helper lists are not supported.

## Regression surface

`BlueprintAutoDeps.HelperProvider` provides helper chains and persisted
attribute contributions across the existing Provider/Reexport module boundary.
`BlueprintAutoDeps.HelperFrontier` exercises all three authoring surfaces,
including attributes depending on sources associated by the other two surfaces.
Its manifest assertions check that the same inferred axes survive placement,
module inclusion, and export.

Coverage includes diamonds, tagged boundaries, opaque helpers, inductive types,
mutually recursive helpers, a 2,048-declaration chain, axiom/missing-name leaves,
multiple labels, manual precedence and exclusions, opt-out, and associations
added between two inference calls. A collector-level test registers a constructor
association through the contribution API; this does not extend the standard
authoring syntax to constructor attachments. Existing direct
dependency, strict-validation, and option-precedence tests remain in force.
`BlueprintAutoDeps.ExpansionPolicy` additionally checks the expanding default,
nested section/namespace scopes, command-local and document-local overrides,
import isolation, independent inference activation, direct-only inductive roots,
and manifest projections for default, disabled, and explicitly enabled expansion
across the three authoring setups.

The end-user contract and migration guidance live in the
[Manual](MANUAL.md#automatic-dependency-inference).
