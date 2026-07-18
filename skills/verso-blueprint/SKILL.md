---
name: verso-blueprint
description: Work with Verso Blueprint Lean projects. Use when Codex needs to build or serve Blueprint HTML, query Blueprint labels/dependencies/owners/tags/work queues, debug generated graph/summary/preview data, inspect or edit Blueprint source modules, add conservative Blueprint nodes or metadata, or reason about `lake exe vbp` workflows in repositories using `VersoBlueprint`.
---

# Verso Blueprint

## Quick Start

Prefer the project-local helper:

```bash
lake exe vbp discover
lake exe vbp build
lake exe vbp query labels
lake exe vbp check
```

Read `references/vbp.md` when you need exact command behavior, JSON shapes, serve behavior, or fallback commands.

Read `references/authoring-patterns.md` before editing Blueprint source, adding nodes, changing dependencies, or diagnosing authoring syntax.

## Workflow

1. Run `lake exe vbp discover` first to identify the package, generator, top-level Blueprint module, output paths, and chapter candidates.
2. Build with `lake exe vbp build` before querying unless generated output already exists and the user only asks to inspect it.
3. Query with `lake exe vbp query ...`; do not ask users to inspect manifest/cache files directly for normal tasks.
4. Use `lake exe vbp query node <label>` when you need the complete record for one Blueprint node.
5. Edit source conservatively when requested. Preserve stable labels, use existing chapter/module patterns, and keep dependency intent clear.
6. Rebuild after source edits. Use `lake exe vbp check` when auditing persisted, copied, or externally supplied generated output. Report changed labels, changed dependency edges, and remaining diagnostics.

## Guardrails

- Treat `_out/site` as the default generated site. Use `--output` only for build destinations and `--site` only for reading an alternate generated site.
- Do not expose `blueprint-manifest.json` or `blueprint-html-cache.json` as the normal interface; `vbp query` and `vbp check` are the normal interface.
- Treat all `vbp query` JSON shapes as unstable. They are for current agent consumption, not a compatibility promise.
- Use `uses` only for mathematical dependency edges. Use `bpref` for prose links that should not affect the graph.
- Keep statement and proof dependencies separate. Statement blocks use statement-side `uses`; `:::proof` blocks use proof-side `uses`.
- Prefer small, explicit source patches over broad rewrites. Do not rename labels unless the user asks for a migration and validation plan.
- If `vbp` is unavailable, fall back to the generator commands in `references/vbp.md` and explain that the project predates the helper.
