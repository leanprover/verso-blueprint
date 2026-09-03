/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

module

-- These are intentionally the fixture's only imports.
import VersoBlueprint
meta import VersoBlueprint

namespace VersoBlueprintBoundaryTests.AuthoringRoot

open Lean Verso
open Genre Manual
open Informal

-- Importing the public root must not make this reference ambiguous between
-- `Lean.Doc.Block` and `Verso.Doc.Block`.
example : Doc.Block Manual := .concat #[]

/-- Declaration used to exercise the public Blueprint attribute. -/
@[blueprint "module.root.attribute"]
def attributedDeclaration : Nat := 1

@[bib "module.root.citation"]
def contractCitation : Verso.Genre.Manual.Bibliography.Citable := .arXiv
  { title := .text "Module public root contract"
  , authors := #[.text "A. Author"]
  , year := 2026
  , id := "module.root.citation"
  }

tex_prelude r#"\newcommand{\modulerootmacro}{\mathsf{ModuleRoot}}"#

#docs (Manual) publicRootContractDoc "Module Public Root Contract" :=
:::::::
:::author "module.root.author" (name := "Module Root Author")
:::

:::group "module.root.group"
Module-root group.
:::

:::definition "module.root.base" (parent := "module.root.group") (owner := "module.root.author")
Base statement with $`\modulerootmacro`.
:::

```lean "module.root.base"
def contractInlineDeclaration : Nat := attributedDeclaration
```

:::theorem "module.root.result" (parent := "module.root.group") (uses := "module.root.base")
The result uses {uses "module.root.base"}[], refers to {bpref "module.root.base"}[],
and cites {Informal.citet "module.root.citation" (kind := theorem) (index := 1)}[].
:::

:::proof "module.root.result" (uses := "module.root.base")
The proof uses the same base statement.
:::

{blueprint_node "module.root.base" -header +compact}

{blueprint_graph}

{blueprint_summary}

{blueprint_bibliography}
:::::::

end VersoBlueprintBoundaryTests.AuthoringRoot
