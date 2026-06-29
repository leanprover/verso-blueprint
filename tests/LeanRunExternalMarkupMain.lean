/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoManual

open Verso.Genre Manual
open Informal

#docs (Manual) externalMarkdownLeanRunDoc "External Markdown Lean Run" :=
:::::::
```md "external.markdown.witness" (slot := statement)
# Markdown witness

For every $n$, **source** text can back a Blueprint node.

<span>raw HTML stays text</span>
```
:::::::

def main (args : List String) : IO UInt32 :=
  Informal.PreviewManifest.blueprintMainWithPreviewData
    externalMarkdownLeanRunDoc.toPart
    args
    (extensionImpls := by exact extension_impls%)
