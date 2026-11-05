import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Status Matrix" =>

One block per formalization status. Each block states the condition it
represents, not how it should look.

What to check:

* Each block's heading, Lean panel, graph node, and Summary entry agree.
* A block whose own Lean code is complete but whose prerequisites are not is
  distinguishable from both a finished block and a block with a `sorry`.
* Every warning says what it is warning about.

:::group "status_group"
Blocks that cover each formalization status.
:::

:::definition "status_statement_only" (parent := "status_group")
Condition: prose only. No Lean code is attached, so nothing is checked.
:::

:::definition "status_definition_complete" (parent := "status_group")
Condition: complete Lean code and no prerequisites.
:::

```lean "status_definition_complete"
def statusBase : Nat := 1
```

:::theorem "status_ready" (parent := "status_group")
Condition: no Lean code yet, and every prerequisite is finished. It uses
{uses "status_definition_complete"}[].
:::

:::theorem "status_sorry" (parent := "status_group")
Condition: Lean code exists but its proof uses `sorry`. It uses
{uses "status_definition_complete"}[].
:::

```lean "status_sorry"
theorem statusSorry : statusBase = 1 := by
  sorry
```

:::theorem "status_blocked" (parent := "status_group")
Condition: no Lean code, and a prerequisite is unfinished. It uses
{uses "status_sorry"}[].
:::

:::theorem "status_local_complete_prerequisite_open" (parent := "status_group")
Condition: this block's own Lean code is complete, but a prerequisite has no
Lean code. It uses {uses "status_statement_only"}[].
:::

```lean "status_local_complete_prerequisite_open"
theorem statusLocalComplete : True := by
  trivial
```

:::theorem "status_fully_closed" (parent := "status_group")
Condition: this block and every prerequisite have complete Lean code. It uses
{uses "status_definition_complete"}[].
:::

```lean "status_fully_closed"
theorem statusFullyClosed : statusBase = 1 := rfl
```

:::theorem "status_proof_open" (parent := "status_group")
Condition: the statement is formalized, and the informal proof below has not
been formalized yet.
:::

:::proof "status_proof_open"
The proof cites {uses "status_fully_closed"}[] and {uses "status_ready"}[].
:::

```lean "status_proof_open"
theorem statusProofOpen : statusBase + 0 = 1 := by
  sorry
```

:::theorem "status_axiom" (parent := "status_group")
Condition: the Lean code is an axiom, so it is assumed rather than proved.
:::

```lean "status_axiom"
axiom statusAxiom : statusBase = 2
```

:::definition "status_external_resolved" (parent := "status_group") (lean := "Nat.add_comm")
Condition: the Lean code is an existing library declaration.
:::

:::definition "status_external_missing" (parent := "status_group") (lean := "Nat.doesNotExist")
Condition: the named Lean declaration does not exist. Generation warns about
this block.
:::
