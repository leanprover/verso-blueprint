import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Block Anatomy" =>

Every block kind, then each combination of header slots.

What to check:

* The kind, number, and header chips fit on one line at desktop width.
* Empty relations, such as a block that uses nothing, do not add noise.
* Statement and proof headers line up their chips in the same columns.
* Metadata, Lean code panels, and proofs read as parts of their block.

:::group "anatomy_group"
Blocks that show each kind and header slot.
:::

:::author "inspection_author" (name := "Inspection Author")
:::

# Kinds

:::definition "anatomy_definition" (parent := "anatomy_group")
A definition. Let $`f(n) = n + 1` for every natural number $`n`.
:::

```lean "anatomy_definition"
def anatomySucc (n : Nat) : Nat := n + 1
```

:::proposition "anatomy_proposition" (parent := "anatomy_group")
A proposition: $`f(0) = 1`, which follows from {uses "anatomy_definition"}[].
:::

:::lemma_ "anatomy_lemma" (parent := "anatomy_group")
A lemma: $`f(n) > n` for every $`n`, by {uses "anatomy_definition"}[].
:::

:::theorem "anatomy_theorem" (parent := "anatomy_group")
A theorem: $`f` is injective. It relies on {uses "anatomy_lemma"}[] and
{uses "anatomy_proposition"}[].
:::

:::proof "anatomy_theorem"
If $`f(a) = f(b)` then $`a + 1 = b + 1`, so $`a = b`. The proof also cites
{uses "anatomy_definition"}[].
:::

```lean "anatomy_theorem"
theorem anatomySuccInjective :
    Function.Injective anatomySucc := by
  intro a b h
  simpa [anatomySucc] using h
```

:::corollary "anatomy_corollary" (parent := "anatomy_group")
A corollary: distinct inputs give distinct outputs, by {uses "anatomy_theorem"}[].
:::

# Header Slots

:::definition "anatomy_isolated"
A block with no relations, no group, and no Lean code. Every relation slot is
empty.
:::

:::definition "anatomy_hub" (parent := "anatomy_group")
A block that many others use. Its header shows a group, a large used-by count,
and a Lean code link.
:::

```lean "anatomy_hub"
def anatomyHub : Nat := 3
```

:::lemma_ "anatomy_hub_user_one"
First user of {uses "anatomy_hub"}[].
:::

:::lemma_ "anatomy_hub_user_two"
Second user of {uses "anatomy_hub"}[].
:::

:::lemma_ "anatomy_hub_user_three"
Third user of {uses "anatomy_hub"}[] and {uses "anatomy_hub_user_one"}[].
:::

:::theorem "anatomy_metadata" (parent := "anatomy_group") (owner := "inspection_author") (tags := "inspection, metadata, long tag list") (effort := "large") (priority := "high")
A block that carries every metadata field, and uses {uses "anatomy_hub"}[].
:::

:::theorem "anatomy_proof_uses_only"
The statement uses nothing. Only the proof below has dependencies.
:::

:::proof "anatomy_proof_uses_only"
The argument combines {uses "anatomy_hub"}[] with {uses "anatomy_definition"}[].
:::

:::definition "anatomy_external" (lean := "Nat.add_comm")
A block whose Lean code is an existing library declaration.
:::

:::theorem "anatomy_a_deliberately_long_label_that_tests_how_headers_wrap" (parent := "anatomy_group")
A block with a very long label, which uses {uses "anatomy_hub"}[] and
{uses "anatomy_theorem"}[].
:::
