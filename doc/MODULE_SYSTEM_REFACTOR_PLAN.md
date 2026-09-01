# Lean Module-System Refactor Plan

Last reviewed: 2026-08-30

This document is the execution plan and verification contract for converting
the `VersoBlueprint` library to Lean's module system. The repository roadmap
links here instead of duplicating the milestones.

## Decision and Scope

The refactor will convert the complete production library under `src/` to the
module system and will define an intentional public authoring and generator
API. It is an API-boundary and incremental-build refactor, not a generation
performance optimization.

The final cutover assumes that `verso-slides` has migrated to the module system.
Slides remain in scope throughout the refactor: no intermediate or final step
may remove their genre dispatch, renderers, assets, or tests merely to make a
module boundary compile.

In scope:

- all Lean sources under `src/`
- the public `VersoBlueprint` authoring root
- generator-facing APIs used by `vbp` and Blueprint projects
- Slides integration
- phase separation between shared data, authoring elaborators, and runtime
  traversal/rendering
- module-only consumer tests and existing non-module downstream consumers
- deterministic incremental-rebuild checks
- affected maintainer and architecture documentation

Out of scope:

- migrating `verso-slides` itself
- changing Blueprint's data model or rendering semantics for unrelated reasons
- preserving accidental access to current private implementation details
- a compatibility layer for obsolete VBP imports or declarations
- the experimental synthetic runtime artifact from the profiling work
- claiming a warm-generation speedup from module headers

## Starting Point

At the time this plan was written:

- `src/` contains 93 Lean files;
- only `VersoBlueprint.Profiling` uses `module`;
- the package already enables `experimental.module`;
- the `VersoBlueprint` library already has `precompileModules := true`;
- `VersoManual` is a module-system dependency;
- `VersoBlueprint.lean` remains a broad non-module facade;
- existing Blueprint projects and most repository tests are non-module
  consumers.

Recheck the source counts rather than updating them by hand:

```bash
find src -name '*.lean' -type f | wc -l
rg -l '^module[[:blank:]]*$' src -g '*.lean' | wc -l
```

The profiling-tree prototype is evidence, not a patch source. It established
that the core library can compile after a broad conversion, and it identified
phase-mixed areas. It did not establish a safe public API or a complete package
conversion: it widened private APIs, duplicated phase-shared data, removed
Slides behavior, and leaked imports that caused downstream name ambiguities.

## Target Boundaries

Production modules should fall into three roles. A source file may implement
more than one role only when the dependency graph shows that splitting it would
not improve phase or public boundaries.

| Role | Contents | Import policy |
| --- | --- | --- |
| Shared data | Data types, configuration, quotations, JSON formats, persistent extension keys, and pure operations genuinely needed in both phases | Import normally and with `meta` only where both phases require it |
| Authoring | Roles, directives, attributes, command expanders, argument parsing, and elaboration diagnostics | Keep in the compile-time closure; do not pull runtime rendering into public meta imports |
| Runtime | Traversal, extension descriptors, HTML/TeX rendering, preview assembly, assets, and generator orchestration | Keep out of the authoring meta closure unless generated code actually refers to it |

The public roots are expected to be:

- `VersoBlueprint`: the normal Blueprint authoring surface;
- `VersoBlueprint.PreviewManifest` and the existing generator entry points:
  the generator/runtime surface used by Blueprint projects and `vbp`;
- `VersoBlueprint.Slides`: the Slides integration surface.

Do not add a new umbrella such as `VersoBlueprint.Runtime` unless a concrete
consumer requires a boundary that the existing generator entry points cannot
express. The source imports, not a parallel API manifest, remain the source of
truth for the public import graph.

## Module Naming and Setup

Name internal modules by feature owner first and responsibility second. Keep
the existing feature module as the authoring facade when it is a useful public
entry point; split only when a dependency or phase boundary requires it.

| Name | Intended responsibility |
| --- | --- |
| `VersoBlueprint.<Feature>` | Public feature facade and authoring syntax |
| `<Feature>.Data` or `<Feature>.Model` | Phase-neutral serialized data or feature-domain model |
| `<Feature>.Config` | Phase-neutral configuration and parsing policy |
| `<Feature>.Render` | HTML/TeX rendering implementation |
| `<Feature>.Traversal` or `<Feature>.Store` | Traversal behavior or persistent state owned by the feature |
| `<Feature>.Assets` or `<Feature>.Cli` | Asset declarations or command-line orchestration |
| `VersoBlueprint.Lib.<Name>` | Small feature-independent utility with more than one natural owner |

Prefer a precise responsibility such as `Render`, `Traversal`, or `Store` over
`Runtime`. Do not introduce a facade, umbrella, or `Lib` module without a
concrete consumer. This table is a naming convention, not a requirement that
every feature acquire every suffix.

Set up each production source with the smallest deliberate boundary:

1. Start with `module`, followed by `public import` only for dependencies that
   exported declarations expose or intentionally re-export.
2. Use plain `import` for implementation-only dependencies and `meta import`
   for elaborator-only dependencies. Use `import all` only for a narrow,
   documented intra-package need; it is not a substitute for a public API.
3. Put the intended external API in a `public section`; keep normalization,
   constructors, proofs, and other representation helpers `private`.
4. A phase-neutral module is defined once. A consumer that executes its API at
   both phases imports that same module normally and with `meta import`.
5. Re-export through one of the consumer-oriented roots only when that root's
   contract needs the declaration. The import graph remains the only module
   manifest; do not add a generator or parallel taxonomy.

## Design Rules

These rules are acceptance conditions, not suggestions:

1. Preserve every supported Manual and Slides feature during every landable
   slice.
2. Keep representation invariants private. In particular, do not expose a
   private constructor or normalization function to repair a module error.
   Prefer a same-module operation, a public smart constructor, or narrowly
   scoped intra-package `import all`.
3. Do not duplicate values into authoring and runtime variants merely to cross
   phases. Extract the phase-neutral value into one shared module.
4. Start a conversion with temporarily broad imports only inside a short-lived
   local step. A reviewed commit must use deliberate `public`, private, `meta`,
   and `all` imports.
5. Do not enable `backward.privateInPublic` or `allowNonModules` as the final
   design.
6. Use `@[expose]` only when definitional reduction is part of the intentional
   external API, never as a generic compilation fix.
7. Keep `precompileModules := true`; its existing runtime benefit is independent
   of this refactor.
8. Treat output identity and extension registration as semantic invariants.
9. Keep legacy downstream projects working through intentional public APIs,
   while making no promise for accidental private access.

## Phase-Mixed Areas to Resolve

The old experiment supplies a useful initial audit list, but each decision must
be re-derived against the current source. Several areas, especially informal
blocks, have already acquired better internal boundaries since that experiment.

| Current area | Boundary to establish | Required proof |
| --- | --- | --- |
| `Cite` | Separate citation data/persistent state, traversal/rendering, and role elaborators | Citations, citation previews, and bibliography output remain identical |
| `Commands.Bibliography` | Keep the part elaborator out of reusable bibliography render/data code | The module authoring fixture can use the command without importing renderer internals at meta phase |
| `Commands.Graph` | Separate command configuration/elaboration from graph block runtime rendering | Graph variants and preview controls pass existing Lean and browser tests |
| `ExternalDeclRender` | Isolate phase-neutral result/configuration types from MetaM rendering implementation where needed | Private marker parsing and rendering helpers remain private |
| `Informal.Block` | Reuse the current `Model`, `Config`, `Render`, `Store`, and `Traversal` boundaries; audit the remaining main module rather than creating another catch-all runtime file | Statement/proof authoring, traversal indexes, numbering, and rendering all pass |
| `Informal.Code` | Separate quoteable/shared code data and extension runtime from authoring syntax | Inline code, folding, dependency inference, and hover output pass |
| `Informal.RustBlock` | Separate shared/runtime extension data from directive expansion | Rust panels and code rendering pass |
| `Informal.Uses` | Separate use metadata/runtime rendering from authoring roles | Statement/proof dependency intent and relation panels pass |
| `Math` and `Macros` | Put data and the TeX-prelude value needed in both phases in one shared owner | No authoring/runtime duplicate of the prelude table is introduced |
| `Graft` | Separate genre detection/elaboration from Manual and Slides render paths without dropping either genre | Manual and Slides graft fixtures both pass |

This table is not exhaustive. The compiler and the public-import review may
identify additional mixed modules, including preview and generator roots.

## Progress Ledger

Use `pending`, `in progress`, or `complete`. A milestone is `complete` only
when its gate below has passed; replace `—` with a durable commit, CI run, or
local evidence report when updating the state.

| Milestone | State | Evidence |
| --- | --- | --- |
| M0 — behavioral and API contract | complete | Local M0 validation matrix, 2026-08-30 |
| M1 — public roots | complete | Strict `PublicRoot`, `PreviewManifest`, and `Slides` module consumers plus the legacy Lean suite, 2026-09-01 |
| M2 — dependency leaves | complete | 100 of 100 dependency and feature sources are modules; phase-neutral preview-manifest, style/hover/Lean-link/code-preview/external-code/citation/command-summary/command-graph data, ordering, collection, HTML/section/markup rendering, and citation/bibliography/summary/graph/graft authoring, manual-preview/source, informal-block, graft, and manifest block/relation-panel/use-reference/inline-code/Rust-panel/preview-external-markup/Slides-node rendering, preview CLI, VBP query/check library and CLI, widget and Slides-node attribute/authoring, Slides integration, and TeX/PDF runtime services, metadata data, core/graft/Slides asset bundles, serialized command blocks, Lean/informal-block/graft-node configuration/storage/traversal/authoring and author/group/source authoring, typed traversal-store, Rust-code, and graph model/API modules now pass strict module consumers |
| M3 — phase-mixed features | in progress | `Math.Data`, `Macros.Data`, and `Informal.Code.Data` own shared phase-neutral payloads; `Informal.Uses` separates normal rendering from meta role elaboration, while `Informal.Code` and `Informal.RustBlock` separate runtime extensions from meta code-block parsers and expanders |
| M4 — roots and cutover | complete | 101 of 101 production sources are modules, `VersoBlueprint` requires the module system, and the M4 gate is green, 2026-09-01 |
| M5 — deliverables and legacy consumers | in progress | Test-blueprint/browser, FLT, Carleson, and project-template validation green at 94 of 99 production modules, 2026-08-31; rerun after the Slides/root cutover |
| M6 — incremental boundaries | complete | Two consecutive warm runs of `scripts/check-incremental-module-boundaries.py`, 2026-08-31 |
| M7 — documentation and final audit | pending | — |

## Milestones and Verification Gates

Each milestone is independently reviewable. Mark it complete only when every
listed gate has passed and the evidence is recorded in the change or local
handoff. Routine command transcripts belong in local reports or CI, not the PR
body.

### M0 — Freeze the behavioral and API contract

Deliverables:

- Record a clean baseline for the core library, CLI, repository tests, test
  blueprints, and current reference catalog.
- Add a focused legacy authoring contract that imports only the intended
  `VersoBlueprint` root and exercises representative public syntax: informal
  statements/proofs, uses, Lean code, citations, math, graph, summary,
  bibliography, grafting, and Slides integration.
- Add `scripts/check-module-boundaries.py`. It should report source/module
  counts and fail on final-state escape hatches such as
  `backward.privateInPublic`, `allowNonModules`, or production sources without
  module headers once final enforcement is enabled.

Gate:

```bash
scripts/run-lean-tests.sh
./scripts/validate-test-blueprints.sh
./scripts/validate-reference-blueprints.sh --run-lean-tests --allow-local-build
```

### M1 — Specify and test the public roots

Deliverables:

- Define a dedicated `VersoBlueprintModuleTests` Lake target for module-only
  consumers as soon as the first real modular public root is available. It
  must not be made green with `allowNonModules`.
- Add module-only compile fixtures for these consumer roles:
  - authoring through `VersoBlueprint`;
  - generation through `PreviewManifest`/the standard generator entry point;
  - Slides authoring through `VersoBlueprint.Slides`;
  - a minimal public-surface probe that catches the known `Lean.Doc.Block`
    versus `Verso.Doc.Block` ambiguity class.
- Inventory declarations required by those fixtures and reference projects.
- Classify root imports as public ordinary, public meta, or implementation-only
  before converting the facade.

Gate:

- Every declaration exposed from a root has an identified consumer.
- The module fixtures compile without importing implementation submodules.
- Existing non-module tests still compile against the same roots.

### M2 — Convert dependency leaves

Convert from the leaves upward so non-module clients can continue importing
converted modules while no module source needs to import an unconverted source.

Suggested order:

1. pure data, parsing, and small library utilities;
2. semantic state, cache, graph, source, and traversal-index data;
3. render helpers and feature-specific runtime modules;
4. authoring/elaboration modules;
5. preview, generator, Slides, and package roots.

For each slice:

- add `module`;
- decide each import rather than mechanically making it public;
- use small `public section` or `public meta section` scopes;
- retain private declarations unless a documented consumer needs them;
- build the converted module and all direct repository consumers;
- keep the slice behaviorally neutral.

Gate:

- No converted module imports a non-module production source.
- No private constructor/helper is widened solely to make the slice compile.
- The relevant existing test roots pass before moving to the next dependency
  layer.

### M3 — Resolve phase-mixed feature modules

Work through the phase-mixed audit table. Treat the old prototype's file splits
as hypotheses and use the current dependency graph and compile errors to decide
the smallest coherent owner for shared values.

Gate for each area:

- its module-only consumer compiles;
- no shared value has separate authoring/runtime copies;
- feature-specific Lean and browser tests pass;
- generated HTML/JSON remains semantically identical, ignoring explicitly
  volatile metadata such as generation timestamps;
- private representation invariants remain enforced.

### M4 — Convert and curate the roots

Deliverables:

- Convert `VersoBlueprint`, `PreviewManifest`, `Slides`, `Vbp`, and remaining
  production roots.
- Replace the broad facade with precise public imports.
- Enable `requiresModuleSystem := true` on the `VersoBlueprint` library only
  after every production root and required dependency satisfies it.
- Remove stale commented module headers and any temporary migration options.

Gate:

```bash
python3 scripts/check-module-boundaries.py
scripts/lean-low-priority lake build VersoBlueprint vbp VersoBlueprintModuleTests
scripts/lean-low-priority lake build VersoBlueprintTests.BlueprintSlides
scripts/lean-low-priority lake test
```

The checker must report every Lean file under `src/` as a module and no final
escape hatch. The build must not emit a non-module dependency warning.

### M5 — Validate real deliverables and legacy consumers

Gate:

```bash
./scripts/validate-test-blueprints.sh
./scripts/validate-reference-blueprints.sh --run-lean-tests --allow-local-build
python3 -m scripts.blueprint_reference_harness validate \
  --project project-template --run-lean-tests
uv run --project tests/browser --extra test python -m pytest \
  tests/browser -q --browser chromium
```

Required outcomes:

- FLT, Carleson, and the explicit project-template fixture compile without
  migrating their Blueprint sources merely to accommodate VBP.
- Manual and Slides sites retain registered extensions, assets, navigation,
  graph/summary/bibliography output, previews, and graft behavior.
- Output comparison finds no unexplained semantic changes.
- No downstream source needs a new qualification because VBP leaked a broad
  namespace into its public imports.

### M6 — Verify incremental boundaries

Add a deterministic rebuild harness rather than using wall-clock timing as its
pass/fail criterion. It must include these scenarios:

1. A private implementation-only change rebuilds its owner but does not
   re-elaborate the module-only authoring consumer.
2. A runtime renderer-only change does not re-elaborate a consumer that imports
   only the authoring surface.
3. A public shared-data change does rebuild the dependent consumer, serving as
   a positive control.
4. Reverting the synthetic edit leaves the worktree clean and the normal build
   green.

Record rebuilt module/job identities. Wall-clock and memory numbers may be
reported as observations, but they are not correctness gates.

Run the harness from the repository root:

```bash
python3 scripts/check-incremental-module-boundaries.py
```

The harness uses a fresh declaration nonce for each synthetic edit so the Lake
artifact cache cannot replay a previous probe and obscure the rebuilt job set.
It restores each source before proceeding and verifies that the final worktree
status is identical to the initial status.

Gate:

- all four scenarios are repeatable from a warm build;
- the two private/runtime-only scenarios demonstrate the intended narrower
  invalidation boundary;
- the positive control proves that the harness can observe a real dependent
  rebuild.

### M7 — Documentation and final audit

Deliverables:

- Update `DESIGN_RATIONALE.md` with the landed phase and public-root
  architecture.
- Update `API.md`, examples, and maintainer documentation for any intentional
  import migration.
- Remove this plan's obsolete implementation detail or mark completed
  milestones with durable evidence; do not leave a second description of the
  final architecture here and in the design rationale.

Final gate:

- M0–M6 are complete;
- the full validation matrix is green from a clean checkout/cache state used by
  CI;
- the final diff contains no feature removal, phase-data duplication, accidental
  public API widening, or module-system escape hatch;
- any changed downstream imports are documented as intentional migrations.

## Commit and Review Slicing

Prefer slices that keep the branch buildable and make one boundary reviewable:

1. contract tests and boundary checker;
2. phase-neutral leaves;
3. one feature-area phase split per commit or small related series;
4. public roots and `requiresModuleSystem` cutover;
5. downstream/incremental validation and documentation.

Do not combine semantic cleanup or rendering redesign with a module conversion
unless the cleanup is required to preserve a private or phase boundary. Record
such a dependency explicitly in the relevant milestone.

## Completion Definition

The refactor is complete when VBP's production sources are all modules, its
public roots are intentional, both module and legacy consumers work, Manual and
Slides output is preserved, and the incremental harness demonstrates narrower
rebuild boundaries. Successful compilation of the broad library root alone is
not completion.
