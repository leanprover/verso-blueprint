/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

public import VersoBlueprint

/-!
A real Blueprint-flavored Manual document for the VBP-owned preview renderer.

The fixture keeps Blueprint extensions intact so browser acceptance exercises
the same math and informal-block payloads used by reference projects.
-/

open Verso.Genre
open Informal

tex_prelude r#"\providecommand{\RR}{\mathbb{R}}"#

#doc (Manual) "VBP Verso renderer fixture" =>

# A real Verso document

This paragraph is elaborated by Verso and rendered by a native React component.
It includes _emphasis_, *strong text*, `inline code`, and a
[link](https://lean-lang.org/).

The renderer preserves inline math $`\RR^{n + 1}` and display math:

$$`
\sum_{i=0}^{n} i
`

:::theorem "vir_preview_fidelity"
An informal theorem contains its real body and more math: $`a^2 + b^2 = c^2`.
:::

:::proof "vir_preview_fidelity"
The retained proof body is visible in the live preview.
:::

```md "vir_preview_fidelity" (slot := summary) (display := summary)
Imported Markdown summary for the preview fixture.
```

```tex "vir_preview_fidelity" (slot := source) (display := source)
\begin{theorem}
External TeX source remains available for comparison.
\end{theorem}
```

```md "vir_preview_fidelity" (slot := hidden)
This default-hidden source must not create visible preview markup.
```

```
#check Nat
```

* an unordered item with _emphasis_
* another item with `code`
 * and a nested item

1. first ordered step
2. second ordered step

> Quotations are ordinary Verso blocks.
  * They can contain nested lists.

: Render boundary

  VBP owns the `Part Manual` renderer and its extension semantics.

: Downstream genres

  The viewer consumes the real Manual tree without a projected document layer.

## A child part

Section identity is independent from edits to this paragraph body.
