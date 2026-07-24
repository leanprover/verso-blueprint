import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

namespace PreviewRuntimeShowcase.CodePanelDecls

def previewExternalDefinition : Nat := 0

abbrev previewExternalAbbrev : Nat := previewExternalDefinition

unsafe def previewExternalUnsafeDefinition : Nat := previewExternalDefinition + 1

/--
The first documented preview definition used to test multi-declaration
docstring rendering in external code panels.
-/
def previewDocstringedDefinition : Nat := 7

/--
Adds a small preview offset to `n`.

The second paragraph keeps paragraph spacing visible when several documented
definitions appear in the same code panel.
-/
def previewDocstringedFunction (n : Nat) : Nat := n + 1

set_option doc.verso true in
/--
A *structural external-panel docstring* with inline mathematics
$`6 + 1 = 7`.

* First structural panel item.
* Second structural panel item.
-/
def previewVersoDocstringedDefinition : Nat := 7

set_option doc.verso true in
/--
A *structural container docstring* for a field-docstring regression.
-/
structure PreviewVersoDocstringedStructure where
  /--
  A *structural field docstring* with inline mathematics $`8 + 1 = 9`.
  -/
  value : Nat

theorem previewExternalTheorem : True := by
  trivial

/--
A documented preview theorem whose statement is intentionally small.
-/
theorem previewDocstringedTheorem : True := by
  trivial

theorem previewExternalTheoremTwo : True := by
  trivial

theorem previewExternalSorry : True := by
  sorry

axiom previewExternalAxiom : True

/--
A small inductive type used to exercise rendered constructor lists.
-/
inductive PreviewStage where
  /-- The initial stage of the preview workflow. -/
  | initial
  /-- A numbered follow-up stage. -/
  | step (n : Nat)

/--
A compact class used to exercise rendered method documentation.
-/
class PreviewFold (α : Type) where
  /-- The neutral preview value. -/
  neutral : α
  /-- Combine two preview values. -/
  combine : α → α → α

/--
A preview Frey package is a compact stand-in for a structure whose constructor
duplicates a field-heavy mathematical record.
-/
structure PreviewFreyPackage where
  /-- The first value in the package. -/
  a : Nat
  /-- The second value in the package. -/
  b : Nat
  /-- The target value in the package. -/
  c : Nat
  /-- The prime-like exponent under discussion. -/
  p : Nat
  /-- The lower-bound hypothesis on `p`. -/
  hp5 : 5 <= p
  /-- The Fermat-like equation carried by the package. -/
  hFLT : a ^ p + b ^ p = c ^ p

/--
Given a counterexample `a^p + b^p = c^p` with `p >= 5`,
there exists a preview Frey package.
-/
theorem PreviewFreyPackage.ofCounterexample {a b c p : Nat} (hp5 : 5 <= p)
    (H : a ^ p + b ^ p = c ^ p) : Nonempty PreviewFreyPackage := by
  exact Nonempty.intro { a := a, b := b, c := c, p := p, hp5 := hp5, hFLT := H }

end PreviewRuntimeShowcase.CodePanelDecls

open PreviewRuntimeShowcase.CodePanelDecls

#doc (Manual) "Code Panels" =>

:::definition "panel_external_definition" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalDefinition")
In-module external definition panel sample.
:::

:::definition "panel_external_short_name_definition" (lean := "previewExternalDefinition")
Namespace-opened external definition panel sample.
:::

:::definition "panel_external_abbrev" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalAbbrev")
In-module external Lean `abbrev` panel sample. Status summaries stay definition-like, while the rendered declaration preserves the `abbrev` keyword.
:::

:::definition "panel_external_unsafe_definition" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalUnsafeDefinition")
In-module external unsafe definition panel sample.
:::

:::definition "panel_external_docstringed_definitions" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedDefinition, PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedFunction")
External definition panel sample with multiple documented Lean definitions.
:::

:::theorem "panel_external_theorem" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalTheorem")
In-module external theorem panel sample.
:::

:::theorem "panel_external_theorem_docstring" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedTheorem")
External theorem panel sample with a declaration docstring.
:::

:::theorem "panel_external_multi_theorem" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalTheorem, PreviewRuntimeShowcase.CodePanelDecls.previewExternalTheoremTwo")
In-module external theorem panel sample with multiple complete declarations.
:::

:::theorem "panel_external_warning" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalSorry")
In-module external theorem panel with a sorry-backed declaration.
:::

:::theorem "panel_external_multi_theorem_warning" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalTheorem, PreviewRuntimeShowcase.CodePanelDecls.previewExternalSorry")
In-module external theorem panel sample with mixed declaration health.
:::

:::theorem "panel_external_multi_theorem_missing" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewExternalTheorem, PreviewRuntimeShowcase.CodePanelDecls.previewExternalMissing")
External theorem panel sample with multiple references and one missing declaration.
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

:::definition "panel_external_inductive" (lean := "PreviewRuntimeShowcase.CodePanelDecls.PreviewStage")
External inductive panel sample with documented constructors.
:::

:::definition "panel_external_class" (lean := "PreviewRuntimeShowcase.CodePanelDecls.PreviewFold")
External class panel sample with documented methods.
:::

:::definition "panel_external_structure" (lean := "PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage")
External structure panel sample with a field-heavy package shape.
:::

:::theorem "panel_external_structure_docstring" (lean := "PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage.ofCounterexample")
External theorem panel sample with a Markdown-like docstring.
:::

:::definition "panel_external_mixed_constructs" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedDefinition, PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedTheorem, PreviewRuntimeShowcase.CodePanelDecls.PreviewStage, PreviewRuntimeShowcase.CodePanelDecls.PreviewFold, PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage")
External declaration panel sample mixing definitions, theorems, inductives, classes, and structures.
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

:::theorem "panel_inline_multi_theorem_proved"
Inline code panel sample with multiple complete Lean theorems.
:::

```lean "panel_inline_multi_theorem_proved"
theorem panelInlineMultiTheoremOkLeft : True := by
  trivial

theorem panelInlineMultiTheoremOkRight : True := by
  trivial
```

:::theorem "panel_inline_multi_theorem_warning"
Inline code panel sample with multiple Lean theorems and mixed declaration health.
:::

```lean "panel_inline_multi_theorem_warning"
theorem panelInlineMultiTheoremWarningOk : True := by
  trivial

theorem panelInlineMultiTheoremWarningSorry : True := by
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

:::definition "panel_inline_structure_docstrings"
Inline Lean structure sample with declaration and field docstrings.
:::

```lean "panel_inline_structure_docstrings"
/--
Inline package docstring used to compare literate Lean
against the external declaration renderer.

* The field `left` is shown as inline code.
* **Bold text** checks richer Markdown.
-/
structure PanelInlineDocstringedStructure where
  /-- The left inline field. -/
  left : Nat
  /-- The right inline field. -/
  right : Nat
  /--
  A proof-like field that keeps dependent-looking field
  layout visible.
  -/
  ordered : left <= right
```

:::definition "panel_inline_inductive_docstrings"
Inline Lean inductive sample with declaration and constructor docstrings.
:::

```lean "panel_inline_inductive_docstrings"
/--
Inline workflow stage docstring used to compare
constructor documentation.
-/
inductive PanelInlineDocstringedStage where
  /-- The initial inline stage. -/
  | initial
  /-- A follow-up inline stage carrying a counter. -/
  | followup (_ : Nat)
```

:::definition "panel_inline_mixed_construct_docstrings"
Inline Lean panel sample mixing documented structures, inductives, and classes.
:::

```lean "panel_inline_mixed_construct_docstrings"
/-- Inline mixed configuration docstring. -/
structure PanelInlineMixedConfig where
  /-- Whether the preview branch is enabled. -/
  enabled : Bool

/-- Inline mixed state docstring. -/
inductive PanelInlineMixedState where
  /-- The ready state. -/
  | ready
  /-- The running state with a step count. -/
  | running (_ : Nat)

/-- Inline mixed fold class docstring. -/
class PanelInlineMixedFold (α : Type) where
  /-- The empty inline value. -/
  empty : α
  /-- Merge two inline values. -/
  merge : α -> α -> α
```

:::definition "panel_no_code"
Statement without associated Lean code.
:::

:::definition "panel_external_verso_docstring" (lean := "PreviewRuntimeShowcase.CodePanelDecls.previewVersoDocstringedDefinition")
External definition panel sample with a structural Verso docstring.
:::

:::definition "panel_external_verso_structure_docstring" (lean := "PreviewRuntimeShowcase.CodePanelDecls.PreviewVersoDocstringedStructure")
External structure panel sample with structural declaration and field docstrings.
:::
