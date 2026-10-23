/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoLspVerso

namespace VersoLspDocs
open Verso Verso.Doc Verso.Genre.Manual VersoLspVerso

set_option doc.verso true

#docs (Genre.Manual) plain "LSP analysis in a Verso document" :=
:::::::
*Rust code and references*

:::row
```lspCode "body" (context := "rust-values")
/// Computes one step. <img src=x onerror=alert('unsafe')>
pub fn step(n: u64) -> u64 { n + 1 }
pub fn demo() -> u64 { /* 😀 */ step(2) }
```
:::

The named reference _{lspRef "step-ref" "step" (context := "rust-values")}[]_
shares its context with the preceding code block.

*Rocq code and references*

```lspCode "body" (context := "rocq-names")
Definition step (n : nat) : nat := S n.
Example step_two : step 2 = 3.
Proof. reflexivity. Qed.
```

A named reference {lspRef "step-ref" "step" (context := "rocq-names")}[] resolves here.

*A diagnostic in authored code*

```lspCode "invalid" (context := "rocq-invalid")
Check missing_name.
```
:::::::

end VersoLspDocs
