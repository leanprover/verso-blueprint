# Blueprint Authoring Patterns

## Project Shape

A standard project has:

- chapter modules with `#doc (Manual) ...` content
- a top-level Blueprint module that includes chapters and overview pages
- a generator entry point, usually `<Project>Main.lean`

Keep this structure unless the user asks for a project reorganization.

## Blocks And Labels

Blueprint nodes use stable labels:

```lean
:::definition "addition_spec"
...
:::

:::theorem "addition_assoc" (uses := "addition_spec")
...
:::

:::proof "addition_assoc"
...
:::
```

Use existing local styles for labels. Do not rename existing labels casually; labels drive links, graph nodes, summary entries, code associations, and generated metadata.

Common statement directives:

- `:::definition`
- `:::proposition`
- `:::lemma_`
- `:::theorem`
- `:::corollary`
- `:::proof`

## Dependencies

Use `{uses "target"}[]` or block-level `(uses := "target")` when the current node mathematically depends on `target`.

Use `{bpref "target"}[]` for prose references that should link but should not create graph edges.

Dependency metadata:

```lean
:::theorem "main_result" (uses := "technical_lemma") (uses_intent := "technical")
...
:::
```

Allowed intent values are `"regular"`, `"auxiliary"`, and `"technical"`. Author-written dependencies are normally manual; use automatic origin only when tooling generated the edge.

Statement and proof dependencies are separate. Add proof-only dependencies on the `:::proof` block, not on the statement block.

## Metadata

Follow existing metadata conventions:

```lean
:::author "project_author" (name := "Project Author")
:::

:::group "addition_core"
Core statements about addition.
:::

:::theorem "addition_right_identity"
  (parent := "addition_core")
  (owner := "project_author")
  (tags := "starter, arithmetic")
  (effort := "small")
  (priority := "high")
...
:::
```

Do not invent new metadata vocabularies in source files. Reuse owners, tags, priorities, and effort values already present unless the user asks for new policy.

## Lean, Rust, And TeX Attachments

Attach inline Lean code with a labeled code block:

````lean
```lean "addition_right_identity"
theorem nat_add_zero_right (n : Nat) : n + 0 = n := by
  simp
```
````

Link to existing compiled declarations with `(lean := "Nat.add_assoc")`.

Attach Rust or raw TeX with labeled code blocks only when the project already uses those surfaces or the user asks for them:

````lean
```rust "ffi_helper"
pub fn ffi_helper(x: i32) -> i32 {
    x + 1
}
```
````

````lean
```tex "addition_right_identity"
\begin{theorem}
...
\end{theorem}
```
````

## Editing Checklist

Before editing, inspect the neighboring chapter and top-level Blueprint module. After editing, run:

```bash
lake exe vbp build
lake exe vbp check
```

When reporting changes, name the labels changed, dependency edges added or removed, and any remaining build/check diagnostics.
