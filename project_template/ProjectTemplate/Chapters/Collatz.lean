module

public import VersoBlueprint
meta import VersoBlueprint

public section

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Collatz" =>

# Side-by-Side Views

These grafts reuse the Collatz entries below. A full card keeps the explanatory
definition together with its attached Lean code, while compact cards keep the
statement and proof facets easy to compare.

:::blueprint_side_by_side +boxed
{blueprint_node "collatz_step" (displayLabel := "Step")}

{blueprint_node "collatz_conjecture" (displayLabel := "Conjecture") -header +compact}
:::

:::blueprint_side_by_side
{blueprint_node "collatz_conjecture" (displayLabel := "Statement") -header +compact}

{blueprint_node "collatz_conjecture" (facet := "proof") (displayLabel := "Proof status") -header +compact}
:::

# Source Entries

:::group "collatz_core"
A small exploratory chapter about the Collatz iteration on natural numbers.
:::

:::definition "collatz_step" (parent := "collatz_core")
The Collatz step sends an even natural number $`n` to $`n / 2` and an odd one
to $`3 * n + 1`. The odd branch combines {uses "multiplication_spec"}[] with
{uses "addition_spec"}[].
:::

```lean "collatz_step"
def collatzStep (n : Nat) : Nat :=
  if n % 2 == 0 then n / 2 else 3 * n + 1

def collatzTerminatesAtOne (n : Nat) : Prop :=
  ∃ steps : Nat, Nat.repeat collatzStep steps n = 1
```

:::theorem "collatz_conjecture" (parent := "collatz_core") (tags := "playful, famous, incomplete") (effort := "medium")
For every positive natural number $`n`, repeated application of the Collatz
step eventually reaches $`1`.
This is the usual termination statement of the Collatz conjecture, phrased in
terms of {uses "collatz_step"}[].
:::

:::proof "collatz_conjecture"
No proof is currently known. This theorem is intentionally left unfinished in
the starter template so the generated graph and summary show an in-progress
goal immediately.
:::

```lean "collatz_conjecture"
theorem collatz_conjecture (n : Nat) (hn : 0 < n) :
    collatzTerminatesAtOne n := by
  have hn' : 0 < n := hn
  sorry
```
