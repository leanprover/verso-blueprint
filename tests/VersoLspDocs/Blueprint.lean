/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
import VersoLspDocs.Plain
import VersoBlueprint

namespace VersoLspDocs
open Verso Verso.Doc Verso.Doc.Elab Verso.Genre.Manual
open Informal

/-- Include the same compiled chapter inside a Blueprint node, exercising
extension children and the captured Blueprint model without copying requests. -/
@[directive]
def sharedLspExample : DirectiveExpanderOf Unit
  | (), _ => ``(Doc.Block.concat plain.toPart.content)

set_option doc.verso true

#docs (Genre.Manual) blueprint "LSP analysis inside Blueprint" :=
:::::::
:::definition "lsp.background"
The background specification.
:::

::::definition "lsp.shared" (uses := "lsp.background")
These foreign-language examples retain their analysis inside a Blueprint node.

:::sharedLspExample
:::
::::

:::proof "lsp.shared"
Foreign-language lookup does not alter Blueprint proof progress.
:::
:::::::

def blueprintDocument : Informal.BlueprintDocument := .capture blueprint.toPart

end VersoLspDocs
