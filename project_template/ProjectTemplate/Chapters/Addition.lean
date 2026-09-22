module

public import VersoBlueprint
meta import VersoBlueprint

public section

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Addition" =>

:::source_document "addition-source"
%%%
title := "Starter Addition Notes"
kind := .pdf
pdf := "source/addition-source.pdf"
%%%
:::

:::group "addition_core"
Core statements about addition on natural numbers.
:::

:::author "project_author" (name := "Project Author")
:::

:::definition "addition_spec" (parent := "addition_core")
We write $`a + b` for the result of adding $`b` to $`a`.
This starter Blueprint begins with the most basic sanity checks around that
operation.
:::

:::theorem "addition_right_identity" (parent := "addition_core") (owner := "project_author") (tags := "starter, arithmetic") (effort := "small") (priority := "high")
%%%
source := {
  document := "addition-source"
  spans := #[
    {
      page := "1"
      pdf := some {
        path := "source/addition-source.pdf"
      }
    }
  ]
}
%%%

For every natural number $`n`, adding zero on the right leaves it unchanged:
$`n + 0 = n`.
This is the first sanity check for {uses "addition_spec"}[].
:::

:::proof "addition_right_identity"
Induct on $`n`. The base case is immediate and the inductive step unfolds one
successor on each side.
:::

```lean "addition_right_identity"
theorem nat_add_zero_right (n : Nat) : n + 0 = n := by
  simp
```

:::theorem "addition_assoc" (parent := "addition_core") (lean := "Nat.add_assoc")
For all natural numbers $`a`, $`b`, and $`c`, addition is associative:
$`(a + b) + c = a + (b + c)`.
This is another consequence of {uses "addition_spec"}[].
:::

:::proof "addition_assoc"
Lean already provides this theorem as `Nat.add_assoc`, so this Blueprint entry
links to an existing declaration instead of restating the code locally.
:::

:::definition "addition_runtime_note" (parent := "addition_core")
Some projects keep implementation notes or helper snippets next to the informal
statement surface. Blueprint can attach a small Rust block for that purpose.
:::

```rust "addition_runtime_note"
pub fn add_preview(x: i32, y: i32) -> i32 {
    x + y
}
```
