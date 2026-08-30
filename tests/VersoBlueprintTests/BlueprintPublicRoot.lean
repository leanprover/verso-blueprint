/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

-- This import is intentionally the only import in the public-root contract.
import VersoBlueprint

namespace Verso.VersoBlueprintTests.BlueprintPublicRoot

open Verso
open Verso.Genre.Manual
open Informal

set_option doc.verso true

/-- Declaration used to exercise the public Blueprint attribute. -/
@[blueprint "contract.attribute"]
def attributedDeclaration : Nat := 1

@[bib "contract.citation"]
def contractCitation : Verso.Genre.Manual.Bibliography.Citable := .arXiv
  { title := inlines!"Public root contract"
  , authors := #[inlines!"A. Author"]
  , year := 2026
  , id := "contract.citation"
  }

tex_prelude r#"\newcommand{\contractmacro}{\mathsf{Contract}}"#

#docs (Genre.Manual) publicRootContractDoc "Public Root Contract" :=
:::::::
:::author "contract.author" (name := "Contract Author")
:::

:::group "contract.group"
Contract group.
:::

:::definition "contract.base" (parent := "contract.group") (owner := "contract.author") (tags := "contract")
Base statement with $`\contractmacro`.
:::

```lean "contract.base"
def contractInlineDeclaration : Nat := attributedDeclaration
```

:::theorem "contract.result" (parent := "contract.group") (uses := "contract.base")
The result uses {uses "contract.base"}[], refers to {bpref "contract.base"}[],
and cites {Informal.citet "contract.citation" (kind := theorem) (index := 1)}[].
:::

:::proof "contract.result" (uses := "contract.base")
The proof uses the same base statement.
:::

{blueprint_node "contract.base" -header +compact}

{blueprint_graph}

{blueprint_summary}

{blueprint_bibliography}
:::::::

end Verso.VersoBlueprintTests.BlueprintPublicRoot
