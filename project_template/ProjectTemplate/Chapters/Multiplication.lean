module

public import VersoBlueprint
meta import VersoBlueprint

public section

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Multiplication" =>

:::group "multiplication_core"
Core statements about multiplication on natural numbers.
:::

:::definition "multiplication_spec" (parent := "multiplication_core")
We write $`a * b` for the product of $`a` and $`b`.
One way to think about multiplication is as repeated addition, building on
{uses "addition_spec"}[].
:::

:::theorem "multiplication_one_right" (parent := "multiplication_core") (tags := "starter, arithmetic") (effort := "small")
For every natural number $`n`, multiplying by one on the right leaves it
unchanged: $`n * 1 = n`.
This is the first sanity check for {uses "multiplication_spec"}[].
:::

:::proof "multiplication_one_right"
Unfold the definition of multiplication and simplify.
:::

```lean "multiplication_one_right"
theorem multiplication_one_right (n : Nat) : n * 1 = n := by
  simp
```

:::theorem "multiplication_assoc" (parent := "multiplication_core") (lean := "Nat.mul_assoc")
For all natural numbers $`a`, $`b`, and $`c`, multiplication is associative:
$`(a * b) * c = a * (b * c)`.
:::

:::proof "multiplication_assoc"
Lean already provides this theorem as `Nat.mul_assoc`, so this Blueprint entry
links to an existing declaration instead of restating the code locally.
:::
