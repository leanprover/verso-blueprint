# `vbp` Reference

Use `lake exe vbp ...` from the Blueprint project root.

## Commands

Run `lake exe vbp --help` for complete local CLI usage. The main command forms are:

```bash
lake exe vbp discover
lake exe vbp build [--output <dir>] [--pdf] [--verbose] [--serve] [--port <n>]
lake exe vbp query [--site <dir>] <selector>
lake exe vbp check [--site <dir>]
```

Query selectors:

```text
selectors
labels
node <label>
uses <label>
used-by <label>
group <label>
owners
tags
work-queue
metadata
search <text>
code <decl>
stats
```

Defaults:

- `build` writes `_out/site`.
- `query` and `check` read `_out/site`.
- Pass `--output <dir>` only to choose where `build` writes generated output.
- Pass `--pdf` to build `_out/site/pdf/main.pdf` from the generated TeX.
- Pass `--verbose` to show Blueprint generation phase progress while building.
- Pass `--site <dir>` to `query` or `check` only when reading a non-default site.

## Build And Serve

`discover` reports the Lake-backed package, generator entry point, generator module, generator source file, and default output paths. Fields ending in `Guess`, such as `topLevelBlueprintModuleGuess` and `chapterCandidateGuesses`, are convention-based hints for agents and may be null or incomplete. The JSON includes `"apiStability":"unstable"` and a `discoveryErrors` array. When Lake workspace discovery fails or no generator entry point can be found, package and generator fields are null and `discoveryErrors` explains why.

`build` discovers the generator, then uses Lake's Lean-file runner to build its
imports and execute it through Lean's interpreter:

```bash
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --output <output>
```

`build --verbose` passes `--verbose` through to the generator run, enabling
Blueprint generation phase progress.
Pass `--pdf` to build `_out/site/pdf/main.pdf` from the generated TeX output.
`--pdf-engine <cmd>` and `--pdf-runs <n>` are forwarded to the generator when
the local project's `vbp` binary supports them; run `lake exe vbp --help` for the
exact local flag surface.

`build --serve` builds once, then serves `<output>/html-multi` with a local static server and keeps running. Without `--port`, it tries port `8000` and falls back to an available port. With `--serve --port <n>`, it fails if the requested port is unavailable. `--port` is accepted only with `--serve`. The command prints the actual preview URL.

`discover`, `query`, and `check` print compact JSON to stdout on success.
`build` streams the attached Lake/generator stdout and stderr. If the generator
run fails, `vbp` writes `vbp build: generator run failed ...` to stderr and
exits nonzero.
Argument errors print to stderr and exit with code 2. Missing or inconsistent
generated data also prints an error to stderr and exits nonzero.

## Query Output

All query commands print compact JSON for agent consumption. The JSON shape is fully unstable today; do not treat it as a compatibility contract. Top-level query objects include `"apiStability":"unstable"`. Query arguments are validated before generated data is read, so unknown or malformed selectors do not require a built site. Query reads the semantic manifest only for valid selectors; use `check` when you need to validate the rendered HTML cache as well.

- `selectors`: query selector forms supported by this `vbp` binary. This selector does not require generated Blueprint data.
- `labels`: statement-level Blueprint block summaries.
- `node <label>`: one complete block entry with title, kind, href, parent/group, owner/tags/priority/effort, statement/proof uses, reverse uses, group data, and Lean preview keys.
- `uses <label>`: statement/proof dependencies and resolved related entries for one label.
- `used-by <label>`: reverse dependencies for one label.
- `group <label>`: group metadata and sibling entries for one label, when present.
- `owners` and `tags`: distinct values from statement-level block entries.
- `work-queue`: statement-level entries with a graph-status-backed actionable
  next step; each row includes `nextStep` (`"statement"` or `"proof"`),
  `statementStatus`, and `proofStatus`. Graph data is the generated planning
  source of truth, so no graph status means no work-queue row.
- `metadata`: statement-level entries with owner, tags, priority, or effort metadata.
- `search <text>`: statement-level entries whose label, title, owner, tag, or parent title contains the text, case-insensitively.
- `code <decl>`: statement-level entries with Lean preview keys containing the declaration text.
- `stats`: counts of statement-level entries by kind, owner, and tag.

If generated data is missing, run `lake exe vbp build` first. If a label is unknown, `query` returns JSON with `"error":"unknown-label"`.

## Check

`lake exe vbp check` audits an already-generated artifact boundary. It is not a repair phase or a required second step after normal generation: `build` catches Lean/Lake compilation, elaboration, generator, and rendering failures, and production generation constructs and finalizes the manifest/cache pair together. Use `check` for persisted, copied, or externally supplied output. It strictly parses generated graph projections and verifies that semantic entries, Lean preview keys, relation previews, and group previews have corresponding rendered HTML cache entries. It prints:

```json
{"apiStability":"unstable","ok":true,"manifestEntries":0,"htmlCacheEntries":0,"errors":[]}
```

The command exits nonzero when generated data is missing, malformed, or internally inconsistent.

## Fallback Without `vbp`

For older projects, inspect the generator entry point, then use:

```bash
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --output _out/site
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --dump-manifest
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --dump-html-cache
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --help
```

The manifest/cache files are implementation details for normal agent work; use them directly only when `vbp query` is unavailable or when debugging `vbp` itself.

## Adoption Boundary

This skill assumes the target project depends on a version of `VersoBlueprint` that provides `lake exe vbp`. Install or copy the whole `skills/verso-blueprint/` directory into the agent runtime's skill directory.

The `vbp query` JSON output is fully unstable for now. It is useful as an agent interface inside one release line, but it is not yet a public compatibility contract.
