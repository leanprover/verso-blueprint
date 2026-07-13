# `vbp` Reference

Use `lake exe vbp ...` from the Blueprint project root.

## Commands

Run `lake exe vbp --help` for complete local CLI usage. The main command forms are:

```bash
lake exe vbp discover
lake exe vbp build [--output <dir>] [--pdf] [--verbose] [--serve] [--port <n>]
lake exe vbp query [--site <dir>] <selector>
lake exe vbp check
```

Query selectors:

```text
selectors
labels
node <label>
all <label>
uses <label>
used-by <label>
group <label>
owners
tags
work-queue
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

`build` discovers the generator entry point directly, runs `lake build <package>`, prepares/elaborates the generator file with Lake so imported OLeans are materialized, then runs the generator through Lean's interpreter:

```bash
lake lean <GeneratorMain>.lean
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --output <output>
```

`build --verbose` passes `--verbose` through to the generator run, enabling Blueprint generation phase progress after the Lake package build completes.

`build --serve` builds once, then serves `<output>/html-multi` with a local static server and keeps running. Without `--port`, it tries port `8000` and falls back to an available port. With `--serve --port <n>`, it fails if the requested port is unavailable. `--port` is accepted only with `--serve`. The command prints the actual preview URL.

## Query Output

All query commands print compact JSON for agent consumption. The JSON shape is fully unstable today; do not treat it as a compatibility contract. Top-level query objects include `"apiStability":"unstable"`. Query reads the semantic manifest only; use `check` when you need to validate the rendered HTML cache as well.

- `selectors`: query selector forms supported by this `vbp` binary. This selector does not require generated Blueprint data.
- `labels`: statement-level Blueprint block summaries.
- `node <label>`: one block entry with title, kind, href, parent/group, owner/tags/priority/effort, statement/proof uses, reverse uses, and Lean preview keys.
- `all <label>`: one-stop agent bundle for a node, including the node, statement/proof uses, reverse uses, and group data.
- `uses <label>`: statement/proof dependencies and resolved related entries for one label.
- `used-by <label>`: reverse dependencies for one label.
- `group <label>`: group metadata and sibling entries for one label, when present.
- `owners` and `tags`: distinct values from statement-level block entries.
- `work-queue`: statement-level entries with owner, tags, priority, or effort metadata.
- `search <text>`: statement-level entries whose label, title, owner, tag, or parent title contains the text, case-insensitively.
- `code <decl>`: statement-level entries with Lean preview keys containing the declaration text.
- `stats`: counts of statement-level entries by kind, owner, and tag.

If generated data is missing, run `lake exe vbp build` first. If a label is unknown, `query` returns JSON with `"error":"unknown-label"`.

## Check

`lake exe vbp check` is a post-build generated-data health check. It does not replace `build`: build catches Lean/Lake compilation, elaboration, generator, and rendering failures. `check` parses generated data and verifies that semantic entries, Lean preview keys, relation previews, and group previews have corresponding rendered HTML cache entries. It prints:

```json
{"apiStability":"unstable","ok":true,"manifestEntries":0,"htmlCacheEntries":0,"errors":[]}
```

The command exits nonzero when generated data is missing, malformed, or internally inconsistent.

## Fallback Without `vbp`

For older projects, inspect the generator entry point, then use:

```bash
lake build <library-or-formalization-target>
lake lean <GeneratorMain>.lean
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --output _out/site
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --dump-manifest
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --dump-html-cache
lake lean <GeneratorMain>.lean -- --run <GeneratorMain>.lean --help
```

The manifest/cache files are implementation details for normal agent work; use them directly only when `vbp query` is unavailable or when debugging `vbp` itself.

## Adoption Boundary

This skill assumes the target project depends on a version of `VersoBlueprint` that provides `lake exe vbp`. Install or copy the whole `skills/verso-blueprint/` directory into the agent runtime's skill directory.

The `vbp query` JSON output is fully unstable for now. It is useful as an agent interface inside one release line, but it is not yet a public compatibility contract.
