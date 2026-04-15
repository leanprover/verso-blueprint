import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

namespace PreviewRuntimeShowcase.CodePanelDecls

def previewExternalDefinition : Nat := 0

abbrev previewExternalAbbrev : Nat := previewExternalDefinition

theorem previewExternalTheorem : True := by
  trivial

theorem previewExternalSorry : True := by
  sorry

axiom previewExternalAxiom : True

end PreviewRuntimeShowcase.CodePanelDecls

#doc (Manual) "Code Panels" =>

:::definition "panel_external_definition" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalDefinition")
In-module external definition panel sample.
:::

:::definition "panel_external_abbrev" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalAbbrev")
In-module external Lean `abbrev` panel sample. Status summaries stay definition-like, while the rendered declaration preserves the `abbrev` keyword.
:::

:::theorem "panel_external_theorem" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalTheorem")
In-module external theorem panel sample.
:::

:::theorem "panel_external_warning" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalSorry")
In-module external theorem panel with a sorry-backed declaration.
:::

:::definition "panel_external_imported_definition" (lean := "Nat.add")
Out-of-module external definition panel sample.
:::

:::theorem "panel_external_imported_theorem" (lean := "Nat.add_assoc")
Out-of-module external theorem panel sample.
:::

:::definition "panel_external_missing" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalMissing")
External declaration panel with a missing declaration.
:::

:::theorem "panel_external_axiom" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalAxiom")
External theorem panel with an axiom-like declaration.
:::

:::definition "panel_inline_proved"
Inline code panel sample with complete Lean code.
:::

```lean "panel_inline_proved"
def panelInlineOnlyOk : Nat := 0
```

:::definition "panel_inline_warning"
Inline code panel sample with a sorry-backed declaration.
:::

```lean "panel_inline_warning"
theorem panelInlineOnlySorry : True := by
  sorry
```

:::definition "panel_inline_progress"
Inline code panel sample with mixed declaration health.
:::

```lean "panel_inline_progress"
def panelInlineOk : Nat := 0

theorem panelInlineSorry : True := by
  sorry
```

:::definition "panel_inline_axiom"
Inline code panel sample with an axiom-like declaration.
:::

```lean "panel_inline_axiom"
axiom panelInlineAxiom : True
```

:::definition "panel_no_code"
Statement without associated Lean code.
:::
